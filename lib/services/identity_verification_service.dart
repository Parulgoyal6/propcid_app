import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/identity_status.dart';

/// The two identifier channels the backend supports for linking. The wire
/// value is the literal string `email` or `phone` — never send the literal
/// string `email_or_phone`.
enum IdentityChannel {
  email('email'),
  phone('phone');

  const IdentityChannel(this.wireName);
  final String wireName;
}

/// Thrown by [IdentityVerificationService] with the backend's structured
/// error detail intact (HTTP status, the server's `error` code string,
/// `retry_after`, and registration's `missing` list) — modeled on the
/// existing split in `edge_functions_service.dart` between
/// `EdgeFunctionsService._invoke` (which flattens every failure to a bare
/// string) and `EdgeFunctionFailure` (which `usernameAuthSignIn` throws
/// instead, specifically so `AuthService` can reproduce the portal's exact
/// per-code message). `verify-identifier` needs the same treatment: its
/// errors are the server's own `error` field (e.g. `"invalid_target"`,
/// `"rate_limited"`), not a human sentence, and `retry_after`/`missing` must
/// survive to the UI rather than being discarded.
class IdentityVerificationFailure implements Exception {
  const IdentityVerificationFailure({
    required this.code,
    this.status,
    this.retryAfter,
    this.missing,
  });

  /// The server's `error` field verbatim — a snake_case code
  /// (`invalid_target`, `invalid_or_expired`, `identifier_conflict`,
  /// `rate_limited`, `provider_unavailable`, `identity_not_verified`) for a
  /// handled failure, or a raw sentence (`"Not authenticated."`,
  /// `"Invalid request body."`) for the handful of cases the backend never
  /// gave a machine code.
  final String code;
  final int? status;
  final int? retryAfter;
  final List<String>? missing;

  /// Portal-equivalent copy for the documented error table (see
  /// `docs/PropCID_Flutter_Auth_Implementation_Plan.md` section 5's "Error
  /// handling"). Field-level errors (`invalid_target`,
  /// `invalid_or_expired`) are intentionally generic here — the caller
  /// still has the raw [code] to attach a more specific inline message to
  /// the actual field if it chooses to.
  String get userMessage {
    switch (code) {
      case 'invalid_target':
        return 'Enter a valid email address or a 10-digit Indian mobile number.';
      case 'invalid_or_expired':
        return 'That code is incorrect or has expired.';
      case 'identifier_conflict':
        return 'That email or phone number already belongs to another account.';
      case 'rate_limited':
        return 'Too many attempts. Please wait before trying again.';
      case 'provider_unavailable':
        return 'Delivery service is temporarily unavailable. Please try again.';
      case 'identity_not_verified':
        return 'Please verify your email and phone number first.';
    }
    if (status == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  String toString() => userMessage;
}

/// Thin client for the authenticated `verify-identifier` Edge Function —
/// links a second login identifier (email or phone) to the CURRENT
/// signed-in user. The caller is always identified from the Supabase
/// session JWT; this never sends a `user_id` field, matching the backend's
/// `getCaller(req)` contract.
///
/// Deliberately a separate file from [EdgeFunctionsService]: that service's
/// `_invoke` collapses every failure into a bare `String`, discarding the
/// status/code/retry_after/missing detail this contract depends on.
class IdentityVerificationService {
  IdentityVerificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _function = 'verify-identifier';

  Future<IdentityStatus> status() async {
    final data = await _invoke({'action': 'status'});
    return IdentityStatus.fromJson(data);
  }

  /// Sends a verification code to [target] over [channel]. Returns the
  /// server's own resend/expiry timings — never assume a fixed cooldown;
  /// an hourly rate-limit window must not be rendered as a flat 60-second
  /// wait. Call this again (not a separate action) to resend.
  Future<IdentitySendResult> send({
    required IdentityChannel channel,
    required String target,
  }) async {
    final data = await _invoke({
      'action': 'send',
      'channel': channel.wireName,
      'target': target,
    });
    final resendIn = data['resend_in'];
    final expiresIn = data['expires_in'];
    return IdentitySendResult(
      resendIn: resendIn is int ? resendIn : null,
      expiresIn: expiresIn is int ? expiresIn : null,
    );
  }

  /// Verifies [otp] for the exact [target] it was sent to. The returned
  /// [IdentityStatus] is the server's canonical post-verify state when
  /// present; `null` means the server's own status refetch failed
  /// server-side (per the documented contract) and the caller must re-fetch
  /// [status] itself rather than assume both identifiers are now verified.
  Future<IdentityStatus?> verify({
    required IdentityChannel channel,
    required String target,
    required String otp,
  }) async {
    final data = await _invoke({
      'action': 'verify',
      'channel': channel.wireName,
      'target': target,
      'otp': otp,
    });
    final status = data['status'];
    if (status is Map) {
      return IdentityStatus.fromJson(Map<String, dynamic>.from(status));
    }
    return null;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(_function, body: body);
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    } on FunctionException catch (e) {
      final details = e.details;
      final errorBody = details is Map ? details : const {};
      final retryAfter = errorBody['retry_after'];
      final missing = errorBody['missing'];
      throw IdentityVerificationFailure(
        status: e.status,
        code: errorBody['error']?.toString() ?? 'unknown_error',
        retryAfter: retryAfter is int ? retryAfter : null,
        missing: missing is List
            ? missing.whereType<String>().toList()
            : null,
      );
    } on FormatException {
      rethrow;
    } on IdentityVerificationFailure {
      rethrow;
    } catch (_) {
      throw const IdentityVerificationFailure(code: 'network_error');
    }
  }
}

/// Server-provided timing for a just-sent code — drives the resend
/// countdown and (informationally) how long the code stays valid.
class IdentitySendResult {
  const IdentitySendResult({this.resendIn, this.expiresIn});

  final int? resendIn;
  final int? expiresIn;
}
