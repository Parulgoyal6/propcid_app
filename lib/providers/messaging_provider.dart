import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/launch_features.dart';
import '../models/channel_summary.dart';
import '../models/collaboration.dart';
import '../models/conversation_summary.dart';
import '../services/collaboration_exceptions.dart';
import '../services/collaboration_service.dart';
import '../services/messaging_service.dart';
import '../services/presence_service.dart';

/// One row in the Collabs tab — a bare request (no conversation yet) or an
/// accepted-or-later collaboration, with its counterparty and any attached
/// reels resolved. Mirrors `Chat.tsx`'s merged `pendingRequests` +
/// `conversations.filter(c => c.collaboration_id)` list.
class CollabInboxEntry {
  final Collaboration collaboration;
  final ConversationParticipant? counterparty;
  final List<CollabReelPreview> attachedReels;

  /// This collaboration's own conversation unread count (0 while still
  /// `requested`, since there is no conversation yet) — drives the numeric
  /// badge on active collaboration rows, cross-referenced from the same
  /// `conversations` read the Chats tab uses, by `conversation_id`.
  final int unreadCount;

  const CollabInboxEntry({
    required this.collaboration,
    this.counterparty,
    this.attachedReels = const [],
    this.unreadCount = 0,
  });

  /// Only meaningful while [collaboration.isRequested] — who this request is
  /// waiting on. `Chat.tsx`: `recipient = initiated_by === 'influencer' ?
  /// client_id : influencer_id`.
  bool isIncomingFor(String userId) {
    final recipient = collaboration.initiatedBy == CollabRoles.influencer
        ? collaboration.clientId
        : collaboration.influencerId;
    return recipient == userId;
  }
}

/// State for the Messages list — the Chats and Channels tabs.
///
/// Follows the shape of `IndividualDashboardProvider` (blueprint §1.2.1). The
/// two tabs load independently so a failure in one never blanks the other.
///
/// Live updates mirror React: a Realtime subscription on `messages` and
/// `channel_messages` refetches on any change, exactly as
/// useConversationUnreadCounts.ts and useUnreadMessages.ts do.
class MessagingProvider extends ChangeNotifier {
  MessagingProvider({
    MessagingService? service,
    CollaborationService? collabService,
    @visibleForTesting bool? loadCollabs,
  }) : _service = service ?? MessagingService(),
       _collabService = collabService ?? CollaborationService(),
       _collabsEnabled = loadCollabs ?? LaunchFeatures.paidCollaborations;

  final MessagingService _service;
  final CollaborationService _collabService;

  /// Whether collaboration loading runs at all. Defaults to
  /// [LaunchFeatures.paidCollaborations] — every production call site
  /// leaves this null. Tests exercising the collaboration-marketplace
  /// loading logic itself (unaffected by this launch-flags pass, per its
  /// own scope) pass `true` explicitly, since the compiled-in flag default
  /// is false for every `flutter test` run.
  final bool _collabsEnabled;
  final SupabaseClient _supabase = Supabase.instance.client;
  final PresenceService _presence = PresenceService();

  RealtimeChannel? _realtime;
  String? _userId;
  bool _disposed = false;

  /// Discards a slow response if a newer load/refresh has since started, so a
  /// realtime-triggered refresh racing with a pull-to-refresh can't clobber a
  /// more recent result with a stale one.
  int _conversationsRequestId = 0;
  int _channelsRequestId = 0;
  int _collabsRequestId = 0;

  /// Every conversation the caller is a party to, INCLUDING collaboration
  /// threads — kept privately only to cross-reference each collaboration's
  /// own unread count in [_loadCollabs]. The public [conversations] getter
  /// below is the Chats-tab-only, collaboration-free view.
  List<ConversationSummary> _allConversations = const [];
  bool _conversationsLoading = true;
  bool _conversationsFailed = false;

  List<ChannelSummary> _channels = const [];
  bool _channelsLoading = true;
  bool _channelsFailed = false;

  List<CollabInboxEntry> _collabs = const [];
  bool _collabsLoading = true;
  bool _collabsFailed = false;

  /// Chats tab only — `Chat.tsx`'s `plainConversations`: every collaboration
  /// conversation is excluded here so it can never appear in both tabs at
  /// once. Collaboration conversations surface only via [collabs].
  List<ConversationSummary> get conversations =>
      List.unmodifiable(_allConversations.where((c) => !c.isCollaboration));
  bool get conversationsLoading => _conversationsLoading;
  bool get conversationsFailed => _conversationsFailed;

  List<ChannelSummary> get channels => List.unmodifiable(_channels);
  bool get channelsLoading => _channelsLoading;
  bool get channelsFailed => _channelsFailed;

  List<CollabInboxEntry> get collabs => List.unmodifiable(_collabs);
  bool get collabsLoading => _collabsLoading;
  bool get collabsFailed => _collabsFailed;

  /// Sum of every active collaboration's own conversation unread count —
  /// the Collabs tab's numeric badge, alongside (not instead of) the
  /// incoming-request dot below.
  int get totalCollabUnread =>
      _collabs.fold(0, (sum, e) => sum + e.unreadCount);

  /// Drives the Collabs tab's badge dot — an incoming request the signed-in
  /// user hasn't acted on yet.
  bool get hasIncomingCollabRequest {
    final userId = _userId;
    if (userId == null) return false;
    return _collabs.any(
      (e) => e.collaboration.isRequested && e.isIncomingFor(userId),
    );
  }

  Future<void> load(String userId) async {
    _userId = userId;
    _presence.attach();
    _subscribe(userId);
    await Future.wait([
      _loadConversations(userId),
      _loadChannels(userId),
      _loadCollabs(userId),
    ]);
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    await Future.wait([
      _loadConversations(userId),
      _loadChannels(userId),
      _loadCollabs(userId),
    ]);
  }

  Future<void> _loadConversations(String userId) async {
    final requestId = ++_conversationsRequestId;
    final hadData = _allConversations.isNotEmpty;
    _conversationsLoading = true;
    // A transient refresh failure must not wipe an already-populated list —
    // only a genuine first load starts from "failed" being meaningful as
    // "nothing to show".
    if (!hadData) _conversationsFailed = false;
    _safeNotify();

    try {
      final loaded = await _service.listConversations(userId);
      if (requestId != _conversationsRequestId) return;
      _allConversations = loaded;
      _conversationsFailed = false;
    } catch (e) {
      if (requestId != _conversationsRequestId) return;
      debugPrint('MessagingProvider._loadConversations failed: $e');
      if (!hadData) {
        _conversationsFailed = true;
        _allConversations = const [];
      }
      // else: keep showing the last-known-good list; the pull-to-refresh
      // spinner simply stops with nothing changed.
    } finally {
      if (requestId == _conversationsRequestId) {
        _conversationsLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> _loadChannels(String userId) async {
    final requestId = ++_channelsRequestId;
    final hadData = _channels.isNotEmpty;
    _channelsLoading = true;
    if (!hadData) _channelsFailed = false;
    _safeNotify();

    try {
      final loaded = await _service.listChannels(userId);
      if (requestId != _channelsRequestId) return;
      _channels = loaded;
      _channelsFailed = false;
    } catch (e) {
      if (requestId != _channelsRequestId) return;
      debugPrint('MessagingProvider._loadChannels failed: $e');
      if (!hadData) {
        _channelsFailed = true;
        _channels = const [];
      }
    } finally {
      if (requestId == _channelsRequestId) {
        _channelsLoading = false;
        _safeNotify();
      }
    }
  }

  Future<void> _loadCollabs(String userId) async {
    if (!_collabsEnabled) {
      _collabs = const [];
      _collabsLoading = false;
      _collabsFailed = false;
      _safeNotify();
      return;
    }

    final requestId = ++_collabsRequestId;
    final hadData = _collabs.isNotEmpty;
    _collabsLoading = true;
    if (!hadData) _collabsFailed = false;
    _safeNotify();

    try {
      final rows = await _collabService.listMyCollaborations(userId);
      if (requestId != _collabsRequestId) return;

      final counterpartyIds = rows
          .map((c) => c.counterpartyIdFor(userId))
          .whereType<String>()
          .toSet();
      final reelIds = rows.expand((c) => c.attachedReelIds).toSet();

      final profiles = await _collabService.resolveProfiles(counterpartyIds);
      final reels = await _collabService.resolveReels(reelIds);
      if (requestId != _collabsRequestId) return;

      // A `declined` request never gains a conversation (only `accept`
      // creates one), so it can never leave `requested` behind as an inert,
      // unopenable card — filtering to "still a live request" OR "has a
      // conversation" drops it (and anything else that is neither) from the
      // list entirely rather than rendering it disabled forever.
      final unreadByCollabId = {
        for (final c in _allConversations)
          if (c.collaborationId != null) c.collaborationId!: c.unreadCount,
      };

      _collabs = rows
          .where((c) => c.isRequested || c.hasConversation)
          .map(
            (c) => CollabInboxEntry(
              collaboration: c,
              counterparty: profiles[c.counterpartyIdFor(userId)],
              attachedReels: c.attachedReelIds
                  .map((id) => reels[id])
                  .whereType<CollabReelPreview>()
                  .toList(),
              unreadCount: unreadByCollabId[c.id] ?? 0,
            ),
          )
          .toList();
      _collabsFailed = false;
    } catch (e) {
      if (requestId != _collabsRequestId) return;
      debugPrint('MessagingProvider._loadCollabs failed: $e');
      if (!hadData) {
        _collabsFailed = true;
        _collabs = const [];
      }
    } finally {
      if (requestId == _collabsRequestId) {
        _collabsLoading = false;
        _safeNotify();
      }
    }
  }

  /// Recipient-only server-side (`collab_transition`'s `accept` branch).
  /// Returns the accepted row (now carrying its new `conversation_id`) so the
  /// caller can open that thread directly, or an error message.
  Future<(Collaboration?, String?)> acceptCollab(String collaborationId) async {
    try {
      final updated = await _collabService.accept(collaborationId);
      await refresh();
      return (updated, null);
    } catch (e) {
      debugPrint('MessagingProvider.acceptCollab failed: $e');
      return (
        null,
        e is CollaborationException
            ? e.message
            : "Couldn't accept the request.",
      );
    }
  }

  Future<String?> declineCollab(String collaborationId) async {
    try {
      await _collabService.decline(collaborationId);
      await refresh();
      return null;
    } catch (e) {
      debugPrint('MessagingProvider.declineCollab failed: $e');
      return e is CollaborationException
          ? e.message
          : "Couldn't decline the request.";
    }
  }

  /// Clears a conversation's badge locally so the list reflects the tap
  /// immediately; the authoritative update happens in the thread and the
  /// Realtime callback reconciles it. Returns the prior count so a failed
  /// mark-as-read can be rolled back with [restoreConversationBadge].
  int clearConversationBadge(String conversationId) {
    var prior = 0;
    _allConversations = _allConversations.map((c) {
      if (c.id != conversationId) return c;
      prior = c.unreadCount;
      return c.copyWith(unreadCount: 0);
    }).toList();
    _safeNotify();
    return prior;
  }

  /// Rolls back an optimistic [clearConversationBadge] when the thread's own
  /// mark-as-read call actually failed, so the badge doesn't lie about
  /// unread state until the next full refresh.
  void restoreConversationBadge(String conversationId, int count) {
    if (count <= 0) return;
    _allConversations = _allConversations
        .map((c) => c.id == conversationId ? c.copyWith(unreadCount: count) : c)
        .toList();
    _safeNotify();
  }

  Future<String?> acceptRequest(String conversationId) async {
    try {
      await _service.acceptConversationRequest(conversationId);
      _allConversations = _allConversations
          .map(
            (c) => c.id == conversationId
                ? c.copyWith(requestStatus: 'accepted')
                : c,
          )
          .toList();
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('MessagingProvider.acceptRequest failed: $e');
      return "Couldn't accept the request.";
    }
  }

  /// Declining a request is implemented as "hide conversation for me",
  /// matching the portal exactly — the sender is never notified.
  Future<String?> declineRequest(String conversationId) async {
    try {
      await _service.hideConversation(conversationId);
      _allConversations = _allConversations
          .where((c) => c.id != conversationId)
          .toList();
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('MessagingProvider.declineRequest failed: $e');
      return "Couldn't decline the request.";
    }
  }

  /// Deletes this conversation for the signed-in user only — mirrors the
  /// portal's per-row "delete chat" action (`Chat.tsx`'s trash icon), which
  /// also just hides the caller's own copy. The other participant's copy and
  /// every message are untouched; a later reply from either side un-hides it,
  /// same as any other conversation [_service.hideConversation] already
  /// touches (declining a request uses the same RPC).
  Future<String?> deleteConversation(String conversationId) async {
    try {
      await _service.hideConversation(conversationId);
      _allConversations = _allConversations
          .where((c) => c.id != conversationId)
          .toList();
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('MessagingProvider.deleteConversation failed: $e');
      return "Couldn't delete the conversation.";
    }
  }

  Future<String?> setConversationMuted(
    String conversationId,
    bool muted,
  ) async {
    try {
      await _service.setConversationMuted(conversationId, muted);
      _allConversations = _allConversations
          .map((c) => c.id == conversationId ? c.copyWith(isMuted: muted) : c)
          .toList();
      _safeNotify();
      return null;
    } catch (e) {
      debugPrint('MessagingProvider.setConversationMuted failed: $e');
      return "Couldn't update mute setting.";
    }
  }

  void _subscribe(String userId) {
    if (_realtime != null) return;

    // Channel names must be unique per subscriber; React appends a random
    // suffix for the same reason.
    final suffix = DateTime.now().microsecondsSinceEpoch;
    _realtime = _supabase.channel('messages-list-$userId-$suffix')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'channel_messages',
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'conversation_participants',
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'collaborations',
        callback: (_) => refresh(),
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
    final channel = _realtime;
    if (channel != null) {
      _realtime = null;
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }
}
