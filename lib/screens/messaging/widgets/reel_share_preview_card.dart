import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/shared_reel_preview.dart';

/// Rich card for a received `reel_share` message — thumbnail + title and a
/// play affordance instead of the generic "Shared a reel" text the bubble
/// falls back to when the reel can't be resolved. Structurally mirrors
/// [PropertySharePreviewCard] so the two share types read as one visual
/// family inside a thread.
///
/// [reel] is null while the batched lookup in [ChatThreadProvider] is still
/// in flight, or if the reel has since been removed/unpublished — a small
/// placeholder covers both cases honestly rather than blocking the bubble.
class ReelSharePreviewCard extends StatelessWidget {
  final SharedReelPreview? reel;
  final bool isMine;

  const ReelSharePreviewCard({
    super.key,
    required this.reel,
    required this.isMine,
  });

  void _openReel(BuildContext context) {
    final id = reel?.id;
    if (id == null || id.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.reelsScreen,
      arguments: {'reelId': id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = reel;
    final foreground = isMine ? Colors.white : AppColors.textPrimary;
    final subForeground = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    if (r == null) {
      return ConstrainedBox(
        // Same rationale as PropertySharePreviewCard's fallback: a cap, not
        // a fixed size, so this never overflows a narrower bubble.
        constraints: const BoxConstraints(maxWidth: 220),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isMine ? Colors.white : AppColors.textHint).withValues(
              alpha: 0.12,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline, size: 18, color: subForeground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Reel unavailable',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    color: subForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _openReel(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          decoration: BoxDecoration(
            color: (isMine ? Colors.white : AppColors.background).withValues(
              alpha: 0.14,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (r.thumbnailUrl != null)
                    CachedNetworkImage(
                      imageUrl: r.thumbnailUrl!,
                      height: 130,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        height: 130,
                        color: AppColors.primaryLight,
                        child: const Icon(
                          Icons.video_collection_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 130,
                      color: AppColors.primaryLight,
                      child: const Center(
                        child: Icon(
                          Icons.video_collection_outlined,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  // Play affordance — this card never plays inline (same
                  // "tap opens the real screen" contract as the property
                  // share card's own "View Details"), it just signals the
                  // thumbnail is a video.
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  r.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
