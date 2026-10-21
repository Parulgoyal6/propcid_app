// Regression guard for the Settings "Change Password" fix: the Settings
// sheet previously had no password capability at all (KNOWN gap per the
// portal's own `ChangePasswordSection.tsx`). Exercises both modes —
// "Change Password" (an email/password account, current password must be
// re-verified first) and "Set Password" (a social-only account, no current
// password to verify) — against `FakeAuthService`, never a live Supabase
// client.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/screens/profile/actions/change_password_screen.dart';

import 'support/fake_auth_service.dart';

User _socialOnlyUser(String id, {String? email}) => User(
  id: id,
  appMetadata: const {
    'providers': ['google'],
  },
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2024-01-01T00:00:00Z',
  email: email,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  group('ChangePasswordScreen — email/password account', () {
    testWidgets('shows "Change Password" and the current-password field', (
      tester,
    ) async {
      final service = FakeAuthService()
        ..currentUserOverride = fakeUser('u-1', email: 'a@b.com');
      await _pump(tester, ChangePasswordScreen(authService: service));

      expect(find.text('Change Password'), findsWidgets);
      expect(find.text('Current Password'), findsOneWidget);
    });

    testWidgets(
      'a wrong current password blocks the update and shows a truthful '
      'error, without ever calling updatePassword',
      (tester) async {
        final service = FakeAuthService()
          ..currentUserOverride = fakeUser('u-1', email: 'a@b.com')
          ..nextLoginError = 'Invalid login credentials';
        await _pump(tester, ChangePasswordScreen(authService: service));

        await tester.enterText(
          find.widgetWithText(TextField, 'Current Password'),
          'wrong-password',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'New Password'),
          'newpass123',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Confirm New Password'),
          'newpass123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
        await tester.pumpAndSettle();

        expect(find.text('Current password is incorrect.'), findsOneWidget);
        expect(service.loginCalls, ['a@b.com']);
      },
    );

    testWidgets(
      'matching new/confirm with a correct current password updates '
      'successfully',
      (tester) async {
        final service = FakeAuthService()
          ..currentUserOverride = fakeUser('u-1', email: 'a@b.com');
        await _pump(tester, ChangePasswordScreen(authService: service));

        await tester.enterText(
          find.widgetWithText(TextField, 'Current Password'),
          'correct-password',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'New Password'),
          'newpass123',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Confirm New Password'),
          'newpass123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
        await tester.pumpAndSettle();

        expect(find.text('Password updated successfully.'), findsOneWidget);
        expect(service.loginCalls, ['a@b.com']);
      },
    );

    testWidgets('mismatched new/confirm is refused before any network call', (
      tester,
    ) async {
      final service = FakeAuthService()
        ..currentUserOverride = fakeUser('u-1', email: 'a@b.com');
      await _pump(tester, ChangePasswordScreen(authService: service));

      await tester.enterText(
        find.widgetWithText(TextField, 'Current Password'),
        'correct-password',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'New Password'),
        'newpass123',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm New Password'),
        'different456',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Change Password'));
      await tester.pumpAndSettle();

      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(service.loginCalls, isEmpty);
    });
  });

  group('ChangePasswordScreen — social-only account', () {
    testWidgets(
      'shows "Set Password" with no current-password field, and never '
      'calls login',
      (tester) async {
        final service = FakeAuthService()
          ..currentUserOverride = _socialOnlyUser('u-1', email: 'a@b.com');
        await _pump(tester, ChangePasswordScreen(authService: service));

        expect(find.text('Set Password'), findsWidgets);
        expect(find.text('Current Password'), findsNothing);

        await tester.enterText(
          find.widgetWithText(TextField, 'New Password'),
          'newpass123',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Confirm New Password'),
          'newpass123',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Set Password'));
        await tester.pumpAndSettle();

        expect(find.text('Password set successfully.'), findsOneWidget);
        expect(service.loginCalls, isEmpty);
      },
    );
  });
}
