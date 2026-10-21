// Regression coverage for the Issue 1 fix: the confirmation screen used to
// treat a non-null propertyId as "the listing is live", regardless of the
// row's real `approval_status`. It must instead show pending-approval
// copy — never "live"/"visible to buyers" — for anything other than an
// `approved` listing, and must never auto-offer "Publish Everywhere" for a
// pending listing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/post_property/property_submission_confirmation_screen.dart';

import 'support/fake_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthProvider must wrap the whole MaterialApp (not just one route's
  // subtree) so it's still reachable from a screen pushed later via the
  // Navigator — matching how the real app wraps its Navigator in main.dart.
  Widget wrap(Widget child, {required AuthProvider authProvider}) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: authProvider,
      child: MaterialApp(home: child),
    );
  }

  late FakeAuthService authService;
  late AuthProvider authProvider;

  setUp(() {
    authService = FakeAuthService();
    authProvider = AuthProvider(
      authService: authService,
      teamService: FakeTeamService(),
    );
  });

  tearDown(() async {
    authProvider.dispose();
    await authService.dispose();
  });

  group('pending property (approval_status: pending)', () {
    testWidgets('does not claim the listing is live or visible to buyers', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const PropertySubmissionConfirmationScreen(
            propertyId: 'p-1',
            approvalStatus: 'pending',
          ),
          authProvider: authProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your listing is live!'), findsNothing);
      expect(find.textContaining('visible to buyers'), findsNothing);
    });

    testWidgets('shows admin-approval / pending wording instead', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const PropertySubmissionConfirmationScreen(
            propertyId: 'p-1',
            approvalStatus: 'pending',
          ),
          authProvider: authProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Listing sent for admin approval'), findsOneWidget);
      expect(find.textContaining('admin approval'), findsWidgets);
    });

    testWidgets('never auto-opens Publish Everywhere', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PropertySubmissionConfirmationScreen(
            propertyId: 'p-1',
            approvalStatus: 'pending',
          ),
          authProvider: authProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Dialog), findsNothing);
      // Confirmation screen must still be the only route on screen — a
      // dialog route would appear as an extra entry above it.
      expect(find.byType(PropertySubmissionConfirmationScreen), findsOneWidget);
    });

    testWidgets('also applies when the row has no approval_status at all', (
      tester,
    ) async {
      // Defends against ever falling back to "assume approved" for an
      // unexpected/null value instead of treating it as not-yet-live.
      await tester.pumpWidget(
        wrap(
          const PropertySubmissionConfirmationScreen(propertyId: 'p-1'),
          authProvider: authProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your listing is live!'), findsNothing);
      expect(find.text('Listing sent for admin approval'), findsOneWidget);
    });
  });

  group('approved property (approval_status: approved)', () {
    testWidgets('shows the live wording', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PropertySubmissionConfirmationScreen(
            propertyId: 'p-1',
            approvalStatus: 'approved',
          ),
          authProvider: authProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your listing is live!'), findsOneWidget);
      expect(find.textContaining('visible to buyers'), findsOneWidget);
      expect(find.text('Listing sent for admin approval'), findsNothing);
    });

    testWidgets(
      'still runs the existing Publish Everywhere offer path without crashing',
      (tester) async {
        // No live Supabase client is available in this test, so the offer's
        // network call fails and is swallowed by its own best-effort catch
        // (see class doc) — this only pins that an approved listing is not
        // blocked from attempting the offer the way a pending one now is.
        await tester.pumpWidget(
          wrap(
            const PropertySubmissionConfirmationScreen(
              propertyId: 'p-1',
              approvalStatus: 'approved',
            ),
            authProvider: authProvider,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('navigation', () {
    testWidgets('Done pops back to the first route, same as before', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: authProvider,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: Center(child: Text('Home Root'))),
          ),
        ),
      );

      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (_) => const PropertySubmissionConfirmationScreen(
            propertyId: 'p-1',
            approvalStatus: 'approved',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your listing is live!'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Home Root'), findsOneWidget);
      expect(find.text('Your listing is live!'), findsNothing);
    });
  });
}
