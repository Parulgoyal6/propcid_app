// Authenticated account deletion — port of DeleteAccountDialog.tsx.
//
// What this pins:
//   * isPhoneAccountEmail matches the portal's isPhoneAccount regex exactly
//     (a phone signup's synthetic u<10digits>@propcid.app email, and nothing
//     that merely looks similar);
//   * the warn step renders the 14-day grace-period copy and both actions;
//   * tapping Continue moves off the warn step without throwing, even with
//     no signed-in user (the state this test environment actually has —
//     there is no way to fake a Supabase session's `currentUser` here, so
//     the richer branches (OTP vs password) aren't exercised by this file).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/screens/profile/account_deletion_screen.dart';

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

  group('isPhoneAccountEmail', () {
    test('matches a phone signup\'s synthetic email', () {
      expect(isPhoneAccountEmail('u9876543210@propcid.app'), isTrue);
      expect(isPhoneAccountEmail('U9876543210@PROPCID.APP'), isTrue);
    });

    test('rejects a real email, null, and near-misses', () {
      expect(isPhoneAccountEmail('someone@example.com'), isFalse);
      expect(isPhoneAccountEmail(null), isFalse);
      expect(isPhoneAccountEmail(''), isFalse);
      // Wrong digit count.
      expect(isPhoneAccountEmail('u987654321@propcid.app'), isFalse);
      // Wrong domain.
      expect(isPhoneAccountEmail('u9876543210@propcid.com'), isFalse);
    });
  });

  group('AccountDeletionScreen', () {
    Future<void> pump(WidgetTester tester) async {
      // The default 800x600 test surface cuts off this screen's Continue/Back
      // row; a tall viewport avoids needing ensureVisible() before every tap.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: AccountDeletionScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('warn step shows the grace-period copy and both actions', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('This action is permanent'), findsOneWidget);
      expect(find.textContaining('14 days after you apply'), findsOneWidget);
      expect(find.text('Download my data'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('Continue moves past the warn step without throwing', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // No signed-in user in this test environment -> _user is null and
      // isPhoneAccountEmail(null) is false, so the password branch renders.
      expect(find.text('Confirm it\'s you'), findsOneWidget);
    });

    testWidgets('Back returns to the warn step', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('This action is permanent'), findsOneWidget);
    });
  });
}
