import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/conversation_summary.dart';
import 'chat_avatar.dart';
import 'relative_time.dart';
import 'unread_badge.dart';

/// One row in the Chats tab: avatar, name, last message, time and unread
/// badge (blueprint §16.6).
///
/// The presence dot uses [ConversationParticipant.isEffectivelyOnline] — a
/// 90-second staleness check on `last_seen_at`, not the raw `is_online` flag
/// — mirroring the portal's `isEffectivelyOnline` in src/utils/presence.ts,
/// so a stale flag from a killed app/closed tab doesn't read as "online".
class ConversationTile extends StatelessWidget {
  final ConversationSummary conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final participant = conversation.otherParticipant;
    final unread = conversation.unreadCount;
    final hasUnread = unread > 0;

    return Semantics(
      label: hasUnread
          ? '${conversation.title}, $unread unread'
          : conversation.title,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: ColoredBox(
          color: AppColors.background,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFEDEDF2))),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ChatAvatar(
                      avatarUrl: participant?.avatarUrl,
                      initials: participant?.initial ?? '?',
                    ),
                    if (participant?.isEffectivelyOnline ?? false)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D9E75),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body.copyWith(
                                fontSize: 14,
                                fontWeight: hasUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (conversation.isMuted) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.notifications_off,
                              size: 13,
                              color: AppColors.textHint,
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            formatRelativeTime(conversation.lastMessageAt),
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (conversation.isPendingRequest) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF4DE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Request',
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFB8860B),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              conversation.isPendingRequest
                                  ? 'Wants to send you a message'
                                  : (conversation.lastMessage.isEmpty
                                        ? 'No messages yet'
                                        : conversation.lastMessage),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 12.5,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: hasUnread
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (hasUnread) ...[
                            const SizedBox(width: 8),
                            UnreadBadge(count: unread),
                          ],
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
