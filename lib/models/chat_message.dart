/// Valid values of `messages.media_status` / `channel_messages.media_status`.
///
/// `text` is the default for a message with no media at all. `pending` means
/// an image is uploaded but not yet moderated; `approved`/`rejected` are the
/// two terminal states `moderate-media` can leave it in.
enum MediaStatus { text, pending, approved, rejected }

MediaStatus _mediaStatusFromString(String? value) {
  switch (value) {
    case 'pending':
      return MediaStatus.pending;
    case 'approved':
      return MediaStatus.approved;
    case 'rejected':
      return MediaStatus.rejected;
    default:
      return MediaStatus.text;
  }
}

/// One message, from either `messages` (1:1) or `channel_messages` (group).
///
/// The two tables share every column this model reads; `channel_messages`
/// additionally carries `media_urls`, which is optional here. Modelling them
/// together lets the 1:1 thread and the channel thread share one bubble list
/// (blueprint §16.8).
class ChatMessage {
  final String id;
  final String senderId;
  final String content;

  /// `text`, `property_share`, `reel_share`, `image`, `audio`, `video` — the
  /// schema is open-ended, so this is kept as a raw string rather than an
  /// enum that could reject a value the backend already stores.
  final String messageType;

  /// Set on `property_share` messages.
  final String? propertyId;

  /// Set on `reel_share` messages — `messages.reel_id`
  /// (`20270424000000_reel_share_messages.sql`).
  final String? reelId;

  /// `messages.project_id` — set on a `project_share` message.
  final String? projectId;

  final List<String> mediaUrls;
  final MediaStatus mediaStatus;
  final bool isRead;
  final DateTime? createdAt;

  /// The message this one is replying to, if any. Rendered by looking the id
  /// up in the already-loaded thread — no separate fetch, matching the portal.
  final String? replyToId;

  /// Set once the sender edits the message's text (within the RPC's 15-minute
  /// window). Null means never edited.
  final DateTime? editedAt;

  /// Set when the sender deletes the message for everyone — the row is kept
  /// as a tombstone (`content`/`media_urls` cleared server-side) rather than
  /// hard-deleted.
  final DateTime? deletedAt;

  /// User ids who deleted this message "for me" — the row must be hidden
  /// from their view while everyone else still sees it.
  final List<String> deletedFor;

  /// Set on `sample_onetime`/`deliverable` collaboration messages — the
  /// `collab_assets` row this bubble renders. Null for every other type.
  final String? collabAssetId;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.messageType,
    this.propertyId,
    this.reelId,
    this.projectId,
    this.mediaUrls = const [],
    this.mediaStatus = MediaStatus.text,
    this.isRead = false,
    this.createdAt,
    this.replyToId,
    this.editedAt,
    this.deletedAt,
    this.deletedFor = const [],
    this.collabAssetId,
  });

  factory ChatMessage.fromSupabase(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    final edited = json['edited_at'] as String?;
    final deleted = json['deleted_at'] as String?;
    final media = json['media_urls'];
    final deletedForRaw = json['deleted_for'];

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      content: (json['content'] as String?) ?? '',
      messageType: (json['message_type'] as String?) ?? 'text',
      propertyId: json['property_id']?.toString(),
      reelId: json['reel_id']?.toString(),
      projectId: json['project_id']?.toString(),
      mediaUrls: media is List
          ? media.map((e) => e.toString()).toList()
          : const <String>[],
      mediaStatus: _mediaStatusFromString(json['media_status'] as String?),
      isRead: (json['is_read'] as bool?) ?? false,
      createdAt: created == null ? null : DateTime.tryParse(created),
      replyToId: json['reply_to_id']?.toString(),
      editedAt: edited == null ? null : DateTime.tryParse(edited),
      deletedAt: deleted == null ? null : DateTime.tryParse(deleted),
      deletedFor: deletedForRaw is List
          ? deletedForRaw.map((e) => e.toString()).toList()
          : const <String>[],
      collabAssetId: json['collab_asset_id']?.toString(),
    );
  }

  bool get isPropertyShare => messageType == 'property_share';
  bool get isReelShare => messageType == 'reel_share';
  bool get isProjectShare => messageType == 'project_share';
  bool get isImage => messageType == 'image';
  bool get isAudio => messageType == 'audio';
  bool get isVideo => messageType == 'video';
  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  // ── Collaboration-marketplace message types ──────────────────────────
  bool get isCollabSystem => messageType == 'collab_system';
  bool get isCollabPayment => messageType == 'collab_payment';
  bool get isCollabAgreement => messageType == 'collab_agreement';
  bool get isLocation => messageType == 'location';
  bool get isCollabSample => messageType == 'sample_onetime';
  bool get isCollabDeliverable => messageType == 'deliverable';
  bool get isCollabMessage =>
      isCollabSystem ||
      isCollabPayment ||
      isCollabAgreement ||
      isLocation ||
      isCollabSample ||
      isCollabDeliverable;

  /// `content` is stored as `"<label>\n<mapsUrl>"` for a `location` message
  /// — the URL is always the last line (`CollabMessageBubbles`'s
  /// `content.split('\n').pop()`, ported literally).
  String get locationLabel => content
      .split('\n')
      .firstWhere((l) => l.isNotEmpty, orElse: () => 'View location');
  String? get locationMapsUrl {
    final lines = content.split('\n').where((l) => l.isNotEmpty).toList();
    return lines.isEmpty ? null : lines.last;
  }

  bool hiddenFor(String userId) => deletedFor.contains(userId);

  /// What to render in a bubble when the type is not plain text.
  ///
  /// `property_share`, `reel_share` and `image` are already stored with a
  /// human-readable `content` string by the web app (e.g. "Shared property:
  /// <title>"/"Shared reel: <title>"), so the fallback is only reached for a
  /// type that arrives with an empty body — blueprint §16.7 requires those
  /// degrade gracefully rather than rendering a blank bubble.
  String get displayContent {
    if (isDeleted) return 'This message was deleted';
    if (content.trim().isNotEmpty) return content;
    if (isPropertyShare) return 'Shared a property';
    if (isReelShare) return 'Shared a reel';
    if (isImage) return 'Sent an image';
    if (isVideo) return 'Sent a video';
    if (isAudio) return 'Voice message';
    if (isCollabSample) return 'Sample video (view once)';
    if (isCollabDeliverable) return 'Final deliverable';
    if (isCollabAgreement) return 'Collaboration agreement';
    if (isLocation) return 'Location shared';
    return 'Unsupported message';
  }
}
