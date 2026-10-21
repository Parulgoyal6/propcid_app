// services/broker_sections_service.dart
//
// Read/write access for the broker dashboard's Spec I sections: Leads, Visit
// Bookings and the Broker Profile.
//
// WHAT IS REUSED, NOT REBUILT
// ---------------------------
// All three surfaces are scoped by "this broker's listings", and
// `PropertyService.getPropertiesByUser` already runs exactly the query the portal
// runs for that (`.eq('user_id').order('created_at', desc)` — verified byte for
// byte in Spec D). So the caller resolves the listings once through it and passes
// the ids down; nothing here re-queries `properties`. That is also why the portal's
// three components each open with their own identical `properties` fetch and this
// does not.
//
// `PropertyService` itself is untouched, as is `BrokerPropertyService` — no new
// write path was needed on either.
//
// NO BACKEND CHANGE
// -----------------
// Every call is a SELECT, an UPDATE the existing RLS already permits, an
// INSERT/UPDATE on the caller's own `broker_profiles` row, a `notifications` INSERT
// of an enum value that already exists, or a realtime subscription to a table
// already in the `supabase_realtime` publication.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'resubmit_for_approval.dart';

import '../core/constants/broker_section_options.dart';
import '../models/broker_section_models.dart';
import '../models/property_model.dart';

/// Raised when a write is refused before it is attempted.
class BrokerSectionException implements Exception {
  const BrokerSectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ── Leads ───────────────────────────────────────────────────────────────────

/// `property_inquiries` across one broker's listings.
///
/// The leads-table ambiguity the contract flagged is resolved: this is
/// `property_inquiries`, not `crm_leads`. `BrokerLeadsManager.tsx:102` reads it,
/// `:194` writes it, and `crm_leads` is referenced by neither — nor by
/// `BrokerAnalytics.tsx` or `BrokerAudienceInsights.tsx`, which derive their own
/// lead metrics from the same table.
class BrokerLeadService {
  BrokerLeadService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'property_inquiries';

  /// Leads across [properties], newest first.
  ///
  /// Takes the listings rather than ids so the property title can be attached
  /// without a join — which is how the portal resolves it too (`:112`,
  /// `properties.find(...)`). `property_inquiries` has no title, and embedding
  /// `properties` would re-read rows the caller already holds.
  ///
  /// An empty list short-circuits: `inFilter('property_id', [])` is answered by
  /// PostgREST with every row the caller can see, which for a broker with no
  /// listings would be every inquiry they are allowed to read.
  Future<List<BrokerLead>> listForProperties(
    List<PropertyModel> properties,
  ) async {
    if (properties.isEmpty) return const [];

    final titles = <String, String>{
      for (final property in properties) property.id: property.title,
    };

    final rows = await _supabase
        .from(table)
        .select(BrokerLead.columns)
        .inFilter('property_id', titles.keys.toList())
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows)
        .map(
          (row) => BrokerLead.fromSupabase(
            row,
            propertyTitle: titles[row['property_id']?.toString()],
          ),
        )
        .toList();
  }

  /// The four counters the portal derives from the same list.
  ///
  /// Three of them are pure folds over [leads]. The fourth — the value of closed
  /// deals — needs the **raw** `properties.price`, which is why this is async.
  ///
  /// WHY IT CANNOT USE PropertyModel
  /// -------------------------------
  /// `properties.price` is TEXT and free-form ("95,00,000", "1.2 Cr"). The portal
  /// folds it with `parseFloat(String(p.price).replace(/[^0-9.]/g,''))`
  /// (`BrokerLeadsManager.tsx:151-156`), which turns "95,00,000" into 9500000.
  ///
  /// Neither field `PropertyModel` exposes reproduces that:
  ///
  ///   * `price` is `double.tryParse(raw)`, and `tryParse("95,00,000")` is **null**
  ///     — so the model reports **0** for every comma-formatted listing;
  ///   * `priceDisplay` is `formatIndianPrice(raw)`, e.g. "₹95.00 L", which strips
  ///     down to 95.0.
  ///
  /// Reporting ₹0 of closed business to a broker who has closed deals would be
  /// worse than one narrow extra read, so this fetches the two columns it needs.
  /// `PropertyModel` is left alone — that discrepancy is app-wide and pre-dates
  /// this spec.
  ///
  /// The read is skipped entirely when there are no closed leads, which is the
  /// common case.
  Future<BrokerLeadStats> statsFor(List<BrokerLead> leads) async {
    if (leads.isEmpty) return BrokerLeadStats.empty;

    final total = leads.length;
    final newLeads = leads.where((l) => l.status == 'new').length;
    final active = leads.where((l) => l.isActive).length;
    final closedLeads = leads.where((l) => l.status == 'closed').toList();

    var closedValue = 0.0;
    if (closedLeads.isNotEmpty) {
      final prices = await _fetchPrices(
        closedLeads.map((l) => l.propertyId).toSet().toList(),
      );
      closedValue = closedLeads.fold<double>(
        0,
        (sum, lead) => sum + (prices[lead.propertyId] ?? 0),
      );
    }

    return BrokerLeadStats(
      total: total,
      newLeads: newLeads,
      active: active,
      closed: closedLeads.length,
      conversionRate: (closedLeads.length / total) * 100,
      closedValue: closedValue,
    );
  }

  /// Public passthrough to [_fetchPrices] — `UnifiedLeadsService` needs the
  /// same raw-price read for its own closed-value fold over a differently
  /// filtered id set (closed + inquiry-sourced ids from the unified list,
  /// not a `List<BrokerLead>`), so it calls this rather than duplicating the
  /// query.
  Future<Map<String, double>> fetchRawPrices(List<String> propertyIds) =>
      _fetchPrices(propertyIds);

  /// Raw `price` per property id, parsed the portal's way.
  ///
  /// A failure yields an empty map rather than propagating: the other three
  /// counters are already correct, and losing the whole stats strip because one
  /// secondary read failed would be the wrong trade.
  Future<Map<String, double>> _fetchPrices(List<String> propertyIds) async {
    if (propertyIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('properties')
          .select('id, price')
          .inFilter('id', propertyIds);

      return {
        for (final row in List<Map<String, dynamic>>.from(rows))
          row['id'].toString(): parsePortalPrice(row['price']),
      };
    } catch (e) {
      debugPrint('BrokerLeadService._fetchPrices failed: $e');
      return const {};
    }
  }

  /// The portal's `parseFloat(String(price).replace(/[^0-9.]/g, ''))`.
  ///
  /// Exposed for tests: this is a contract with the portal, and its one surprising
  /// behaviour — "1.2 Cr" folding to `1.2` rather than 12000000 — is a portal bug
  /// carried deliberately so both platforms report the same figure.
  @visibleForTesting
  static double parsePortalPrice(Object? raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    final digits = raw.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    // JS parseFloat("") is NaN and the portal maps that to 0; Dart's tryParse
    // returns null, so `?? 0` lands on the same number.
    return double.tryParse(digits) ?? 0;
  }

  /// Writes a lead's new status.
  ///
  /// [status] is the **app-side** value; the enum value is resolved here.
  /// `brokerLeadStatusToDb` returns null for anything unmapped and this refuses
  /// rather than falling back to `'pending'` — the portal's `|| 'pending'` is what
  /// makes its "Lost" option destructive, and reproducing that would mean writing
  /// a status the broker did not choose.
  ///
  /// `updated_at` is sent explicitly, matching `:195`. RLS scopes the UPDATE to
  /// inquiries on the caller's own listings.
  Future<void> setStatus({
    required String leadId,
    required String status,
  }) async {
    final dbValue = brokerLeadStatusToDb(status);
    if (dbValue == null) {
      throw BrokerSectionException(
        '"$status" is not a status this lead can be set to.',
      );
    }

    await _supabase
        .from(table)
        .update({
          'status': dbValue,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', leadId);
  }
}

// ── Visit bookings ──────────────────────────────────────────────────────────

/// `property_visit_bookings` across one broker's listings, with realtime.
///
/// The contract records realtime as a **confirmed** requirement rather than a
/// verify-item, and it is: `BrokerVisitBookingsManager.tsx:136-155` subscribes to
/// `postgres_changes` on `event: '*'` and re-fetches on anything. The plumbing is
/// in place too — 20260315160000 sets `REPLICA IDENTITY FULL` on this table and
/// adds it to the `supabase_realtime` publication, in an applied migration.
class PropertyVisitBookingService {
  PropertyVisitBookingService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'property_visit_bookings';

  /// The channel name the portal uses. Shared deliberately: two clients on the
  /// same name receive the same broadcasts, which is the intent.
  static const String channelName = 'property-visit-bookings-updates';

  /// Already an enum value (20260315190000:5), so using it implies no schema work.
  static const String notificationType = 'visit_booking_update';

  /// Bookings across [properties], soonest requested date first.
  Future<List<PropertyVisitBooking>> listForProperties(
    List<PropertyModel> properties,
  ) async {
    if (properties.isEmpty) return const [];

    final titles = <String, String>{
      for (final property in properties) property.id: property.title,
    };

    final rows = await _supabase
        .from(table)
        .select(PropertyVisitBooking.columns)
        .inFilter('property_id', titles.keys.toList())
        .order('preferred_date', ascending: true);

    return List<Map<String, dynamic>>.from(rows)
        .map(
          (row) => PropertyVisitBooking.fromSupabase(
            row,
            propertyTitle: titles[row['property_id']?.toString()],
          ),
        )
        .toList();
  }

  /// Subscribes to every change on the table and calls [onChange].
  ///
  /// Deliberately as coarse as the portal's: `event: '*'`, no filter, and the
  /// callback re-fetches rather than trying to patch the list from the payload.
  /// A filter is not possible here anyway — the scope is "bookings on my
  /// listings", which is a join the realtime filter syntax cannot express — so the
  /// subscription is table-wide and the *fetch* it triggers is what applies RLS
  /// and the property scope.
  ///
  /// Returns the channel so the caller can remove it on dispose. Leaking it would
  /// keep re-fetching for a screen that is gone.
  RealtimeChannel subscribe(void Function() onChange) {
    return _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Stops a subscription started by [subscribe].
  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (e) {
      // Disposal must not throw into a widget's dispose().
      debugPrint('PropertyVisitBookingService.unsubscribe failed: $e');
    }
  }

  /// Updates a booking's slot and status, then notifies the visitor when the new
  /// status is one the portal notifies on.
  ///
  /// `BrokerVisitBookingsManager.tsx:166-190`. `updated_at` is sent to match it,
  /// though unlike the project table this one has a `handle_updated_at` trigger
  /// (20260314133000:58) and would maintain the column itself — harmless, and kept
  /// so the two platforms issue the same payload.
  ///
  /// A failed notification does not fail the update: the booking change is the
  /// broker's intent and has already committed.
  Future<void> updateBooking({
    required PropertyVisitBooking booking,
    required DateTime preferredDate,
    required String? preferredTime,
    required String status,
    required String propertyTitle,
  }) async {
    if (status.trim().isEmpty) {
      throw const BrokerSectionException('Choose a status.');
    }

    await _supabase
        .from(table)
        .update({
          // A DATE column — the day only, never an instant.
          'preferred_date': _dateOnly(preferredDate),
          'preferred_time': (preferredTime?.isEmpty ?? true)
              ? null
              : preferredTime,
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', booking.id);

    if (_notifyingStatuses.contains(status)) {
      await _notifyVisitor(
        userId: booking.userId,
        propertyTitle: propertyTitle,
        status: status,
        date: preferredDate,
        time: preferredTime,
        bookingId: booking.id,
        propertyId: booking.propertyId,
      );
    }
  }

  /// Writes only [status] (and `updated_at`) — the slot stays as it is.
  ///
  /// The Leads tab's unified status picker only ever moves a visit between
  /// pending/confirmed/completed (see `visitLeadStatusToDb`); it has no date
  /// or time to send, unlike [updateBooking], which is the Visits tab's own
  /// "reschedule" editor. Notifies the same way `updateBooking` does, for the
  /// same statuses.
  Future<void> updateStatusOnly({
    required String bookingId,
    required String? userId,
    required String propertyTitle,
    required String status,
    String? propertyId,
  }) async {
    final rows = await _supabase
        .from(table)
        .update({
          'status': status,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', bookingId)
        .select('preferred_date, preferred_time');

    if (_notifyingStatuses.contains(status) && userId != null) {
      final rowList = List<Map<String, dynamic>>.from(rows);
      final row = rowList.isEmpty ? null : rowList.first;
      final date = row != null
          ? DateTime.tryParse(row['preferred_date']?.toString() ?? '')
          : null;
      if (date != null) {
        await _notifyVisitor(
          userId: userId,
          propertyTitle: propertyTitle,
          status: status,
          date: date,
          time: row?['preferred_time']?.toString(),
          bookingId: bookingId,
          propertyId: propertyId,
        );
      }
    }
  }

  /// The three statuses `:181` notifies on. `completed` is not among them, even
  /// though `notifyVisitBookingUpdate` has copy for it — the portal never passes
  /// it.
  static const Set<String> _notifyingStatuses = {
    'confirmed',
    'cancelled',
    'rescheduled',
  };

  /// Copy transcribed from `notifyVisitBookingUpdate`
  /// (utils/notificationHelpers.ts:189-211), including that a cancellation omits
  /// the slot line.
  ///
  /// `data.bookingId`/`data.propertyId`/`data.source`/`data.recipientRole`
  /// are additive (no portal/backend equivalent writes them) — this writer
  /// always notifies the VISITOR after the OWNER (the signed-in broker)
  /// changed the booking, so `recipientRole` is hardcoded `'requester'`.
  /// `resolveNotificationDestination` reads `recipientRole` first and
  /// `bookingId`'s mere presence/absence only as a fallback for rows written
  /// before this fix (or by the backend, which has no such field) — adding
  /// `bookingId` here is safe specifically because `recipientRole` is always
  /// present on new rows and is checked first.
  Future<void> _notifyVisitor({
    required String userId,
    required String propertyTitle,
    required String status,
    required DateTime date,
    required String? time,
    String? bookingId,
    String? propertyId,
  }) async {
    final action = _actionLabel(status);
    final slot = status == 'cancelled'
        ? ''
        : ' New slot: ${_dateOnly(date)}'
              '${time != null && time.isNotEmpty ? ' at $time' : ''}';

    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'type': notificationType,
        'title': 'Visit $action',
        'message':
            'Your visit for "$propertyTitle" has been ${action.toLowerCase()}.$slot',
        'data': {
          'title': propertyTitle,
          'status': status,
          'date': _dateOnly(date),
          'time': time,
          if (bookingId != null) 'bookingId': bookingId,
          if (propertyId != null) 'propertyId': propertyId,
          'source': 'property',
          'recipientRole': 'requester',
        },
      });
    } catch (e) {
      debugPrint('PropertyVisitBookingService._notifyVisitor failed: $e');
    }
  }

  static String _actionLabel(String status) => switch (status) {
    'confirmed' => 'Confirmed',
    'cancelled' => 'Cancelled',
    'rescheduled' => 'Rescheduled',
    'completed' => 'Completed',
    _ => status,
  };

  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

// ── Broker profile ──────────────────────────────────────────────────────────

/// The caller's own `broker_profiles` row.
class BrokerProfileService {
  BrokerProfileService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'broker_profiles';

  /// This broker's profile, or null when they have never saved one.
  ///
  /// `maybeSingle`, not `single`: `user_id` is UNIQUE so there is at most one row,
  /// and zero is the normal state for a broker who has not filled the form in.
  Future<BrokerProfile?> fetchMine(String userId) async {
    final row = await _supabase
        .from(table)
        .select(BrokerProfile.columns)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return BrokerProfile.fromSupabase(row);
  }

  /// Inserts or updates, decided by whether [profile] already has an id.
  ///
  /// `BrokerProfileManager.tsx:152-168` branches the same way. An upsert would be
  /// shorter but would need the conflict target spelled out, and the portal's two
  /// paths are what the RLS policies are written against — separate INSERT and
  /// UPDATE policies, both `auth.uid() = user_id`.
  ///
  /// `approval_status` is never in the payload (it is a reviewer's column);
  /// editing an existing profile instead calls `resubmit_for_approval` first,
  /// which sends it back to review exactly as the portal does.
  Future<BrokerProfile> save({
    required String userId,
    required BrokerProfile profile,
  }) async {
    if (profile.fullName.trim().isEmpty) {
      // Also NOT NULL in the schema, so this would be a 23502.
      throw const BrokerSectionException('A full name is required.');
    }

    final payload = <String, dynamic>{
      'user_id': userId,
      'full_name': profile.fullName.trim(),
      'rera_number': profile.reraNumber,
      'license_number': profile.licenseNumber,
      'agency_name': profile.agencyName,
      'years_of_experience': profile.yearsOfExperience,
      'company_description': profile.companyDescription,
      'office_address': profile.officeAddress,
      'city': profile.city,
      'state': profile.state,
      'pincode': profile.pincode,
      'mobile_number': profile.mobileNumber,
      'email': profile.email,
      'website': profile.website,
      // Written back exactly as read. The portal has no editor for either and
      // sends what it loaded (`:147-148`); dropping them here would delete a
      // specialisation the registration flow set.
      'property_types': profile.propertyTypes,
      'operating_cities': profile.operatingCities,
    };

    final existingId = profile.id;
    if (existingId != null) {
      // Editing a live broker profile sends it back to review, like the
      // website (BrokerProfileManager). Runs before the write.
      await resubmitForApproval(_supabase, table: table, id: existingId);
    }
    final row = existingId == null
        ? await _supabase
              .from(table)
              .insert(payload)
              .select(BrokerProfile.columns)
              .single()
        : await _supabase
              .from(table)
              .update(payload)
              .eq('id', existingId)
              .select(BrokerProfile.columns)
              .single();

    return BrokerProfile.fromSupabase(row);
  }
}
