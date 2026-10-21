import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/scale_tap.dart';
import '../core/widgets/shimmer_loader.dart';
import '../core/utils/property_area_formatter.dart';
import '../models/property_model.dart';
import 'round_icon_button.dart';
import 'verified_badge.dart';

class PropertyCardHorizontal extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  /// Opt-in, same convention as [onFavoriteToggle]: only rendered when a
  /// caller supplies it.
  final VoidCallback? onCompareToggle;
  final bool isInCompare;

  const PropertyCardHorizontal({
    super.key,
    required this.property,
    this.onTap,
    this.onFavoriteToggle,
    this.onCompareToggle,
    this.isInCompare = false,
  });

  @override
  Widget build(BuildContext context) {
    // Same 16 dp gap as the old margin, moved outside ScaleTap so the press
    // glow hugs the card rather than the gap beside it.
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ScaleTap(
      onTap: onTap,
      scaleDown: 0.97,
      glowRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        ),
        // Thin frosted-glass edge for depth, drawn over the content.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppConstants.cardRadius),
                    topRight: Radius.circular(AppConstants.cardRadius),
                  ),
                  child: CachedNetworkImage(
                    imageUrl: property.imageUrl,
                    width: 280,
                    height: 175,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const ShimmerBox(),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.textHint.withOpacity(0.1),
                      child: const Icon(Icons.error),
                    ),
                  ),
                ),
                if (property.isVerified)
                  const Positioned(top: 8, left: 8, child: VerifiedBadge()),
                if (onCompareToggle != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: RoundIconButton(
                      size: 32,
                      iconSize: 18,
                      onTap: onCompareToggle,
                      icon: isInCompare
                          ? Icons.check_circle
                          : Icons.compare_arrows_rounded,
                      color: isInCompare
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      semanticLabel: isInCompare
                          ? 'Remove from compare'
                          : 'Add to compare',
                    ),
                  ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            property.location,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(property.builderName, style: AppTextStyles.caption),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // The portal only ever renders a bed/bath badge inside
                      // its `category === 'residential'` branch
                      // (PropertyCard.tsx) — every other category falls
                      // through with no badge. For commercial specifically,
                      // PropertyModel.beds/baths are repurposed to carry the
                      // washrooms count (see property_model.dart's
                      // `fromSupabase`), so showing them here is always
                      // wrong, not just for Land/PG.
                      if (property.category == 'residential') ...[
                        _buildSpecIcon(Icons.bed, '${property.beds}'),
                        const SizedBox(width: 12),
                        _buildSpecIcon(Icons.bathtub, '${property.baths}'),
                        const SizedBox(width: 12),
                      ],
                      _buildSpecIcon(
                        Icons.square_foot,
                        formatPropertyAreaCompact(property),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        property.priceDisplay,
                        style: AppTextStyles.price.copyWith(fontSize: 18),
                      ),
                      if (property.isVerified) const VerifiedBadge(),
                    ],
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

  Widget _buildSpecIcon(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(value, style: AppTextStyles.caption),
      ],
    );
  }
}
