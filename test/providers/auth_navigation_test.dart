import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/app_navigator.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/services/auth_resolver.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_auth_service.dart';

/// Verifies AuthProvider is the *single* owner of navigation — the exact
/// property the "Home, then back to Sign In" Google-OAuth bug violated.
/// Uses a bare MaterialApp with the real `appNavigatorKey` and placeholder
/// screens (not the app's real Home/AccountTypeScreen/registration screens,
/// which have dependencies — Supabase, other providers — this harness does
/// not set up) so only the navigation mechanics are under test, via the
/// named-route destinations `_performNavigation` pushes.
class _TestApp extends StatelessWidget {
  const _TestApp({required this.provider});
  final AuthProvider provider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: Text('SPLASH')),
        onGenerateRoute: (settings) {
          final label = switch (settings.name) {
            '/auth' => 'AUTH_SCREEN',
            '/builder-profile' => 'BUILDER_REG',
            '/broker-profile' => 'BROKER_REG',
            '/influencer-profile' => 'INFLUENCER_REG',
            _ => 'UNKNOWN:${settings.name}',
          };
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(body: Text(label)),
          );
        },
      ),
    );
  }
}

/// A fixed number of plain frame pumps, each of which fully drains the
/// microtask queue — used instead of `pumpAndSettle()` throughout this file
/// because neither of that method's usual assumptions holds here:
/// `_TestApp` never watches `AuthProvider` (nothing reschedules a frame when
/// the background auth/profile-fetch chain — several `await`s deep, plus a
/// real `SharedPreferences` round-trip inside `logout()` — finally
/// resolves, so `pumpAndSettle` can decide "settled" before that chain is
/// actually done); and separately, a screen with a persistent/indeterminate
/// animation would make `pumpAndSettle` loop until its own timeout instead.
/// A bounded set of plain pumps sidesteps both failure modes.
Future<void> settle(WidgetTester tester) async {
  // Plain pump first, for any purely-synchronous work (e.g. a Navigator
  // push AuthProvider already triggered before this was even called) —
  // `runAsync` immediately after a just-triggered, not-yet-pumped
  // transition was observed to leave it unrendered.
  await tester.pump();
  // Then step outside the FakeAsync zone `testWidgets` normally runs in, so
  // the awaited real microtask/event-loop turns this provider's async
  // chain needs (stream delivery, the fake service's own internal awaits,
  // SharedPreferences inside logout()) actually get to run — plain
  // `pump()`/`pumpAndSettle()` alone were not reliably flushing this chain.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  await tester.pump();
  // Finally let any resulting route-transition animation finish — bounded
  // in this harness since nothing here schedules frames indefinitely.
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService authService;
  late AuthProvider provider;

  setUp(() {
    // AuthProvider.logout() reads SharedPreferences (to clear the legacy
    // pending-type keys) — without a mocked backing store, that call hangs
    // waiting on a platform channel no test environment answers.
    SharedPreferences.setMockInitialValues({});
    authService = FakeAuthService();
    provider = AuthProvider(
      authService: authService,
      teamService: FakeTeamService(),
    );
  });

  tearDown(() async {
    provider.dispose();
    await authService.dispose();
  });

  testWidgets(
    'a resolved destination does not navigate until enableNavigation is called '
    '(the Splash hand-off) — Home/Auth must not render prematurely',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      await tester.pumpWidget(_TestApp(provider: provider));
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await settle(tester);

      // Destination is known...
      expect(provider.destination, AuthDestination.needsBuilderRegistration);
      // ...but nothing has navigated away from the splash placeholder yet.
      expect(find.text('SPLASH'), findsOneWidget);
      expect(find.text('BUILDER_REG'), findsNothing);

      provider.enableNavigation();
      await settle(tester);

      expect(find.text('BUILDER_REG'), findsOneWidget);
      expect(find.text('SPLASH'), findsNothing);
    },
  );

  testWidgets('signedOut navigates to /auth once navigation is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_TestApp(provider: provider));
    provider.enableNavigation();

    authService.emit(AuthState(AuthChangeEvent.signedOut, null));
    await tester.pumpAndSettle();

    expect(find.text('AUTH_SCREEN'), findsOneWidget);
  });

  testWidgets(
    'blocked account signs out and returns to /auth via handleBlockedAccount',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'is_blocked': true,
        'user_type': 'individual',
        'profile_complete': true,
      };
      authService.currentUserOverride = user;

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await settle(tester);

      expect(find.text('AUTH_SCREEN'), findsOneWidget);
      expect(authService.logoutCallCount, 1);
    },
  );

  testWidgets(
    'Google regression: account A signs in (slow fetch), logs out, account B '
    'signs in and resolves — B is never overwritten when A\'s stale fetch '
    'finally lands, and nothing renders prematurely along the way',
    (tester) async {
      final userA = fakeUser('user-a');
      final userB = fakeUser('user-b');
      final pauseA = Completer<void>();
      authService.pauseNextFetch = pauseA;
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.profilesByUserId['user-b'] = {
        'user_type': 'broker',
        'profile_complete': false,
      };

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();

      // A signs in — fetch starts but is paused mid-flight, simulating the
      // profile round-trip that hadn't landed yet when the original bug's
      // Home screen appeared prematurely.
      authService.currentUserOverride = userA;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(userA)));
      // Deliberately NOT settle(tester) here — A's fetch is paused on a
      // Completer that only resolves when pauseA.complete() is called
      // below, so a bounded pump just confirms it is genuinely still
      // pending, not settled early.
      await tester.pump();
      await tester.pump();

      // Still resolving — must not have shown anything for A yet.
      expect(provider.isResolving, isTrue);
      expect(find.text('SPLASH'), findsOneWidget);
      expect(find.text('BUILDER_REG'), findsNothing);

      // A logs out before their own fetch resolves.
      await provider.logout();
      await settle(tester);
      expect(find.text('AUTH_SCREEN'), findsOneWidget);

      // B signs in; B's fetch is unpaused (pauseNextFetch was already
      // consumed by A's in-flight call) and resolves immediately.
      authService.currentUserOverride = userB;
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(userB)));
      await settle(tester);
      expect(find.text('BROKER_REG'), findsOneWidget);

      // Repeated "tab switch"-style rebuilds must not disturb this.
      await tester.pump();
      await tester.pump();
      expect(find.text('BROKER_REG'), findsOneWidget);

      // Now A's stale fetch finally resolves — it must be dropped, not
      // resurface A's builder-registration screen over B's.
      pauseA.complete();
      await settle(tester);

      expect(find.text('BROKER_REG'), findsOneWidget);
      expect(find.text('BUILDER_REG'), findsNothing);
      expect(find.text('AUTH_SCREEN'), findsNothing);
      expect(provider.userId, 'user-b');
    },
  );

  testWidgets(
    'repeated tokenRefreshed events for the same resolved user do not change '
    'the screen or re-trigger navigation to a different destination',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'influencer',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await settle(tester);
      expect(find.text('INFLUENCER_REG'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        authService.emit(
          AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
        );
        await tester.pump();
      }
      await settle(tester);

      expect(find.text('INFLUENCER_REG'), findsOneWidget);
    },
  );

  // Both destinations below (needsBuilderRegistration, needsAccountType) are
  // driven through the exact same _maybeNavigate/_performNavigation dedup
  // path — the property under test here is that path's behavior, not
  // anything specific to a particular destination. needsBuilderRegistration
  // is deliberately used instead of needsAccountType because it goes through
  // a *named* route ('/builder-profile'), which this harness's
  // onGenerateRoute intercepts with the BUILDER_REG stub — needsAccountType
  // pushes the real AccountTypeScreen directly, and that screen's
  // PremiumButton pulls in Poppins via google_fonts, which starts a real,
  // unawaited background HTTP fetch prone to timing-dependent failures in a
  // widget-test sandbox, unrelated to anything this file is testing.
  testWidgets(
    'destination resolved before the Navigator exists is retained and '
    'navigates exactly once it becomes ready (requirement: never lose a '
    'destination to a temporarily-null appNavigatorKey.currentState)',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      // Navigation enabled and the identity resolved BEFORE any widget (and
      // therefore before appNavigatorKey.currentState) exists.
      provider.enableNavigation();
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );

      expect(provider.destination, AuthDestination.needsBuilderRegistration);

      // The Navigator becomes ready now.
      await tester.pumpWidget(_TestApp(provider: provider));
      await settle(tester);

      expect(find.text('BUILDER_REG'), findsOneWidget);
      expect(find.text('SPLASH'), findsNothing);

      // A further settle must not push it a second time (e.g. duplicate
      // instances, or a crash from re-entrant navigation).
      await settle(tester);
      expect(find.text('BUILDER_REG'), findsOneWidget);
    },
  );

  testWidgets(
    'new-user event burst (signedIn+tokenRefreshed+userUpdated) navigates to '
    'the setup screen exactly once and never flashes a registration/Home screen first',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;
      final pause = Completer<void>();
      authService.pauseNextFetch = pause;

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();

      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await tester.pump();
      authService.emit(
        AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
      );
      authService.emit(
        AuthState(AuthChangeEvent.userUpdated, fakeSession(user)),
      );
      await tester.pump();

      // Still resolving (the paused fetch hasn't landed) — nothing must
      // have navigated away from Splash yet, in particular never Home.
      expect(find.text('SPLASH'), findsOneWidget);
      expect(find.text('BUILDER_REG'), findsNothing);

      pause.complete();
      await settle(tester);

      expect(find.text('BUILDER_REG'), findsOneWidget);
      expect(find.text('SPLASH'), findsNothing);
      expect(find.text('AUTH_SCREEN'), findsNothing);
    },
  );
}
