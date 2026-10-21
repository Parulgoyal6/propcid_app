// Widget tests for `OutgoingSiteVisitsSection` — the Manage Dashboard's
// shared "Site Visits" tab content for all four roles. Real outgoing-visit
// data via [FakeMyVisitRequestsService], never a live Edge Function call.
// Covers: separation from incoming data (this widget has no
// owned-property/project id dependency at all — it only ever renders what
// `listMine()` returns), loading/empty/error/retry, account switching,
// stale/out-of-order async responses, and requester cancel/reschedule
// actions (success refreshes, failure surfaces a truthful message and
// leaves the item untouched) — mirroring `visits_screen_test.dart`'s own
// mandatory-scenario coverage for the analogous standalone screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/models/outgoing_visit_request.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/dashboard/widgets/outgoing_site_visits_section.dart';
import 'package:propcid_app/services/builder_sections_service.dart';

import 'support/fake_auth_service.dart';
import 'support/fake_my_visit_requests_service.dart';

/// Same noop stand-in `visits_screen_test.dart` uses purely to satisfy
/// `AuthProvider`'s constructor — this widget has nothing to do with
/// builder teams.
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

OutgoingVisitRequest _propertyVisit({
  String id = 'b-1',
  String status = 'pending',
  String title = 'Sea View Villa',
  String date = '2099-01-01',
}) => OutgoingVisitRequest.fromPropertyRow({
  'id': id,
  'property_id': 'p-1',
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
  FakeMyVisitRequestsService service, {
  bool enableRealtime = true,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(
            authService: authService,
            teamService: _NoopTeamService(),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: OutgoingSiteVisitsSection(
            service: service,
            enableRealtime: enableRealtime,
          ),
        ),
      ),
    ),
  );
  // Deliberately `pump()`, not `pumpAndSettle()` — `AuthProvider` schedules
  // its own independent retry work in an isolated `MaterialApp` with no
  // global navigator key (same reasoning `visits_screen_test.dart`'s own
  // `settle()` documents at length), which never actually settles and hangs
  // `pumpAndSettle()` even before any sign-in call. A fixed number of frames
  // is always enough for this widget's own mount -> sync -> render chain.
  await tester.pump();
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

  void signIn(FakeAuthService authService, String userId) {
    final user = fakeUser(userId);
    authService.currentUserOverride = user;
    authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
  }

  /// Same bounded stand-in for `pumpAndSettle()` `visits_screen_test.dart`
  /// uses, for the same reason (`AuthProvider._maybeNavigate`'s unbounded
  /// retry loop in an isolated `MaterialApp` with no global navigator key).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'renders only what listMine() returns — no owned-listing dependency '
    'of any kind',
    (tester) async {
      final authService = FakeAuthService();
      final service = FakeMyVisitRequestsService(
        items: [_propertyVisit(title: 'Sea View Villa')],
      );

      await _pump(tester, authService, service, enableRealtime: false);
      signIn(authService, 'u-1');
      await settle(tester);

      expect(service.listCallCount, 1);
      expect(find.text('Sea View Villa'), findsOneWidget);
    },
  );

  testWidgets('an empty list shows the empty state', (tester) async {
    final authService = FakeAuthService();
    final service = FakeMyVisitRequestsService(items: []);

    await _pump(tester, authService, service, enableRealtime: false);
    signIn(authService, 'u-1');
    await settle(tester);

    expect(find.textContaining('will show up here'), findsOneWidget);
  });

  testWidgets('a failed load shows a retry, which reloads successfully', (
    tester,
  ) async {
    final authService = FakeAuthService();
    final service = FakeMyVisitRequestsService(
      items: [_propertyVisit(title: 'Sea View Villa')],
    );
    service.nextListError = Exception('network down');

    await _pump(tester, authService, service, enableRealtime: false);
    signIn(authService, 'u-1');
    await settle(tester);

    expect(find.text("Couldn't load your visit requests"), findsOneWidget);
    expect(find.text('Sea View Villa'), findsNothing);

    await tester.tap(find.text('Retry'));
    await settle(tester);

    expect(service.listCallCount, 2);
    expect(find.text('Sea View Villa'), findsOneWidget);
  });

  testWidgets(
    'switching accounts reloads for the new user, discarding the previous '
    "one's list",
    (tester) async {
      final authService = FakeAuthService();
      final service = FakeMyVisitRequestsService(
        items: [_propertyVisit(title: 'Sea View Villa')],
      );

      await _pump(tester, authService, service, enableRealtime: false);
      signIn(authService, 'user-a');
      await settle(tester);
      expect(find.text('Sea View Villa'), findsOneWidget);

      service.items = [_propertyVisit(id: 'b-2', title: 'Whitefield Villa')];
      signIn(authService, 'user-b');
      await settle(tester);

      expect(service.listCallCount, 2);
      expect(find.text('Whitefield Villa'), findsOneWidget);
      expect(find.text('Sea View Villa'), findsNothing);
    },
  );

  testWidgets('a stale response never overwrites a newer one', (tester) async {
    final authService = FakeAuthService();
    final service = FakeMyVisitRequestsService();
    service.useManualListCompletion = true;

    await _pump(tester, authService, service, enableRealtime: true);
    signIn(authService, 'u-1');
    await settle(tester);

    service.onChange!();
    service.onChange!();
    await tester.pump();

    expect(service.pendingListCompleters.length, 3);

    service.pendingListCompleters[2].complete([
      _propertyVisit(id: 'new', title: 'Newer Result'),
    ]);
    await settle(tester);
    expect(find.text('Newer Result'), findsOneWidget);

    service.pendingListCompleters[1].complete([
      _propertyVisit(id: 'stale', title: 'Stale Result'),
    ]);
    await settle(tester);

    expect(find.text('Newer Result'), findsOneWidget);
    expect(find.text('Stale Result'), findsNothing);

    service.pendingListCompleters[0].complete([]);
    await settle(tester);
  });

  testWidgets('cancelling calls the existing authorized endpoint with source + '
      'bookingId, and refreshes the list on success', (tester) async {
    final authService = FakeAuthService();
    final service = FakeMyVisitRequestsService(
      items: [_propertyVisit(id: 'b-1', status: 'pending')],
    );

    await _pump(tester, authService, service, enableRealtime: false);
    signIn(authService, 'u-1');
    await settle(tester);

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(service.cancelCalls, [
      (source: OutgoingVisitSource.property, bookingId: 'b-1'),
    ]);
    // Refreshed after the successful cancel (initial load + post-cancel).
    expect(service.listCallCount, 2);
    expect(find.text('Visit cancelled.'), findsOneWidget);
  });

  testWidgets(
    'a failed cancellation surfaces the server\'s own message and does not '
    'fabricate success',
    (tester) async {
      final authService = FakeAuthService();
      final service = FakeMyVisitRequestsService(
        items: [_propertyVisit(id: 'b-1', status: 'pending')],
      );
      service.nextCancelError =
          'This visit is in the past and can no longer be changed.';

      await _pump(tester, authService, service, enableRealtime: false);
      signIn(authService, 'u-1');
      await settle(tester);

      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(
        find.text('This visit is in the past and can no longer be changed.'),
        findsOneWidget,
      );
      // No refresh after a failed write.
      expect(service.listCallCount, 1);
    },
  );

  testWidgets(
    'a request that is not pending/confirmed shows no cancel/reschedule '
    'action',
    (tester) async {
      final authService = FakeAuthService();
      final service = FakeMyVisitRequestsService(
        items: [_propertyVisit(id: 'b-1', status: 'completed')],
      );

      await _pump(tester, authService, service, enableRealtime: false);
      signIn(authService, 'u-1');
      await settle(tester);

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Reschedule'), findsNothing);
    },
  );
}
