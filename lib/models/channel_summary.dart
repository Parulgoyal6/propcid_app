/// One row in the Messages → Channels list.
///
/// Mirrors what features/messaging/ChannelsList.tsx assembles: the channel
/// row, the caller's own participant role, the participant count and the
/// timestamp of the most recent message.
class ChannelSummary {
  final String id;
  final String name;
  final String? description;
  final String? createdBy;
  final int? maxParticipants;

  /// The signed-in user's role in this channel (`admin`, `moderator`,
  /// `member`, …) from `channel_participants.role`.
  final String? myRole;

  final int participantCount;
  final DateTime? lastMessageAt;
  final int unreadCount;

  /// The signed-in user's own `channel_participants.muted_at`.
  final bool isMuted;

  /// `channels.created_at` — the row is always selected with this column
  /// (`MessagingService.listChannels`), but it went unused until the list's
  /// own sort needed a "most recent activity" fallback for a channel with no
  /// messages yet (see that method's own sort comparator).
  final DateTime? createdAt;

  const ChannelSummary({
    required this.id,
    required this.name,
    this.description,
    this.createdBy,
    this.maxParticipants,
    this.myRole,
    this.participantCount = 0,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.isMuted = false,
    this.createdAt,
  });

  factory ChannelSummary.fromSupabase(
    Map<String, dynamic> json, {
    String? myRole,
    int participantCount = 0,
    DateTime? lastMessageAt,
    int unreadCount = 0,
    bool isMuted = false,
  }) {
    final id = json['id']?.toString();
    if (id == null) {
      throw ArgumentError('ChannelSummary.fromSupabase: row has no id');
    }
    return ChannelSummary(
      id: id,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Untitled channel',
      description: json['description'] as String?,
      createdBy: json['created_by']?.toString(),
      maxParticipants: (json['max_participants'] as num?)?.toInt(),
      myRole: myRole,
      participantCount: participantCount,
      lastMessageAt: lastMessageAt,
      unreadCount: unreadCount,
      isMuted: isMuted,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  bool get isAdmin => myRole?.toLowerCase() == 'admin';
  bool get isModerator => myRole?.toLowerCase() == 'moderator';
  bool get canModerate => isAdmin || isModerator;

  /// Two-letter avatar fallback from the channel name.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '#';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }
}

/// One row from the `channel-participants-list` edge function — a channel
/// member plus their admin-moderation state, for [ChannelSettingsScreen]'s
/// Members tab. Mirrors `ChannelSettingsModal.tsx`'s `Participant` interface.
class ChannelParticipantDetail {
  final String id;
  final String userId;
  final String role;
  final DateTime? joinedAt;
  final DateTime? blockedAt;
  final String displayName;
  final String? avatarUrl;

  const ChannelParticipantDetail({
    required this.id,
    required this.userId,
    required this.role,
    this.joinedAt,
    this.blockedAt,
    required this.displayName,
    this.avatarUrl,
  });

  factory ChannelParticipantDetail.fromJson(Map<String, dynamic> json) {
    final profile = json['user_profile'] as Map<String, dynamic>?;
    final name = (profile?['display_name'] as String?)?.trim();
    return ChannelParticipantDetail(
      id: json['id'].toString(),
      userId: json['user_id'].toString(),
      role: (json['role'] as String?) ?? 'member',
      joinedAt: DateTime.tryParse(json['joined_at']?.toString() ?? ''),
      blockedAt: json['blocked_at'] == null
          ? null
          : DateTime.tryParse(json['blocked_at'].toString()),
      displayName: (name?.isNotEmpty ?? false) ? name! : 'Unknown User',
      avatarUrl: profile?['avatar_url'] as String?,
    );
  }

  String get initial =>
      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
}
