// Route protection — a disabled feature's screen must never be
// instantiated, even by direct named-route navigation (a deep link, a
// stale saved route, a notification payload), not just hidden from menus.
//
// This mirrors `PropertyApp.onGenerateRoute`'s own gate — `lib/app.dart`
// checks `LaunchFeatures.routeEnabled(settings.name)` before its route
// switch and redirects to `RoleHomeRouter` when it's false — using the
// same real screen widgets and the same real `RoleHomeRouter`. It does not
// pump the full `PropertyApp` (whose `home: SplashScreen()` and global
// `PendingInvitationGate`/orb overlay pull in unrelated startup machinery
// this task doesn't touch), so a future change to `app.dart`'s route table
// itself is not covered by this file — only that a route
// `LaunchFeatures.routeEnabled` says is disabled never reaches its screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/config/launch_features.dart';
import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/payment/payment_method_screen.dart';
import 'package:propcid_app/screens/role_home_router.dart';
import 'package:propcid_app/screens/social/social_accounts_screen.dart';
import 'package:propcid_app/screens/social/social_hub_screen.dart';
import 'package:propcid_app/screens/subscription/subscription_billing_screen.dart';
import 'package:propcid_app/screens/subscription/upgrade_screen.dart';

/// `RoleHomeRouter` always resolves to the full `HomeScreen` once
/// `userType` is known — heavy machinery this test has no reason to drag
/// in. Kept perpetually in the "still resolving" state instead, which
/// `RoleHomeRouter` renders as a plain loading spinner: enough to prove the
/// redirect happened, without needing Home's own dependencies.
class _StillResolvingAuth extends AuthProvider {
  @override
  bool get isLoggedIn => true;

  @override
  String? get userType => null;
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

  final navigatorKey = GlobalKey<NavigatorState>();

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // The exact gate `lib/app.dart`'s `onGenerateRoute` runs before its own
    // switch.
    if (!LaunchFeatures.routeEnabled(settings.name)) {
      return MaterialPageRoute(builder: (_) => const RoleHomeRouter());
    }
    switch (settings.name) {
      case AppConstants.upgradeScreen:
        return MaterialPageRoute(builder: (_) => const UpgradeScreen());
      case AppConstants.subscriptionBillingScreen:
        return MaterialPageRoute(
          builder: (_) => const SubscriptionBillingScreen(),
        );
      case AppConstants.paymentMethodScreen:
        return MaterialPageRoute(builder: (_) => const PaymentMethodScreen());
      case AppConstants.socialScreen:
        return MaterialPageRoute(builder: (_) => const SocialHubScreen());
      case AppConstants.socialAccountsScreen:
        return MaterialPageRoute(builder: (_) => const SocialAccountsScreen());
      default:
        return MaterialPageRoute(builder: (_) => const RoleHomeRouter());
    }
  }

  Future<void> pumpAppAndNavigate(WidgetTester tester, String route) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => _StillResolvingAuth(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
          onGenerateRoute: onGenerateRoute,
        ),
      ),
    );
    navigatorKey.currentState!.pushNamed(route);
    // Not `pumpAndSettle`: the redirect target's "still resolving" state is
    // a plain indeterminate `CircularProgressIndicator`, which animates
    // forever by design and would never let `pumpAndSettle` finish. A
    // couple of frames is enough for the push transition itself to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('Subscription/payment routes redirect instead of instantiating', () {
    testWidgets('/upgrade', (tester) async {
      await pumpAppAndNavigate(tester, AppConstants.upgradeScreen);
      expect(find.byType(UpgradeScreen), findsNothing);
      expect(find.byType(RoleHomeRouter), findsOneWidget);
    });

    testWidgets('/subscription-billing', (tester) async {
      await pumpAppAndNavigate(tester, AppConstants.subscriptionBillingScreen);
      expect(find.byType(SubscriptionBillingScreen), findsNothing);
      expect(find.byType(RoleHomeRouter), findsOneWidget);
    });

    testWidgets('/payment-method', (tester) async {
      await pumpAppAndNavigate(tester, AppConstants.paymentMethodScreen);
      expect(find.byType(PaymentMethodScreen), findsNothing);
      expect(find.byType(RoleHomeRouter), findsOneWidget);
    });
  });

  group('Social routes redirect instead of instantiating', () {
    testWidgets('/social', (tester) async {
      await pumpAppAndNavigate(tester, AppConstants.socialScreen);
      expect(find.byType(SocialHubScreen), findsNothing);
      expect(find.byType(RoleHomeRouter), findsOneWidget);
    });

    testWidgets('/social/accounts', (tester) async {
      await pumpAppAndNavigate(tester, AppConstants.socialAccountsScreen);
      expect(find.byType(SocialAccountsScreen), findsNothing);
      expect(find.byType(RoleHomeRouter), findsOneWidget);
    });
  });
}
