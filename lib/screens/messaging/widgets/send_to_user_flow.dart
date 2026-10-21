import 'package:flutter/material.dart';

import '../../../services/messaging_service.dart';
import 'new_chat_sheet.dart';

/// "Send to a user" — the picker + send flow behind the button on the
/// property/reel share sheets.
///
/// Mirrors the portal's `SendToUserModal` + `ShareToSocial.tsx`'s
/// `handleSendToUser`/`onSend` wiring: pick a recipient (reusing
/// [showNewChatSheet], the same search-by-name picker `new_chat_sheet.dart`
/// already uses for "Start New Chat"), start or reuse a request-gated DM with
/// them (`MessagingService.startConversation`'s own default —
/// `skipRequestGate: false`, matching `SendToUserModal.handleSelect`'s
/// explicit `false`), then hand the resulting conversation id to [onSend] to
/// insert the actual share message.
///
/// On success this closes [context]'s current sheet, matching the portal's
/// `onOpenChange(false)` call inside its own `onSend` — the picker itself has
/// already closed by then (unlike the portal's modal, which stays open with a
/// per-row spinner until the send completes).
Future<void> runSendToUserFlow(
  BuildContext context, {
  required String currentUserId,
  required Future<void> Function(String conversationId) onSend,
}) async {
  final recipient = await showNewChatSheet(context, currentUserId);
  if (recipient == null || !context.mounted) return;

  try {
    final conversationId = await MessagingService().startConversation(
      recipient.userId,
    );
    await onSend(conversationId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Sent to ${recipient.displayName}')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to send. Please try again.')),
    );
  }
}
