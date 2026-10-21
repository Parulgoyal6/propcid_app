import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/scale_tap.dart';
import '../core/widgets/shimmer_loader.dart';
import '../core/utils/property_area_formatter.dart';
import '../models/property_model.dart';

class PropertyCardCompact extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;

  /// Opt-in, same convention as [onEdit]/[onDelete]: only rendered when a
  /// caller supplies it.
  final VoidCallback? onCompareToggle;
  final bool isInCompare;

  /// Shown only when the caller supplies it — this card is reused for
  /// browsing (Shortlist, public profiles), where the viewer never owns the
  /// listing, so the edit affordance stays opt-in rather than conditioned on
  /// an ownership flag threaded through every call site.
  final VoidCallback? onEdit;

  /// Same opt-in rule as [onEdit] — only the owner's own "My Content" call
  /// site supplies this, so browsing surfaces never render it.
  final VoidCallback? onDelete;

  const PropertyCardCompact({
    super.key,
    required this.property,
    this.onTap,
    this.onFavoriteToggle,
    this.onCompareToggle,
    this.isInCompare = false,
    this.onEdit,
    this.onDelete,
  });

  /// Slightly narrower than `AppConstants.propertyCompactImageWidth` so the
  /// title/price column gets more room inside the rounded card.
  static const double _kImageWidth = 112;

  @override
  Widget build(BuildContext context) {
    // Same margin as before, moved outside ScaleTap so the press glow hugs
    // the card rather than the surrounding gap.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: ScaleTap(
      onTap: onTap,
      scaleDown: 0.98,
      glowRadius: BorderRadius.circular(20),
      // Translucent glass row card. No blur of its own: it sits on a
      // frosted panel / glass backdrop and scrolls in lists, where stacked
      // live blurs would cost frames for no visible gain.
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: AppColors.glassGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14F97316),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: CachedNetworkImage(
                    imageUrl: property.imageUrl,
                    width: _kImageWidth,
                    height: AppConstants.propertyCompactImageHeight,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => const ShimmerBox(),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.textHint.withOpacity(0.1),
                      child: const Icon(Icons.error),
                    ),
                  ),
                ),
                if (property.isVerified)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.verifiedBadge,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Verified',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 10,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${property.photoCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    property.title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          property.location,
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    property.priceDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.price.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // The portal only ever shows Bed/Bath for
                    // `property.category === 'residential'` (PropertyCard.tsx)
                    // — every other category shows area alone. For commercial
                    // specifically, PropertyModel.beds/baths are repurposed to
                    // carry the washrooms count (see property_model.dart's
                    // `fromSupabase`), so showing them here as "Beds"/"Baths"
                    // is always wrong, not just for Land.
                    property.category == 'residential'
                        ? '${formatPropertyArea(property)} • ${property.beds} Beds • ${property.baths} Baths'
                        : formatPropertyArea(property),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onEdit != null)
              GestureDetector(
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Icon(
                    Icons.edit_outlined,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            if (onDelete != null)
              GestureDetector(
                onTap: onDelete,
                child: const Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 8),
                  child: Icon(
                    Icons.delete_outline,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            if (onCompareToggle != null)
              GestureDetector(
                onTap: onCompareToggle,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 8),
                  child: Icon(
                    isInCompare
                        ? Icons.check_circle
                        : Icons.compare_arrows_rounded,
                    color: isInCompare
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 22,
                  ),
                ),
              ),
            GestureDetector(
              onTap: onFavoriteToggle,
              // Heart in a small glass bubble.
              child: Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1FEF4444),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.red,
                  size: 17,
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
