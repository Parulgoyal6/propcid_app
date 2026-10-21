import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/compare_toggle_handler.dart';
import '../../../models/property_model.dart';
import '../../../providers/compare_provider.dart';
import '../../../providers/property_provider.dart';
import '../../../widgets/property_card_vertical.dart';
import '../../../widgets/section_header.dart';
import 'empty_rail_placeholder.dart';

/// Generic horizontal property rail, parameterized by [title] and a
/// client-side [selector] over the already-loaded `properties` list — shared
/// by Luxury Collection / New Launches / Investment Opportunities so those
/// three near-identical rails don't need three near-duplicate files. No new
/// queries: every rail is just a different sort/filter of data already in
/// `PropertyProvider.properties`.
class PropertyRailSection extends StatelessWidget {
  const PropertyRailSection({
    super.key,
    required this.title,
    required this.selector,
    this.showWhenEmpty = false,
    this.emptyMessage,
    double? cardWidth,
    double? cardImageHeight,
  }) : cardWidth = cardWidth ?? AppConstants.propertyCardWidth,
       cardImageHeight =
           cardImageHeight ?? AppConstants.propertyCardImageHeight;

  final String title;
  final List<PropertyModel> Function(List<PropertyModel> all) selector;

  /// When true the rail keeps its header and shows [EmptyRailPlaceholder]
  /// instead of collapsing to nothing once [selector] returns no items.
  final bool showWhenEmpty;
  final String? emptyMessage;

  /// Lets one rail (Luxury Collection) render a visibly larger "step up"
  /// card than the others, for image-rhythm variety — same card widget,
  /// just a different size.
  final double cardWidth;
  final double cardImageHeight;

  @override
  Widget build(BuildContext context) {
    // Bounds each card's decoded image to its actual on-screen pixels
    // (this rail's own `cardWidth`/`cardImageHeight` — which may be an
    // override, e.g. Luxury Collection's larger card — not the shared
    // defaults) rather than the source's native resolution.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (cardWidth * dpr).round();
    final cacheHeight = (cardImageHeight * dpr).round();
    return Consumer<PropertyProvider>(
      builder: (context, propertyProvider, child) {
        final items = selector(propertyProvider.properties);
        if (items.isEmpty && !showWhenEmpty) return const SizedBox.shrink();
        final rowHeight =
            AppConstants.propertyCardHeight +
            (cardImageHeight - AppConstants.propertyCardImageHeight);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: title,
              actionLabel: 'See all ›',
              onActionTap: () => Navigator.pushNamed(
                context,
                AppConstants.searchResultsScreen,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              EmptyRailPlaceholder(
                height: rowHeight,
                message: emptyMessage ?? 'No listings here yet',
              )
            else
              SizedBox(
                height: rowHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final property = items[index];
                    // Narrowed to just this card's own compare state — was
                    // a whole-provider `context.watch` at the top of
                    // build(), which rebuilt every rail using this shared
                    // widget on any compare toggle anywhere in the app.
                    return Selector<CompareProvider, bool>(
                      selector: (_, compare) => compare.isSelected(property.id),
                      builder: (context, isInCompare, _) {
                        return PropertyCardVertical(
                          property: property,
                          width: cardWidth,
                          imageHeight: cardImageHeight,
                          imageCacheWidth: cacheWidth,
                          imageCacheHeight: cacheHeight,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppConstants.propertyDetailScreen,
                            arguments: {'propertyId': property.id},
                          ),
                          onFavoriteToggle: () =>
                              propertyProvider.toggleShortlist(property.id),
                          isInCompare: isInCompare,
                          onCompareToggle: () =>
                              handleCompareToggle(context, property),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
