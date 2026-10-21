// Pins the Leads/Visits routing contract `resolveNotificationDestination`
// now implements for `visit_booking_new`/`visit_booking_update` — the core
// of this fix's notification-navigation requirement. `visit_booking_update`
// is written in BOTH directions (owner→requester and requester→owner) and
// must land on a different Manage Dashboard tab depending on which; these
// cases pin that disambiguation against the exact payload shapes confirmed
// from the backend's real writers (`notify_on_visit_booking` trigger,
// `insertVisitBookingUpdateNotification` helper, `my-visit-booking-manage`)
// and this app's own two writers (`SiteVisitService`/
// `PropertyVisitBookingService`), rather than guessed shapes.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/navigation/dashboard_section.dart';
import 'package:propcid_app/core/navigation/notification_route_resolver.dart';

void main() {
  group('visit_booking_new', () {
    test('always opens the owner\'s Leads tab', () {
      // Exact shape `notify_on_visit_booking` (the DB trigger, the only
      // writer of this type) inserts for a property visit.
      final destination = resolveNotificationDestination(
        type: 'visit_booking_new',
        data: {
          'bookingId': 'b-1',
          'propertyId': 'p-1',
          'title': 'Sea View Villa',
          'visitor_name': 'Asha Rao',
          'visitor_phone': '9876543210',
          'date': '2026-11-01',
          'time': '10:00',
        },
      );

      expect(destination, isNotNull);
      expect(destination!.route, AppConstants.manageDashboardScreen);
      expect(destination.arguments?['section'], DashboardSection.leads);
      expect(destination.arguments?['highlightBookingId'], 'b-1');
      expect(destination.arguments?['highlightSource'], 'property');
    });

    test('resolves source from whichever id key is present (project)', () {
      final destination = resolveNotificationDestination(
        type: 'visit_booking_new',
        data: {'bookingId': 'b-2', 'projectId': 'proj-1'},
      );
      expect(destination!.arguments?['highlightSource'], 'project');
    });
  });

  group('visit_booking_update — owner changed it, requester receives it', () {
    test('explicit recipientRole routes to Site Visits', () {
      // This app's own writers now set this explicitly.
      final destination = resolveNotificationDestination(
        type: 'visit_booking_update',
        data: {
          'title': 'Sea View Villa',
          'status': 'confirmed',
          'date': '2026-11-02',
          'time': '11:00',
          'propertyId': 'p-1',
          'bookingId': 'b-1',
          'recipientRole': 'requester',
        },
      );

      expect(destination, isNotNull);
      expect(destination!.route, AppConstants.manageDashboardScreen);
      expect(destination.arguments?['section'], DashboardSection.visits);
    });

    test(
      'known legacy Flutter payload (title/status/date/time, no booking id) '
      'still opens Site Visits without needing a highlighted record',
      () {
        // The exact pre-fix shape `PropertyVisitBookingService._notifyVisitor`
        // wrote — and still the exact shape the portal's own shared
        // `insertVisitBookingUpdateNotification` helper writes today for a
        // profile-visit owner update, which this app never touches.
        final destination = resolveNotificationDestination(
          type: 'visit_booking_update',
          data: {
            'title': 'Sea View Villa',
            'status': 'cancelled',
            'date': '2026-11-02',
            'time': null,
          },
        );

        expect(destination, isNotNull);
        expect(destination!.route, AppConstants.manageDashboardScreen);
        expect(destination.arguments?['section'], DashboardSection.visits);
        // No booking id to highlight — must not block opening the section.
        expect(destination.arguments?.containsKey('highlightBookingId'), isFalse);
      },
    );

    test(
      'legacy project-visit payload (has projectId, no bookingId) also '
      'opens Site Visits, not a project detail page',
      () {
        // The exact pre-fix shape `SiteVisitService._notifyVisitor` wrote.
        final destination = resolveNotificationDestination(
          type: 'visit_booking_update',
          data: {
            'title': 'Skyline Towers',
            'status': 'rescheduled',
            'date': '2026-11-03',
            'time': '09:30',
            'projectId': 'proj-1',
          },
        );

        expect(destination!.arguments?['section'], DashboardSection.visits);
        expect(destination.route, AppConstants.manageDashboardScreen);
      },
    );
  });

  group(
    'visit_booking_update — requester cancelled/rescheduled, owner receives it',
    () {
      test('explicit recipientRole routes to Leads', () {
        final destination = resolveNotificationDestination(
          type: 'visit_booking_update',
          data: {
            'title': 'Sea View Villa',
            'status': 'cancelled',
            'bookingId': 'b-1',
            'propertyId': 'p-1',
            'recipientRole': 'owner',
          },
        );

        expect(destination!.arguments?['section'], DashboardSection.leads);
      });

      test(
        'backend\'s my-visit-booking-manage shape (has bookingId, no '
        'recipientRole) falls back to Leads via bookingId presence',
        () {
          // Exact shape `my-visit-booking-manage/index.ts:109-153` inserts —
          // this backend writer has no `recipientRole` field and never will
          // without a schema/endpoint change, which is out of scope.
          final destination = resolveNotificationDestination(
            type: 'visit_booking_update',
            data: {
              'bookingId': 'b-9',
              'title': 'Sea View Villa',
              'status': 'cancelled',
              'visitor_name': 'Asha Rao',
              'date': '2026-11-05',
              'time': '14:00',
              'propertyId': 'p-1',
            },
          );

          expect(destination!.arguments?['section'], DashboardSection.leads);
          expect(destination.arguments?['highlightBookingId'], 'b-9');
        },
      );
    },
  );

  group('visit_booking_update — genuinely ambiguous payload', () {
    test(
      'no recognisable visit shape at all falls back to the dashboard\'s '
      'ordinary default tab rather than guessing a direction',
      () {
        final destination = resolveNotificationDestination(
          type: 'visit_booking_update',
          data: const {},
        );

        expect(destination, isNotNull);
        expect(destination!.route, AppConstants.manageDashboardScreen);
        expect(destination.arguments, isNull);
      },
    );
  });

  group('unrelated notification routes are unchanged', () {
    test('property_approved still resolves to the property detail screen', () {
      final destination = resolveNotificationDestination(
        type: 'property_approved',
        data: {'property_id': 'p-1'},
      );
      expect(destination!.route, AppConstants.propertyDetailScreen);
      expect(destination.arguments, {'propertyId': 'p-1'});
    });

    test('lead_assigned still resolves to the leads list route', () {
      final destination = resolveNotificationDestination(
        type: 'lead_assigned',
        data: const {},
      );
      expect(destination!.route, AppConstants.myLeadsScreen);
    });

    test('an unknown type still resolves to null', () {
      final destination = resolveNotificationDestination(
        type: 'something_new',
        data: const {},
      );
      expect(destination, isNull);
    });
  });
}
