import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import 'property_card_search_grid.dart';

/// Card height of the real list row.
///
/// Duplicated from `property_card_search_row.dart`'s private `_kImageHeight`
/// rather than exported from it, because Phase 3 is closed and a completed file
/// is not being reopened for this. If that card's height ever changes, this must
/// change with it — the whole point of a skeleton is that content swaps in
/// without the layout shifting. The grid's extent below does not have this
/// problem: `kSearchGridTileExtent` is already public and imported directly.
const double _kRowCardHeight = 120;

/// Width of the real list row's image column.
const double _kRowImageWidth = 112;

/// Image height of the real grid tile.
const double _kGridImageHeight = 96;

/// How many placeholders to draw. Enough to fill a phone viewport without
/// building rows nobody will see.
const int _kRowCount = 5;
const int _kTileCount = 6;

/// One shimmer sweep wrapping a whole surface, so the highlight travels across
/// the list as a single motion instead of each card animating on its own clock.
Widget _shimmer({required Widget child}) {
  return Shimmer.fromColors(
    baseColor: Colors.grey[300]!,
    highlightColor: Colors.grey[100]!,
    child: child,
  );
}

/// A grey block standing in for a line of text or an image.
class _Block extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const _Block({this.width, required this.height, this.radius = 4});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// First-load placeholder for the List surface.
///
/// Search-scoped rather than an extension of `core/widgets/shimmer_loader.dart`:
/// that file's `PropertyCardShimmer` is a 220x140 rail card and its
/// `PropertyListShimmer` a 120x100 row, and both are rendered by the Messages
/// and Profile screens. Reshaping either to match this module's cards would have
/// changed those surfaces.
class SearchResultsListSkeleton extends StatelessWidget {
  const SearchResultsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: ListView.builder(
        // Inert: a placeholder that scrolls invites interaction with nothing.
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingXL,
          AppConstants.spacingM,
          AppConstants.spacingXL,
          AppConstants.spacingM,
        ),
        itemCount: _kRowCount,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
          child: _buildRow(),
        ),
      ),
    );
  }

  Widget _buildRow() {
    return Container(
      height: _kRowCardHeight,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Block(
            width: _kRowImageWidth,
            height: _kRowCardHeight,
            radius: 0,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // Mirrors the real row: price, title, locality, facts.
                  _Block(width: 96, height: 20),
                  SizedBox(height: AppConstants.spacingXS),
                  _Block(width: double.infinity, height: 14),
                  SizedBox(height: 2),
                  _Block(width: 120, height: 12),
                  SizedBox(height: 6),
                  _Block(width: 140, height: 11),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-load placeholder for the Grid surface.
class SearchResultsGridSkeleton extends StatelessWidget {
  const SearchResultsGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _shimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingXL,
          AppConstants.spacingM,
          AppConstants.spacingXL,
          AppConstants.spacingM,
        ),
        // Same delegate values as the real grid, so nothing reflows on swap.
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: AppConstants.spacingS,
          mainAxisSpacing: AppConstants.spacingL,
          mainAxisExtent: kSearchGridTileExtent,
        ),
        itemCount: _kTileCount,
        itemBuilder: (context, index) => _buildTile(),
      ),
    );
  }

  Widget _buildTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Block(
            width: double.infinity,
            height: _kGridImageHeight,
            radius: 0,
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                _Block(width: 70, height: 16),
                SizedBox(height: 3),
                _Block(width: double.infinity, height: 12),
                SizedBox(height: 5),
                _Block(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
