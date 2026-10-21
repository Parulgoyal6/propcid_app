// Drives `OutgoingSiteVisitsSection` without a live Supabase client/Edge
// Function — same "override the network-touching methods, hand back a
// real-but-unconnected channel" pattern as `FakeVisitBookingService`.
import 'dart:async';

import 'package:propcid_app/models/outgoing_visit_request.dart';
import 'package:propcid_app/services/my_visit_requests_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeMyVisitRequestsService extends MyVisitRequestsService {
  FakeMyVisitRequestsService({List<OutgoingVisitRequest>? items})
    : items = items ?? <OutgoingVisitRequest>[],
      super(
        client: SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  List<OutgoingVisitRequest> items;

  Object? nextListError;
  Object? nextCancelError;
  Object? nextRescheduleError;

  int listCallCount = 0;
  final List<({OutgoingVisitSource source, String bookingId})> cancelCalls =
      [];
  final List<({OutgoingVisitSource source, String bookingId, String date, String time})>
  rescheduleCalls = [];

  /// When true, [listMine] never resolves on its own — each call queues a
  /// [Completer] in [pendingListCompleters] for the test to complete
  /// manually, in whatever order it chooses, exactly like
  /// `FakeVisitBookingService.useManualListCompletion`.
  bool useManualListCompletion = false;
  final List<Completer<List<OutgoingVisitRequest>>> pendingListCompleters = [];

  void Function()? onChange;
  int subscribeCount = 0;
  int unsubscribeCount = 0;
  String? lastSubscribedUserId;

  @override
  Future<List<OutgoingVisitRequest>> listMine() async {
    listCallCount++;
    if (useManualListCompletion) {
      final completer = Completer<List<OutgoingVisitRequest>>();
      pendingListCompleters.add(completer);
      return completer.future;
    }
    final error = nextListError;
    if (error != null) {
      nextListError = null;
      throw error;
    }
    return List<OutgoingVisitRequest>.from(items);
  }

  @override
  Future<void> cancel({
    required OutgoingVisitSource source,
    required String bookingId,
  }) async {
    cancelCalls.add((source: source, bookingId: bookingId));
    final error = nextCancelError;
    if (error != null) {
      nextCancelError = null;
      throw error;
    }
  }

  @override
  Future<void> reschedule({
    required OutgoingVisitSource source,
    required String bookingId,
    required String preferredDate,
    required String preferredTime,
  }) async {
    rescheduleCalls.add((
      source: source,
      bookingId: bookingId,
      date: preferredDate,
      time: preferredTime,
    ));
    final error = nextRescheduleError;
    if (error != null) {
      nextRescheduleError = null;
      throw error;
    }
  }

  @override
  RealtimeChannel subscribeToMine(String userId, void Function() callback) {
    subscribeCount++;
    lastSubscribedUserId = userId;
    onChange = callback;
    return Supabase.instance.client.channel(
      'test-outgoing-visits-$subscribeCount',
    );
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {
    unsubscribeCount++;
  }
}
