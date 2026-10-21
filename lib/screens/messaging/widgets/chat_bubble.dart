import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/chat_message.dart';
import '../../../models/message_reaction.dart';
import '../../../models/shared_property_preview.dart';
import '../../../models/shared_project_preview.dart';
import '../../../models/shared_reel_preview.dart';
import '../../../services/chat_media_service.dart';
import '../../../services/messaging_exceptions.dart';
import 'chat_media_view.dart';
import 'project_share_preview_card.dart';
import 'property_share_preview_card.dart';
import 'reel_share_preview_card.dart';
import 'relative_time.dart';

/// Quick-react emoji set — matches the small, fixed palette most chat apps
/// (and the portal's `ReactionBar.tsx`) offer rather than a full picker.
const List<String> quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// One message bubble (blueprint §16.7).
///
/// Prototype spec: max 78% width, 16 dp radius, own messages solid primary
/// with white text and no shadow, incoming white with
/// `0 2px 8px rgba(26,26,46,0.05)`, timestamp beneath in 10 dp hint colour.
///
/// Long-press opens reply/react/edit/delete actions — reusing the same
/// `toggle_reaction`/`edit_message`/`delete_message_for_me`/
/// `delete_message_for_everyone` RPCs the portal calls (see
/// ChatThreadProvider), parameterised by surface so DM and channel bubbles
/// share this one widget.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  /// `'dm'` or `'channel'` — needed to resolve media signed URLs.
  final String surface;

  /// Sender name, shown above incoming bubbles in channel threads only.
  final String? senderName;

  final ChatMessage? repliedMessage;
  final String? repliedSenderName;
  final List<MessageReaction> reactions;
  final String currentUserId;

  /// Resolved property for a `property_share` message — null while the
  /// batched lookup is in flight or the message isn't a property share.
  final SharedPropertyPreview? sharedProperty;

  /// Resolved reel for a `reel_share` message — null while the batched
  /// lookup is in flight or the message isn't a reel share.
  final SharedReelPreview? sharedReel;
  final SharedProjectPreview? sharedProject;

  final ValueChanged<String>? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;
  final VoidCallback? onReport;
  final VoidCallback? onForward;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.currentUserId,
    this.surface = 'dm',
    this.senderName,
    this.repliedMessage,
    this.repliedSenderName,
    this.reactions = const [],
    this.sharedProperty,
    this.sharedReel,
    this.sharedProject,
    this.onReact,
    this.onReply,
    this.onEdit,
    this.onDeleteForMe,
    this.onDeleteForEveryone,
    this.onReport,
    this.onForward,
  });

  /// Only an approved image actually has a signed URL to fetch — a
  /// pending/rejected image, or a non-image message, has nothing to save.
  bool get _canSaveImage =>
      message.isImage &&
      message.mediaStatus == MediaStatus.approved &&
      message.mediaUrls.isNotEmpty;

  void _openActions(BuildContext context) {
    if (message.isDeleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ActionSheet(
        isMine: isMine,
        canEdit: isMine && message.messageType == 'text',
        quickEmojis: quickReactionEmojis,
        onSaveImage: !_canSaveImage
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                _saveImage(context);
              },
        onReact: onReact == null
            ? null
            : (emoji) {
                Navigator.of(sheetContext).pop();
                onReact!(emoji);
              },
        onReply: onReply == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onReply!();
              },
        onEdit: onEdit == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onEdit!();
              },
        onDeleteForMe: onDeleteForMe == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onDeleteForMe!();
              },
        onDeleteForEveryone: onDeleteForEveryone == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onDeleteForEveryone!();
              },
        onReport: onReport == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onReport!();
              },
        onForward: onForward == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onForward!();
              },
      ),
    );
  }

  /// Downloads the message's image (via its signed URL) and saves it to the
  /// device gallery. Self-contained — unlike reply/edit/delete, saving a
  /// copy locally has no thread-level side effect, so it needs no callback
  /// threaded up from `ChatThreadScreen`.
  Future<void> _saveImage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    try {
      await ChatMediaService().saveImageToGallery(
        path: message.mediaUrls.first,
        surface: surface,
      );
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Image saved to gallery')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is ChatMediaValidationError
                ? e.message
                : "Couldn't save the image. Please try again.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hasMedia = message.isImage || message.isVideo;

    // A small "tail" corner (WhatsApp/Telegram-style) instead of a uniform
    // rounded rectangle — the corner nearest the sender's own side is
    // squared off, which is what reads as a speech-bubble pointer at a
    // glance without needing a custom-painted tail shape.
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    if (message.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: width * 0.76),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: bubbleRadius,
                border: Border.all(color: const Color(0xFFEDEDF2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block, size: 13, color: AppColors.textHint),
                  const SizedBox(width: 6),
                  Text(
                    'This message was deleted',
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (senderName != null && !isMine) ...[
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 3),
              child: Text(
                senderName!,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
          GestureDetector(
            onLongPress: () => _openActions(context),
            child: Container(
              constraints: BoxConstraints(maxWidth: width * 0.76),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : AppColors.cardBackground,
                borderRadius: bubbleRadius,
                boxShadow: isMine ? null : AppColors.surfaceCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (repliedMessage != null) _buildReplyQuote(),
                  if (message.isPropertyShare)
                    PropertySharePreviewCard(
                      property: sharedProperty,
                      isMine: isMine,
                    )
                  else if (message.isReelShare)
                    ReelSharePreviewCard(reel: sharedReel, isMine: isMine)
                  else if (message.isProjectShare)
                    ProjectSharePreviewCard(
                      project: sharedProject,
                      fallbackText: message.displayContent,
                      isMine: isMine,
                    )
                  else if (hasMedia || message.isAudio)
                    ChatMediaView(
                      message: message,
                      surface: surface,
                      isMine: isMine,
                    )
                  else
                    Text(
                      message.displayContent,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        height: 1.45,
                        color: isMine ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (reactions.isNotEmpty) _buildReactionRow(),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.isEdited) ...[
                  Text(
                    'edited · ',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
                Text(
                  formatClockTime(message.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.textHint,
                  ),
                ),
                // Read receipt — WhatsApp/Telegram-style ticks, driven by the
                // `is_read` column the thread already fetches; single grey
                // tick = sent, double primary-tinted tick = read.
                if (isMine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    message.isRead ? Icons.done_all : Icons.done,
                    size: 13,
                    color: message.isRead
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyQuote() {
    final reply = repliedMessage!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (isMine ? Colors.white : AppColors.primary).withValues(
          alpha: 0.1,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white70 : AppColors.primary,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            repliedSenderName ?? 'Message',
            style: AppTextStyles.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isMine ? Colors.white : AppColors.primary,
            ),
          ),
          Text(
            reply.displayContent,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: isMine
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactions.map((r) {
          final mine = r.reactedBy(currentUserId);
          return GestureDetector(
            onTap: onReact == null ? null : () => onReact!(r.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: mine
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: mine ? AppColors.primary : const Color(0xFFEDEDF2),
                ),
              ),
              child: Text(
                '${r.emoji} ${r.count}',
                style: AppTextStyles.caption.copyWith(fontSize: 10.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  final bool isMine;
  final bool canEdit;
  final List<String> quickEmojis;
  final ValueChanged<String>? onReact;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;
  final VoidCallback? onReport;
  final VoidCallback? onForward;
  final VoidCallback? onSaveImage;

  const _ActionSheet({
    required this.isMine,
    required this.canEdit,
    required this.quickEmojis,
    this.onReact,
    this.onReply,
    this.onEdit,
    this.onDeleteForMe,
    this.onDeleteForEveryone,
    this.onReport,
    this.onForward,
    this.onSaveImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReact != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: quickEmojis
                      .map(
                        (e) => GestureDetector(
                          onTap: () => onReact!(e),
                          child: Text(e, style: const TextStyle(fontSize: 24)),
                        ),
                      )
                      .toList(),
                ),
              ),
            const Divider(height: 1),
            if (onReply != null) _tile(context, Icons.reply, 'Reply', onReply!),
            if (onForward != null)
              _tile(context, Icons.forward_outlined, 'Forward', onForward!),
            if (onSaveImage != null)
              _tile(
                context,
                Icons.download_rounded,
                'Save image',
                onSaveImage!,
              ),
            if (canEdit && onEdit != null)
              _tile(context, Icons.edit_outlined, 'Edit', onEdit!),
            if (onDeleteForMe != null)
              _tile(
                context,
                Icons.delete_outline,
                'Delete for me',
                onDeleteForMe!,
              ),
            if (isMine && onDeleteForEveryone != null)
              _tile(
                context,
                Icons.delete_forever_outlined,
                'Delete for everyone',
                onDeleteForEveryone!,
                destructive: true,
              ),
            if (!isMine && onReport != null)
              _tile(
                context,
                Icons.flag_outlined,
                'Report',
                onReport!,
                destructive: true,
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final color = destructive ? Colors.red : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: AppTextStyles.body.copyWith(fontSize: 14, color: color),
      ),
      onTap: onTap,
    );
  }
}
