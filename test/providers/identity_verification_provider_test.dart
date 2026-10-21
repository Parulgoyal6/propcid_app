// Focused tests for IdentityVerificationProvider — the Phase 1
// identity-linking state holder. Covers the explicit checks called out for
// this feature: linking in both directions, the signed-in user id staying
// unchanged across a verify, identifier conflicts, and stale responses
// after an account switch being discarded rather than applied to the wrong
// account.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/identity_status.dart';
import 'package:propcid_app/providers/identity_verification_provider.dart';
import 'package:propcid_app/services/identity_verification_service.dart';

/// In-memory fake standing in for the real `verify-identifier` HTTP calls —
/// production always uses [IdentityVerificationService] against the real
/// Supabase client; this drives the same public contract deterministically.
class FakeIdentityVerificationService implements IdentityVerificationService {
  IdentityStatus statusResult = const IdentityStatus(
    email: null,
    emailVerified: false,
    phone: null,
    phoneVerified: false,
  );
  Object? statusError;
  int statusCalls = 0;

  IdentitySendResult sendResult = const IdentitySendResult(
    resendIn: 60,
    expiresIn: 600,
  );
  Object? sendError;
  final List<String> sendTargets = [];

  /// When set, returned as-is from [verify]. When left `null` and
  /// [verifyError] is also `null`, [verify] returns `null` — simulating the
  /// documented "status can be absent if its final lookup fails" case.
  IdentityStatus? verifyResult;
  Object? verifyError;

  /// Lets a test delay [verify]'s resolution to exercise an account-switch
  /// race — the provider must discard this response if the user changed
  /// before it resolves.
  Future<void>? verifyDelay;

  @override
  Future<IdentityStatus> status() async {
    statusCalls += 1;
    if (statusError != null) throw statusError!;
    return statusResult;
  }

  @override
  Future<IdentitySendResult> send({
    required IdentityChannel channel,
    required String target,
  }) async {
    sendTargets.add(target);
    if (sendError != null) throw sendError!;
    return sendResult;
  }

  @override
  Future<IdentityStatus?> verify({
    required IdentityChannel channel,
    required String target,
    required String otp,
  }) async {
    if (verifyDelay != null) await verifyDelay;
    if (verifyError != null) throw verifyError!;
    return verifyResult;
  }
}

class FakeIdentitySessionGuard implements IdentitySessionGuard {
  FakeIdentitySessionGuard(this._userId);

  String? _userId;
  int refreshCalls = 0;
  bool throwOnRefresh = false;

  /// Simulates the signed-in account changing exactly when
  /// [refreshSession] is called (e.g. a concurrent logout/login landing
  /// mid-request).
  String? switchUserIdOnRefresh;

  @override
  String? get currentUserId => _userId;

  @override
  Future<void> refreshSession() async {
    refreshCalls += 1;
    if (switchUserIdOnRefresh != null) _userId = switchUserIdOnRefresh;
    if (throwOnRefresh) throw Exception('refresh failed');
  }
}

void main() {
  const userA = 'user-aaaa';
  const userB = 'user-bbbb';

  group('syncUser', () {
    test('resets cached state when the user id changes', () {
      final provider = IdentityVerificationProvider(
        service: FakeIdentityVerificationService(),
        sessionGuard: FakeIdentitySessionGuard(userA),
      );
      provider.syncUser(userA);
      expect(provider.userId, userA);

      provider.syncUser(userB);
      expect(provider.userId, userB);
      expect(provider.status, isNull);
      expect(provider.loadError, isNull);
    });

    test('is a no-op for a repeated call with the same user id', () async {
      final fakeService = FakeIdentityVerificationService()
        ..statusResult = const IdentityStatus(
          email: 'a@example.com',
          emailVerified: true,
          phone: null,
          phoneVerified: false,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      );
      provider.syncUser(userA);
      await provider.ensureLoaded();
      expect(provider.status, isNotNull);

      provider.syncUser(userA); // same id again
      expect(provider.status, isNotNull, reason: 'must not reset on no-op sync');
    });

    test('resets to signed-out (null) and clears status', () async {
      final fakeService = FakeIdentityVerificationService();
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      );
      provider.syncUser(userA);
      await provider.ensureLoaded();

      provider.syncUser(null);
      expect(provider.userId, isNull);
      expect(provider.status, isNull);
    });
  });

  group('linking in both directions', () {
    test('mobile-first: verifying email adopts the canonical status', () async {
      final fakeService = FakeIdentityVerificationService()
        ..verifyResult = const IdentityStatus(
          email: 'real@example.com',
          emailVerified: true,
          phone: '9876543210',
          phoneVerified: true,
        );
      final guard = FakeIdentitySessionGuard(userA);
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: guard,
      )..syncUser(userA);

      await provider.sendCode(
        channel: IdentityChannel.email,
        target: 'real@example.com',
      );
      expect(provider.pendingTarget(IdentityChannel.email), 'real@example.com');

      await provider.verifyCode(
        channel: IdentityChannel.email,
        target: 'real@example.com',
        otp: '123456',
      );

      expect(provider.status?.emailVerified, isTrue);
      expect(provider.status?.phoneVerified, isTrue);
      expect(provider.pendingTarget(IdentityChannel.email), isNull);
      expect(guard.refreshCalls, 1);
    });

    test('email-first: verifying phone adopts the canonical status', () async {
      final fakeService = FakeIdentityVerificationService()
        ..verifyResult = const IdentityStatus(
          email: 'real@example.com',
          emailVerified: true,
          phone: '9876543210',
          phoneVerified: true,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);

      await provider.sendCode(
        channel: IdentityChannel.phone,
        target: '9876543210',
      );
      await provider.verifyCode(
        channel: IdentityChannel.phone,
        target: '9876543210',
        otp: '654321',
      );

      expect(provider.status?.phoneVerified, isTrue);
      expect(provider.status?.emailVerified, isTrue);
    });

    test(
      'an absent inline status after verify triggers a status re-fetch rather than assuming success',
      () async {
        final fakeService = FakeIdentityVerificationService()
          ..verifyResult = null // server's own status refetch failed
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

        await provider.verifyCode(
          channel: IdentityChannel.phone,
          target: '9876543210',
          otp: '111111',
        );

        expect(fakeService.statusCalls, 1);
        expect(provider.status?.phoneVerified, isTrue);
      },
    );
  });

  group('the signed-in user id must not change across a verify', () {
    test(
      'a verify result is discarded if the account changed during the request',
      () async {
        final fakeService = FakeIdentityVerificationService()
          ..verifyResult = const IdentityStatus(
            email: 'real@example.com',
            emailVerified: true,
            phone: null,
            phoneVerified: false,
          );
        final guard = FakeIdentitySessionGuard(userA)
          ..switchUserIdOnRefresh = userB;
        final provider = IdentityVerificationProvider(
          service: fakeService,
          sessionGuard: guard,
        )..syncUser(userA);

        await provider.verifyCode(
          channel: IdentityChannel.email,
          target: 'real@example.com',
          otp: '123456',
        );

        // The account changed mid-request (simulated via the session guard)
        // — this verification must never be applied.
        expect(provider.status, isNull);
      },
    );

    test('a session-refresh failure does not fail the verification itself', () async {
      final fakeService = FakeIdentityVerificationService()
        ..verifyResult = const IdentityStatus(
          email: 'real@example.com',
          emailVerified: true,
          phone: null,
          phoneVerified: false,
        );
      final guard = FakeIdentitySessionGuard(userA)..throwOnRefresh = true;
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: guard,
      )..syncUser(userA);

      await provider.verifyCode(
        channel: IdentityChannel.email,
        target: 'real@example.com',
        otp: '123456',
      );

      expect(provider.status?.emailVerified, isTrue);
    });
  });

  group('identifier conflicts', () {
    test('sendCode throws identifier_conflict and leaves no pending target', () async {
      final fakeService = FakeIdentityVerificationService()
        ..sendError = const IdentityVerificationFailure(
          code: 'identifier_conflict',
          status: 409,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);

      await expectLater(
        provider.sendCode(
          channel: IdentityChannel.phone,
          target: '9876543210',
        ),
        throwsA(
          isA<IdentityVerificationFailure>().having(
            (e) => e.code,
            'code',
            'identifier_conflict',
          ),
        ),
      );
      expect(provider.pendingTarget(IdentityChannel.phone), isNull);
    });

    test('verifyCode surfaces identifier_conflict without touching status', () async {
      final fakeService = FakeIdentityVerificationService()
        ..verifyError = const IdentityVerificationFailure(
          code: 'identifier_conflict',
          status: 409,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);

      await expectLater(
        provider.verifyCode(
          channel: IdentityChannel.phone,
          target: '9876543210',
          otp: '123456',
        ),
        throwsA(isA<IdentityVerificationFailure>()),
      );
      expect(provider.status, isNull);
    });

    test('rate_limited preserves retry_after on the failure', () async {
      final fakeService = FakeIdentityVerificationService()
        ..sendError = const IdentityVerificationFailure(
          code: 'rate_limited',
          status: 429,
          retryAfter: 3600,
        );
      final provider = IdentityVerificationProvider(
        service: fakeService,
        sessionGuard: FakeIdentitySessionGuard(userA),
      )..syncUser(userA);

      try {
        await provider.sendCode(
          channel: IdentityChannel.email,
          target: 'a@example.com',
        );
        fail('expected IdentityVerificationFailure');
      } on IdentityVerificationFailure catch (e) {
        expect(e.retryAfter, 3600);
      }
    });
  });

  group('stale responses after account switching', () {
    test(
      'a slow verify for the previous user is discarded once a new user is synced in',
      () async {
        final fakeService = FakeIdentityVerificationService()
          ..verifyResult = const IdentityStatus(
            email: 'a-account@example.com',
            emailVerified: true,
            phone: null,
            phoneVerified: false,
          )
          ..verifyDelay = Future<void>.delayed(const Duration(milliseconds: 30));
        final provider = IdentityVerificationProvider(
          service: fakeService,
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);

        final pending = provider.verifyCode(
          channel: IdentityChannel.email,
          target: 'a-account@example.com',
          otp: '123456',
        );

        // Account B signs in before A's slow verify resolves.
        provider.syncUser(userB);
        await pending;

        expect(
          provider.status,
          isNull,
          reason: "account A's late verification must never apply to B",
        );
        expect(provider.userId, userB);
      },
    );

    test(
      'a slow status load for the previous user is discarded once a new user is synced in',
      () async {
        final fakeService = FakeIdentityVerificationService();
        final provider = IdentityVerificationProvider(
          service: fakeService,
          sessionGuard: FakeIdentitySessionGuard(userA),
        )..syncUser(userA);

        fakeService.statusResult = const IdentityStatus(
          email: 'a-account@example.com',
          emailVerified: true,
          phone: null,
          phoneVerified: false,
        );
        final pending = provider.ensureLoaded();
        provider.syncUser(userB);
        await pending;

        expect(provider.status, isNull);
        expect(provider.userId, userB);
      },
    );
  });
}
