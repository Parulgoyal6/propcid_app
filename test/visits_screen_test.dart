// Widget tests for the buyer-facing "My Visits" screen — real backend data
// via [FakeVisitBookingService], never a live Supabase call. Covers the
// mandatory scenarios for Scope 1 that this screen owns: real visit loading,
// empty state, cancellation persistence (and truthful failure), sign-out,
// account switching, and stale/out-of-order async responses.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/broker_section_models.dart';
import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/navigation_provider.dart';
import 'package:propcid_app/screens/visits/visits_screen.dart';
import 'package:propcid_app/services/builder_sections_service.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_visit_booking_service.dart';

/// A `BuilderTeamService` fake used only to satisfy `AuthProvider`'s
/// constructor — this screen has nothing to do with builder teams. Backed by
/// a `SupabaseClient` with auto-refresh explicitly off, unlike
/// `support/fake_auth_service.dart`'s own `FakeTeamService`: that one leaves
/// GoTrue's default auto-refresh timer running, which outlives the widget
/// tree in a `testWidgets` test and trips flutter_test's pending-timer
/// check — harmless in the tests that already tolerate it, but this file
/// constructs a fresh instance per test (including a mid-test "restart"),
/// so any leaked timer would compound.
class _NoopTeamService extends BuilderTeamService {
  _NoopTeamService()
    : super(
        client: SupabaseClient(
          'http://localhost:54321',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<List<BuilderTeamMember>> myActiveMemberships(String userId) async =>
      const [];

  @override
  Future<List<BuilderTeamInvitation>> myPendingInvitations(
    String email,
  ) async => const [];

  @override
  Future<BuilderTeamInvitation?> myPendingPhoneInvitation() async => null;
}

PropertyVisitBooking _booking({
  String id = 'b-1',
  String status = 'pending',
  String title = 'Sea View 3BHK',
  String date = '2026-09-12',
}) => PropertyVisitBooking.fromBuyerRow({
  'id': id,
  'property_id': 'p-1',
  'user_id': 'u-1',
  'visitor_name': 'Asha Rao',
  'visitor_phone': '9876543210',
  'preferred_date': date,
  'preferred_time': '10:00',
  'status': status,
  'created_at': '2026-08-01T10:00:00Z',
  'properties': {
    'title': title,
    'location': 'Bandra West',
    'media_urls': <String>[],
  },
});

Future<void> _pump(
  WidgetTester tester,
  FakeAuthService authService,
  FakeVisitBookingService visitService,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            authService: authService,
            teamService: _NoopTeamService(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
      ],
      child: MaterialApp(
        home: VisitsScreen(service: visitService, enableRealtime: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // Deliberately no `await Future.delayed(...)` here: `testWidgets` runs
  // inside a FakeAsync zone, where a bare real-time delay never resolves on
  // its own (nothing advances that clock) and hangs forever. The stream
  // event's delivery is a microtask, not a timer — `settle()`'s first
  // `tester.pump()` is what actually flushes it.
  void signIn(FakeAuthService authService, String userId) {
    final user = fakeUser(userId);
    authService.currentUserOverride = user;
    authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
  }

  /// A bounded stand-in for `pumpAndSettle()`.
  ///
  /// Once a user is signed in, `AuthProvider._maybeNavigate` schedules its
  /// own independent `addPostFrameCallback` loop trying to navigate via the
  /// app's global `appNavigatorKey` (`auth_provider.dart:195-207`). This
  /// test's isolated `MaterialApp` never registers that key — deliberately,
  /// since wiring it up would let `AuthProvider` actually push
  /// `AccountTypeScreen`/`HomeScreen` and replace `VisitsScreen` out from
  /// under these assertions — so `currentState` never becomes ready and the
  /// retry reschedules itself every single frame, forever. That is real
  /// (if here incidental) `AuthProvider` behavior, not a `VisitsScreen` bug —
  /// see the implementation report's RLS/limitations section — so
  /// `pumpAndSettle()` (which waits for scheduled work to reach zero) would
  /// hang. A fixed number of frames is always enough for this screen's own
  /// sign-in -> load -> render chain, which has no unbounded work of its own.
  Future<void> settle(WidgetTester tester) async {
    // Matches `auth_navigation_test.dart`'s own `settle()` exactly: plain
    // `pump()`/`pumpAndSettle()` alone do not reliably flush AuthProvider's
    // async chain (stream delivery, this fake service's own awaits) because
    // `testWidgets` runs inside a `FakeAsync` zone — `runAsync` is what
    // actually steps outside it so real event-loop turns happen.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('signed out shows a sign-in prompt and never calls the backend', (
    tester,
  ) async {
    final authService = FakeAuthService();
    final visitService = FakeVisitBookingService();

    await _pump(tester, authService, visitService);

    expect(find.text('Sign in to see your visits'), findsOneWidget);
    expect(visitService.listCallCount, 0);
  });

  testWidgets('an empty list shows the empty state, not a fake booking', (
    tester,
  ) async {
    final authService = FakeAuthService();
    final visitService = FakeVisitBookingService(bookings: []);

    await _pump(tester, authService, visitService);
    signIn(authService, 'u-1');
    await settle(tester);

    expect(visitService.listCallCount, 1);
    expect(find.text('No upcoming visits'), findsOneWidget);
  });

  testWidgets('real visit loading renders the actual property/date/status', (
    tester,
  ) async {
    final authService = FakeAuthService();
    final visitService = FakeVisitBookingService(
      bookings: [_booking(status: 'confirmed')],
    );

    await _pump(tester, authService, visitService);
    signIn(authService, 'u-1');
    await settle(tester);

    expect(visitService.listCallCount, 1);
    expect(find.text('Sea View 3BHK'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    // No hardcoded agent name from the old fake data anywhere on screen.
    expect(find.textContaining('Rajesh Kumar'), findsNothing);
  });

  testWidgets(
    'cancelling persists: the service is called and the status updates',
    (tester) async {
      final authService = FakeAuthService();
      final visitService = FakeVisitBookingService(
        bookings: [_booking(status: 'pending')],
      );

      await _pump(tester, authService, visitService);
      signIn(authService, 'u-1');
      await settle(tester);

      await tester.tap(find.text('Cancel Visit'));
      await settle(tester);
      await tester.tap(find.text('Yes, Cancel'));
      await settle(tester);

      expect(visitService.cancelCalls, ['b-1']);
      expect(find.text('Visit cancelled.'), findsOneWidget);

      // "Survives a restart": a fresh screen instance (and fresh AuthProvider —
      // the broadcast auth-state stream does not replay past events, so the
      // sign-in is re-emitted too, exactly as a real app re-establishes its
      // session from a persisted token on cold start) reading the same
      // (now-mutated) backing store sees the persisted status, not the
      // pre-cancellation one.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, authService, visitService);
      signIn(authService, 'u-1');
      await settle(tester);
      expect(find.text('Cancelled'), findsOneWidget);
    },
  );

  testWidgets(
    'a failed cancellation shows a truthful error and leaves the booking untouched',
    (tester) async {
      final authService = FakeAuthService();
      final booking = _booking(status: 'pending');
      final visitService = FakeVisitBookingService(bookings: [booking]);
      visitService.nextCancelError = Exception('permission denied');

      await _pump(tester, authService, visitService);
      signIn(authService, 'u-1');
      await settle(tester);

      await tester.tap(find.text('Cancel Visit'));
      await settle(tester);
      await tester.tap(find.text('Yes, Cancel'));
      await settle(tester);

      // No success text anywhere, and the status never silently flips.
      expect(find.text('Visit cancelled.'), findsNothing);
      expect(find.textContaining("Couldn't cancel"), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Cancelled'), findsNothing);
    },
  );

  testWidgets(
    'switching accounts reloads for the new user, discarding the previous one\'s list',
    (tester) async {
      final authService = FakeAuthService();
      final visitService = FakeVisitBookingService(
        bookings: [_booking(id: 'b-1', title: 'Sea View 3BHK')],
      );

      await _pump(tester, authService, visitService);
      signIn(authService, 'user-a');
      await settle(tester);
      expect(find.text('Sea View 3BHK'), findsOneWidget);

      // A different account signs in — a fresh list for that user.
      visitService.bookings = [_booking(id: 'b-2', title: 'Whitefield Villa')];
      signIn(authService, 'user-b');
      await settle(tester);

      expect(visitService.listCallCount, 2);
      expect(find.text('Whitefield Villa'), findsOneWidget);
      expect(find.text('Sea View 3BHK'), findsNothing);
    },
  );

  testWidgets('a stale response never overwrites a newer one', (tester) async {
    final authService = FakeAuthService();
    final visitService = FakeVisitBookingService();
    visitService.useManualListCompletion = true;

    await _pump(tester, authService, visitService);
    signIn(authService, 'u-1');
    await settle(tester);

    // The realtime callback fires twice before either request resolves —
    // exactly the ordering a rapid double-refresh would produce.
    visitService.onChange!();
    visitService.onChange!();
    await tester.pump();

    expect(
      visitService.pendingListCompleters.length,
      3,
    ); // initial load + 2 refreshes

    // The newer (3rd) request resolves first...
    visitService.pendingListCompleters[2].complete([
      _booking(id: 'new', title: 'Newer Result'),
    ]);
    await settle(tester);
    expect(find.text('Newer Result'), findsOneWidget);

    // ...then the stale (2nd) request resolves after it. It must not undo
    // the newer result.
    visitService.pendingListCompleters[1].complete([
      _booking(id: 'stale', title: 'Stale Result'),
    ]);
    await settle(tester);

    expect(find.text('Newer Result'), findsOneWidget);
    expect(find.text('Stale Result'), findsNothing);

    // Clean up the still-pending first completer so the test process exits
    // cleanly.
    visitService.pendingListCompleters[0].complete([]);
    await settle(tester);
  });

  testWidgets('rescheduling calls the service with a date/time and returns the '
      'booking to pending', (tester) async {
    final authService = FakeAuthService();
    final booking = _booking(status: 'confirmed');
    final visitService = FakeVisitBookingService(bookings: [booking]);

    await _pump(tester, authService, visitService);
    signIn(authService, 'u-1');
    await settle(tester);

    expect(find.text('Confirmed'), findsOneWidget);

    await tester.tap(find.text('Reschedule'));
    await settle(tester);
    // Date picker dialog — accept its own default selection.
    await tester.tap(find.text('OK'));
    await settle(tester);
    // Time picker dialog — accept its own default selection.
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(visitService.rescheduleCalls, hasLength(1));
    expect(visitService.rescheduleCalls.single['bookingId'], booking.id);
    expect(
      find.text('Reschedule requested — waiting for the owner to reconfirm.'),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
  });

  testWidgets(
    'a failed reschedule shows a truthful error and leaves the booking untouched',
    (tester) async {
      final authService = FakeAuthService();
      final booking = _booking(status: 'confirmed');
      final visitService = FakeVisitBookingService(bookings: [booking]);
      visitService.nextRescheduleError = Exception('permission denied');

      await _pump(tester, authService, visitService);
      signIn(authService, 'u-1');
      await settle(tester);

      await tester.tap(find.text('Reschedule'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester);

      expect(find.textContaining("Couldn't reschedule"), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Pending'), findsNothing);
    },
  );
}
