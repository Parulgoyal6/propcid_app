/// A send/action was refused by the backend for a reason the user should be
/// told about (rate limit, blocked, request-gated) — as opposed to a network
/// failure, which gets a generic retry message.
///
/// Mirrors the portal's `MessageSendDeniedError` in
/// features/messaging/lib/useDmMessaging.ts.
class MessageSendDeniedError implements Exception {
  final String message;
  const MessageSendDeniedError(this.message);
  @override
  String toString() => message;
}

/// The `moderate-comment` edge function explicitly rejected the text.
/// Mirrors the portal's `MessageModerationError`.
class MessageModerationError implements Exception {
  final String message;
  const MessageModerationError(this.message);
  @override
  String toString() => message;
}

/// Client-side upload validation failed (wrong mime, too large, too long).
/// Mirrors the portal's `ChatMediaValidationError` in
/// features/messaging/lib/uploadChatMedia.ts.
class ChatMediaValidationError implements Exception {
  final String message;
  const ChatMediaValidationError(this.message);
  @override
  String toString() => message;
}

/// A channel-admin action (settings update, add/remove/block member) was
/// refused. The message comes straight from the edge function, which
/// re-verifies the caller's real role/permissions server-side rather than
/// trusting the client — mirrors `ChannelSettingsModal.tsx`'s
/// `EdgeFunctionError` handling.
class ChannelAdminError implements Exception {
  final String message;
  const ChannelAdminError(this.message);
  @override
  String toString() => message;
}

/// Maps a raw Postgres/PostgREST error (rate-limit trigger, RLS block) to the
/// exact user-facing copy the portal uses. `error` is whatever
/// `PostgrestException`/generic exception was thrown by the insert.
///
/// Matches on the *exact* message text for the rate-limit case, not just the
/// `P0001` code — every RPC in this module also raises bare `P0001` for
/// unrelated reasons (`'Not authenticated'`, `'Invalid surface'`, …).
Exception mapSendError(Object error) {
  final message = error.toString();
  final code = postgrestErrorCode(error);

  if (code == 'P0001' && message.contains('sending messages too quickly')) {
    return const MessageSendDeniedError(
      'You are sending messages too quickly. Please slow down.',
    );
  }
  if (code == '42501') {
    return const MessageSendDeniedError('This message could not be delivered.');
  }
  return Exception(message);
}

String? postgrestErrorCode(Object error) {
  try {
    // PostgrestException (supabase_flutter) exposes a `code` getter without
    // requiring an import here — read it dynamically so this file has no
    // hard dependency on the exact exception type.
    final dynamic e = error;
    return e.code as String?;
  } catch (_) {
    return null;
  }
}

/// A short, human-readable "what actually went wrong" string for an action
/// that isn't expected to fail often (block/report/mute/etc.) — as opposed to
/// [mapSendError], which maps *known* send-path failures to fixed copy. Used
/// to make an otherwise-generic "couldn't do X" snackbar diagnosable: a
/// Postgres error code like `42501` (RLS denied) or `42P01` (missing table —
/// e.g. a migration not yet applied on this environment) tells you exactly
/// what to check, where a bare "something went wrong" doesn't.
String describeError(Object error) {
  final code = postgrestErrorCode(error);
  String? message;
  try {
    final dynamic e = error;
    message = e.message as String?;
  } catch (_) {
    message = null;
  }
  final text = message ?? error.toString();
  return code == null ? text : '$code: $text';
}
