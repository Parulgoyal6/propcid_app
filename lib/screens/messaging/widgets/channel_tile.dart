import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/channel_summary.dart';
import 'chat_avatar.dart';
import 'relative_time.dart';
import 'unread_badge.dart';

/// One row in the Channels tab (blueprint §16.6).
///
/// Shows the participant count in place of a "last message" preview:
/// ChannelsList.tsx selects only `created_at` for the latest message, not its
/// body, so there is no preview text to display without a query React does
/// not make.
class ChannelTile extends StatelessWidget {
  final ChannelSummary channel;
  final VoidCallback onTap;

  const ChannelTile({super.key, required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final unread = channel.unreadCount;
    final hasUnread = unread > 0;

    final memberLabel = channel.participantCount == 1
        ? '1 member'
        : '${channel.participantCount} members';

    return Semantics(
      label: hasUnread ? '${channel.name}, $unread unread' : channel.name,
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
                ChatAvatar(avatarUrl: null, initials: channel.initials),
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
                              channel.name,
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
                          if (channel.isMuted) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.notifications_off,
                              size: 13,
                              color: AppColors.textHint,
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            formatRelativeTime(channel.lastMessageAt),
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
                          Expanded(
                            child: Text(
                              channel.isAdmin
                                  ? '$memberLabel · Admin'
                                  : memberLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 12.5,
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
