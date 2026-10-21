import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/shared_property_preview.dart';

/// Rich card for a received `property_share` message — image/title/price/
/// location instead of the generic "Shared a property" text the bubble used
/// to fall back to when the property couldn't be resolved (or before this
/// repair pass, always). Deliberately not `PropertyCardCompact` — that
/// widget carries browsing-only chrome (favorite/edit/delete) that doesn't
/// belong inside a chat bubble.
///
/// [property] is null while the batched lookup in [ChatThreadProvider] is
/// still in flight, or if the property has since been removed — a small
/// placeholder covers both cases honestly rather than blocking the bubble.
class PropertySharePreviewCard extends StatelessWidget {
  final SharedPropertyPreview? property;
  final bool isMine;

  const PropertySharePreviewCard({
    super.key,
    required this.property,
    required this.isMine,
  });

  void _openProperty(BuildContext context) {
    final id = property?.id;
    if (id == null || id.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.propertyDetailScreen,
      arguments: {'propertyId': id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = property;
    final foreground = isMine ? Colors.white : AppColors.textPrimary;
    final subForeground = isMine
        ? Colors.white.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    if (p == null) {
      return ConstrainedBox(
        // A cap, not a fixed size — the chat bubble only guarantees up to
        // ~76% of the screen width minus its own padding, which on a
        // narrower screen/window can be less than 220. `width:` would force
        // this exact size regardless and overflow the bubble; `maxWidth`
        // lets it shrink to whatever room is actually available.
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
              Icon(Icons.home_work_outlined, size: 18, color: subForeground),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Property unavailable',
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
      onTap: () => _openProperty(context),
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
                children: [
                  if (p.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: p.imageUrl!,
                      height: 110,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        height: 110,
                        color: AppColors.primaryLight,
                        child: const Icon(
                          Icons.home_work_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 90,
                      color: AppColors.primaryLight,
                      child: const Center(
                        child: Icon(
                          Icons.home_work_outlined,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite_border,
                        size: 13,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (p.location != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 11,
                            color: subForeground,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              p.location!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 10.5,
                                color: subForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (p.price != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        p.price!,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: isMine ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Same destination the rest of this card's own tap
                    // already opens — an explicit button for it too, matching
                    // the reference design, not a second action.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.white
                            : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Center(
                        child: Text(
                          'View Details',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
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
