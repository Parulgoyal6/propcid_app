// Focused check for the Phase 1 identity-linking feature's reliance on
// AuthProvider's existing same-user event coalescing.
//
// IdentityVerificationProvider.verifyCode calls
// `Supabase.instance.client.auth.refreshSession()` directly after a
// successful link, rather than routing through AuthProvider — see that
// method's doc comment. That is only safe because AuthProvider already
// treats a repeated `tokenRefreshed` event for an already-resolved user as a
// no-op for navigation purposes (proven generally by
// `auth_navigation_test.dart`'s "repeated tokenRefreshed events..." case).
// This test exercises that exact composition from the identity-linking
// feature's own point of view: a user mid-way through a registration wizard
// completes email/phone verification (triggering a session refresh) and
// must not be bounced to a different screen as a side effect.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/app_navigator.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/services/auth_resolver.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_auth_service.dart';

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

/// Same bounded-pump helper as `auth_navigation_test.dart` — see its own
/// comment for why `pumpAndSettle` alone is not reliable here.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService authService;
  late AuthProvider provider;

  setUp(() {
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
    'a token refresh triggered by completing identity verification does not navigate away from the current registration screen',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await settle(tester);

      expect(provider.destination, AuthDestination.needsBuilderRegistration);
      expect(find.text('BUILDER_REG'), findsOneWidget);

      // Simulates exactly what IdentityVerificationProvider.verifyCode does
      // after a successful email/phone link: refresh the session for the
      // SAME, already-resolved user.
      authService.emit(
        AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
      );
      await settle(tester);

      expect(
        provider.destination,
        AuthDestination.needsBuilderRegistration,
        reason: 'completing identity verification must not change the resolved destination',
      );
      expect(
        find.text('BUILDER_REG'),
        findsOneWidget,
        reason: 'the wizard screen must still be the one showing',
      );
      expect(find.text('AUTH_SCREEN'), findsNothing);
      expect(find.text('SPLASH'), findsNothing);
    },
  );

  testWidgets(
    'a burst of token-refresh events for the same user during verification settles once, not repeatedly',
    (tester) async {
      final user = fakeUser('user-a');
      authService.profilesByUserId['user-a'] = {
        'user_type': 'builder',
        'profile_complete': false,
      };
      authService.currentUserOverride = user;

      await tester.pumpWidget(_TestApp(provider: provider));
      provider.enableNavigation();
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      await settle(tester);

      // A send + a verify + the session refresh can plausibly each touch
      // the auth stream in quick succession — none of them should re-fire
      // navigation.
      for (var i = 0; i < 3; i++) {
        authService.emit(
          AuthState(AuthChangeEvent.tokenRefreshed, fakeSession(user)),
        );
      }
      await settle(tester);

      expect(provider.destination, AuthDestination.needsBuilderRegistration);
      expect(find.text('BUILDER_REG'), findsOneWidget);
    },
  );
}
