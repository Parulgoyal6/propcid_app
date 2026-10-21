// screens/notifications/notifications_screen.dart
//
// The Notification Centre — G-2, G-3 and G-4.
//
// WHAT THIS REPLACED
// ------------------
// Until Spec G this file held five hardcoded `_Notif` literals with
// `picsum.photos` placeholder images and no Supabase reference anywhere. Meanwhile
// five services were writing real rows into `notifications` — so every notification
// this app produced, including all of Specs H, I and F, was invisible. The write
// path worked; the read path did not exist.
//
// WHAT WAS KEPT
// -------------
// Every visual decision: the back chip, the "N new" pill, Mark all read, the
// gradient filter chips, the 48 dp tinted icon square, the unread tint and left
// border, the 8 dp unread dot, the relative timestamp, and the empty state's
// "You're all caught up!". The design is unchanged; only the data behind it is real.
//
// Three behaviours changed, each because the mock could afford something real data
// cannot:
//
//   * **Swipe-to-dismiss is gone.** It called `_notifications.removeWhere` — fine on
//     a local list, but `notifications` has no DELETE policy (RLS grants SELECT and
//     UPDATE only), so there is nothing to delete against. It offered an Undo that
//     did nothing, too. Long-press now toggles read/unread instead, which is the
//     portal's own secondary action (`NotificationList.tsx:116-123`).
//   * **The "View" chip is gone.** It navigated to `propertyDetailScreen` with
//     `n.propertyId ?? '1'` — a hardcoded fallback id. Tapping the row now routes
//     properly via `resolveNotificationDestination`.
//   * **Images are gone.** No notification payload carries an image URL; the mock's
//     came from picsum. The type icon is what remains, and it is what the portal
//     shows too.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/launch_features.dart';
import '../../core/animations/page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/navigation/notification_route_resolver.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/app_notification.dart';
import '../../models/conversation_summary.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_thread_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/collaboration_service.dart';
import '../../services/messaging_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../messaging/chat_thread_screen.dart';
import '../messaging/messages_list_screen.dart';
import '../profile/profile_reviews_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _activeFilter = kNotificationFilters.first;

  @override
  void initState() {
    super.initState();
    // The provider is app-level and may already be loaded from the badge. `load` is
    // idempotent per user id, so this is a no-op in that case rather than a second
    // fetch and a second channel.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load(
        context.read<AuthProvider>().userId,
      );
    });
  }

  List<AppNotification> _filtered(List<AppNotification> all) {
    if (_activeFilter == kNotificationFilters.first) return all;
    // Matched on the style's bucket rather than on the raw type, so eighteen enum
    // values collapse onto the four chips the design specifies.
    return all.where((n) => n.filter == _activeFilter).toList();
  }

  Future<void> _open(AppNotification notification) async {
    final provider = context.read<NotificationProvider>();

    // Read first, and regardless of whether there is anywhere to go — the portal
    // marks read before its switch runs (`NotificationList.tsx:54-57`), and a tap on
    // a type with no destination should still clear the dot.
    await provider.markRead(notification);
    if (!mounted) return;

    if (NotificationTypes.collabTypes.contains(notification.type)) {
      // Marked read above already; a disabled build just stops here rather
      // than navigating into a hidden collaboration screen.
      if (!LaunchFeatures.paidCollaborations) return;
      await _openCollab(notification);
      return;
    }

    if (notification.type == NotificationTypes.bulkMessage) {
      // No conversation/message row backs a bulk message — the notification
      // itself is the only record of what was sent. Show it in place rather
      // than calling resolveNotificationDestination, which would (correctly)
      // return null for this type. Mirrors the portal's NotificationList.tsx,
      // which opens a detail popup for the same reason.
      _openBulkMessage(notification);
      return;
    }

    if (notification.type == NotificationTypes.newRating) {
      // `trigger_notify_on_rating`'s payload never carries the rated user's
      // own id — the recipient always *is* the rated user — so there is
      // nothing for resolveNotificationDestination (a pure function with no
      // auth access) to read. Opens the dedicated Reviews screen — the same
      // destination the profile's own Reviews stat tile uses
      // (ProfileScreen's `onReviewsTap`) — rather than the full public
      // profile, since that's the page this notification is actually about.
      final auth = context.read<AuthProvider>();
      final userId = auth.userId;
      if (userId != null) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ProfileReviewsScreen(
              userId: userId,
              displayName: auth.userName,
              isBuilder: auth.userType == 'builder',
            ),
          ),
        );
      }
      return;
    }

    // A new-message notification carries the conversation it came from
    // (`notify_new_message` writes conversation_id, sender_id, sender_name),
    // so open that chat directly instead of the general Messages list.
    // `message_received` is never a case in resolveNotificationDestination
    // (see its own header comment) precisely because this lookup-then-open
    // logic can't be expressed as that pure function — so the fallback below
    // is explicit rather than falling through to a call that would resolve
    // to null.
    if (notification.type == NotificationTypes.messageReceived) {
      final conversationId = notification.data['conversation_id']?.toString();
      if (conversationId != null && conversationId.isNotEmpty) {
        final opened = await _openMessageThread(conversationId);
        if (opened || !mounted) return;
        // Couldn't resolve the conversation - fall through to the Messages
        // list rather than open a thread with guessed details.
      }
      if (mounted) Navigator.pushNamed(context, AppConstants.messagesScreen);
      return;
    }

    final destination = applyTeamWorkspaceOverride(
      baseline: resolveNotificationDestination(
        type: notification.type,
        data: notification.data,
      ),
      data: notification.data,
      activeTeamMemberships: context.read<AuthProvider>().activeTeamMemberships,
    );
    if (destination == null) return;

    Navigator.pushNamed(
      context,
      destination.route,
      arguments: destination.arguments,
    );
  }

  /// Opens the chat a new-message notification points at. Looks the
  /// conversation up by id (the same query the Messages list uses) so the
  /// thread gets the person's real name, avatar, message-request status and
  /// mute state. Returns false - opening nothing - when it can't be found, so
  /// the caller can fall back to the Messages list.
  Future<bool> _openMessageThread(String conversationId) async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return false;

    ConversationSummary? conversation;
    try {
      final all = await MessagingService().listConversations(userId);
      for (final c in all) {
        if (c.id == conversationId) {
          conversation = c;
          break;
        }
      }
    } catch (_) {
      return false;
    }
    if (conversation == null || !mounted) return false;
    final found = conversation;

    Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: found.id,
          title: found.title,
          avatarUrl: found.otherParticipant?.avatarUrl,
          initials: found.otherParticipant?.initial ?? '?',
          participantUserId: found.otherParticipant?.userId,
          requestStatus: found.requestStatus,
          isMuted: found.isMuted,
          collaborationId: found.collaborationId,
        ),
      ),
    );
    return true;
  }

  /// A `collab_*` notification's routing can't be a pure function like
  /// [resolveNotificationDestination] — it needs to look the collaboration
  /// up (status, conversation, counterparty) rather than trust anything in
  /// the payload beyond `collaboration_id`. Never guesses a conversation id:
  /// `requested`/no-conversation states open the Collabs tab; `accepted` and
  /// later resolve and open the actual thread.
  Future<void> _openCollab(AppNotification notification) async {
    final collaborationId = notification.data['collaboration_id']?.toString();
    final userId = context.read<AuthProvider>().userId;
    if (collaborationId == null || collaborationId.isEmpty || userId == null) {
      return;
    }

    final destination = await CollaborationService()
        .resolveNotificationDestination(
          collaborationId: collaborationId,
          currentUserId: userId,
        );
    if (!mounted) return;

    if (destination.target == CollabNotificationTarget.collabsInbox) {
      Navigator.of(context).push(
        PremiumPageRoute(
          settings: const RouteSettings(name: AppConstants.messagesScreen),
          builder: (_) => const MessagesListScreen(initialTab: 2),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.chatThreadScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.conversation,
          threadId: destination.conversationId!,
          title: destination.counterpartyName ?? 'Collaboration',
          avatarUrl: destination.counterpartyAvatarUrl,
          initials: (destination.counterpartyName?.isNotEmpty ?? false)
              ? destination.counterpartyName![0].toUpperCase()
              : '?',
          participantUserId: destination.counterpartyId,
          collaborationId: collaborationId,
        ),
      ),
    );
  }

  /// Shows a bulk message's own title/message in place. There is no
  /// conversation or message row to open — [sendBulkMessage] and the
  /// backend's broadcast path both write a plain `notifications` row, and
  /// its `title`/`message` columns are the only record of what was sent.
  void _openBulkMessage(AppNotification notification) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(notification.title),
        content: SingleChildScrollView(child: Text(notification.message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRead(AppNotification notification) async {
    final provider = context.read<NotificationProvider>();
    if (notification.isRead) {
      await provider.markUnread(notification);
    } else {
      await provider.markRead(notification);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final visible = _filtered(provider.items);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(
              unreadCount: provider.unreadCount,
              onMarkAllRead: provider.markAllRead,
            ),
            _FilterRow(
              active: _activeFilter,
              onChanged: (f) => setState(() => _activeFilter = f),
            ),
            Expanded(child: _body(provider, visible)),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }

  Widget _body(NotificationProvider provider, List<AppNotification> visible) {
    if (provider.loading && provider.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // A failure is not an empty inbox. "You're all caught up!" over a network error
    // would be a lie, so this offers a retry instead.
    if (provider.failed && provider.items.isEmpty) {
      return _FailedState(onRetry: provider.refresh);
    }

    if (visible.isEmpty) {
      return _EmptyState(
        // Distinguishes "nothing at all" from "nothing in this filter" — otherwise a
        // filter with no matches reads as an empty inbox.
        filtered: provider.items.isNotEmpty,
        filter: _activeFilter,
      );
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _NotificationCard(
          notification: visible[i],
          onTap: () => _open(visible[i]),
          onLongPress: () => _toggleRead(visible[i]),
        ),
      ),
    );
  }
}

// ── App bar ─────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  const _AppBar({required this.unreadCount, required this.onMarkAllRead});

  final int unreadCount;
  final VoidCallback onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Back',
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: AppColors.cardShadow,
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading2,
                ),
                const SizedBox(height: 2),
                Text(
                  'Stay updated with your latest activity',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Dimmed and inert with nothing to mark, rather than silently
          // doing nothing — `markAllRead` short-circuits on zero anyway.
          Opacity(
            opacity: unreadCount > 0 ? 1 : 0.45,
            child: GestureDetector(
              onTap: unreadCount > 0 ? onMarkAllRead : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.done_all, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Mark all read',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chips ────────────────────────────────────────────────────────────

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.active, required this.onChanged});

  final String active;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: kNotificationFilters.length,
        itemBuilder: (context, i) {
          final filter = kNotificationFilters[i];
          final isActive = active == filter;
          return GestureDetector(
            onTap: () => onChanged(filter),
            child: AnimatedContainer(
              duration: const Duration(
                milliseconds: AppConstants.animationDurationMs,
              ),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: isActive ? AppColors.primaryGradient : null,
                color: isActive ? null : Colors.white,
                borderRadius: BorderRadius.circular(
                  AppConstants.chipRadius * 2,
                ),
                boxShadow: isActive
                    ? AppColors.primaryGlow
                    : AppColors.cardShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _filterIcon(filter),
                    size: 13,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    filter,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One icon per filter chip label — purely a display choice alongside the
/// existing text, matching each `kNotificationFilters` entry by name.
IconData _filterIcon(String filter) {
  switch (filter) {
    case 'Price Drop':
      return Icons.sell_outlined;
    case 'Visits':
      return Icons.person_outline_rounded;
    case 'Matches':
      return Icons.star_border_rounded;
    case 'Enquiries':
      return Icons.mail_outline_rounded;
    default:
      return Icons.home_outlined;
  }
}

// ── Card ────────────────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onLongPress,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;
    final style = notification.style;
    final routable =
        resolveNotificationDestination(
          type: notification.type,
          data: notification.data,
        ) !=
        null;

    return Semantics(
      button: true,
      label:
          '${notification.title}. ${notification.message}. '
          '${isRead ? 'Read' : 'Unread'}. '
          'Long press to mark as ${isRead ? 'unread' : 'read'}.',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isRead
                  ? Colors.white
                  : AppColors.primaryLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              border: isRead
                  ? null
                  : Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      width: 1,
                    ),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(style.icon, size: 22, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.message,
                        style: AppTextStyles.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              notification.relativeTime,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // A chevron only where the tap goes somewhere. The mock
                          // showed a "View" button on every card and sent them all
                          // to a hardcoded property id.
                          if (routable)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: AppColors.textHint,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── States ──────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.filter});

  /// True when the inbox has rows but this filter matches none of them.
  final bool filtered;
  final String filter;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              size: 38,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            filtered ? 'Nothing here' : 'No notifications',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'No ${filter.toLowerCase()} notifications.'
                : "You're all caught up!",
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _FailedState extends StatelessWidget {
  const _FailedState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 38,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text("Couldn't load notifications", style: AppTextStyles.heading3),
          const SizedBox(height: 6),
          Text(
            'Check your connection and try again.',
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
