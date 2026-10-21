// services/my_visit_requests_service.dart
//
// The requester-side "My Visit Requests" surface — visits the signed-in
// user personally made on OTHER people's properties, projects or profiles.
// Backs the Manage Dashboard's Visits tab for all four roles (Builder/
// Broker/Individual/Influencer): unlike the dashboard's Leads tab (incoming
// requests on the user's OWN listings — `UnifiedLeadsService`/
// `SiteVisitService.listForProjects`), this is always scoped to requests
// the signed-in user made themselves, never by any locally-known
// property/project id list.
//
// Deliberately calls the EXISTING `my-visit-requests` Edge Function rather
// than three separate direct-table Supabase queries: the function already
// derives the requester purely from the caller's own JWT (`getCaller(req)`),
// already covers all three source tables (property/project/profile) in one
// round trip, and is the same contract the website's own
// `MyVisitRequests.tsx` uses — a second, parallel query built here could
// disagree with it over what counts as "mine". `VisitBookingService`
// (property-only, the standalone `/visits` screen) is left as-is; this
// service is additive, for the dashboard's wider three-source need.
//
// Cancel/reschedule go through the existing `my-visit-booking-manage` Edge
// Function too, for the same reason: it is the one place that validates
// requester ownership, booking status and visit-time windows server-side
// (`my-visit-booking-manage/index.ts:53-107`) — this service makes no
// authorization decision of its own and never attempts a direct-table
// UPDATE for a requester action (RLS grants no such policy; see
// `VisitBookingService`'s own header comment for why that fails today).
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/outgoing_visit_request.dart';

class MyVisitRequestsService {
  MyVisitRequestsService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// All three sources merged and sorted newest-first — same ordering
  /// `MyVisitRequests.tsx:160-164` applies after combining its three arrays.
  Future<List<OutgoingVisitRequest>> listMine() async {
    final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke('my-visit-requests');
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw message ?? 'Could not load your visit requests.';
    }

    final data = response.data;
    if (data is! Map) {
      throw 'Could not load your visit requests.';
    }

    final items = <OutgoingVisitRequest>[
      for (final row in _rowsOf(data['propertyVisits']))
        OutgoingVisitRequest.fromPropertyRow(row),
      for (final row in _rowsOf(data['projectVisits']))
        OutgoingVisitRequest.fromProjectRow(row),
      for (final row in _rowsOf(data['profileVisitRequests']))
        OutgoingVisitRequest.fromProfileRow(row),
    ];

    items.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  static List<Map<String, dynamic>> _rowsOf(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  /// `{action: "cancel", source, bookingId}` — the exact contract
  /// `my-visit-booking-manage/index.ts:21-27` expects. Throws the server's
  /// own validation message (e.g. "This visit is in the past and can no
  /// longer be changed.") on failure, same pattern as
  /// `PropertyService.getOwnershipDocumentUrls`.
  Future<void> cancel({
    required OutgoingVisitSource source,
    required String bookingId,
  }) => _manage({
    'action': 'cancel',
    'source': source.wireValue,
    'bookingId': bookingId,
  });

  /// `{action: "reschedule", source, bookingId, preferredDate, preferredTime}`.
  /// `preferredDate` must already be `YYYY-MM-DD` and `preferredTime`
  /// `HH:MM`/`HH:MM:SS` — the server rejects anything else (its own regex
  /// checks), so this method does not reformat either argument.
  Future<void> reschedule({
    required OutgoingVisitSource source,
    required String bookingId,
    required String preferredDate,
    required String preferredTime,
  }) => _manage({
    'action': 'reschedule',
    'source': source.wireValue,
    'bookingId': bookingId,
    'preferredDate': preferredDate,
    'preferredTime': preferredTime,
  });

  Future<void> _manage(Map<String, dynamic> body) async {
    try {
      await _supabase.functions.invoke('my-visit-booking-manage', body: body);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error']?.toString() : null;
      throw message ?? 'Could not update this visit request.';
    }
  }

  /// Realtime refresh across all three source tables — mirrors
  /// `MyVisitRequests.tsx:86-108`'s three `postgres_changes` subscriptions,
  /// one `RealtimeChannel` carrying all three bindings. Returns the channel
  /// so the caller can remove it on dispose; leaking it would keep
  /// re-fetching for a screen that is gone.
  RealtimeChannel subscribeToMine(String userId, void Function() onChange) {
    return _supabase
        .channel('my-visit-requests-dashboard-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'property_visit_bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'project_visit_bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profile_visit_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'requester_user_id',
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
      debugPrint('MyVisitRequestsService.unsubscribe failed: $e');
    }
  }
}
