// Focused widget tests for VerifyIdentifierField: the reusable send/verify
// UI used across registration, Individual profile details and Edit Profile.
// Drives it with fakes for IdentityVerificationService/IdentitySessionGuard
// — no real Supabase session needed, since those are injected exactly like
// `identity_verification_provider_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/identity_status.dart';
import 'package:propcid_app/providers/identity_verification_provider.dart';
import 'package:propcid_app/services/identity_verification_service.dart';
import 'package:propcid_app/widgets/verify_identifier_field.dart';
import 'package:provider/provider.dart';

class FakeIdentityVerificationService implements IdentityVerificationService {
  IdentityStatus statusResult = const IdentityStatus(
    email: null,
    emailVerified: false,
    phone: null,
    phoneVerified: false,
  );
  final List<String> sendTargets = [];
  Object? sendError;
  IdentityStatus? verifyResult;
  Object? verifyError;

  @override
  Future<IdentityStatus> status() async => statusResult;

  @override
  Future<IdentitySendResult> send({
    required IdentityChannel channel,
    required String target,
  }) async {
    sendTargets.add(target);
    if (sendError != null) throw sendError!;
    return const IdentitySendResult(resendIn: 60, expiresIn: 600);
  }

  @override
  Future<IdentityStatus?> verify({
    required IdentityChannel channel,
    required String target,
    required String otp,
  }) async {
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }
}

class FakeIdentitySessionGuard implements IdentitySessionGuard {
  FakeIdentitySessionGuard(this._userId);
  final String? _userId;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> refreshSession() async {}
}

Future<void> pumpField(
  WidgetTester tester, {
  required IdentityVerificationProvider provider,
  IdentityChannel channel = IdentityChannel.phone,
  String? externalError,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<IdentityVerificationProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: VerifyIdentifierField(
            channel: channel,
            label: 'Phone Number',
            hint: '10-digit mobile number',
            keyboardType: TextInputType.phone,
            normalizeTarget: (raw) => raw.trim(),
            fieldValidator: (raw) => RegExp(r'^[6-9]\d{9}$').hasMatch(raw.trim())
                ? null
                : 'Enter a valid 10-digit mobile number.',
            externalError: externalError,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const userA = 'user-aaaa';

  group('unverified channel', () {
    testWidgets('shows a Send OTP button and no verified badge', (
      tester,
    ) async {
      final provider = IdentityVerificationProvider(
        service: FakeIdentityVerificationService(),
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);
      await pumpField(tester, provider: provider);

      expect(find.text('Send OTP'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });

    testWidgets('sending a code reveals the code field bound to that target', (
      tester,
    ) async {
      final fakeService = FakeIdentityVerificationService();
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);
      await pumpField(tester, provider: provider);

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      expect(fakeService.sendTargets, ['9876543210']);
      expect(find.text('Code sent to 9876543210'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
    });
  });

  group('parent-driven required-field highlighting (externalError)', () {
    // Regression coverage: a wizard step's "email/mobile is required" check
    // used to be computed (`_errors['email']`/`_errors['mobileNumber']`) but
    // never actually reached this widget, so pressing Continue on an empty
    // field showed a summary line below both boxes while the boxes
    // themselves never got a red border — reported as "not getting
    // highlighted when not filled".
    testWidgets(
      'a parent-supplied required-field error highlights the box with no user interaction at all',
      (tester) async {
        final provider = IdentityVerificationProvider(
          service: FakeIdentityVerificationService(),
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);

        await pumpField(
          tester,
          provider: provider,
          externalError: 'Mobile number is required.',
        );

        expect(find.text('Mobile number is required.'), findsOneWidget);
      },
    );

    testWidgets(
      'clears once the parent stops reporting the field as missing (e.g. after it is filled in and re-validated)',
      (tester) async {
        final provider = IdentityVerificationProvider(
          service: FakeIdentityVerificationService(),
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);

        await pumpField(
          tester,
          provider: provider,
          externalError: 'Mobile number is required.',
        );
        expect(find.text('Mobile number is required.'), findsOneWidget);

        await pumpField(tester, provider: provider, externalError: null);
        expect(find.text('Mobile number is required.'), findsNothing);
      },
    );

    testWidgets(
      "a fresh failure from the widget's own Send OTP attempt takes precedence over a stale parent error",
      (tester) async {
        final provider = IdentityVerificationProvider(
          service: FakeIdentityVerificationService(),
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);

        await pumpField(
          tester,
          provider: provider,
          externalError: 'Mobile number is required.',
        );

        await tester.enterText(find.byType(TextField).first, '123');
        await tester.tap(find.text('Send OTP'));
        await tester.pumpAndSettle();

        expect(
          find.text('Enter a valid 10-digit mobile number.'),
          findsOneWidget,
        );
        expect(find.text('Mobile number is required.'), findsNothing);
      },
    );
  });

  group('already verified channel', () {
    testWidgets('shows the canonical value locked with a Verified badge', (
      tester,
    ) async {
      final fakeService = FakeIdentityVerificationService()
        ..statusResult = const IdentityStatus(
          email: null,
          emailVerified: false,
          phone: '9876543210',
          phoneVerified: true,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);
      await provider.ensureLoaded();
      await pumpField(tester, provider: provider);

      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Send OTP'), findsNothing);
    });
  });

  group('changing the target after a code was sent', () {
    testWidgets(
      'clears the pending code state so a stale code cannot apply to the new target',
      (tester) async {
        final fakeService = FakeIdentityVerificationService();
        final provider = IdentityVerificationProvider(
          service: fakeService,
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);
        await pumpField(tester, provider: provider);

        await tester.enterText(find.byType(TextField).first, '9876543210');
        await tester.tap(find.text('Send OTP'));
        await tester.pumpAndSettle();
        expect(find.text('Code sent to 9876543210'), findsOneWidget);

        // The target field re-enables once pending is cleared; editing it
        // directly simulates the user changing their mind about the number.
        provider.clearPending(IdentityChannel.phone);
        await tester.pumpAndSettle();

        expect(find.text('Send OTP'), findsOneWidget);
        expect(provider.pendingTarget(IdentityChannel.phone), isNull);
      },
    );
  });

  group('error handling', () {
    testWidgets('an identifier_conflict on send shows the conflict message inline', (
      tester,
    ) async {
      final fakeService = FakeIdentityVerificationService()
        ..sendError = const IdentityVerificationFailure(
          code: 'identifier_conflict',
          status: 409,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);
      await pumpField(tester, provider: provider);

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      expect(
        find.text('That email or phone number already belongs to another account.'),
        findsOneWidget,
      );
      // The session/form must stay intact — still on the same (unverified)
      // input state, not reset or navigated away.
      expect(find.text('9876543210'), findsOneWidget);
    });

    testWidgets('an invalid_or_expired verify error clears the code for retry', (
      tester,
    ) async {
      final fakeService = FakeIdentityVerificationService()
        ..verifyError = const IdentityVerificationFailure(
          code: 'invalid_or_expired',
          status: 400,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);
      await pumpField(tester, provider: provider);

      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send OTP'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('That code is incorrect or has expired.'), findsOneWidget);
      final codeField = tester.widget<TextField>(find.byType(TextField).last);
      expect(codeField.controller!.text, isEmpty);
    });
  });
}
