import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../models/property_model.dart';
import 'people_result_card.dart' show PeopleAvatar;
import 'property_card_search_row.dart' show InCompareBadge;
import 'property_card_facts.dart';

/// Image height for the grid tile.
const double _kImageHeight = 90;

/// Fixed tile height, handed to the grid delegate as `mainAxisExtent`. See
/// `PropertyCardSearchGrid`'s own doc comment for why this stays fixed rather
/// than an aspect ratio. Grew from the original 180 when the tile gained the
/// same poster/category/listing-type/location details the List card already
/// showed — 90 image + poster row + title + tags row + location + facts,
/// each with their own gap, plus 20 dp of padding, comfortably clears 230;
/// 240 leaves headroom for text-scale variation.
const double kSearchGridTileExtent = 240;

/// The listing-type chip's colours — same prototype pair
/// `PropertyCardSearchRow` uses, reproduced here rather than imported since
/// that class keeps its helpers private to itself.
const Color _kListingChipBg = Color(0xFFFCE4EC);
const Color _kListingChipFg = Color(0xFFD6336C);

/// The Search results Grid-surface card.
///
/// A NEW widget, not a variant of `PropertyCardVertical`: that widget is
/// rendered by four Home rails (featured, latest, recommended, trending),
/// hard-codes `margin: right 16` (which would produce uneven gutters inside a
/// GridView), and carries a 36 dp heart, a locality overlay and luxury-threshold
/// logic that the redesign's tile does not have. Bending it to fit would have
/// changed all four of those rails.
class PropertyCardSearchGrid extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback? onTap;
  /// The heart button — Like/Unlike (`user_likes`), not Save.
  final VoidCallback? onFavoriteToggle;

  /// Whether the heart renders filled. Supplied by the caller from
  /// `PropertyProvider.isLiked`, since `PropertyModel` only carries the
  /// saved (`isShortlisted`) flag.
  final bool isLiked;

  /// Compare toggle — the same Add/Remove-from-compare action the List card
  /// has (portal PropertyCard shows it in grid view too).
  final VoidCallback? onCompareToggle;
  final bool isInCompare;

  const PropertyCardSearchGrid({
    super.key,
    required this.property,
    this.onTap,
    this.onFavoriteToggle,
    this.isLiked = false,
    this.onCompareToggle,
    this.isInCompare = false,
  });

  (IconData, String)? get _categoryChip => switch (property.category) {
    'residential' => (Icons.home_rounded, 'Residential'),
    'commercial' => (Icons.store_mall_directory_rounded, 'Commercial'),
    'land' => (Icons.landscape_rounded, 'Land'),
    'pg_coliving' => (Icons.groups_rounded, 'PG/Co-living'),
    'others' => (Icons.category_rounded, 'Others'),
    _ => null,
  };

  String? get _listingLabel => switch (property.propertyType) {
    'sell' => 'For Sale',
    'rent' => 'For Rent',
    'lease' => 'For Lease',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      scaleDown: 0.97,
      glowRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.cardShadow,
          // Portal Search.tsx: a compared property gets a ring.
          border: isInCompare
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.7), width: 2)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: _kImageHeight, child: _buildImage()),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: property.imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => const ShimmerBox(),
          errorWidget: (context, url, error) => ColoredBox(
            color: AppColors.textHint.withValues(alpha: 0.1),
            child: const Icon(Icons.broken_image, size: 20),
          ),
        ),
        if (onFavoriteToggle != null)
          Positioned(
            top: 6,
            right: 6,
            child: Semantics(
              label: isLiked ? 'Unlike property' : 'Like property',
              button: true,
              child: GestureDetector(
                onTap: onFavoriteToggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                  ),
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    size: 13,
                    color: isLiked
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        if (onCompareToggle != null)
          Positioned(
            top: 6,
            left: 6,
            child: Semantics(
              label: isInCompare ? 'Remove from compare' : 'Add to compare',
              button: true,
              child: GestureDetector(
                onTap: onCompareToggle,
                behavior: HitTestBehavior.opaque,
                child: isInCompare
                    ? const InCompareBadge()
                    : Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(
                            AppConstants.pillRadius,
                          ),
                        ),
                        child: const Icon(
                          Icons.compare_arrows_rounded,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
          ),
        if (property.photoCount > 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt, size: 9, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    '${property.photoCount}',
                    style: const TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    final category = _categoryChip;
    final listingLabel = _listingLabel;
    final initials = _initialsFor(property.postedByName);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PeopleAvatar(
                avatarUrl: property.postedByAvatarUrl,
                initials: initials,
                size: 16,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  property.postedByName?.trim().isNotEmpty == true
                      ? property.postedByName!.trim()
                      : 'PropCid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            property.title,
            style: AppTextStyles.body.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          if (category != null || listingLabel != null)
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                if (category != null)
                  _chip(
                    icon: category.$1,
                    label: category.$2,
                    bg: AppColors.primaryLight,
                    fg: AppColors.primary,
                    bordered: true,
                  ),
                if (listingLabel != null)
                  _chip(
                    icon: Icons.sell_rounded,
                    label: listingLabel,
                    bg: _kListingChipBg,
                    fg: _kListingChipFg,
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            property.priceDisplay,
            style: AppTextStyles.price.copyWith(fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 10,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  property.location,
                  style: AppTextStyles.caption.copyWith(fontSize: 9.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            propertyFactsLine(property),
            style: AppTextStyles.caption.copyWith(
              fontSize: 9.5,
              color: AppColors.textHint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    bool bordered = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        border: bordered ? Border.all(color: fg.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8.5, color: fg),
          const SizedBox(width: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.chip.copyWith(
              fontSize: 8.5,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Same 2-letter rule the Search results List card's fallback uses,
  /// falling back to "PC" (PropCid) rather than a generic "U" — this card's
  /// fallback identity is the platform, not a generic user.
  String _initialsFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'PC';
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'PC';
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? 'PC' : letters;
  }
}
