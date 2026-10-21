import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown by [EdgeFunctionsService.usernameAuthSignIn] with enough detail
/// (`status`, `code`) for [AuthService] to reproduce the portal's exact
/// message mapping — see `propcid/supabase/functions/username-auth/index.ts`
/// — instead of collapsing every failure into one generic string the way
/// [EdgeFunctionsService]'s other calls do.
class EdgeFunctionFailure implements Exception {
  final int? status;
  final String? code;
  final String message;

  const EdgeFunctionFailure({required this.message, this.status, this.code});

  @override
  String toString() => message;
}

/// Thin wrapper around the deployed `send-otp` and `username-auth` Supabase
/// Edge Functions.
///
/// Never creates, edits or redeploys a function — this only calls the ones
/// already deployed for the shared backend (same functions the website uses).
class EdgeFunctionsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — surface the server's own message rather than a generic one.
  Future<Map<String, dynamic>> _invoke(
    String function, {
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _supabase.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ??
          'Could not reach the server. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  /// `phoneNumber` must already be E.164 (e.g. `+919876543210`) —
  /// see `Validators.toE164`.
  Future<Map<String, dynamic>> sendOtp(String phoneNumber) =>
      _invoke('send-otp', body: {'action': 'send', 'phoneNumber': phoneNumber});

  /// `channel: 'voice'` asks MSG91 for a voice call retry instead of SMS.
  Future<Map<String, dynamic>> resendOtp(
    String phoneNumber, {
    String channel = 'text',
  }) => _invoke(
    'send-otp',
    body: {'action': 'resend', 'phoneNumber': phoneNumber, 'channel': channel},
  );

  /// Verifies the OTP. Does **not** return a session — see
  /// `AuthService.verifyOtp` for the magic-link exchange that does.
  Future<Map<String, dynamic>> verifyOtp({
    required String phoneNumber,
    required String otp,
    String? name,
  }) => _invoke(
    'send-otp',
    body: {
      'action': 'verify',
      'phoneNumber': phoneNumber,
      'otp': otp,
      if (name != null && name.isNotEmpty) 'name': name,
    },
  );

  /// Calls the `username-auth` Edge Function's `signin` action — the same
  /// endpoint the portal's `SignIn.tsx` uses instead of resolving an email or
  /// username client-side. That RPC (`get_email_by_username`) is revoked from
  /// `anon`/`authenticated` (`20270318020000_harden_definer_functions.sql`),
  /// so this is the only supported way to sign in with a username, and the
  /// only way to sign in with an email that also avoids a second round-trip.
  ///
  /// Returns `{'access_token': ..., 'refresh_token': ...}` on success. On
  /// failure, throws an [EdgeFunctionFailure] carrying the HTTP status and,
  /// for the one case the UI must word differently, `code:
  /// 'email_not_confirmed'` — see `username-auth/index.ts` for the exact
  /// status/body contract this mirrors.
  Future<Map<String, dynamic>> usernameAuthSignIn(
    String identifier,
    String password,
  ) async {
    try {
      final response = await _supabase.functions.invoke(
        'username-auth',
        body: {
          'action': 'signin',
          'identifier': identifier,
          'password': password,
        },
      );
      final data = response.data;
      if (data is Map &&
          data['access_token'] is String &&
          data['refresh_token'] is String) {
        return Map<String, dynamic>.from(data);
      }
      // 2xx but not the shape we expect — treat like the server's own
      // generic invalid-credentials response rather than a network error.
      throw const EdgeFunctionFailure(message: 'Invalid username or password.');
    } on FunctionException catch (e) {
      final details = e.details;
      final serverError = details is Map ? details['error']?.toString() : null;
      throw EdgeFunctionFailure(
        status: e.status,
        code: serverError == 'email_not_confirmed'
            ? 'email_not_confirmed'
            : null,
        message: serverError ?? 'Could not reach the server. Please try again.',
      );
    } on EdgeFunctionFailure {
      rethrow;
    } catch (e) {
      throw const EdgeFunctionFailure(
        message: 'A network error occurred. Please try again.',
      );
    }
  }

  // ── Account deletion (Settings → Delete Account) ─────────────────────────
  //
  // Mirrors the portal's DeleteAccountDialog.tsx exactly — the same two Edge
  // Functions, called the same way. The caller's identity is verified via
  // their JWT server-side; user_id/email/phone are never sent from here.

  /// The phone numbers on this account, so the caller can check whatever the
  /// user re-types matches one of them (or the account email) before
  /// treating them as re-verified.
  Future<List<String>> deleteAccountRequestPhones() async {
    final data = await _invoke(
      'delete-account-request',
      body: const {'action': 'phones'},
    );
    final phones = data['phones'];
    if (phones is! List) return const [];
    return phones.whereType<String>().toList();
  }

  /// Files the `account_deletion_requests` row. Only ever called after the
  /// caller has already re-verified (password re-entry or phone OTP) —
  /// this function itself does not check that, it trusts the caller the
  /// same way the portal's dialog does.
  Future<void> deleteAccountRequestSubmit() => _invoke(
    'delete-account-request',
    body: const {'action': 'submit'},
  );

  /// Signed, 5-minute download URL for a JSON export of everything account
  /// deletion would remove — offered before the deletion flow's confirm
  /// step, same as the portal's "Download my data" button.
  Future<String> exportUserData() async {
    final data = await _invoke('export-user-data', body: const {});
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw 'Failed to generate a download link.';
    }
    return url;
  }
}
