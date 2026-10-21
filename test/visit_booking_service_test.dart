// Pins `VisitBookingService`'s exact write/read contract against
// `BookVisitModal.tsx:156-178` (insert) and `MyVisitRequests.tsx:76-92`
// (list) — and `PropertyInquiryService`'s against the `property_inquiries`
// schema (20250724173621_...sql:33-45) — without ever touching a live
// Supabase backend. `buildInsertPayload` on both services and
// `PropertyVisitBooking.fromBuyerRow` are pure functions; the only I/O paths
// (createBooking/submit's early `StateError` when signed out) are exercised
// against a real-but-never-connected `SupabaseClient`, so no network call is
// ever made.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/broker_section_models.dart';
import 'package:propcid_app/services/property_inquiry_service.dart';
import 'package:propcid_app/services/visit_booking_service.dart';

/// A `SupabaseClient` that never connects to a real backend and never starts
/// GoTrue's periodic auto-refresh timer (which would otherwise outlive the
/// test and trip flutter_test's pending-timer check).
SupabaseClient _testClient() => SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

void main() {
  // Only the two "signed-out guard" groups below construct a bare
  // `SupabaseClient` (never connected to a real backend — see their doc
  // comments); this just ensures the test binding exists before they do.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('VisitBookingService.buildInsertPayload', () {
    test('matches BookVisitModal.tsx\'s exact field set and shape', () {
      final payload = VisitBookingService.buildInsertPayload(
        userId: 'u-1',
        propertyId: 'p-1',
        visitorName: '  Asha Rao  ',
        visitorPhone: ' 9876543210 ',
        preferredDate: DateTime(2026, 9, 3),
        preferredTime: '02:00',
        message: '  Looking forward to it  ',
      );

      expect(payload, {
        'user_id': 'u-1',
        'property_id': 'p-1',
        'visitor_name': 'Asha Rao',
        'visitor_phone': '9876543210',
        'preferred_date': '2026-09-03',
        'preferred_time': '02:00',
        'message': 'Looking forward to it',
        'status': 'pending',
      });
    });

    test('a blank message is stored as null, not an empty string', () {
      final payload = VisitBookingService.buildInsertPayload(
        userId: 'u-1',
        propertyId: 'p-1',
        visitorName: 'Asha Rao',
        visitorPhone: '9876543210',
        preferredDate: DateTime(2026, 1, 1),
        preferredTime: '10:00',
        message: '   ',
      );
      expect(payload['message'], isNull);
    });

    test('a single-digit month/day is zero-padded (a DATE column, not free text)', () {
      final payload = VisitBookingService.buildInsertPayload(
        userId: 'u-1',
        propertyId: 'p-1',
        visitorName: 'Asha Rao',
        visitorPhone: '9876543210',
        preferredDate: DateTime(2026, 1, 5),
        preferredTime: '10:00',
      );
      expect(payload['preferred_date'], '2026-01-05');
    });

    test('status is always pending — a buyer never creates any other status', () {
      final payload = VisitBookingService.buildInsertPayload(
        userId: 'u-1',
        propertyId: 'p-1',
        visitorName: 'Asha Rao',
        visitorPhone: '9876543210',
        preferredDate: DateTime(2026, 1, 1),
        preferredTime: '10:00',
      );
      expect(payload['status'], 'pending');
    });
  });

  group('PropertyVisitBooking.fromBuyerRow', () {
    test('hydrates title/image/location from the inline properties join', () {
      final booking = PropertyVisitBooking.fromBuyerRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'user_id': 'u-1',
        'visitor_name': 'Asha Rao',
        'visitor_phone': '9876543210',
        'preferred_date': '2026-09-03',
        'preferred_time': '02:00',
        'message': 'Hi',
        'status': 'confirmed',
        'created_at': '2026-08-01T10:00:00Z',
        'properties': {
          'id': 'p-1',
          'title': 'Sea View 3BHK',
          'location': 'Bandra West',
          'media_urls': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
          'user_id': 'owner-1',
        },
      }, ownerName: 'Rahul Sharma', ownerPhone: '9998887776');

      expect(booking.propertyTitle, 'Sea View 3BHK');
      expect(booking.propertyLocation, 'Bandra West');
      expect(booking.propertyImageUrl, 'https://example.com/a.jpg');
      expect(booking.ownerName, 'Rahul Sharma');
      expect(booking.ownerPhone, '9998887776');
      expect(booking.status, 'confirmed');
    });

    test('a booking with no properties join and no owner resolves to nulls, not a crash', () {
      final booking = PropertyVisitBooking.fromBuyerRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'user_id': 'u-1',
        'visitor_name': 'Asha Rao',
        'visitor_phone': '9876543210',
        'preferred_date': '2026-09-03',
        'status': 'pending',
      });

      expect(booking.propertyTitle, isNull);
      expect(booking.propertyImageUrl, isNull);
      expect(booking.propertyLocation, isNull);
      expect(booking.ownerName, isNull);
      expect(booking.ownerPhone, isNull);
    });

    test('copyWith preserves the buyer-only hydrated fields', () {
      final booking = PropertyVisitBooking.fromBuyerRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'user_id': 'u-1',
        'visitor_name': 'Asha Rao',
        'visitor_phone': '9876543210',
        'preferred_date': '2026-09-03',
        'status': 'pending',
        'properties': {'title': 'Sea View 3BHK', 'location': 'Bandra West'},
      }, ownerName: 'Rahul Sharma', ownerPhone: '9998887776');

      final cancelled = booking.copyWith(status: 'cancelled');

      expect(cancelled.status, 'cancelled');
      expect(cancelled.propertyTitle, 'Sea View 3BHK');
      expect(cancelled.propertyLocation, 'Bandra West');
      expect(cancelled.ownerName, 'Rahul Sharma');
      expect(cancelled.ownerPhone, '9998887776');
    });
  });

  group('VisitBookingService — signed-out guard (no network involved)', () {
    test('createBooking throws StateError, never reaching Supabase', () async {
      final service = VisitBookingService(client: _testClient());

      await expectLater(
        service.createBooking(
          propertyId: 'p-1',
          visitorName: 'Asha Rao',
          visitorPhone: '9876543210',
          preferredDate: DateTime(2026, 1, 1),
          preferredTime: '10:00',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('VisitBookingService.cancelBooking / rescheduleBooking', () {
    // Regression guard for the fix: these used to attempt a direct table
    // UPDATE (rejected by RLS for a buyer's own booking — see the file-level
    // doc comment). Both now go through the `my-visit-booking-manage` Edge
    // Function instead; against a bare, never-connected client (no backend
    // reachable) that call fails over the network, and this pins down that
    // the failure surfaces as a typed, user-presentable
    // [VisitManageException] rather than a raw/uncaught exception.
    final booking = PropertyVisitBooking.fromBuyerRow({
      'id': 'b-1',
      'property_id': 'p-1',
      'user_id': 'u-1',
      'visitor_name': 'Asha Rao',
      'visitor_phone': '9876543210',
      'preferred_date': '2026-09-03',
      'preferred_time': '10:00',
      'status': 'pending',
    });

    test(
      'cancelBooking surfaces a VisitManageException, not a raw error',
      () async {
        final service = VisitBookingService(client: _testClient());
        await expectLater(
          service.cancelBooking(booking),
          throwsA(isA<VisitManageException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'rescheduleBooking surfaces a VisitManageException, not a raw error',
      () async {
        final service = VisitBookingService(client: _testClient());
        await expectLater(
          service.rescheduleBooking(
            booking,
            preferredDate: DateTime(2026, 9, 10),
            preferredTime: '14:30',
          ),
          throwsA(isA<VisitManageException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('PropertyInquiryService.buildInsertPayload', () {
    test('matches the property_inquiries schema exactly', () {
      final payload = PropertyInquiryService.buildInsertPayload(
        inquirerId: 'u-1',
        propertyId: 'p-1',
        message: '  Interested, please call.  ',
        contactPhone: ' 9876543210 ',
        contactEmail: ' buyer@example.com ',
      );

      expect(payload, {
        'property_id': 'p-1',
        'inquirer_id': 'u-1',
        'message': 'Interested, please call.',
        'contact_phone': '9876543210',
        'contact_email': 'buyer@example.com',
        'preferred_contact_time': null,
        'status': 'pending',
      });
    });

    test('omitted contact details are stored as null, matching nullable VARCHAR columns', () {
      final payload = PropertyInquiryService.buildInsertPayload(
        inquirerId: 'u-1',
        propertyId: 'p-1',
        message: 'Interested',
      );
      expect(payload['contact_phone'], isNull);
      expect(payload['contact_email'], isNull);
    });
  });

  group('DuplicateInquiryException', () {
    test('describes itself for direct display', () {
      expect(
        const DuplicateInquiryException().toString(),
        contains('already sent an enquiry'),
      );
    });
  });

  group('PropertyInquiryService — signed-out guard (no network involved)', () {
    test('submit throws StateError, never reaching Supabase', () async {
      final service = PropertyInquiryService(client: _testClient());

      await expectLater(
        service.submit(propertyId: 'p-1', message: 'Hi'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
