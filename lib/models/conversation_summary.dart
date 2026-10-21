/// The other person in a 1:1 conversation.
///
/// Resolved from the `profiles_public` view, which is what
/// features/messaging/ChatModal.tsx reads — not the `profiles` table.
class ConversationParticipant {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeenAt;

  const ConversationParticipant({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeenAt,
  });

  /// Single-letter avatar fallback, matching how the rest of the app derives
  /// initials.
  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

  /// `is_online` alone is not trustworthy — a client can vanish without ever
  /// flipping it back to false (closed tab, killed app, dead connection).
  /// Mirrors the portal's `isEffectivelyOnline` in src/utils/presence.ts:
  /// only trust the flag while `last_seen_at` is fresher than 90s, with a
  /// 10s allowance for clock skew putting it slightly in the future.
  bool get isEffectivelyOnline {
    if (!isOnline || lastSeenAt == null) return false;
    final age = DateTime.now().difference(lastSeenAt!);
    return age > const Duration(seconds: -10) &&
        age < const Duration(seconds: 90);
  }

  ConversationParticipant copyWith({bool? isOnline, DateTime? lastSeenAt}) {
    return ConversationParticipant(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

/// One row in the Messages → Chats list.
class ConversationSummary {
  final String id;
  final DateTime? lastMessageAt;

  /// Null when the other participant's profile could not be resolved — React
  /// leaves `other_participant` undefined in that case rather than inventing
  /// a name.
  final ConversationParticipant? otherParticipant;

  /// Body of the most recent message, or empty when the conversation has none.
  final String lastMessage;

  final int unreadCount;

  /// The signed-in user's own `conversation_participants.request_status`.
  /// `'pending'` means this is an unaccepted message request — the composer
  /// is replaced by an Accept/Decline banner until it flips to `'accepted'`.
  final String requestStatus;

  /// The signed-in user's own `conversation_participants.muted_at` — whether
  /// *this* device's user has muted notifications for the conversation.
  final bool isMuted;

  /// Set only when this thread backs a Collaboration Marketplace deal — see
  /// `useCollabState.ts`'s `DmConversation.collaboration_id`. Null for every
  /// ordinary DM.
  final String? collaborationId;

  const ConversationSummary({
    required this.id,
    this.lastMessageAt,
    this.otherParticipant,
    this.lastMessage = '',
    this.unreadCount = 0,
    this.requestStatus = 'accepted',
    this.isMuted = false,
    this.collaborationId,
  });

  bool get isPendingRequest => requestStatus == 'pending';
  bool get isCollaboration => collaborationId != null;

  String get title => otherParticipant?.displayName ?? 'Unknown';

  ConversationSummary copyWith({
    int? unreadCount,
    String? requestStatus,
    bool? isMuted,
    ConversationParticipant? otherParticipant,
  }) {
    return ConversationSummary(
      id: id,
      lastMessageAt: lastMessageAt,
      otherParticipant: otherParticipant ?? this.otherParticipant,
      lastMessage: lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      requestStatus: requestStatus ?? this.requestStatus,
      isMuted: isMuted ?? this.isMuted,
      collaborationId: collaborationId,
    );
  }
}
