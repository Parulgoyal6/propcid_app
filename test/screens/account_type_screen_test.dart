import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/auth/account_type_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fake_auth_service.dart';

/// The Full-Name-+-User-Type setup step. Portal-parity checks: only the four
/// real types are offered (never Buyer/Seller/Admin/Super Admin), a name is
/// required, and a successful submission narrowly upserts
/// user_id/display_name/user_type/profile_complete:false — never user_role.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthService authService;
  late AuthProvider provider;

  Future<void> pumpScreen(WidgetTester tester, {required String userId}) {
    return tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(home: AccountTypeScreen(userId: userId)),
      ),
    );
  }

  setUp(() {
    authService = FakeAuthService();
    provider = AuthProvider(
      authService: authService,
      teamService: FakeTeamService(),
    );
  });

  tearDown(() {
    provider.dispose();
  });

  testWidgets(
    'offers exactly the four real types and never Buyer/Seller/Admin',
    (tester) async {
      await pumpScreen(tester, userId: 'user-a');

      expect(find.text('Individual'), findsOneWidget);
      expect(find.text('Builder'), findsOneWidget);
      expect(find.text('Broker'), findsOneWidget);
      expect(find.text('Influencer'), findsOneWidget);

      expect(find.text('Buyer'), findsNothing);
      expect(find.text('Seller'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Super Admin'), findsNothing);
    },
  );

  testWidgets(
    'submitting with no name and no type selected shows both validation errors and writes nothing',
    (tester) async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      await pumpScreen(tester, userId: 'user-a');

      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your name.'), findsOneWidget);
      expect(find.text('Please select an account type.'), findsOneWidget);
      expect(authService.upsertCalls, isEmpty);
    },
  );

  testWidgets(
    'a valid Full Name + Builder submission upserts narrowly (no user_role) and never enters Home directly',
    (tester) async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      authService.profilesByUserId['user-a'] = {
        'user_type': null,
        'profile_complete': false,
      };
      await pumpScreen(tester, userId: 'user-a');

      await tester.enterText(find.byType(TextField).first, 'Jane Doe');
      await tester.tap(find.text('Builder'));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      // Not pumpAndSettle(): on success this screen deliberately leaves
      // `_isSaving` true forever (the real app expects AuthProvider's own
      // navigation to replace it), so PremiumButton's indeterminate spinner
      // keeps scheduling frames and pumpAndSettle would never see "settled".
      // A bounded number of plain pumps is enough to let the upsert +
      // refreshProfile chain complete without depending on that.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }

      expect(authService.upsertCalls, [
        {'userId': 'user-a', 'displayName': 'Jane Doe', 'userType': 'builder'},
      ]);
      expect(
        authService.profilesByUserId['user-a']?['profile_complete'],
        false,
      );
      expect(
        authService.profilesByUserId['user-a']?.containsKey('user_role'),
        isFalse,
      );
    },
  );

  testWidgets(
    'a failed upsert stays on the setup screen and shows an error, writing nothing marked complete',
    (tester) async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      await pumpScreen(tester, userId: 'user-a');

      // No session at submit time (simulated by clearing it after the screen
      // has already read the (empty) prefill) — completeAccountSetup rejects
      // and the screen must show that, not crash or proceed.
      authService.currentUserOverride = null;

      await tester.enterText(find.byType(TextField).first, 'Jane Doe');
      await tester.tap(find.text('Individual'));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(authService.upsertCalls, isEmpty);
      // Still on the setup screen — not Home, not anything else.
      expect(find.byType(AccountTypeScreen), findsOneWidget);
    },
  );

  testWidgets(
    'prefills Full Name from AuthProvider.userName, but the field stays editable',
    (tester) async {
      final user = fakeUser('user-a');
      authService.currentUserOverride = user;
      authService.profilesByUserId['user-a'] = {
        'display_name': 'Prefilled Name',
        'user_type': null,
        'profile_complete': false,
      };
      authService.emit(AuthState(AuthChangeEvent.signedIn, fakeSession(user)));
      // A bare `await Future.delayed(...)` never resolves inside
      // testWidgets' FakeAsync zone (it intercepts real timers) — this runs
      // the wait in the real zone instead, which is what actually lets
      // AuthProvider's async profile fetch land before the screen mounts.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      await pumpScreen(tester, userId: 'user-a');

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'Prefilled Name');
      expect(field.enabled, isNot(false));
    },
  );
}
