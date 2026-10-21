// Drives booking-dependent widgets/providers without a live Supabase client —
// same "override the network-touching methods, hand back a real-but-
// unconnected channel" pattern as `_FakeBookingService` in
// broker_sections_test.dart.
import 'dart:async';

import 'package:propcid_app/models/broker_section_models.dart';
import 'package:propcid_app/services/visit_booking_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeVisitBookingService extends VisitBookingService {
  FakeVisitBookingService({List<PropertyVisitBooking>? bookings})
      : bookings = bookings ?? <PropertyVisitBooking>[],
        super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            // Without this, GoTrue starts a real periodic auto-refresh
            // timer that outlives the widget tree and fails
            // flutter_test's "no pending timers after dispose" check.
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  List<PropertyVisitBooking> bookings;

  Object? nextCreateError;
  Object? nextListError;
  Object? nextCancelError;
  Object? nextRescheduleError;

  final List<Map<String, dynamic>> createCalls = <Map<String, dynamic>>[];
  int listCallCount = 0;
  final List<String> cancelCalls = <String>[];
  final List<Map<String, dynamic>> rescheduleCalls = <Map<String, dynamic>>[];

  /// When true, [listMyBookings] never resolves on its own — each call
  /// queues a [Completer] in [pendingListCompleters] for the test to
  /// complete manually, in whatever order it chooses. This is what lets a
  /// test simulate an out-of-order (stale) response.
  bool useManualListCompletion = false;
  final List<Completer<List<PropertyVisitBooking>>> pendingListCompleters =
      <Completer<List<PropertyVisitBooking>>>[];

  /// The callback the widget handed [subscribeToMine]; a test fires it to
  /// simulate a realtime event without a websocket.
  void Function()? onChange;
  int subscribeCount = 0;
  int unsubscribeCount = 0;
  String? lastSubscribedUserId;

  @override
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
    createCalls.add({
      'propertyId': propertyId,
      'visitorName': visitorName,
      'visitorPhone': visitorPhone,
      'preferredDate': preferredDate,
      'preferredTime': preferredTime,
      'message': message,
    });
    final error = nextCreateError;
    if (error != null) {
      nextCreateError = null;
      throw error;
    }
    final booking = PropertyVisitBooking(
      id: 'b-${createCalls.length}',
      propertyId: propertyId,
      userId: 'u-1',
      visitorName: visitorName,
      visitorPhone: visitorPhone,
      preferredDate: preferredDate,
      propertyTitle: 'Fake Property',
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      preferredTime: preferredTime,
      message: message,
      status: 'pending',
      createdAt: DateTime(2026, 1, 1),
    );
    bookings = [booking, ...bookings];
    return booking;
  }

  @override
  Future<List<PropertyVisitBooking>> listMyBookings(String userId) async {
    listCallCount++;
    if (useManualListCompletion) {
      final completer = Completer<List<PropertyVisitBooking>>();
      pendingListCompleters.add(completer);
      return completer.future;
    }
    final error = nextListError;
    if (error != null) {
      nextListError = null;
      throw error;
    }
    return List<PropertyVisitBooking>.from(bookings);
  }

  @override
  Future<PropertyVisitBooking> cancelBooking(
    PropertyVisitBooking booking,
  ) async {
    cancelCalls.add(booking.id);
    final error = nextCancelError;
    if (error != null) {
      nextCancelError = null;
      throw error;
    }
    final updated = booking.copyWith(status: 'cancelled');
    bookings = bookings.map((b) => b.id == booking.id ? updated : b).toList();
    return updated;
  }

  @override
  Future<PropertyVisitBooking> rescheduleBooking(
    PropertyVisitBooking booking, {
    required DateTime preferredDate,
    required String preferredTime,
  }) async {
    rescheduleCalls.add({
      'bookingId': booking.id,
      'preferredDate': preferredDate,
      'preferredTime': preferredTime,
    });
    final error = nextRescheduleError;
    if (error != null) {
      nextRescheduleError = null;
      throw error;
    }
    final updated = booking.copyWith(
      preferredDate: preferredDate,
      preferredTime: preferredTime,
      status: 'pending',
    );
    bookings = bookings.map((b) => b.id == booking.id ? updated : b).toList();
    return updated;
  }

  @override
  RealtimeChannel subscribeToMine(String userId, void Function() callback) {
    subscribeCount++;
    lastSubscribedUserId = userId;
    onChange = callback;
    // `client.channel(name)` builds the object without opening a socket —
    // `.subscribe()` is what connects, and this deliberately does not call
    // it. So the widget gets a real channel to hold and hand back on
    // dispose.
    return Supabase.instance.client.channel('test-visits-$subscribeCount');
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {
    unsubscribeCount++;
  }
}
