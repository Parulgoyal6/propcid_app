// screens/messaging/widgets/collab_tile.dart
//
// One row in the Collabs tab — either a bare pending request (no
// conversation yet: Accept/Decline for the recipient, a waiting state for
// the initiator) or an accepted-or-later collaboration (opens its
// conversation, shows a status badge). Ports the row structure described in
// `Chat.tsx`'s Collabs tab: amber ring on the avatar, a Handshake marker, and
// the status badge replacing the last-message preview text entirely for
// accepted+ rows.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/collaboration.dart';
import '../../../providers/messaging_provider.dart';
import '../widgets/chat_avatar.dart';

const Color kCollabAccent = Color(0xFFF59E0B);

class CollabTile extends StatelessWidget {
  final CollabInboxEntry entry;
  final String currentUserId;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// This collaboration's own conversation unread count — shown as a
  /// numeric badge on active (accepted-or-later) rows, alongside the
  /// existing incoming-request dot for still-`requested` rows.
  final int unreadCount;

  const CollabTile({
    super.key,
    required this.entry,
    required this.currentUserId,
    required this.onTap,
    this.busy = false,
    this.onAccept,
    this.onDecline,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final collab = entry.collaboration;
    final name = entry.counterparty?.displayName ?? 'Unknown';
    final incoming = entry.isIncomingFor(currentUserId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: collab.hasConversation ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kCollabAccent, width: 2),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ChatAvatar(
                      avatarUrl: entry.counterparty?.avatarUrl,
                      initials: entry.counterparty?.initial ?? '?',
                      size: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.handshake_outlined,
                              size: 14,
                              color: kCollabAccent,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _StatusOrMessage(entry: entry, incoming: incoming),
                      ],
                    ),
                  ),
                  if (collab.isRequested && incoming)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: kCollabAccent,
                        shape: BoxShape.circle,
                      ),
                    )
                  else if (unreadCount > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: kCollabAccent,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              if (entry.attachedReels.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: entry.attachedReels.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final reel = entry.attachedReels[i];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: reel.thumbnailUrl != null
                            ? Image.network(
                                reel.thumbnailUrl!,
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _reelPlaceholder(),
                              )
                            : _reelPlaceholder(),
                      );
                    },
                  ),
                ),
              ],
              if (collab.isRequested && incoming) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: busy ? null : onDecline,
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: busy ? null : onAccept,
                        child: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _reelPlaceholder() => Container(
    width: 52,
    height: 52,
    color: AppColors.background,
    child: const Icon(
      Icons.play_circle_outline,
      size: 20,
      color: AppColors.textHint,
    ),
  );
}

class _StatusOrMessage extends StatelessWidget {
  final CollabInboxEntry entry;
  final bool incoming;
  const _StatusOrMessage({required this.entry, required this.incoming});

  @override
  Widget build(BuildContext context) {
    final collab = entry.collaboration;

    if (collab.isRequested) {
      final text = incoming
          ? (entry.collaboration.requestMessage?.trim().isNotEmpty == true
                ? entry.collaboration.requestMessage!.trim()
                : 'Wants to collaborate with you')
          : 'Waiting for a response';
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kCollabAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        collabStatusLabel(collab.status),
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: kCollabAccent,
        ),
      ),
    );
  }
}
