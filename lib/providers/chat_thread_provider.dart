import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../models/message_reaction.dart';
import '../models/shared_property_preview.dart';
import '../models/shared_project_preview.dart';
import '../models/shared_reel_preview.dart';
import '../services/chat_media_service.dart';
import '../services/messaging_exceptions.dart';
import '../services/messaging_service.dart';
import '../services/presence_service.dart';

/// Which backing table a thread reads and writes.
enum ChatThreadKind {
  /// 1:1 — `messages`, scoped by `conversation_id`.
  conversation,

  /// Group — `channel_messages`, scoped by `channel_id`.
  channel,
}

/// State for a single open thread, 1:1 or channel.
///
/// Kept separate from [MessagingProvider] deliberately. Blueprint §16.7 lists
/// one provider for both, but the list and the thread are independent routes:
/// a thread opened directly (or after the list is disposed) still needs its
/// own state, and threading one provider through `Navigator.push` would make
/// the thread unusable on its own. Both share the same [MessagingService], so
/// there is no duplicated query logic.
///
/// §16.8 notes the channel thread "can share most structure" with the 1:1 one
/// — [kind] is that seam.
class ChatThreadProvider extends ChangeNotifier {
  ChatThreadProvider({
    required this.kind,
    required this.threadId,
    required this.userId,
    this.participantUserId,
    MessagingService? service,
    ChatMediaService? mediaService,
  }) : _service = service ?? MessagingService(),
       _mediaService = mediaService ?? ChatMediaService();

  final ChatThreadKind kind;

  /// `conversation_id` or `channel_id` depending on [kind].
  final String threadId;

  final String userId;

  /// The other person in a 1:1 thread — null for channels (and for a DM
  /// whose participant couldn't be resolved, in which case block state
  /// simply isn't checked). Needed here (not just at the screen) because
  /// block state now lives on the provider alongside the messages it gates.
  final String? participantUserId;

  final MessagingService _service;
  final ChatMediaService _mediaService;
  final SupabaseClient _supabase = Supabase.instance.client;
  final PresenceService _presence = PresenceService();

  RealtimeChannel? _realtime;
  RealtimeChannel? _typingChannel;
  Timer? _typingClearTimer;
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  /// Discards a slow response if a newer request has since started —
  /// otherwise a realtime-triggered refetch racing with `send()`'s own
  /// refetch (or a pull-to-refresh) can clobber a more recent result with a
  /// stale one.
  int _fetchRequestId = 0;

  List<ChatMessage> _messages = const [];
  Map<String, ConversationParticipant> _senders = const {};
  Map<String, List<MessageReaction>> _reactions = const {};
  Map<String, SharedPropertyPreview> _sharedProperties = const {};
  Map<String, SharedReelPreview> _sharedReels = const {};
  Map<String, SharedProjectPreview> _sharedProjects = const {};
  bool _loading = true;
  bool _failed = false;
  bool _sending = false;
  bool _hasMoreOlder = true;
  bool _loadingMore = false;
  bool _otherTyping = false;
  ChatMessage? _replyingTo;

  /// Channel-only: senders the caller has personally blocked. Their
  /// messages — past and future, including realtime inserts — are filtered
  /// out of this thread entirely, matching the portal's `ChannelChat.tsx`.
  /// Not used for DM threads, where blocking instead disables the composer
  /// and shows a banner rather than hiding existing history — see
  /// [isBlockedByMe].
  Set<String> _blockedSenderIds = const {};

  /// DM-only: whether the *caller* has personally blocked the other
  /// participant — derived solely from the caller's own `user_blocks` row
  /// (never "have they blocked me"; the portal doesn't expose that to the
  /// blocked party either, so a message that fails to send because the
  /// *other* party blocked the caller still just surfaces the generic
  /// "This message could not be delivered." error, unchanged).
  bool _isBlockedByMe = false;
  bool _blockActionInFlight = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get loading => _loading;
  bool get failed => _failed;
  bool get sending => _sending;
  bool get hasMoreOlder => _hasMoreOlder;
  bool get loadingMore => _loadingMore;
  bool get otherTyping => _otherTyping;
  ChatMessage? get replyingTo => _replyingTo;
  bool get isChannel => kind == ChatThreadKind.channel;
  bool get isBlockedByMe => _isBlockedByMe;
  bool get blockActionInFlight => _blockActionInFlight;

  /// `'dm'` or `'channel'` — the literal string every reaction/edit/delete
  /// RPC expects.
  String get _surface => isChannel ? 'channel' : 'dm';

  /// Sender profiles, populated for channel threads only — a 1:1 thread
  /// already knows who the other party is.
  ConversationParticipant? senderFor(String senderId) => _senders[senderId];

  List<MessageReaction> reactionsFor(String messageId) =>
      _reactions[messageId] ?? const [];

  SharedPropertyPreview? sharedPropertyFor(String? propertyId) =>
      propertyId == null ? null : _sharedProperties[propertyId];

  SharedReelPreview? sharedReelFor(String? reelId) =>
      reelId == null ? null : _sharedReels[reelId];

  SharedProjectPreview? sharedProjectFor(String? projectId) =>
      projectId == null ? null : _sharedProjects[projectId];

  /// Batch-resolves every `property_id` in [messages] not already cached —
  /// one query per call site regardless of how many `property_share`
  /// bubbles are on the page, never one query per bubble. Cached for the
  /// life of this provider instance (a thread's properties don't change
  /// underneath it), so scrolling back over already-seen messages doesn't
  /// re-query.
  Future<void> _resolveSharedProperties(List<ChatMessage> messages) async {
    final missing = messages
        .where((m) => m.isPropertyShare && m.propertyId != null)
        .map((m) => m.propertyId!)
        .where((id) => !_sharedProperties.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      final fetched = await _service.fetchSharedProperties(missing);
      _sharedProperties = {..._sharedProperties, ...fetched};
      _safeNotify();
    } catch (e) {
      debugPrint('ChatThreadProvider._resolveSharedProperties failed: $e');
    }
  }

  /// Batch-resolves every `reel_id` in [messages] not already cached — one
  /// query per call site regardless of how many `reel_share` bubbles are on
  /// the page, never one query per bubble. Same shape as
  /// [_resolveSharedProperties], cached for the life of this provider
  /// instance for the same reason.
  Future<void> _resolveSharedReels(List<ChatMessage> messages) async {
    final missing = messages
        .where((m) => m.isReelShare && m.reelId != null)
        .map((m) => m.reelId!)
        .where((id) => !_sharedReels.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      final fetched = await _service.fetchSharedReels(missing);
      _sharedReels = {..._sharedReels, ...fetched};
      _safeNotify();
    } catch (e) {
      debugPrint('ChatThreadProvider._resolveSharedReels failed: $e');
    }
  }

  /// Batch-resolves every project_id in [messages] not already cached,
  /// same shape as [_resolveSharedReels] - cached for the life of this
  /// provider so a project shared several times is looked up once.
  Future<void> _resolveSharedProjects(List<ChatMessage> messages) async {
    final missing = messages
        .where((m) => m.isProjectShare && m.projectId != null)
        .map((m) => m.projectId!)
        .where((id) => !_sharedProjects.containsKey(id))
        .toSet();
    if (missing.isEmpty) return;
    try {
      final fetched = await _service.fetchSharedProjects(missing);
      _sharedProjects = {..._sharedProjects, ...fetched};
      _safeNotify();
    } catch (e) {
      debugPrint('ChatThreadProvider._resolveSharedProjects failed: $e');
    }
  }

  /// The message a reply/quote strip is pointing at, resolved from the
  /// already-loaded thread — no separate fetch, matching the portal.
  ChatMessage? repliedMessage(String? replyToId) {
    if (replyToId == null) return null;
    for (final m in _messages) {
      if (m.id == replyToId) return m;
    }
    return null;
  }

  Future<void> load() async {
    _presence.attach();
    _subscribe();
    _subscribeTyping();
    // Block state is reloaded every time a thread is opened, not cached
    // across sessions — so blocking/unblocking from another screen (or the
    // Blocked Users list) is always reflected the next time this thread
    // opens, not just after a block/unblock performed from right here.
    await _loadBlockState();
    await _fetch();
    // Opening a thread clears its unread rows, matching both ChatModal.tsx
    // and ChannelChat.tsx. A failure here must not become an unhandled
    // future error — mark-as-read failing silently just means the badge
    // reconciles a little later (MessagingProvider.refresh on thread close).
    try {
      await _markRead();
    } catch (e) {
      debugPrint('ChatThreadProvider._markRead failed: $e');
    }
  }

  Future<void> _loadBlockState() async {
    try {
      if (isChannel) {
        _blockedSenderIds = await _service.myBlockedUserIds(userId);
      } else if (participantUserId != null) {
        _isBlockedByMe = await _service.haveIBlocked(
          userId,
          participantUserId!,
        );
      }
    } catch (e) {
      debugPrint('ChatThreadProvider._loadBlockState failed: $e');
    }
  }

  /// Blocks the DM participant — disables the composer/attach/mic (the
  /// screen reads [isBlockedByMe] to do that) and shows a banner, matching
  /// the portal. No-op for channels (there is no "block this channel").
  Future<String?> blockParticipant() async {
    final other = participantUserId;
    if (other == null || isChannel || _blockActionInFlight) return null;
    _blockActionInFlight = true;
    _safeNotify();
    try {
      await _service.blockUser(other);
      _isBlockedByMe = true;
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.blockParticipant failed: $e');
      return "Couldn't block this person.";
    } finally {
      _blockActionInFlight = false;
      _safeNotify();
    }
  }

  Future<String?> unblockParticipant() async {
    final other = participantUserId;
    if (other == null || isChannel || _blockActionInFlight) return null;
    _blockActionInFlight = true;
    _safeNotify();
    try {
      await _service.unblockUser(other);
      _isBlockedByMe = false;
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.unblockParticipant failed: $e');
      return "Couldn't unblock this person.";
    } finally {
      _blockActionInFlight = false;
      _safeNotify();
    }
  }

  Future<void> refresh() => _fetch();

  /// Fetches the latest window and **merges** it into whatever's already
  /// loaded — never a wholesale replace. On the very first load (`_messages`
  /// still empty) there's nothing to merge into, so the fetched page just
  /// becomes the list directly. On every later call (pull-to-refresh, the
  /// belt-and-suspenders sync after a send/edit, or a realtime fallback),
  /// merging means a thread with 150 messages loaded (50 latest + 100 older
  /// via [loadMore]) never collapses back down to 50 just because something
  /// changed — the fix for the exact "pagination destroyed by any refetch"
  /// bug this repair pass targets.
  Future<void> _fetch() async {
    final requestId = ++_fetchRequestId;
    final isFirstLoad = _messages.isEmpty;
    _loading = isFirstLoad;
    _failed = false;
    _safeNotify();

    try {
      final loaded = isChannel
          ? await _service.listChannelMessages(threadId)
          : await _service.listMessages(threadId);

      if (requestId != _fetchRequestId) return; // superseded by a newer call

      _messages = isFirstLoad
          ? _filterHidden(loaded)
          : _mergeIntoMessages(loaded);
      if (isFirstLoad) {
        _hasMoreOlder = loaded.length >= MessagingService.messagePageSize;
      }

      // Channel bubbles are attributed to a sender; resolve any we don't have.
      if (isChannel) {
        final missing = loaded
            .map((m) => m.senderId)
            .where((id) => id.isNotEmpty && !_senders.containsKey(id))
            .toSet();
        if (missing.isNotEmpty) {
          final fetched = await _service.fetchSenderProfiles(missing);
          if (requestId != _fetchRequestId) return;
          _senders = {..._senders, ...fetched};
        }
      }

      await _refreshReactions(loaded.map((m) => m.id).toList());
      if (requestId != _fetchRequestId) return;
      await _resolveSharedProperties(loaded);
      if (requestId != _fetchRequestId) return;
      await _resolveSharedReels(loaded);
      if (requestId != _fetchRequestId) return;
      await _resolveSharedProjects(loaded);
      if (requestId != _fetchRequestId) return;
    } catch (e) {
      if (requestId != _fetchRequestId) return;
      debugPrint('ChatThreadProvider._fetch failed: $e');
      _failed = true;
    } finally {
      if (requestId == _fetchRequestId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  /// Loads the page immediately older than the earliest currently-loaded
  /// message and prepends it. A deliberate divergence from the portal (which
  /// loads a thread's entire history unbounded) — see MessagingService docs.
  Future<void> loadMore() async {
    if (_loadingMore || !_hasMoreOlder || _messages.isEmpty) return;
    _loadingMore = true;
    _safeNotify();

    try {
      final oldest = _messages.first.createdAt;
      final older = oldest == null
          ? const <ChatMessage>[]
          : isChannel
          ? await _service.listChannelMessages(threadId, before: oldest)
          : await _service.listMessages(threadId, before: oldest);

      _hasMoreOlder = older.length >= MessagingService.messagePageSize;
      final visible = _filterHidden(older);
      if (visible.isNotEmpty) {
        _messages = [...visible, ..._messages];
      }
      if (older.isNotEmpty) {
        await _refreshReactions(older.map((m) => m.id).toList());
        await _resolveSharedProperties(older);
        await _resolveSharedReels(older);
        await _resolveSharedProjects(older);
      }
    } catch (e) {
      debugPrint('ChatThreadProvider.loadMore failed: $e');
    } finally {
      _loadingMore = false;
      _safeNotify();
    }
  }

  Future<void> _refreshReactions(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    try {
      final fetched = await _service.fetchReactions(
        messageIds: messageIds,
        surface: _surface,
      );
      _reactions = {..._reactions, ...fetched};
    } catch (e) {
      debugPrint('ChatThreadProvider._refreshReactions failed: $e');
    }
  }

  /// Drops any message the current user deleted "for me", and — for channel
  /// threads only — any message from a sender the caller has personally
  /// blocked (past history and, via [_mergeIntoMessages], future realtime
  /// inserts too; matches the portal's `ChannelChat.tsx`, which filters
  /// blocked senders on both the initial fetch and the live feed). DM
  /// blocking does *not* hide existing history this way — it only disables
  /// sending new messages, via [isBlockedByMe].
  ///
  /// The single choke point every path that populates `_messages` goes
  /// through, so realtime merges, `loadMore()`, and a fresh `_fetch()` all
  /// agree on what's visible instead of each remembering to filter it
  /// separately.
  bool _isVisible(ChatMessage m) =>
      !m.hiddenFor(userId) &&
      (!isChannel || !_blockedSenderIds.contains(m.senderId));

  List<ChatMessage> _filterHidden(List<ChatMessage> messages) =>
      messages.where(_isVisible).toList();

  /// Upserts [rows] into `_messages` by id and re-sorts — an id already
  /// present is replaced in place (an edit, a media-status change, a
  /// read-state flip); an id not yet present is inserted; a row that's now
  /// hidden-for-me (its own "delete for me" echoing back) is removed rather
  /// than upserted. Never drops an existing id that isn't mentioned in
  /// [rows] — that's what makes every caller of this (the merge-fetch in
  /// [_fetch], the realtime patch below, the cursor-based fallback) safe to
  /// call without destroying already-loaded older pages.
  List<ChatMessage> _mergeIntoMessages(Iterable<ChatMessage> rows) {
    final byId = {for (final m in _messages) m.id: m};
    for (final row in rows) {
      if (_isVisible(row)) {
        byId[row.id] = row;
      } else {
        byId.remove(row.id);
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });
    return merged;
  }

  /// Fallback for when a realtime payload can't be merged directly (parsing
  /// failure, or an event type we don't special-case) — fetches only what's
  /// newer than the latest message already loaded and merges it in, so even
  /// the fallback path never re-fetches "latest N" and collapses older pages
  /// the way the old `_fetch()`-on-every-event design did.
  Future<void> _mergeFromCursor() async {
    try {
      final cursor = _messages.isEmpty ? null : _messages.last.createdAt;
      final newer = isChannel
          ? await _service.listChannelMessages(threadId, after: cursor)
          : await _service.listMessages(threadId, after: cursor);
      if (newer.isEmpty) return;
      _messages = _mergeIntoMessages(newer);
      _safeNotify();
      await _resolveSharedProperties(newer);
      await _resolveSharedReels(newer);
      await _resolveSharedProjects(newer);
    } catch (e) {
      debugPrint('ChatThreadProvider._mergeFromCursor failed: $e');
    }
  }

  /// Applies one realtime `messages`/`channel_messages` change without ever
  /// re-fetching "latest N" (which would silently drop any older page
  /// already loaded via [loadMore]). INSERT/UPDATE both upsert the row by id
  /// via [_mergeIntoMessages] (an UPDATE is how an edit, a delete-for-
  /// everyone tombstone, and a media-moderation status flip all arrive —
  /// there's no separate channel for any of those, just an UPDATE on this
  /// same row); DELETE removes the id directly. Anything that can't be
  /// parsed from the payload falls back to [_mergeFromCursor], never to the
  /// old wholesale re-fetch.
  void _applyRealtimeChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final row = ChatMessage.fromSupabase(payload.newRecord);
          _messages = _mergeIntoMessages([row]);
          _safeNotify();
          if (isChannel && payload.eventType == PostgresChangeEvent.insert) {
            _resolveSenderIfMissing(row.senderId);
          }
          if (row.isPropertyShare) {
            _resolveSharedProperties([row]);
          }
          if (row.isReelShare) {
            _resolveSharedReels([row]);
          }
          if (row.isProjectShare) {
            _resolveSharedProjects([row]);
          }
          break;
        case PostgresChangeEvent.delete:
          final oldId = payload.oldRecord['id']?.toString();
          if (oldId != null) {
            _messages = _messages.where((m) => m.id != oldId).toList();
            _safeNotify();
          }
          break;
        default:
          _mergeFromCursor();
      }
    } catch (e) {
      debugPrint(
        'ChatThreadProvider._applyRealtimeChange: payload merge failed, '
        'falling back to cursor merge: $e',
      );
      _mergeFromCursor();
    }
  }

  void _resolveSenderIfMissing(String senderId) {
    if (senderId.isEmpty || _senders.containsKey(senderId)) return;
    _service.fetchSenderProfiles({senderId}).then((fetched) {
      if (_disposed) return;
      _senders = {..._senders, ...fetched};
      _safeNotify();
    });
  }

  Future<void> _markRead() async {
    if (isChannel) {
      await _service.markChannelAsRead(channelId: threadId, userId: userId);
    } else {
      await _service.markConversationAsRead(
        conversationId: threadId,
        userId: userId,
      );
    }
  }

  void setReplyTo(ChatMessage? message) {
    _replyingTo = message;
    _safeNotify();
  }

  /// Sends [text]. Returns null on success, or an error message for the caller
  /// to surface in a snackbar (blueprint §12).
  Future<String?> send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return null;

    _sending = true;
    _safeNotify();

    final replyToId = _replyingTo?.id;

    try {
      if (isChannel) {
        await _service.sendChannelMessage(
          channelId: threadId,
          senderId: userId,
          content: body,
          replyToId: replyToId,
        );
      } else {
        await _service.sendMessage(
          conversationId: threadId,
          senderId: userId,
          content: body,
          replyToId: replyToId,
        );
      }
      _replyingTo = null;
      // React refetches after sending rather than appending optimistically;
      // the Realtime callback will also fire, and _fetch is idempotent.
      await _fetch();
      return null;
    } on MessageModerationError catch (e) {
      return e.message;
    } on MessageSendDeniedError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.send failed: $e');
      return 'Message not sent. Check your connection and try again.';
    } finally {
      _sending = false;
      _safeNotify();
    }
  }

  bool _uploadingMedia = false;
  bool get uploadingMedia => _uploadingMedia;

  /// Shares a property picked from [showSharePropertySheet] into this
  /// thread. Reuses [MessagingService.sendPropertyShare] (which had zero
  /// callers before this repair pass) for either surface.
  Future<String?> sharePropertyFromPicker(
    SharedPropertyPreview property,
  ) async {
    if (_uploadingMedia) return null;
    _uploadingMedia = true;
    _safeNotify();
    try {
      await _service.sendPropertyShare(
        threadId: threadId,
        senderId: userId,
        propertyId: property.id,
        content: 'Shared property: ${property.title}',
        surface: _surface,
      );
      await _fetch();
      return null;
    } on MessageSendDeniedError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.sharePropertyFromPicker failed: $e');
      return "Couldn't share the property. Check your connection and try again.";
    } finally {
      _uploadingMedia = false;
      _safeNotify();
    }
  }

  /// Sends a reel picked in the in-chat reel picker as a `reel_share`
  /// message - the portal's `sendReelShare` (DMs' `useDmMessaging.ts`, or
  /// `ChannelChat.tsx`'s "Share reel" button for a channel), via
  /// [MessagingService.sendReelShare].
  Future<String?> shareReelFromPicker(SharedReelPreview reel) async {
    if (_uploadingMedia) return null;
    _uploadingMedia = true;
    _safeNotify();
    try {
      await _service.sendReelShare(
        threadId: threadId,
        senderId: userId,
        reelId: reel.id,
        content: 'Shared reel: ${reel.title}',
        surface: _surface,
      );
      await _fetch();
      return null;
    } on MessageSendDeniedError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.shareReelFromPicker failed: $e');
      return "Couldn't share the reel. Check your connection and try again.";
    } finally {
      _uploadingMedia = false;
      _safeNotify();
    }
  }

  /// Uploads and sends an image message via the same private `chat-media`
  /// bucket + `moderate-media` pipeline the portal uses — see
  /// [ChatMediaService.sendImage]. Works in both DMs and channels.
  Future<String?> sendImage(Uint8List bytes, String extension) async {
    if (_uploadingMedia) return null;
    _uploadingMedia = true;
    _safeNotify();
    try {
      await _mediaService.sendImage(
        bytes: bytes,
        extension: extension,
        surface: _surface,
        threadId: threadId,
        senderId: userId,
      );
      await _fetch();
      return null;
    } on ChatMediaValidationError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.sendImage failed: $e');
      return "Couldn't send the image. Check your connection and try again.";
    } finally {
      _uploadingMedia = false;
      _safeNotify();
    }
  }

  /// Uploads and sends a video message — see [ChatMediaService.sendVideo].
  /// Channel-only, matching the portal's `uploadChatMedia.ts`
  /// (`assertValidFile`: `'Video is only supported in channels right now.'`);
  /// a DM thread refuses before ever touching the network.
  Future<String?> sendVideo(XFile file) async {
    if (!isChannel) return 'Video is only supported in channels right now.';
    if (_uploadingMedia) return null;
    _uploadingMedia = true;
    _safeNotify();
    try {
      await _mediaService.sendVideo(
        file: file,
        surface: _surface,
        threadId: threadId,
        senderId: userId,
      );
      await _fetch();
      return null;
    } on ChatMediaValidationError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.sendVideo failed: $e');
      return "Couldn't send the video. Check your connection and try again.";
    } finally {
      _uploadingMedia = false;
      _safeNotify();
    }
  }

  Future<String?> sendVoiceNote(
    Uint8List bytes,
    String extension,
    Duration duration,
  ) async {
    if (_uploadingMedia) return null;
    _uploadingMedia = true;
    _safeNotify();
    try {
      await _mediaService.sendVoiceNote(
        bytes: bytes,
        extension: extension,
        duration: duration,
        surface: _surface,
        threadId: threadId,
        senderId: userId,
      );
      await _fetch();
      return null;
    } on ChatMediaValidationError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('ChatThreadProvider.sendVoiceNote failed: $e');
      return "Couldn't send the voice message. Check your connection and try again.";
    } finally {
      _uploadingMedia = false;
      _safeNotify();
    }
  }

  Future<String?> toggleReaction(String messageId, String emoji) async {
    try {
      await _service.toggleReaction(
        messageId: messageId,
        surface: _surface,
        emoji: emoji,
      );
      await _refreshReactions([messageId]);
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.toggleReaction failed: $e');
      return "Couldn't react to that message.";
    }
  }

  /// Sender-only, text-only, within the RPC's 15-minute window — this is a
  /// client-side hint; the server enforces the real cutoff and rejects late
  /// edits with its own error message.
  Future<String?> editMessage(String messageId, String newContent) async {
    try {
      await _service.editMessage(
        messageId: messageId,
        surface: _surface,
        newContent: newContent,
      );
      await _fetch();
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.editMessage failed: $e');
      return 'Failed to edit message.';
    }
  }

  Future<String?> deleteForMe(String messageId) async {
    try {
      await _service.deleteMessageForMe(
        messageId: messageId,
        surface: _surface,
      );
      _messages = _messages.where((m) => m.id != messageId).toList();
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.deleteForMe failed: $e');
      return 'Failed to delete message.';
    }
  }

  Future<String?> deleteForEveryone(String messageId) async {
    try {
      await _service.deleteMessageForEveryone(
        messageId: messageId,
        surface: _surface,
      );
      await _fetch();
      return null;
    } catch (e) {
      debugPrint('ChatThreadProvider.deleteForEveryone failed: $e');
      return 'Failed to delete message.';
    }
  }

  // ── Typing indicator (Realtime broadcast, not persisted to the DB) ──────
  //
  // Exact match to the portal's Chat.tsx: 2s send throttle, 3s auto-clear on
  // the receiving side, cleared on thread switch/dispose.

  void _subscribeTyping() {
    if (isChannel) return; // portal has no typing indicator for channels
    _typingChannel = _supabase.channel('conversation:$threadId')
      ..onBroadcast(
        event: 'typing',
        callback: (payload) {
          if (payload['userId'] == userId) return;
          _otherTyping = true;
          _safeNotify();
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3), () {
            _otherTyping = false;
            _safeNotify();
          });
        },
      )
      ..subscribe();
  }

  void notifyTyping() {
    if (isChannel) return;
    final channel = _typingChannel;
    if (channel == null) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSentAt) < const Duration(seconds: 2)) return;
    _lastTypingSentAt = now;
    channel.sendBroadcastMessage(event: 'typing', payload: {'userId': userId});
  }

  // ── Realtime (messages + reactions) ──────────────────────────────────────

  void _subscribe() {
    if (_realtime != null) return;

    final table = isChannel ? 'channel_messages' : 'messages';
    final column = isChannel ? 'channel_id' : 'conversation_id';
    final suffix = DateTime.now().microsecondsSinceEpoch;

    _realtime = _supabase.channel('thread-$threadId-$suffix')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: threadId,
        ),
        callback: _applyRealtimeChange,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'message_reactions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'surface',
          value: _surface,
        ),
        callback: (_) => _refreshReactions(
          _messages.map((m) => m.id).toList(),
        ).then((_) => _safeNotify()),
      )
      ..subscribe();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _presence.detach();
    _typingClearTimer?.cancel();
    final channel = _realtime;
    if (channel != null) {
      _realtime = null;
      _supabase.removeChannel(channel);
    }
    final typing = _typingChannel;
    if (typing != null) {
      _typingChannel = null;
      _supabase.removeChannel(typing);
    }
    super.dispose();
  }
}
