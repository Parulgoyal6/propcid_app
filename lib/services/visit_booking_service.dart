// services/visit_booking_service.dart
//
// The buyer-side half of `property_visit_bookings`: submitting a visit
// request, listing "my" own bookings, and (attempting to) cancel one.
//
// The broker/owner-side half — bookings across a broker's own listings,
// updating status — already lives in `PropertyVisitBookingService`
// (broker_sections_service.dart). This is a deliberately separate, smaller
// class rather than folded into that one: the two sides have no overlapping
// RLS scope (`user_id = auth.uid()` here, `properties.user_id = auth.uid()`
// there) and no shared query shape.
//
// Contract pinned from the portal:
//   * insert — `BookVisitModal.tsx:156-178`: visitor_name, visitor_phone,
//     preferred_date (YYYY-MM-DD), preferred_time, message, status:
//     'pending', user_id, property_id.
//   * list — `MyVisitRequests.tsx:76-92`: `select('*, properties(id, title,
//     location, media_urls)').eq('user_id', ...).order('created_at',
//     ascending: false)`. `user_id` (the owner) is added to that join list
//     here so [PropertyVisitBooking.fromBuyerRow] can batch-resolve
//     owner name/phone the same PII-aware way `PropertyService
//     .getPropertyDetail` already does for the detail screen.
//   * realtime — `MyVisitRequests.tsx:47-53`'s first `.on(...)` clause (the
//     `project_visit_bookings`/`profile_visit_requests` clauses do not apply:
//     this app does not create those two booking kinds).
//
// Cancellation and rescheduling both go through the `my-visit-booking-manage`
// Edge Function (`backend/functions/my-visit-booking-manage/index.ts` in the
// portal repo) rather than a direct table update. `property_visit_bookings`
// (migration `20260314133000_add_property_visit_bookings.sql`) has exactly
// four RLS policies: buyers may INSERT their own row and SELECT their own
// rows; only the property owner may UPDATE a row's status directly. There is
// no policy letting the visitor update their own booking, so a direct client
// update is rejected — the Edge Function runs with the service role instead,
// after verifying server-side that the booking belongs to the caller, its
// status is still `pending`/`confirmed`, and the booked slot is still in the
// future (IST). A reschedule re-validates the new slot the same way and
// returns the row to `pending` for the owner to reconfirm; it also writes the
// owner-facing notification itself — this client must not write a second one.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/broker_section_models.dart';

/// Thrown when `my-visit-booking-manage` returns `{error: ...}` — e.g. the
/// booking is no longer pending/confirmed, or its slot is already in the
/// past. Carries the server's own message so the UI can surface it as-is
/// instead of a generic failure string.
class VisitManageException implements Exception {
  const VisitManageException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VisitBookingService {
  VisitBookingService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'property_visit_bookings';

  /// The joined select shape used by both [createBooking] (via `.select()`
  /// on the insert) and [listMyBookings], so a freshly created booking and
  /// one re-fetched from the list are hydrated identically.
  static const String _joinedSelect =
      '*, properties(id, title, location, media_urls, user_id)';

  /// Inserts one visit request for the signed-in user and returns the row
  /// Supabase actually wrote — callers must not report success until this
  /// resolves. Throws [StateError] if nobody is signed in; any
  /// [PostgrestException] (RLS denial, FK violation on a deleted property,
  /// network error) is rethrown untouched for the caller to surface.
  Future<PropertyVisitBooking> createBooking({
    required String propertyId,
    required String visitorName,
    required String visitorPhone,
    required DateTime preferredDate,
    required String preferredTime,
    String? message,
    String? ownerName,
    String? ownerPhone,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in to book a visit.');
    }

    final payload = buildInsertPayload(
      userId: userId,
      propertyId: propertyId,
      visitorName: visitorName,
      visitorPhone: visitorPhone,
      preferredDate: preferredDate,
      preferredTime: preferredTime,
      message: message,
    );

    final row = await _supabase
        .from(table)
        .insert(payload)
        .select(_joinedSelect)
        .single();

    return PropertyVisitBooking.fromBuyerRow(
      row,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
    );
  }

  /// The exact row this service writes, split out so the shape and the
  /// blank-to-null rule can be asserted without a database — same pattern as
  /// `RequirementService.buildPayload`.
  @visibleForTesting
  static Map<String, dynamic> buildInsertPayload({
    required String userId,
    required String propertyId,
    required String visitorName,
    required String visitorPhone,
    required DateTime preferredDate,
    required String preferredTime,
    String? message,
  }) {
    return {
      'user_id': userId,
      'property_id': propertyId,
      'visitor_name': visitorName.trim(),
      'visitor_phone': visitorPhone.trim(),
      'preferred_date': _dateOnly(preferredDate),
      'preferred_time': preferredTime,
      'message': _nullIfBlank(message),
      'status': 'pending',
    };
  }

  /// This buyer's own bookings, newest first, with each owner's name/phone
  /// batch-resolved in one extra query (mirrors `MyVisitRequests.tsx:94-97`'s
  /// own batched profile lookup for `profile_visit_requests`).
  Future<List<PropertyVisitBooking>> listMyBookings(String userId) async {
    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from(table)
          .select(_joinedSelect)
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    );

    final ownerIds = <String>{
      for (final row in rows)
        if (_ownerIdOf(row) != null) _ownerIdOf(row)!,
    };

    final owners = await _resolveOwners(ownerIds);

    return rows.map((row) {
      final owner = owners[_ownerIdOf(row)];
      return PropertyVisitBooking.fromBuyerRow(
        row,
        ownerName: owner?['display_name']?.toString(),
        ownerPhone: owner?['phone']?.toString(),
      );
    }).toList();
  }

  static String? _ownerIdOf(Map<String, dynamic> row) =>
      (row['properties'] as Map<String, dynamic>?)?['user_id']?.toString();

  /// `display_name`/`phone` for each id in [ownerIds], keyed by user id.
  ///
  /// Selecting `phone` here is the same PII-aware call `PropertyService
  /// .getPropertyDetail` already makes for the signed-in detail screen
  /// (`property_service.dart:224-233`) — this method is only ever reached by
  /// an authenticated buyer (RLS on `property_visit_bookings` itself requires
  /// it), so the same justification applies.
  Future<Map<String, Map<String, dynamic>>> _resolveOwners(
    Set<String> ownerIds,
  ) async {
    if (ownerIds.isEmpty) return const {};
    final rows = await _supabase
        .from('profiles')
        .select('user_id, display_name, phone')
        .inFilter('user_id', ownerIds.toList());
    return {
      for (final row in List<Map<String, dynamic>>.from(rows))
        row['user_id'].toString(): row,
    };
  }

  /// Cancels the visitor's own booking via `my-visit-booking-manage` — see
  /// the file-level doc comment for why this cannot be a direct table
  /// update. The function returns only `{ok: true}`, not the updated row, so
  /// the new status is applied locally via [PropertyVisitBooking.copyWith]
  /// rather than a second round trip.
  Future<PropertyVisitBooking> cancelBooking(
    PropertyVisitBooking booking,
  ) async {
    await _invokeManage({
      'action': 'cancel',
      'source': 'property',
      'bookingId': booking.id,
    });
    return booking.copyWith(status: 'cancelled');
  }

  /// Reschedules the visitor's own booking via `my-visit-booking-manage`.
  /// [preferredTime] must be 24-hour `HH:mm` (the function's own
  /// `TIME_RE`) — not the "h:mm AM/PM" shape the create-booking sheet's
  /// custom time picker produces, so callers must format accordingly.
  /// A successful reschedule always comes back `pending` (the function's own
  /// rule — the owner must reconfirm the new slot), mirrored here rather
  /// than re-fetched.
  Future<PropertyVisitBooking> rescheduleBooking(
    PropertyVisitBooking booking, {
    required DateTime preferredDate,
    required String preferredTime,
  }) async {
    await _invokeManage({
      'action': 'reschedule',
      'source': 'property',
      'bookingId': booking.id,
      'preferredDate': _dateOnly(preferredDate),
      'preferredTime': preferredTime,
    });
    return booking.copyWith(
      preferredDate: preferredDate,
      preferredTime: preferredTime,
      status: 'pending',
    );
  }

  /// Calls the shared `my-visit-booking-manage` function and throws
  /// [VisitManageException] with the server's own message on any failure —
  /// same "surface the real error, never fake success" rule [createBooking]
  /// already follows.
  Future<void> _invokeManage(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.functions.invoke(
        'my-visit-booking-manage',
        body: body,
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw VisitManageException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      throw VisitManageException(
        message?.toString() ?? 'Could not reach the server. Please try again.',
      );
    } catch (e) {
      if (e is VisitManageException) rethrow;
      throw const VisitManageException(
        'A network error occurred. Please try again.',
      );
    }
  }

  /// Realtime refresh scoped to this buyer's own rows —
  /// `MyVisitRequests.tsx:47-53`. Returns the channel so the caller can
  /// remove it on dispose; leaking it would keep re-fetching for a screen
  /// that is gone.
  RealtimeChannel subscribeToMine(String userId, void Function() onChange) {
    return _supabase
        .channel('my-visit-requests-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Stops a subscription started by [subscribeToMine].
  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (e) {
      // Disposal must not throw into a widget's dispose().
      debugPrint('VisitBookingService.unsubscribe failed: $e');
    }
  }

  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String? _nullIfBlank(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
