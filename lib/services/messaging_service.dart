import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/channel_summary.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../models/message_reaction.dart';
import '../models/shared_property_preview.dart';
import '../models/shared_project_preview.dart';
import '../models/shared_reel_preview.dart';
import 'messaging_exceptions.dart';

/// Direct (1:1) and channel messaging.
///
/// Every query below mirrors its counterpart in the React portal — see
/// blueprint §9. Two behaviours are deliberately *not* implemented client-side
/// because the database already owns them:
///
///  * `trigger_notify_new_message` / `notify_channel_message_trigger` create
///    the recipient's notification. ChatModal.tsx calls this out explicitly:
///    inserting a notification here as well would deliver it twice.
///  * `update_conversation_last_message_trigger` maintains
///    `conversations.last_message_at`. Sending a message must not write it.
class MessagingService {
  MessagingService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  // ── Conversations (1:1) ───────────────────────────────────────────────────

  /// The signed-in user's conversations, newest activity first.
  ///
  /// Mirrors `fetchConversations` in features/messaging/ChatModal.tsx. The
  /// `conversations` select carries no user filter there either — RLS scopes
  /// the rows to the caller's own conversations.
  ///
  /// React resolves participants, profiles and last messages with a
  /// per-conversation loop (three round-trips each). This batches those into
  /// one query apiece via `.inFilter`, producing identical results without an
  /// N+1 — the same "resolve in one extra round-trip" pattern
  /// hooks/useProfileViews.ts already uses for its viewer profiles.
  Future<List<ConversationSummary>> listConversations(String userId) async {
    try {
      final convRows = await _supabase
          .from('conversations')
          .select('id, last_message_at, collaboration_id')
          .order('last_message_at', ascending: false);

      final conversations = List<Map<String, dynamic>>.from(convRows as List);
      if (conversations.isEmpty) return const [];

      final ids = conversations
          .map((c) => c['id']?.toString())
          .whereType<String>()
          .toList();

      final participantRows = await _supabase
          .from('conversation_participants')
          .select(
            'conversation_id, user_id, request_status, muted_at, hidden_at',
          )
          .inFilter('conversation_id', ids);

      // conversation_id -> the *other* participant's user id, and the
      // caller's own request_status/mute/hidden state for that conversation.
      // A row with a null conversation_id/user_id is skipped rather than
      // `.toString()`'d into the literal `"null"`, which would otherwise
      // silently pollute the batched profile lookup below with a bogus id.
      final otherIdByConversation = <String, String>{};
      final selfStatusByConversation =
          <
            String,
            ({String requestStatus, bool isMuted, DateTime? hiddenAt})
          >{};
      for (final row in List<Map<String, dynamic>>.from(
        participantRows as List,
      )) {
        final convId = row['conversation_id']?.toString();
        final memberId = row['user_id']?.toString();
        if (convId == null || memberId == null) {
          debugPrint(
            'MessagingService.listConversations: skipping participant row '
            'with null id(s): $row',
          );
          continue;
        }
        if (memberId == userId) {
          selfStatusByConversation[convId] = (
            requestStatus: (row['request_status'] as String?) ?? 'accepted',
            isMuted: row['muted_at'] != null,
            hiddenAt: DateTime.tryParse((row['hidden_at'] as String?) ?? ''),
          );
        } else {
          otherIdByConversation[convId] = memberId;
        }
      }

      final profilesById = await _fetchPublicProfiles(
        otherIdByConversation.values.toSet(),
      );

      // Batched "last non-deleted-for-me message per conversation" — reuses
      // the portal's own perf RPC instead of scanning every message row for
      // every conversation.
      final lastMessageByConversation = <String, String>{};
      try {
        final previewRows = await _supabase.rpc(
          'get_conversation_message_previews',
          params: {'p_conversation_ids': ids, 'p_user_id': userId},
        );
        for (final row in List<Map<String, dynamic>>.from(
          previewRows as List,
        )) {
          final convId = row['conversation_id']?.toString();
          if (convId == null) continue;
          final deletedAt = row['deleted_at'];
          lastMessageByConversation[convId] = deletedAt != null
              ? 'This message was deleted'
              : (row['content'] as String?) ?? '';
        }
      } catch (e) {
        debugPrint(
          'MessagingService.listConversations: message previews '
          'unavailable: $e',
        );
      }

      Map<String, int> unread;
      try {
        unread = await unreadCountsByConversation(userId);
      } catch (e) {
        // A failed unread-count lookup must not be indistinguishable from
        // "genuinely zero unread" — fall back to showing no badges rather
        // than silently lying about them, but don't fail the whole list.
        debugPrint(
          'MessagingService.listConversations: unread counts unavailable: $e',
        );
        unread = const {};
      }

      // Opening a chat (`startConversation`) creates the conversation +
      // participant rows immediately, before any message is sent — without
      // this check, that empty conversation shows in the inbox like a real
      // one. Checked independently of the previews above, which filter out
      // messages deleted-for-me: a conversation whose messages are all
      // deleted-for-me is a real past conversation (should still show, just
      // with no preview text), not an empty never-messaged one. Mirrors
      // `dm-inbox-bootstrap/index.ts:80-97,152-158` exactly — no
      // collaboration exemption there either.
      Set<String> conversationIdsWithMessages;
      try {
        final messageRows = await _supabase
            .from('messages')
            .select('conversation_id')
            .inFilter('conversation_id', ids);
        conversationIdsWithMessages =
            List<Map<String, dynamic>>.from(messageRows as List)
                .map((r) => r['conversation_id']?.toString())
                .whereType<String>()
                .toSet();
      } catch (e) {
        // Fails open — a broken existence check must not empty the whole
        // inbox, only fail to hide never-messaged conversations.
        debugPrint(
          'MessagingService.listConversations: message existence check '
          'unavailable: $e',
        );
        conversationIdsWithMessages = ids.toSet();
      }

      return conversations
          .where((c) => c['id'] != null)
          .map((conv) {
            final id = conv['id'].toString();
            final otherId = otherIdByConversation[id];
            final createdRaw = conv['last_message_at'] as String?;
            final lastMessageAt = createdRaw == null
                ? null
                : DateTime.tryParse(createdRaw);
            final selfStatus = selfStatusByConversation[id];

            return (
              summary: ConversationSummary(
                id: id,
                lastMessageAt: lastMessageAt,
                otherParticipant: otherId == null
                    ? null
                    : profilesById[otherId],
                lastMessage: lastMessageByConversation[id] ?? '',
                unreadCount: unread[id] ?? 0,
                requestStatus: selfStatus?.requestStatus ?? 'accepted',
                isMuted: selfStatus?.isMuted ?? false,
                collaborationId: conv['collaboration_id']?.toString(),
              ),
              hiddenForMe: _isHiddenForMe(selfStatus?.hiddenAt, lastMessageAt),
            );
          })
          // A conversation "deleted" from the caller's own list (Trash2 in
          // the portal, swipe-to-delete here) stays hidden only until a
          // newer message arrives — same WhatsApp/Telegram behaviour as the
          // portal's fetchConversations: an incoming message un-hides the
          // thread rather than the hide being permanent/one-way. A
          // conversation with no messages at all (opened but never actually
          // messaged) never shows, regardless of hidden state.
          .where(
            (row) =>
                !row.hiddenForMe &&
                conversationIdsWithMessages.contains(row.summary.id),
          )
          .map((row) => row.summary)
          .toList();
    } catch (e) {
      debugPrint('MessagingService.listConversations failed: $e');
      rethrow;
    }
  }

  /// Mirrors the portal's `_hiddenForMe` in useDmMessaging.ts exactly: hidden
  /// only while nothing newer than the hide has arrived. A conversation with
  /// no messages at all (`lastMessageAt` null) stays hidden once hidden —
  /// there is nothing that could have superseded it.
  bool _isHiddenForMe(DateTime? hiddenAt, DateTime? lastMessageAt) {
    if (hiddenAt == null) return false;
    if (lastMessageAt == null) return true;
    return !lastMessageAt.isAfter(hiddenAt);
  }

  /// Resolves display names and avatars from the `profiles_public` view —
  /// the same view ChatModal.tsx reads, not the `profiles` table.
  Future<Map<String, ConversationParticipant>> _fetchPublicProfiles(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};

    final rows = await _supabase
        .from('profiles_public')
        .select('user_id, display_name, avatar_url, is_online, last_seen_at')
        .inFilter('user_id', userIds.toList());

    final result = <String, ConversationParticipant>{};
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final id = row['user_id']?.toString();
      if (id == null) continue;
      final lastSeenRaw = row['last_seen_at'] as String?;
      result[id] = ConversationParticipant(
        userId: id,
        displayName: (row['display_name'] as String?) ?? 'Unknown',
        avatarUrl: row['avatar_url'] as String?,
        isOnline: (row['is_online'] as bool?) ?? false,
        lastSeenAt: lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw),
      );
    }
    return result;
  }

  /// Columns shared by every `messages`/`channel_messages` select — kept in
  /// one place so a new column (e.g. a future `forwarded_from_id`) only needs
  /// updating here.
  static const String _messageColumns =
      'id, content, sender_id, message_type, property_id, media_urls, '
      'media_status, created_at, is_read, reply_to_id, edited_at, '
      'deleted_at, deleted_for';

  /// `channel_messages` adds `reel_id` on top of the shared columns —
  /// channels can hold a `reel_share` message too (schema from
  /// `20271007060000_channel_messages_reel_share.sql`, the same migration
  /// the portal's `ChannelChat.tsx` "Share reel" button already relies on).
  /// `collab_asset_id`/`project_id` stay DM-only below: the collaboration
  /// marketplace and builder-project sharing are both 1:1-only features with
  /// no channel column for either.
  static const String _channelMessageColumns = '$_messageColumns, reel_id';

  /// `messages` only — `channel_messages` has no `collab_asset_id` or
  /// `project_id` column (both are 1:1-only features), so these must never
  /// be used for a channel select.
  static const String _dmMessageColumns =
      '$_messageColumns, collab_asset_id, reel_id, project_id';

  /// Exposes the column sets above for a regression test asserting `reel_id`
  /// is readable from both DM and channel selects, and that the
  /// 1:1-only columns never leak into the channel select — production code
  /// never reads these, only `test/reel_share_dm_test.dart`.
  @visibleForTesting
  static String get messageColumnsForTest => _channelMessageColumns;
  @visibleForTesting
  static String get dmMessageColumnsForTest => _dmMessageColumns;

  /// Searches an entire thread's history server-side — not just what's
  /// currently paged into memory. Mobile paginates (50/page) while the
  /// portal loads a thread's full history and filters it client-side; a
  /// client-side-only search here would silently miss anything not yet
  /// scrolled into view, so this queries the same table/RLS directly instead
  /// (just a different `WHERE`, no new backend contract).
  Future<List<ChatMessage>> searchMessagesInThread({
    required String threadId,
    required bool isChannel,
    required String term,
  }) async {
    final query = term.trim();
    if (query.isEmpty) return const [];

    try {
      final table = isChannel ? 'channel_messages' : 'messages';
      final column = isChannel ? 'channel_id' : 'conversation_id';

      final rows = await _supabase
          .from(table)
          .select(isChannel ? _channelMessageColumns : _dmMessageColumns)
          .eq(column, threadId)
          .ilike('content', '%$query%')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(ChatMessage.fromSupabase).toList();
    } catch (e) {
      debugPrint('MessagingService.searchMessagesInThread failed: $e');
      rethrow;
    }
  }

  /// Most recent page of a conversation, newest-first on the wire (reversed
  /// to oldest-first for display). Mirrors `fetchMessages` in ChatModal.tsx,
  /// with pagination added on top — see [messagePageSize].
  ///
  /// Pass [before] (an already-loaded message's `createdAt`) to load the page
  /// immediately older than it, for "load more" on scroll-to-top. Pass
  /// [after] instead to load everything newer than an already-loaded
  /// message, ascending — the merge-fetch fallback a realtime handler uses
  /// when it can't merge a single payload row directly; this never touches
  /// older history the way a bare re-fetch of "latest N" would.
  Future<List<ChatMessage>> listMessages(
    String conversationId, {
    DateTime? before,
    DateTime? after,
  }) async {
    try {
      var query = _supabase
          .from('messages')
          .select(_dmMessageColumns)
          .eq('conversation_id', conversationId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      if (after != null) {
        query = query.gt('created_at', after.toUtc().toIso8601String());
      }

      if (after != null) {
        final rows = await query
            .order('created_at', ascending: true)
            .limit(mergeFetchCap);
        return List<Map<String, dynamic>>.from(
          rows as List,
        ).map(ChatMessage.fromSupabase).toList();
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(messagePageSize);

      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(ChatMessage.fromSupabase).toList().reversed.toList();
    } catch (e) {
      debugPrint('MessagingService.listMessages failed: $e');
      rethrow;
    }
  }

  /// Safety cap on an [after]-cursor merge-fetch — this path only runs when a
  /// realtime payload couldn't be merged directly, which should be rare, but
  /// an unbounded query after a long realtime outage would be a real cost.
  static const int mergeFetchCap = 200;

  /// Messages per page — the portal itself loads a thread's entire history
  /// unbounded (see docs/messaging audit), which doesn't scale on mobile
  /// data/battery. Paginating is a deliberate, flagged divergence.
  static const int messagePageSize = 50;

  /// Sends a plain-text message.
  ///
  /// Mirrors `sendTextMessage` in useDmMessaging.ts: moderates the text
  /// first (fails open — a moderation-service outage must never block a
  /// legitimate send), then inserts. Errors from the insert itself (rate
  /// limit, RLS block) are mapped to the portal's exact user-facing copy.
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String content,
    String? replyToId,
  }) async {
    final trimmed = content.trim();
    await moderateText(trimmed);

    try {
      await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': trimmed,
        'message_type': 'text',
        if (replyToId != null) 'reply_to_id': replyToId,
      });
    } catch (e) {
      debugPrint('MessagingService.sendMessage failed: $e');
      throw mapSendError(e);
    }
  }

  /// Shares a property into a conversation. There is no dedicated RPC for
  /// this on the portal either — `sendPropertyShare` in useDmMessaging.ts is
  /// also a raw insert.
  /// [surface] is `'dm'` or `'channel'` — same convention as the reaction/
  /// edit/delete RPCs, so this one method covers both instead of a second
  /// `sendChannelPropertyShare` twin (there had been zero callers of this
  /// method at all before this repair pass, so nothing depends on the old
  /// DM-only signature).
  Future<void> sendPropertyShare({
    required String threadId,
    required String senderId,
    required String propertyId,
    required String content,
    String surface = 'dm',
  }) async {
    final table = surface == 'channel' ? 'channel_messages' : 'messages';
    final idColumn = surface == 'channel' ? 'channel_id' : 'conversation_id';
    try {
      await _supabase.from(table).insert({
        idColumn: threadId,
        'sender_id': senderId,
        'content': content,
        'message_type': 'property_share',
        'property_id': propertyId,
      });
    } catch (e) {
      debugPrint('MessagingService.sendPropertyShare failed: $e');
      throw mapSendError(e);
    }
  }

  /// Shares a reel into a DM or a channel — a raw insert of `reel_id` +
  /// `message_type: 'reel_share'`. DM support comes from `messages.reel_id`
  /// / the widened `messages_message_type_check`
  /// (`20270424000000_reel_share_messages.sql`); channel support — the
  /// portal's `ChannelChat.tsx` "Share reel" button already uses this —
  /// comes from `channel_messages.reel_id` /
  /// `channel_messages_message_type_check`
  /// (`20271007060000_channel_messages_reel_share.sql`). [surface] is `'dm'`
  /// or `'channel'`, same convention as [sendPropertyShare].
  Future<void> sendReelShare({
    required String threadId,
    required String senderId,
    required String reelId,
    required String content,
    String surface = 'dm',
  }) async {
    final table = surface == 'channel' ? 'channel_messages' : 'messages';
    final idColumn = surface == 'channel' ? 'channel_id' : 'conversation_id';
    try {
      await _supabase.from(table).insert({
        idColumn: threadId,
        'sender_id': senderId,
        'content': content,
        'message_type': 'reel_share',
        'reel_id': reelId,
      });
    } catch (e) {
      debugPrint('MessagingService.sendReelShare failed: $e');
      throw mapSendError(e);
    }
  }

  /// Shares a builder project into a DM — the portal's exact call
  /// (`sendProjectShare` in useDmMessaging.ts): the already-deployed
  /// `dm-send-message` Edge Function with `kind: 'project'`, which itself
  /// checks the project exists and writes the `project_share` row (content
  /// "Shared project: <title>", rendered here as a normal text bubble).
  Future<void> sendProjectShare({
    required String conversationId,
    required String projectId,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'dm-send-message',
        body: {
          'conversationId': conversationId,
          'kind': 'project',
          'projectId': projectId,
        },
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
    } catch (e) {
      debugPrint('MessagingService.sendProjectShare failed: $e');
      throw mapSendError(e);
    }
  }

  /// Properties matching [term], sourced from `properties_public` — the
  /// exact same view+shape the portal's `SharePropertyModal.tsx` queries
  /// (`select id, title, price, location, media_urls`, `ilike title`,
  /// newest first, capped at 15).
  Future<List<SharedPropertyPreview>> searchProperties(String term) async {
    final query = term.trim();
    if (query.length < 2) return const [];

    try {
      final rows = await _supabase
          .from('properties_public')
          .select('id, title, price, location, media_urls')
          .ilike('title', '%$query%')
          .order('created_at', ascending: false)
          .limit(15);

      return List<Map<String, dynamic>>.from(rows as List)
          .where((row) => row['id'] != null)
          .map(SharedPropertyPreview.fromSupabase)
          .toList();
    } catch (e) {
      debugPrint('MessagingService.searchProperties failed: $e');
      rethrow;
    }
  }

  /// Batch-resolves every distinct `property_id` visible in a page of
  /// messages in one query — avoids an N+1 property lookup per
  /// `property_share` bubble, same `inFilter('id', ids)` pattern already
  /// used throughout this file (e.g. [listChannels]).
  Future<Map<String, SharedPropertyPreview>> fetchSharedProperties(
    Set<String> propertyIds,
  ) async {
    if (propertyIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('properties_public')
          .select('id, title, price, location, media_urls')
          .inFilter('id', propertyIds.toList());

      final result = <String, SharedPropertyPreview>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['id']?.toString();
        if (id == null) continue;
        result[id] = SharedPropertyPreview.fromSupabase(row);
      }
      return result;
    } catch (e) {
      debugPrint('MessagingService.fetchSharedProperties failed: $e');
      return const {};
    }
  }

  /// Same video/photo split `ReelsService._getPropertyVideoRows` uses when
  /// building a listing's own video as a reel — needed here too so a shared
  /// listing-video reel's preview shows its cover photo, never the raw video
  /// URL as a thumbnail.
  static final RegExp _reelVideoExtension = RegExp(
    r'\.(mp4|webm|ogg|mov|avi|m4v|mkv|3gp)$',
    caseSensitive: false,
  );
  static bool _isReelVideoUrl(String url) =>
      url.startsWith('data:video/') ||
      _reelVideoExtension.hasMatch(url.split('?').first);

  /// Batch-resolves every distinct `reel_id` visible in a page of messages in
  /// as few queries as possible — avoids an N+1 reel lookup per `reel_share`
  /// bubble, same `inFilter('id', ids)` pattern as [fetchSharedProperties].
  ///
  /// A `reel_id` can point at either an uploaded reel (`influencer_videos`)
  /// or a listing's own video played as a reel (`properties_public` — the
  /// same public-safe view [fetchSharedProperties] already reads), mirroring
  /// the two sources `ReelsService.getReels()` merges into one feed. There is
  /// no separate discriminator column on `messages.reel_id`, so this checks
  /// `influencer_videos` first and only queries `properties_public` for
  /// whatever ids it didn't find there — never both for the same id.
  /// Reels matching [term], for the in-chat reel picker - the portal's
  /// ShareReelModal search: the already-deployed `chat-share-search`
  /// function with `kind: 'reel'` (approved + active reels whose title
  /// matches, newest first, max 15, each with its owner's display name).
  /// Fewer than two characters never hits the server.
  Future<List<SharedReelPreview>> searchReels(String term) async {
    final query = term.trim();
    if (query.length < 2) return const [];

    final response = await _supabase.functions.invoke(
      'chat-share-search',
      body: {'kind': 'reel', 'term': query},
    );
    final data = response.data;
    final results = data is Map ? data['results'] : null;
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (r is Map && r['id'] != null)
          SharedReelPreview(
            id: r['id'].toString(),
            title: r['title']?.toString() ?? '',
            thumbnailUrl: (r['thumbnail_url']?.toString().isNotEmpty ?? false)
                ? r['thumbnail_url'].toString()
                : null,
            ownerName: r['owner_name']?.toString(),
          ),
    ];
  }

  /// Resolves the projects behind `project_share` messages — the portal's
  /// `ProjectShareMessage` fetch: the already-deployed `project-inventory-list`
  /// function, which returns the project's title/description/location (we
  /// ignore its inventory). A project that can't be loaded is simply absent,
  /// so the bubble falls back to the message text.
  Future<Map<String, SharedProjectPreview>> fetchSharedProjects(
    Set<String> projectIds,
  ) async {
    if (projectIds.isEmpty) return const {};
    final result = <String, SharedProjectPreview>{};
    await Future.wait([
      for (final id in projectIds)
        () async {
          try {
            final response = await _supabase.functions.invoke(
              'project-inventory-list',
              body: {'projectId': id, 'availableOnly': true},
            );
            final data = response.data;
            final project = data is Map ? data['project'] : null;
            if (project is! Map) return;
            result[id] = SharedProjectPreview(
              id: id,
              title: project['title']?.toString() ?? '',
              description: project['description']?.toString(),
              location: project['location']?.toString(),
            );
          } catch (e) {
            debugPrint('MessagingService.fetchSharedProjects($id) failed: $e');
          }
        }(),
    ]);
    return result;
  }

  Future<Map<String, SharedReelPreview>> fetchSharedReels(
    Set<String> reelIds,
  ) async {
    if (reelIds.isEmpty) return const {};
    final result = <String, SharedReelPreview>{};

    try {
      final rows = await _supabase
          .from('influencer_videos')
          .select('id, title, thumbnail_url')
          .inFilter('id', reelIds.toList());

      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['id']?.toString();
        if (id == null) continue;
        final title = (row['title'] as String?)?.trim();
        final thumbnail = (row['thumbnail_url'] as String?)?.trim();
        result[id] = SharedReelPreview(
          id: id,
          title: title != null && title.isNotEmpty ? title : 'Untitled reel',
          thumbnailUrl: thumbnail != null && thumbnail.isNotEmpty
              ? thumbnail
              : null,
        );
      }
    } catch (e) {
      debugPrint(
        'MessagingService.fetchSharedReels (influencer_videos) failed: $e',
      );
    }

    final remaining = reelIds.where((id) => !result.containsKey(id)).toList();
    if (remaining.isNotEmpty) {
      try {
        final rows = await _supabase
            .from('properties_public')
            .select('id, title, media_urls')
            .inFilter('id', remaining);

        for (final row in List<Map<String, dynamic>>.from(rows as List)) {
          final id = row['id']?.toString();
          if (id == null) continue;
          final media = List<dynamic>.from(row['media_urls'] ?? const [])
              .map((u) => u?.toString() ?? '')
              .where((u) => u.trim().isNotEmpty)
              .toList();
          final cover = media.where((u) => !_isReelVideoUrl(u)).firstOrNull;
          final title = (row['title'] as String?)?.trim();
          result[id] = SharedReelPreview(
            id: id,
            title: title != null && title.isNotEmpty ? title : 'Untitled reel',
            thumbnailUrl: cover,
          );
        }
      } catch (e) {
        debugPrint(
          'MessagingService.fetchSharedReels (properties_public) failed: $e',
        );
      }
    }

    return result;
  }

  /// Forwards a message into a *different* DM conversation — a brand-new
  /// message row copying the content, exactly like the portal's
  /// `ForwardMessageModal.tsx` (no `forwarded_from` reference/pointer column
  /// exists, so this can't and shouldn't invent one). Matches the portal's
  /// own scope exactly: DM target only, and only `text`/`property_share`
  /// source messages — image/voice forwarding is out of scope there too,
  /// since `get-chat-media-url`'s lookup assumes one message row per storage
  /// path, which a copied row would violate.
  Future<void> forwardMessage({
    required String targetConversationId,
    required String senderId,
    required ChatMessage message,
  }) async {
    if (message.isPropertyShare && message.propertyId != null) {
      await sendPropertyShare(
        threadId: targetConversationId,
        senderId: senderId,
        propertyId: message.propertyId!,
        content: message.content,
      );
      return;
    }
    await sendMessage(
      conversationId: targetConversationId,
      senderId: senderId,
      content: message.content,
    );
  }

  /// Unread count per conversation.
  ///
  /// Mirrors `useConversationUnreadCounts` — unread rows not sent by the
  /// caller, grouped client-side. RLS keeps the result to the caller's own
  /// conversations, which is why React issues no participant filter either.
  Future<Map<String, int>> unreadCountsByConversation(String userId) async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('conversation_id')
          .eq('is_read', false)
          .neq('sender_id', userId);

      final counts = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['conversation_id']?.toString();
        if (id == null) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      debugPrint('MessagingService.unreadCountsByConversation failed: $e');
      rethrow;
    }
  }

  /// Marks everything the other party sent as read.
  ///
  /// Mirrors `markConversationAsRead` in useConversationUnreadCounts.ts.
  /// Rethrows on failure so callers (the badge-clear reconciliation in
  /// [MessagingProvider]) can tell "marked read" apart from "silently
  /// failed" instead of the update vanishing without a trace.
  Future<void> markConversationAsRead({
    required String conversationId,
    required String userId,
  }) async {
    try {
      await _supabase
          .from('messages')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('MessagingService.markConversationAsRead failed: $e');
      rethrow;
    }
  }

  // ── Starting a new conversation ───────────────────────────────────────────

  /// Minimum characters before the recipient search runs, matching
  /// NewChatModal.tsx's `term.trim().length < 2` guard.
  static const int recipientSearchMinLength = 2;

  /// Candidate recipients matching [term].
  ///
  /// Mirrors `handleSearch` in features/messaging/NewChatModal.tsx — same
  /// table, same columns, same moderation filters (case-insensitive name
  /// match, excluding self, approved and not admin-blocked) and the same
  /// 10-row limit. On top of that — `profiles.is_blocked` is an admin
  /// moderation flag, not the caller's personal block list — this also
  /// excludes anyone the *caller* has personally blocked via `user_blocks`,
  /// which the original implementation confused with the moderation flag and
  /// never actually excluded.
  Future<List<ConversationParticipant>> searchRecipients({
    required String term,
    required String currentUserId,
  }) async {
    final query = term.trim();
    if (query.length < recipientSearchMinLength) return const [];

    try {
      final blockedIds = await myBlockedUserIds(currentUserId);

      final rows = await _supabase
          .from('profiles')
          .select('user_id, display_name, avatar_url, user_type')
          .ilike('display_name', '%$query%')
          .neq('user_id', currentUserId)
          .eq('approval_status', 'approved')
          .eq('is_blocked', false)
          .limit(10);

      return List<Map<String, dynamic>>.from(rows as List)
          .where((row) => row['user_id'] != null)
          .where((row) => !blockedIds.contains(row['user_id'].toString()))
          .map(
            (row) => ConversationParticipant(
              userId: row['user_id'].toString(),
              displayName: (row['display_name'] as String?) ?? 'Unknown',
              avatarUrl: row['avatar_url'] as String?,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('MessagingService.searchRecipients failed: $e');
      rethrow;
    }
  }

  /// The caller's own personal block list — ids in `user_blocks` where
  /// `blocker_id = currentUserId`. Deliberately one-directional (never "who
  /// has blocked me"): the portal doesn't expose that to the blocked party
  /// either, so mobile doesn't infer or surface it.
  Future<Set<String>> myBlockedUserIds(String currentUserId) async {
    try {
      final rows = await _supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', currentUserId);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map((r) => r['blocked_id']?.toString()).whereType<String>().toSet();
    } catch (e) {
      debugPrint('MessagingService.myBlockedUserIds failed: $e');
      return const {};
    }
  }

  /// Whether the caller has personally blocked [otherUserId] — the one
  /// direction that's ever surfaced in the UI (see [myBlockedUserIds]).
  Future<bool> haveIBlocked(String currentUserId, String otherUserId) async {
    try {
      final rows = await _supabase
          .from('user_blocks')
          .select('blocked_id')
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', otherUserId)
          .limit(1);
      return List.from(rows as List).isNotEmpty;
    } catch (e) {
      debugPrint('MessagingService.haveIBlocked failed: $e');
      return false;
    }
  }

  /// Profiles the caller has personally blocked, for the "Blocked Users"
  /// management screen.
  Future<List<ConversationParticipant>> fetchBlockedUsers(
    String currentUserId,
  ) async {
    try {
      final ids = await myBlockedUserIds(currentUserId);
      if (ids.isEmpty) return const [];
      final profiles = await _fetchPublicProfiles(ids);
      return profiles.values.toList();
    } catch (e) {
      debugPrint('MessagingService.fetchBlockedUsers failed: $e');
      rethrow;
    }
  }

  /// Starts (or reuses) a conversation and immediately hides it for the
  /// caller — used to "decline" a message request, mirroring the portal's
  /// `hideConversation` being reused for the decline action.
  Future<void> hideConversation(String conversationId) async {
    try {
      await _supabase.rpc(
        'hide_conversation',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      debugPrint('MessagingService.hideConversation failed: $e');
      rethrow;
    }
  }

  /// Accepts a pending message request — flips the caller's own
  /// `request_status` to `'accepted'` so they can now reply.
  Future<void> acceptConversationRequest(String conversationId) async {
    try {
      await _supabase.rpc(
        'accept_conversation_request',
        params: {'p_conversation_id': conversationId},
      );
    } catch (e) {
      debugPrint('MessagingService.acceptConversationRequest failed: $e');
      rethrow;
    }
  }

  Future<void> setConversationMuted(String conversationId, bool muted) async {
    try {
      await _supabase.rpc(
        'set_conversation_muted',
        params: {'p_conversation_id': conversationId, 'p_muted': muted},
      );
    } catch (e) {
      debugPrint('MessagingService.setConversationMuted failed: $e');
      rethrow;
    }
  }

  Future<void> setChannelMuted(String channelId, bool muted) async {
    try {
      await _supabase.rpc(
        'set_channel_muted',
        params: {'p_channel_id': channelId, 'p_muted': muted},
      );
    } catch (e) {
      debugPrint('MessagingService.setChannelMuted failed: $e');
      rethrow;
    }
  }

  /// Returns the conversation id shared with [withUserId], creating it if there
  /// isn't one yet.
  ///
  /// Delegates to the existing `start_conversation(with_user_id uuid)` RPC —
  /// the same call `Chat.tsx` and `ChatModal.tsx` make. The function is
  /// SECURITY DEFINER and idempotent: it looks for an existing conversation
  /// between the two users first and only inserts when none exists, adding
  /// both participant rows itself. Doing this client-side instead would mean
  /// writing `conversations` and `conversation_participants` directly, which
  /// the RLS policies deliberately do not allow.
  ///
  /// [skipRequestGate] mirrors the portal's `p_skip_request_gate`: pass
  /// `true` only for a conversation started from a genuine property/lead
  /// context (the sender explicitly shares a listing) — every other caller
  /// must pass `false` so the recipient's row starts `pending` and has to be
  /// accepted before the sender's replies land. The default here is `false`
  /// (the *safer*, more-gated choice, deliberately the opposite of the RPC's
  /// own `p_skip_request_gate default true`) so a future call site that
  /// forgets to specify it fails safe into "gated" rather than silently
  /// bypassing the request flow — this default was the exact bug fixed in
  /// this repair pass (every existing caller now passes the flag explicitly
  /// regardless).
  Future<String> startConversation(
    String withUserId, {
    bool skipRequestGate = false,
  }) async {
    try {
      final result = await _supabase.rpc(
        'start_conversation',
        params: {
          'with_user_id': withUserId,
          'p_skip_request_gate': skipRequestGate,
        },
      );

      final conversationId = result?.toString();
      if (conversationId == null || conversationId.isEmpty) {
        throw 'This user account is no longer available.';
      }
      return conversationId;
    } catch (e) {
      debugPrint('MessagingService.startConversation failed: $e');
      rethrow;
    }
  }

  /// Whether the caller and [otherUserId] have blocked each other, in either
  /// direction. Never raises — returns `false` if unauthenticated.
  Future<bool> isBlockedWith(String otherUserId) async {
    try {
      final result = await _supabase.rpc(
        'is_blocked_with',
        params: {'p_other_user_id': otherUserId},
      );
      return result == true;
    } catch (e) {
      debugPrint('MessagingService.isBlockedWith failed: $e');
      return false;
    }
  }

  // ── Channels (group) ──────────────────────────────────────────────────────

  /// [listChannels]'s own sort: most-recent-activity first. A channel with
  /// no messages yet has no `lastMessageAt`, so this falls back to its own
  /// `createdAt` rather than always sorting it to the bottom — which is what
  /// previously sent a just-created, empty channel straight to the end of
  /// the list instead of the top. Extracted (`@visibleForTesting`) so this
  /// ordering can be pinned down without a live Supabase call.
  @visibleForTesting
  static int compareChannelsByRecentActivity(
    ChannelSummary a,
    ChannelSummary b,
  ) {
    final at = a.lastMessageAt ?? a.createdAt;
    final bt = b.lastMessageAt ?? b.createdAt;
    if (at == null && bt == null) return a.name.compareTo(b.name);
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  /// Channels the user has joined.
  ///
  /// Mirrors `fetchChannels` in features/messaging/ChannelsList.tsx: the
  /// caller's memberships first, then the channel rows, then a participant
  /// count and last-message timestamp per channel. The per-channel counts are
  /// batched here for the same reason as [listConversations].
  Future<List<ChannelSummary>> listChannels(String userId) async {
    try {
      final membershipRows = await _supabase
          .from('channel_participants')
          .select('channel_id, role, muted_at')
          .eq('user_id', userId);

      final memberships = List<Map<String, dynamic>>.from(
        membershipRows as List,
      ).where((m) => m['channel_id'] != null).toList();
      if (memberships.isEmpty) return const [];

      final channelIds = memberships
          .map((m) => m['channel_id'].toString())
          .toList();
      final roleByChannel = {
        for (final m in memberships)
          m['channel_id'].toString(): m['role'] as String?,
      };
      final mutedByChannel = {
        for (final m in memberships)
          m['channel_id'].toString(): m['muted_at'] != null,
      };

      final channelRows = await _supabase
          .from('channels')
          .select(
            'id, name, description, created_at, created_by, '
            'max_participants',
          )
          .inFilter('id', channelIds);

      final allParticipants = await _supabase
          .from('channel_participants')
          .select('channel_id')
          .inFilter('channel_id', channelIds);

      final participantCounts = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(
        allParticipants as List,
      )) {
        final id = row['channel_id']?.toString();
        if (id == null) continue;
        participantCounts[id] = (participantCounts[id] ?? 0) + 1;
      }

      final messageRows = await _supabase
          .from('channel_messages')
          .select('channel_id, created_at, sender_id, is_read')
          .inFilter('channel_id', channelIds)
          .order('created_at', ascending: false);

      final lastMessageAt = <String, DateTime>{};
      final unread = <String, int>{};
      for (final row in List<Map<String, dynamic>>.from(messageRows as List)) {
        final id = row['channel_id']?.toString();
        if (id == null) continue;
        final created = row['created_at'] as String?;
        final parsed = created == null ? null : DateTime.tryParse(created);
        if (parsed != null && !lastMessageAt.containsKey(id)) {
          lastMessageAt[id] = parsed;
        }
        // Same rule the unread hooks apply: not mine and not yet read.
        if (row['is_read'] != true && row['sender_id']?.toString() != userId) {
          unread[id] = (unread[id] ?? 0) + 1;
        }
      }

      final channels =
          List<Map<String, dynamic>>.from(
              channelRows as List,
            ).where((row) => row['id'] != null).map((row) {
              final id = row['id'].toString();
              return ChannelSummary.fromSupabase(
                row,
                myRole: roleByChannel[id],
                participantCount: participantCounts[id] ?? 0,
                lastMessageAt: lastMessageAt[id],
                unreadCount: unread[id] ?? 0,
                isMuted: mutedByChannel[id] ?? false,
              );
            }).toList()
            ..sort(compareChannelsByRecentActivity);

      return channels;
    } catch (e) {
      debugPrint('MessagingService.listChannels failed: $e');
      rethrow;
    }
  }

  /// Most recent page of a channel, oldest-first for display. Mirrors
  /// `fetchMessages` in features/messaging/ChannelChat.tsx, paginated the
  /// same way as [listMessages].
  Future<List<ChatMessage>> listChannelMessages(
    String channelId, {
    DateTime? before,
    DateTime? after,
  }) async {
    try {
      var query = _supabase
          .from('channel_messages')
          .select(_channelMessageColumns)
          .eq('channel_id', channelId);

      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      if (after != null) {
        query = query.gt('created_at', after.toUtc().toIso8601String());
      }

      if (after != null) {
        final rows = await query
            .order('created_at', ascending: true)
            .limit(mergeFetchCap);
        return List<Map<String, dynamic>>.from(
          rows as List,
        ).map(ChatMessage.fromSupabase).toList();
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(messagePageSize);

      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(ChatMessage.fromSupabase).toList().reversed.toList();
    } catch (e) {
      debugPrint('MessagingService.listChannelMessages failed: $e');
      rethrow;
    }
  }

  /// Display names/avatars for a set of channel senders.
  ///
  /// A channel thread shows who sent each message, which the 1:1 thread does
  /// not need. Resolved in one batched round-trip.
  Future<Map<String, ConversationParticipant>> fetchSenderProfiles(
    Set<String> senderIds,
  ) => _fetchPublicProfiles(senderIds);

  /// Mirrors `sendMessage` in ChannelChat.tsx: moderate first (fail-open),
  /// then insert, mapping rate-limit/RLS errors to the portal's exact copy.
  Future<void> sendChannelMessage({
    required String channelId,
    required String senderId,
    required String content,
    String? replyToId,
  }) async {
    final trimmed = content.trim();
    await moderateText(trimmed);

    try {
      await _supabase.from('channel_messages').insert({
        'channel_id': channelId,
        'sender_id': senderId,
        'content': trimmed,
        'message_type': 'text',
        if (replyToId != null) 'reply_to_id': replyToId,
      });
    } catch (e) {
      debugPrint('MessagingService.sendChannelMessage failed: $e');
      throw mapSendError(e);
    }
  }

  /// Mirrors `markMessagesAsRead` in ChannelChat.tsx. Rethrows on failure —
  /// see [markConversationAsRead].
  Future<void> markChannelAsRead({
    required String channelId,
    required String userId,
  }) async {
    try {
      await _supabase
          .from('channel_messages')
          .update({
            'is_read': true,
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('channel_id', channelId)
          .neq('sender_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('MessagingService.markChannelAsRead failed: $e');
      rethrow;
    }
  }

  // ── Message actions (reply/react/edit/delete) — shared by DM & channel ────
  //
  // `surface` is always the literal string 'dm' or 'channel', matching the
  // portal's features/messaging/lib/messageActions.ts.

  Future<String> toggleReaction({
    required String messageId,
    required String surface,
    required String emoji,
  }) async {
    try {
      final result = await _supabase.rpc(
        'toggle_reaction',
        params: {
          'p_message_id': messageId,
          'p_surface': surface,
          'p_emoji': emoji,
        },
      );
      return result as String? ?? 'added';
    } catch (e) {
      debugPrint('MessagingService.toggleReaction failed: $e');
      rethrow;
    }
  }

  /// Reactions for a batch of messages on one surface, grouped by message id
  /// then by emoji.
  Future<Map<String, List<MessageReaction>>> fetchReactions({
    required List<String> messageIds,
    required String surface,
  }) async {
    if (messageIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('message_reactions')
          .select('message_id, emoji, user_id')
          .eq('surface', surface)
          .inFilter('message_id', messageIds);

      final byMessage = <String, List<Map<String, dynamic>>>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['message_id']?.toString();
        if (id == null) continue;
        (byMessage[id] ??= []).add(row);
      }
      return {
        for (final entry in byMessage.entries)
          entry.key: MessageReaction.groupByEmoji(entry.value),
      };
    } catch (e) {
      debugPrint('MessagingService.fetchReactions failed: $e');
      rethrow;
    }
  }

  Future<void> editMessage({
    required String messageId,
    required String surface,
    required String newContent,
  }) async {
    try {
      await _supabase.rpc(
        'edit_message',
        params: {
          'p_message_id': messageId,
          'p_surface': surface,
          'p_new_content': newContent.trim(),
        },
      );
    } catch (e) {
      debugPrint('MessagingService.editMessage failed: $e');
      rethrow;
    }
  }

  Future<void> deleteMessageForMe({
    required String messageId,
    required String surface,
  }) async {
    try {
      await _supabase.rpc(
        'delete_message_for_me',
        params: {'p_message_id': messageId, 'p_surface': surface},
      );
    } catch (e) {
      debugPrint('MessagingService.deleteMessageForMe failed: $e');
      rethrow;
    }
  }

  Future<void> deleteMessageForEveryone({
    required String messageId,
    required String surface,
  }) async {
    try {
      await _supabase.rpc(
        'delete_message_for_everyone',
        params: {'p_message_id': messageId, 'p_surface': surface},
      );
    } catch (e) {
      debugPrint('MessagingService.deleteMessageForEveryone failed: $e');
      rethrow;
    }
  }

  // ── Moderation & presence ──────────────────────────────────────────────

  /// Calls the `moderate-comment` edge function before a text send. Fails
  /// open on any transport/parsing error (matching the portal exactly) —
  /// only an explicit `isAllowed: false` blocks the send.
  Future<void> moderateText(String text) async {
    if (text.isEmpty) return;
    try {
      final response = await _supabase.functions.invoke(
        'moderate-comment',
        body: {'comment': text},
      );
      final data = response.data;
      if (data is Map && data['isAllowed'] == false) {
        throw MessageModerationError(
          (data['reason'] as String?) ?? "This message isn't allowed.",
        );
      }
    } on MessageModerationError {
      rethrow;
    } catch (e) {
      debugPrint('MessagingService.moderateText failed open: $e');
    }
  }

  /// Heartbeat — the only legal way to write `profiles.is_online`/
  /// `last_seen_at`; a raw `.update()` on `profiles` is silently stripped of
  /// those two columns by a DB trigger for any non-service-role caller.
  Future<void> updateOwnPresence(bool isOnline) async {
    try {
      await _supabase.rpc(
        'update_own_presence',
        params: {'p_is_online': isOnline},
      );
    } catch (e) {
      debugPrint('MessagingService.updateOwnPresence failed: $e');
    }
  }

  // ── Blocking & reporting ───────────────────────────────────────────────

  /// Idempotent: blocking someone who is already blocked is treated as
  /// success (the desired end state — "this person is blocked" — already
  /// holds), rather than surfacing the `user_blocks_pkey` unique-constraint
  /// violation a plain insert would throw on a repeat call.
  Future<void> blockUser(String userId) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) throw StateError('Not authenticated');
      await _supabase.from('user_blocks').insert({
        'blocker_id': me,
        'blocked_id': userId,
      });
    } catch (e) {
      if (postgrestErrorCode(e) == '23505') {
        debugPrint(
          'MessagingService.blockUser: already blocked, treating as success',
        );
        return;
      }
      debugPrint('MessagingService.blockUser failed: $e');
      rethrow;
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) throw StateError('Not authenticated');
      await _supabase
          .from('user_blocks')
          .delete()
          .eq('blocker_id', me)
          .eq('blocked_id', userId);
    } catch (e) {
      debugPrint('MessagingService.unblockUser failed: $e');
      rethrow;
    }
  }

  // ── Channel administration ─────────────────────────────────────────────
  //
  // `channels` INSERT is self-service for any authenticated user
  // (`created_by = auth.uid()`); adding participants requires being the
  // creator or an existing admin/moderator — see
  // 20250823170108_..._fix_channel_rls.sql. Creating a channel does not
  // auto-add the creator as a participant, so that's a second insert here,
  // which the same RLS policy explicitly allows for the creator.

  Future<String> createChannel({
    required String name,
    String? description,
  }) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) throw StateError('Not authenticated');

      final inserted = await _supabase
          .from('channels')
          .insert({
            'name': name.trim(),
            if (description != null && description.trim().isNotEmpty)
              'description': description.trim(),
            'created_by': me,
          })
          .select('id')
          .single();

      final channelId = inserted['id']?.toString();
      if (channelId == null) {
        throw StateError('Channel insert returned no id');
      }

      await _supabase.from('channel_participants').insert({
        'channel_id': channelId,
        'user_id': me,
        'role': 'admin',
      });

      return channelId;
    } catch (e) {
      debugPrint('MessagingService.createChannel failed: $e');
      rethrow;
    }
  }

  /// Adds an existing user to a channel — admin/moderator/creator only,
  /// server-enforced. Used only by channel *creation* (seeding initial
  /// members, where the inserting user is always the brand-new creator);
  /// adding a member to an *existing* channel from the settings screen goes
  /// through [addChannelMembers] instead, matching the portal's own split
  /// (`CreateChannelModal.tsx` inserts directly; `ChannelSettingsModal.tsx`
  /// calls the `channel-members-add` edge function for its extra validation —
  /// the max_participants cap and re-adding a previously-removed member).
  Future<void> addChannelParticipant({
    required String channelId,
    required String userId,
  }) async {
    try {
      await _supabase.from('channel_participants').insert({
        'channel_id': channelId,
        'user_id': userId,
        'role': 'member',
      });
    } catch (e) {
      debugPrint('MessagingService.addChannelParticipant failed: $e');
      rethrow;
    }
  }

  /// Leaves a channel via the `channel-leave` Edge Function rather than a
  /// direct `channel_participants` delete — admin succession (promoting the
  /// longest-standing active moderator, or else member, and transferring
  /// `channels.created_by` when the creator leaves) must happen atomically
  /// server-side via `leave_channel_with_succession`; a plain client delete
  /// could leave a channel with no admin at all. [userId] is accepted for
  /// call-site compatibility but unused — the function derives the caller
  /// from the verified JWT, never a client-supplied id.
  Future<void> leaveChannel(String channelId, String userId) async {
    await _invokeChannelFn('channel-leave', {'channelId': channelId});
  }

  // ── Channel settings & member management ───────────────────────────────
  //
  // Mirrors `ChannelSettingsModal.tsx` exactly: every write here goes through
  // the same edge function the portal uses (channel-settings-update,
  // channel-members-add, channel-member-remove, channel-member-block,
  // channel-participants-list) rather than a direct table call, because each
  // one re-verifies the caller's real permissions server-side — see each
  // function's own header comment. In particular, `channels` UPDATE RLS only
  // allows the literal creator, and `channel_participants` has no UPDATE RLS
  // policy at all, so admin-remove and admin-block can only ever happen
  // through these functions, never a plain table call.

  Future<Map<String, dynamic>> _invokeChannelFn(
    String name,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _supabase.functions.invoke(name, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw ChannelAdminError(data['error'].toString());
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on ChannelAdminError {
      rethrow;
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw ChannelAdminError(
        message?.toString() ?? 'That action could not be completed.',
      );
    } catch (e) {
      throw const ChannelAdminError(
        'A network error occurred. Please try again.',
      );
    }
  }

  /// The channel's own settings row — for prefilling the Settings tab and
  /// deriving `isAdmin` (`created_by == me`).
  Future<Map<String, dynamic>> fetchChannelInfo(String channelId) async {
    try {
      final row = await _supabase
          .from('channels')
          .select(
            'id, name, description, created_by, max_participants, '
            'messaging_permission',
          )
          .eq('id', channelId)
          .single();
      return Map<String, dynamic>.from(row as Map);
    } catch (e) {
      debugPrint('MessagingService.fetchChannelInfo failed: $e');
      rethrow;
    }
  }

  /// Participants with their admin-moderation state (role, `blocked_at`, row
  /// id) via `channel-participants-list`, which also resolves each member's
  /// profile server-side in one round trip.
  Future<List<ChannelParticipantDetail>> fetchChannelParticipantsDetailed(
    String channelId,
  ) async {
    final data = await _invokeChannelFn('channel-participants-list', {
      'channelId': channelId,
    });
    final rows = (data['participants'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return rows.map(ChannelParticipantDetail.fromJson).toList();
  }

  /// Updates name/description/max participants/who-can-message. Creator-only
  /// server-side — see `channel-settings-update`'s header comment.
  Future<void> updateChannelSettings({
    required String channelId,
    required String name,
    String? description,
    required int maxParticipants,
    required String messagingPermission,
  }) {
    return _invokeChannelFn('channel-settings-update', {
      'channelId': channelId,
      'name': name,
      'description': description ?? '',
      'maxParticipants': maxParticipants,
      'messagingPermission': messagingPermission,
    });
  }

  /// Adds one or more existing users to an existing channel — admin only.
  /// Returns how many were actually added (may be fewer than requested if
  /// some were already members).
  Future<int> addChannelMembers({
    required String channelId,
    required List<String> userIds,
  }) async {
    final data = await _invokeChannelFn('channel-members-add', {
      'channelId': channelId,
      'userIds': userIds,
    });
    return (data['added'] as num?)?.toInt() ?? 0;
  }

  /// Soft-removes a member — admin/moderator only, never the creator. See
  /// `channel-member-remove`'s header comment for why this isn't a plain RLS
  /// delete (a hard delete would also erase the removed member's read access
  /// to the channel's history).
  Future<void> removeChannelParticipant({
    required String channelId,
    required String participantRowId,
    required String targetUserId,
  }) {
    return _invokeChannelFn('channel-member-remove', {
      'channelId': channelId,
      'participantRowId': participantRowId,
      'targetUserId': targetUserId,
    });
  }

  /// Channel-wide admin block/unblock — distinct from [blockUser] (the
  /// personal, any-member, viewer-scoped block further down). Admin/
  /// moderator only, never the creator or self.
  Future<void> setChannelParticipantBlocked({
    required String channelId,
    required String participantRowId,
    required String targetUserId,
    required bool blocked,
  }) {
    return _invokeChannelFn('channel-member-block', {
      'channelId': channelId,
      'participantRowId': participantRowId,
      'targetUserId': targetUserId,
      'blocked': blocked,
    });
  }

  Future<void> reportMessage({
    required String messageId,
    required String surface,
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    try {
      final me = _supabase.auth.currentUser?.id;
      if (me == null) throw StateError('Not authenticated');
      await _supabase.from('message_reports').insert({
        'reporter_id': me,
        'reported_user_id': reportedUserId,
        'message_id': messageId,
        'surface': surface,
        'reason': reason,
        if (details != null) 'details': details,
      });
    } catch (e) {
      debugPrint('MessagingService.reportMessage failed: $e');
      rethrow;
    }
  }
}
