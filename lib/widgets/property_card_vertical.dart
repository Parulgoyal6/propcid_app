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

/// Same proxy threshold used for the Home "Luxury Collection" rail — kept in
/// one place isn't practical across files (no shared constants module for
/// it), but it's the identical ₹2Cr figure, not a new invented rule.
const double _kLuxuryThreshold = 20000000;

class PropertyCardVertical extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  /// Opt-in, same convention as [onFavoriteToggle]: only rendered when a
  /// caller supplies it, so screens that don't wire Compare are unaffected.
  final VoidCallback? onCompareToggle;
  final bool isInCompare;

  /// Optional size override so a rail can render a visibly larger "step up"
  /// card (e.g. Luxury Collection) without a second, near-duplicate widget.
  /// Defaults match the standard rail sizing everywhere else.
  final double width;
  final double imageHeight;

  /// Bounds the decoded image to roughly this many physical pixels
  /// (`memCacheWidth`/`memCacheHeight` on the underlying
  /// `CachedNetworkImage`) instead of decoding at the source's native
  /// resolution. Null by default — every existing caller (this card is used
  /// outside Home too) keeps its exact current behaviour unless it opts in;
  /// only the Home rails pass a value, sized from this card's own rendered
  /// `width`/`imageHeight` × the device's pixel ratio.
  final int? imageCacheWidth;
  final int? imageCacheHeight;

  const PropertyCardVertical({
    super.key,
    required this.property,
    this.onTap,
    this.onFavoriteToggle,
    this.onCompareToggle,
    this.isInCompare = false,
    double? width,
    double? imageHeight,
    this.imageCacheWidth,
    this.imageCacheHeight,
  }) : width = width ?? AppConstants.propertyCardWidth,
       imageHeight = imageHeight ?? AppConstants.propertyCardImageHeight;

  @override
  Widget build(BuildContext context) {
    // Margin sits outside ScaleTap (same 16 dp gap as before) so the press
    // glow hugs the card itself, not the gap beside it.
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ScaleTap(
      onTap: onTap,
      scaleDown: 0.97,
      glowRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.cardShadow,
        ),
        // Thin frosted-glass edge for depth; drawn over the content, so the
        // card's layout and contents are unchanged.
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
                    width: width,
                    height: imageHeight,
                    fit: BoxFit.cover,
                    memCacheWidth: imageCacheWidth,
                    memCacheHeight: imageCacheHeight,
                    placeholder: (context, url) => const ShimmerBox(),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.textHint.withOpacity(0.1),
                      child: const Icon(Icons.error),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (property.isFeatured)
                        const _CardBadge(label: 'Featured'),
                      if (property.isVerified) ...[
                        if (property.isFeatured) const SizedBox(height: 6),
                        const VerifiedBadge(),
                      ],
                      if (property.price >= _kLuxuryThreshold) ...[
                        if (property.isFeatured || property.isVerified)
                          const SizedBox(height: 6),
                        const _CardBadge(
                          label: 'Luxury',
                          icon: Icons.diamond_outlined,
                          color: Color(0xFFB8860B),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      if (onCompareToggle != null) ...[
                        RoundIconButton(
                          size: 36,
                          iconSize: 20,
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
                        const SizedBox(width: 6),
                      ],
                      GestureDetector(
                        onTap: onFavoriteToggle,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            property.isShortlisted
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: property.isShortlisted
                                ? Colors.red
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
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
                        if (property.photoCount > 0) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${property.photoCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    property.builderName,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      // wrong, not just for Land.
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
                      OutlinedButton(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

class _CardBadge extends StatelessWidget {
  const _CardBadge({
    required this.label,
    this.icon,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
