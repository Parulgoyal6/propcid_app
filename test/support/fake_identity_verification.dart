import 'package:propcid_app/models/identity_status.dart';
import 'package:propcid_app/providers/identity_verification_provider.dart';
import 'package:propcid_app/services/identity_verification_service.dart';

/// Shared fake for `verify-identifier` calls — no real Supabase Edge
/// Function involved. [statusFuture], when set, lets a test control exactly
/// when `.status()` resolves (e.g. an uncompleted `Completer`'s future),
/// which is what makes the two draft-vs-status loading orders in
/// `draft_reconciliation_test.dart` deterministic rather than racy.
class FakeIdentityVerificationService implements IdentityVerificationService {
  IdentityStatus statusResult = const IdentityStatus(
    email: null,
    emailVerified: false,
    phone: null,
    phoneVerified: false,
  );
  Future<IdentityStatus>? statusFuture;
  int statusCalls = 0;

  IdentitySendResult sendResult = const IdentitySendResult(
    resendIn: 60,
    expiresIn: 600,
  );
  Object? sendError;
  final List<String> sendTargets = [];

  IdentityStatus? verifyResult;
  Object? verifyError;

  @override
  Future<IdentityStatus> status() async {
    statusCalls += 1;
    final future = statusFuture;
    if (future != null) return future;
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
