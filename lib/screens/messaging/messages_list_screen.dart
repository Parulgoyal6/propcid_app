import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../config/launch_features.dart';
import '../../core/animations/page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/channel_summary.dart';
import '../../models/conversation_summary.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_thread_provider.dart';
import '../../providers/messaging_provider.dart';
import '../../services/collaboration_service.dart';
import '../../services/messaging_service.dart';
import 'blocked_users_screen.dart';
import 'chat_thread_screen.dart';
import 'widgets/channel_tile.dart';
import 'widgets/collab_tile.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/create_channel_sheet.dart';
import 'widgets/new_chat_sheet.dart';

/// Messages — Chats, Channels and Collabs (blueprint §16.6; Collabs added by
/// the Collaboration Marketplace port — mirrors `Chat.tsx`'s third tab).
class MessagesListScreen extends StatelessWidget {
  /// 0 = Chats, 1 = Channels, 2 = Collabs. Set by
  /// `resolveCollabNotificationDestination` when a `collab_*` notification
  /// with no conversation yet routes here.
  final int initialTab;

  /// Overrides the real services [MessagingProvider] uses. Null in every
  /// production call site; tests inject fakes here instead of hitting
  /// Supabase.
  @visibleForTesting
  final MessagingService? service;

  @visibleForTesting
  final CollaborationService? collabService;

  const MessagesListScreen({
    super.key,
    this.initialTab = 0,
    this.service,
    this.collabService,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          MessagingProvider(service: service, collabService: collabService),
      child: _MessagesListView(initialTab: initialTab),
    );
  }
}

class _MessagesListView extends StatefulWidget {
  final int initialTab;
  const _MessagesListView({this.initialTab = 0});

  @override
  State<_MessagesListView> createState() => _MessagesListViewState();
}

class _MessagesListViewState extends State<_MessagesListView> {
  /// Clamped to (0, 1) — Chats/Channels only — when paid collaborations are
  /// disabled, so an `initialTab: 2` deep-link (e.g. from a stale
  /// notification) safely lands on Channels instead of a tab that no longer
  /// exists.
  late int _tab = widget.initialTab.clamp(
    0,
    LaunchFeatures.paidCollaborations ? 2 : 1,
  );
  String? _loadedUserId;
  final Set<String> _collabActionBusy = {};

  /// Inline filter over the already-loaded lists. Purely client-side — no
  /// extra query, so it works offline and costs nothing.
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Bumped when the header's search icon is tapped: the always-visible
  /// search field is rebuilt with autofocus, so the keyboard opens on it.
  int _searchFocusTick = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _query = '';
    });
  }

  List<ConversationSummary> get _visibleConversations {
    final messaging = context.read<MessagingProvider>();
    if (_query.isEmpty) return messaging.conversations;
    final q = _query.toLowerCase();
    return messaging.conversations
        .where(
          (c) =>
              c.title.toLowerCase().contains(q) ||
              c.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  List<ChannelSummary> get _visibleChannels {
    final messaging = context.read<MessagingProvider>();
    if (_query.isEmpty) return messaging.channels;
    final q = _query.toLowerCase();
    return messaging.channels
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.description ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  /// Opens the recipient picker, then the resulting conversation.
  ///
  /// The conversation is created (or reused) by the `start_conversation` RPC,
  /// which is what the web app calls for the same flow.
  Future<void> _startNewChat() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    final recipient = await showNewChatSheet(context, userId);
    if (recipient == null || !mounted) return;

    final messaging = context.read<MessagingProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    String conversationId;
    try {
      // A cold pick from the recipient search carries no property/lead
      // context, so it must be gated like the portal's own cold DMs —
      // the recipient's row starts `pending` until they accept.
      conversationId = await MessagingService().startConversation(
        recipient.userId,
        skipRequestGate: false,
      );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text("Couldn't start the conversation.")),
        );
      return;
    }

    if (!mounted) return;

    // Opened straight from the picked recipient rather than by looking the new
    // row up after a refresh — a conversation with no messages yet may not sort
    // where expected, and the header needs a name and avatar either way.
    await navigator.push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: conversationId,
          title: recipient.displayName,
          avatarUrl: recipient.avatarUrl,
          initials: recipient.initial,
          // Lets the thread header open this person's public profile. Nothing
          // else about this flow changes.
          participantUserId: recipient.userId,
        ),
      ),
    );

    if (mounted) await messaging.refresh();
  }

  Future<void> _createChannel() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    final channelId = await showCreateChannelSheet(context, userId);
    if (channelId == null || !mounted) return;
    await context.read<MessagingProvider>().refresh();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || userId == _loadedUserId) return;
    _loadedUserId = userId;

    // `load()` is an async method, but its body runs synchronously up to the
    // first `await` — and both `_loadConversations` and `_loadChannels` raise
    // their loading flags and notify before that point. This method is reached
    // from didChangeDependencies, which runs inside the build phase, so
    // calling it directly marks this element dirty while it is still building
    // and trips `assert(!_dirty)` in framework.dart.
    //
    // Deferring to the end of the frame lets the first build complete with the
    // provider's initial (loading) state, then delivers the notification when
    // the tree is settled. The provider reference is captured now rather than
    // looked up in the callback, so nothing touches this context after the
    // widget may have been deactivated.
    final provider = context.read<MessagingProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId);
    });
  }

  Future<void> _openConversation(ConversationSummary conversation) async {
    final messaging = context.read<MessagingProvider>();
    // Optimistic badge clear; the thread performs the authoritative update and
    // the Realtime callback reconciles the list.
    messaging.clearConversationBadge(conversation.id);

    await Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: conversation.id,
          title: conversation.title,
          avatarUrl: conversation.otherParticipant?.avatarUrl,
          initials: conversation.otherParticipant?.initial ?? '?',
          // Null when the participant could not be resolved, which leaves the
          // header inert exactly as it was.
          participantUserId: conversation.otherParticipant?.userId,
          requestStatus: conversation.requestStatus,
          isMuted: conversation.isMuted,
          // Always null for anything reachable from the Chats tab (which
          // excludes collaboration conversations entirely) — passed through
          // anyway so this entry point never has to be revisited if that
          // ever changes; every route into a conversation should carry its
          // real collaborationId rather than assume it has none.
          collaborationId: conversation.collaborationId,
        ),
      ),
    );

    if (mounted) await messaging.refresh();
  }

  Future<void> _openChannel(ChannelSummary channel) async {
    final messaging = context.read<MessagingProvider>();

    await Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.channelChatScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.channel,
          threadId: channel.id,
          title: channel.name,
          subtitle: channel.participantCount == 1
              ? '1 member'
              : '${channel.participantCount} members',
          initials: channel.initials,
          isMuted: channel.isMuted,
          isChannelAdmin: channel.isAdmin,
        ),
      ),
    );

    if (mounted) await messaging.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final messaging = context.watch<MessagingProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildTabPills(messaging),
                  if (_tab != 2) ...[
                    const SizedBox(height: 14),
                    MessagesSearchField(
                      key: ValueKey('msg-search-$_tab-$_searchFocusTick'),
                      controller: _searchController,
                      hint: _tab == 0 ? 'Search chats...' : 'Search channels...',
                      autofocus: _searchFocusTick > 0,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      onClear: _clearSearch,
                    ),
                  ],
                  const SizedBox(height: 6),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: messaging.refresh,
                child: switch (_tab) {
                  0 => _buildChats(messaging),
                  1 => _buildChannels(messaging),
                  _ => _buildCollabs(messaging),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _logoAssetPath = 'assets/branding/propcid_logo.png';
  static const double _logoAspectRatio = 862 / 203;

  /// Logo row (back, Propcid wordmark, search / new / more), then the big
  /// "Messages" title with its tagline.
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              label: 'Back',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackground,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x141A1A2E),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_back,
                    size: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            Semantics(
              label: 'PropCid',
              image: true,
              child: SizedBox(
                height: 25,
                child: AspectRatio(
                  aspectRatio: _logoAspectRatio,
                  child: Image.asset(
                    _logoAssetPath,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            const Spacer(),
            // Search focuses the always-visible field; "+" opens the
            // recipient picker (or channel creation) as before.
            if (_tab != 2) ...[
              _HeaderAction(
                icon: Icons.search,
                semanticLabel: 'Search messages',
                onTap: () => setState(() => _searchFocusTick++),
              ),
              const SizedBox(width: 10),
              _HeaderAction(
                icon: Icons.add,
                semanticLabel: _tab == 0 ? 'New message' : 'Create channel',
                filled: true,
                onTap: _tab == 0 ? _startNewChat : _createChannel,
              ),
              const SizedBox(width: 6),
            ],
            _buildOverflowMenu(),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Messages',
          style: AppTextStyles.heading1.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(
                'Stay connected with your network',
                style: AppTextStyles.body.copyWith(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.auto_awesome,
              size: 15,
              color: AppColors.primary,
            ),
          ],
        ),
      ],
    );
  }

  /// Chats / Channels (/ Collabs) as separate pills: the selected one is the
  /// orange gradient with a glow, the others are white with a light border.
  Widget _buildTabPills(MessagingProvider messaging) {
    final tabs = <({String label, IconData icon})>[
      (label: 'Chats', icon: Icons.chat_bubble_rounded),
      (label: 'Channels', icon: Icons.groups_outlined),
      if (LaunchFeatures.paidCollaborations)
        // Total unread across every active collaboration's own conversation,
        // plus the existing incoming-request dot - both signals.
        (
          label:
              'Collabs'
              '${messaging.totalCollabUnread > 0 ? ' (${messaging.totalCollabUnread})' : ''}'
              '${messaging.hasIncomingCollabRequest ? ' •' : ''}',
          icon: Icons.handshake_outlined,
        ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              label: tabs[i].label,
              button: true,
              selected: i == _tab,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: i == _tab ? null : () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: i == _tab ? AppColors.ctaGradient : null,
                    color: i == _tab ? null : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(18),
                    border: i == _tab
                        ? null
                        : Border.all(
                            color: AppColors.primary.withValues(alpha: 0.14),
                          ),
                    boxShadow: i == _tab
                        ? AppColors.ctaShadow
                        : AppColors.surfaceCardShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i].icon,
                        size: 18,
                        color: i == _tab
                            ? Colors.white
                            : AppColors.textPrimary,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          tabs[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: i == _tab
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The only global entry point to Blocked Users management — there's no
  /// app-wide Settings screen this repo hangs privacy controls off of yet,
  /// so it lives here rather than being invented elsewhere.
  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      icon: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x141A1A2E),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.more_vert,
          size: 18,
          color: AppColors.textPrimary,
        ),
      ),
      onSelected: (value) {
        if (value == 'blocked_users') _openBlockedUsers();
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'blocked_users',
          child: Row(
            children: [
              Icon(Icons.block, size: 18),
              SizedBox(width: 8),
              Text('Blocked Users'),
            ],
          ),
        ),
      ],
    );
  }

  void _openBlockedUsers() {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlockedUsersScreen(currentUserId: userId),
      ),
    );
  }

  Widget _buildChats(MessagingProvider messaging) {
    if (messaging.conversationsLoading) return const _ListShimmer();

    if (messaging.conversationsFailed) {
      return _scrollable(
        EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load messages",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: messaging.refresh,
        ),
      );
    }

    if (messaging.conversations.isEmpty) {
      return _scrollable(
        const EmptyStateView(
          icon: Icons.chat_bubble_outline,
          title: 'No conversations yet',
          message: 'Messages from buyers and sellers will appear here.',
        ),
      );
    }

    final visible = _visibleConversations;
    if (visible.isEmpty) {
      return _scrollable(
        EmptyStateView(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message: 'No conversations match "$_query".',
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final conversation = visible[index];
        return Dismissible(
          key: ValueKey(conversation.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            color: AppColors.error,
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          confirmDismiss: (_) => _confirmDeleteChat(conversation),
          child: ConversationTile(
            conversation: conversation,
            onTap: () => _openConversation(conversation),
          ),
        );
      },
    );
  }

  /// Swipe-to-delete on a Chats row — the mobile equivalent of the portal's
  /// per-row trash icon (`Chat.tsx`). Deletes only after the user confirms,
  /// and only actually dismisses the row once the delete call succeeds — a
  /// failure snaps the row back instead of leaving the list out of sync with
  /// the server.
  Future<bool> _confirmDeleteChat(ConversationSummary conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete chat?'),
        content: Text(
          'This removes your copy of the conversation with '
          '${conversation.title}. They can still message you again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    final error = await context.read<MessagingProvider>().deleteConversation(
      conversation.id,
    );
    if (!mounted) return false;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return false;
    }
    return true;
  }

  Widget _buildChannels(MessagingProvider messaging) {
    if (messaging.channelsLoading) return const _ListShimmer();

    if (messaging.channelsFailed) {
      return _scrollable(
        EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load channels",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: messaging.refresh,
        ),
      );
    }

    if (messaging.channels.isEmpty) {
      return _scrollable(
        const EmptyStateView(
          icon: Icons.forum_outlined,
          title: 'No channels yet',
          message: 'Channel conversations will appear here',
        ),
      );
    }

    final visible = _visibleChannels;
    if (visible.isEmpty) {
      return _scrollable(
        EmptyStateView(
          icon: Icons.search_off_rounded,
          title: 'No matches',
          message: 'No channels match "$_query".',
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final channel = visible[index];
        return ChannelTile(
          channel: channel,
          onTap: () => _openChannel(channel),
        );
      },
    );
  }

  Widget _buildCollabs(MessagingProvider messaging) {
    if (messaging.collabsLoading) return const _ListShimmer();

    if (messaging.collabsFailed) {
      return _scrollable(
        EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load collaborations",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: messaging.refresh,
        ),
      );
    }

    if (messaging.collabs.isEmpty) {
      return _scrollable(
        const EmptyStateView(
          icon: Icons.handshake_outlined,
          title: 'No collaborations yet',
          message:
              'Collaboration requests you send or receive will appear here.',
        ),
      );
    }

    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return const SizedBox.shrink();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: messaging.collabs.length,
      itemBuilder: (context, index) {
        final entry = messaging.collabs[index];
        return CollabTile(
          entry: entry,
          currentUserId: userId,
          busy: _collabActionBusy.contains(entry.collaboration.id),
          onTap: () => _openCollab(entry),
          onAccept: () => _acceptCollab(entry),
          onDecline: () => _declineCollab(entry),
          unreadCount: entry.unreadCount,
        );
      },
    );
  }

  Future<void> _openCollab(CollabInboxEntry entry) async {
    final conversationId = entry.collaboration.conversationId;
    if (conversationId == null) return;
    final messaging = context.read<MessagingProvider>();
    await Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: conversationId,
          title: entry.counterparty?.displayName ?? 'Collaboration',
          avatarUrl: entry.counterparty?.avatarUrl,
          initials: entry.counterparty?.initial ?? '?',
          participantUserId: entry.counterparty?.userId,
          collaborationId: entry.collaboration.id,
        ),
      ),
    );
    if (mounted) await messaging.refresh();
  }

  Future<void> _acceptCollab(CollabInboxEntry entry) async {
    final id = entry.collaboration.id;
    setState(() => _collabActionBusy.add(id));
    final messaging = context.read<MessagingProvider>();
    final (updated, error) = await messaging.acceptCollab(id);
    if (!mounted) return;
    setState(() => _collabActionBusy.remove(id));
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final conversationId = updated?.conversationId;
    if (conversationId == null) return;
    await Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: conversationId,
          title: entry.counterparty?.displayName ?? 'Collaboration',
          avatarUrl: entry.counterparty?.avatarUrl,
          initials: entry.counterparty?.initial ?? '?',
          participantUserId: entry.counterparty?.userId,
          collaborationId: id,
        ),
      ),
    );
    if (mounted) await messaging.refresh();
  }

  Future<void> _declineCollab(CollabInboxEntry entry) async {
    final id = entry.collaboration.id;
    setState(() => _collabActionBusy.add(id));
    final error = await context.read<MessagingProvider>().declineCollab(id);
    if (!mounted) return;
    setState(() => _collabActionBusy.remove(id));
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// Keeps empty and error states pull-to-refreshable.
  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Circular header action, matching the prototype's search and "+" buttons:
/// 36 dp, white with a soft shadow, or solid primary for the filled variant.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool filled;

  const _HeaderAction({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : AppColors.cardBackground,
            shape: BoxShape.circle,
            boxShadow: filled
                ? AppColors.primaryActionShadow
                : const [
                    BoxShadow(
                      color: Color(0x141A1A2E),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: filled ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Row placeholders while the lists load — follows the `PropertyCardShimmer`
/// pattern rather than flashing an empty state (blueprint §12).
class _ListShimmer extends StatelessWidget {
  const _ListShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: 6,
      itemBuilder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 12,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
