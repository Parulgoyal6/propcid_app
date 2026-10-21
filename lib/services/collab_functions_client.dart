// services/collab_functions_client.dart
//
// Centralized authenticated Edge Function invocation for the Collaboration
// Marketplace. Replaces CollaborationService's previous ad-hoc `_invoke` and
// is the single call path for every collab Edge Function this app calls:
// `collab-agreement`, `collab-create-order`, `verify-payment` (collaboration
// context only — the subscription checkout's own `PaymentService.verifyPayment`
// is untouched), `collab-sample-view`, `collab-deliverable-url`,
// `collab-dispute`, `download-collab-invoice`.
//
// Contract:
//   1. Uses only `Supabase.instance.client` (or an injected client in tests).
//   2. Requires `auth.currentUser` and a real current session before ever
//      calling the network.
//   3. Resolves/refreshes an expired session before invocation.
//   4. Sends the latest bearer access token explicitly as the Authorization
//      header, rather than trusting whatever the client's own internal state
//      last cached.
//   5. Every call is bounded by a timeout.
//   6. If — and only if — the FIRST response is HTTP 401, the session is
//      refreshed and the call retried exactly once with the new token.
//      Any other failure (network, 4xx/5xx, timeout) is surfaced as-is and
//      never blindly retried — a payment or dispute call must not silently
//      fire twice.
//   7. Debug logging never includes tokens, signatures, request bodies,
//      secrets, email or phone — only the function name, response status,
//      a short user-id prefix, whether a session exists, its expiry, and the
//      retry count.
//   8. The server's own error text and HTTP status reach the caller intact.
//   9. No usable session -> a clear, user-facing "Your session expired.
//      Please sign in again." error, before any network call is attempted.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A collaboration Function call was refused or could not be made — the
/// message is always safe to show the user as-is (either the server's own
/// text, or one of this file's own user-appropriate copies).
class CollabAuthException implements Exception {
  final String message;

  /// The HTTP status the server actually returned, when known — preserved so
  /// the UI can tell a validation refusal (4xx, server text is authoritative)
  /// from a transient failure (5xx/timeout/network) if it ever needs to.
  final int? statusCode;

  const CollabAuthException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Internal signal that the first attempt came back 401 — caught only inside
/// [CollabFunctionsClient.invoke], never surfaced to a caller.
class _Unauthorized implements Exception {
  const _Unauthorized();
}

class CollabFunctionsClient {
  CollabFunctionsClient({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const Duration timeout = Duration(seconds: 40);

  void _log(String message) {
    if (kDebugMode) debugPrint('[collab-auth] $message');
  }

  String _idPrefix(String id) => id.length <= 8 ? id : id.substring(0, 8);

  /// Invokes [function] with [body], fully authenticated. Throws
  /// [CollabAuthException] on any failure — including "no usable session",
  /// which never reaches the network at all.
  Future<Map<String, dynamic>> invoke(
    String function, {
    Map<String, dynamic> body = const {},
  }) async {
    final user = _supabase.auth.currentUser;
    var session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      throw const CollabAuthException(
        'Your session expired. Please sign in again.',
      );
    }

    // Refresh a session that is already stale before spending the single
    // 401-retry on a token we already knew was bad.
    if (session.isExpired) {
      session = await _tryRefresh();
      if (session == null) {
        throw const CollabAuthException(
          'Your session expired. Please sign in again.',
        );
      }
    }

    _log(
      'invoke $function hasSession=true userId=${_idPrefix(user.id)} '
      'expiresAt=${session.expiresAt} retry=0',
    );

    try {
      return await _call(function, body: body, token: session.accessToken);
    } on _Unauthorized {
      final refreshed = await _tryRefresh();
      if (refreshed == null) {
        throw const CollabAuthException(
          'Your session expired. Please sign in again.',
        );
      }
      _log(
        'invoke $function retrying after 401 userId=${_idPrefix(user.id)} '
        'expiresAt=${refreshed.expiresAt} retry=1',
      );
      return await _call(function, body: body, token: refreshed.accessToken);
    }
  }

  Future<Session?> _tryRefresh() async {
    try {
      final response = await _supabase.auth.refreshSession();
      return response.session;
    } catch (e) {
      _log('session refresh failed: ${e.runtimeType}');
      return null;
    }
  }

  Future<Map<String, dynamic>> _call(
    String function, {
    required Map<String, dynamic> body,
    required String token,
  }) async {
    try {
      final response = await _supabase.functions
          .invoke(
            function,
            body: body,
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(timeout);
      _log('$function -> status=${response.status}');

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw CollabAuthException(
          data['error'].toString(),
          statusCode: response.status,
        );
      }
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    } on FunctionException catch (e) {
      _log('$function -> FunctionException status=${e.status}');
      if (e.status == 401) throw const _Unauthorized();
      final details = e.details;
      final message = details is Map ? details['error'] : null;
      throw CollabAuthException(
        message?.toString() ?? 'Could not reach the server. Please try again.',
        statusCode: e.status,
      );
    } on TimeoutException {
      _log('$function -> timed out');
      throw const CollabAuthException(
        'The server took too long to respond. Please try again.',
      );
    } on CollabAuthException {
      rethrow;
    } catch (e) {
      _log('$function -> threw ${e.runtimeType}');
      throw const CollabAuthException(
        'A network error occurred. Please try again.',
      );
    }
  }
}
