/// One emoji's aggregated reactions on a message.
///
/// Reactions live in `message_reactions` (one row per user per message,
/// keyed by `surface` — `'dm'` or `'channel'` — since the table isn't FK'd
/// to either `messages` or `channel_messages`). This is the client-side
/// aggregate, grouped by emoji, mirroring `MessageReaction` in the portal's
/// features/messaging/lib/messageActions.ts.
class MessageReaction {
  final String emoji;
  final int count;
  final List<String> userIds;

  const MessageReaction({
    required this.emoji,
    required this.count,
    this.userIds = const [],
  });

  bool reactedBy(String userId) => userIds.contains(userId);

  /// Groups raw `message_reactions` rows (each `{emoji, user_id}`) into one
  /// [MessageReaction] per distinct emoji.
  static List<MessageReaction> groupByEmoji(List<Map<String, dynamic>> rows) {
    final byEmoji = <String, List<String>>{};
    for (final row in rows) {
      final emoji = row['emoji'] as String?;
      final userId = row['user_id']?.toString();
      if (emoji == null || userId == null) continue;
      (byEmoji[emoji] ??= []).add(userId);
    }
    return byEmoji.entries
        .map(
          (e) => MessageReaction(
            emoji: e.key,
            count: e.value.length,
            userIds: e.value,
          ),
        )
        .toList();
  }
}
