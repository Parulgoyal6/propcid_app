import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/property_model.dart';
import 'people_result_card.dart' show PeopleAvatar;

/// Card width and image height, per the redesign's map strip.
const double _kCardWidth = 200;
const double _kCardImageHeight = 70;

/// Overall strip height. Grew from the original 138 when the card gained the
/// same poster/category/listing-type/location details the List and Grid
/// cards already show — see `_MapStripCard._buildContent` for the exact
/// line-by-line budget.
const double kMapCardStripHeight = 186;

/// Same listing-type chip colours `PropertyCardSearchGrid`/
/// `PropertyCardSearchRow` use, reproduced locally per this module's own
/// convention of keeping each card's helpers private to itself.
const Color _kListingChipBg = Color(0xFFFCE4EC);
const Color _kListingChipFg = Color(0xFFD6336C);

/// The horizontally-scrolling rail of result cards beneath the map.
///
/// Tapping a card does exactly what tapping its pin does — the redesign wires
/// both to the same `openPreview(i)` — so this takes a single callback and the
/// screen decides what that means.
class MapCardStrip extends StatelessWidget {
  final List<PropertyModel> properties;
  final ValueChanged<PropertyModel> onCardTap;

  /// Lets the screen scroll the rail programmatically if it ever needs to.
  final ScrollController? controller;

  const MapCardStrip({
    super.key,
    required this.properties,
    required this.onCardTap,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kMapCardStripHeight,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        // Leading inset only, matching the redesign's `padding-left: 20`; the
        // last card is allowed to run to the edge so the rail reads as scrollable.
        padding: const EdgeInsets.only(left: AppConstants.spacingXL),
        itemCount: properties.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppConstants.spacingM),
        itemBuilder: (context, index) {
          final property = properties[index];
          return _MapStripCard(
            property: property,
            onTap: () => onCardTap(property),
          );
        },
      ),
    );
  }
}

/// Private to the strip: a denser sibling of the list and grid cards.
///
/// Not `PropertyCardCompact` — that is a 130x95 image ROW rendered by the
/// Shortlist screen and Profile's My Content, so it is both the wrong shape and
/// off limits. Not `PropertyCardSearchGrid` either: this card is a fixed 200 dp
/// wide, has an 80 dp image and drops the facts line, so bending the grid tile
/// would have meant three optional parameters and two conditionals.
class _MapStripCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback onTap;

  const _MapStripCard({required this.property, required this.onTap});

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

  String _initialsFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'PC';
    final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'PC';
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters.isEmpty ? 'PC' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${property.title}, ${property.priceDisplay}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: _kCardWidth,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            // The redesign gives the strip the quieter chrome shadow, not the
            // orange-tinted one the list and grid cards carry.
            boxShadow: AppColors.surfaceCardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: _kCardImageHeight,
                    width: double.infinity,
                    child: CachedNetworkImage(
                      imageUrl: property.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => ColoredBox(
                        color: AppColors.textHint.withValues(alpha: 0.1),
                      ),
                      errorWidget: (context, url, error) => ColoredBox(
                        color: AppColors.textHint.withValues(alpha: 0.1),
                        child: const Icon(Icons.broken_image, size: 18),
                      ),
                    ),
                  ),
                  if (property.photoCount > 0)
                    Positioned(
                      left: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.camera_alt,
                              size: 9,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${property.photoCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final category = _categoryChip;
    final listingLabel = _listingLabel;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              PeopleAvatar(
                avatarUrl: property.postedByAvatarUrl,
                initials: _initialsFor(property.postedByName),
                size: 14,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  property.postedByName?.trim().isNotEmpty == true
                      ? property.postedByName!.trim()
                      : 'PropCid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            property.title,
            style: AppTextStyles.body.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (category != null || listingLabel != null) ...[
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (category != null)
                  _chip(
                    icon: category.$1,
                    label: category.$2,
                    bg: AppColors.primaryLight,
                    fg: AppColors.primary,
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
          ],
          const SizedBox(height: 3),
          Text(
            property.priceDisplay,
            style: AppTextStyles.price.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.location_on,
                size: 9,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  property.location,
                  style: AppTextStyles.caption.copyWith(fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 7.5, color: fg),
          const SizedBox(width: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.chip.copyWith(
              fontSize: 7.5,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
