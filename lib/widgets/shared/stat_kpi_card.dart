import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The metric tile shared by every dashboard's Analytics and Audience grids
/// (blueprint §16.5).
///
/// Extracted from the near-identical `_card` helpers inside
/// `BrokerStatsWidget`, `BuilderStatsWidget`, `InfluencerStatsWidget` and the
/// Individual dashboard's `_StatCard`, so all four roles share one shape,
/// spacing and shadow instead of four slightly different ones.
///
/// Prototype spec: white card, 16 dp radius,
/// `0 2px 10px rgba(26,26,46,0.05)`, 14 dp padding, a 34 dp rounded-square
/// icon box, a 17 dp bold value and an 11 dp muted label — left-aligned.
///
/// The approved design tints every icon box uniformly — a `#EEEDFE` square with
/// a primary glyph — so [accent] now defaults to primary and is left in place
/// only for the few callers that still pass a role colour.
class MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  const MetricCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.accent = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.surfaceCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                // Flat `#EEEDFE` when primary, matching the design exactly,
                // rather than a 12%-alpha wash of it.
                color: accent == AppColors.primary
                    ? AppColors.primaryLight
                    : accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTextStyles.heading2.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  // Poppins' default line box is looser than the prototype's
                  // CSS line-height, which is what pushed this Column past its
                  // cell. Pinning 1.2 reproduces the browser metrics.
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // Flexible so a long label can never push the column past a fixed
            // cell height — it ellipsises instead of overflowing.
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-column grid of [MetricCard]s, matching the prototype's Analytics and
/// Audience layouts.
class MetricCardGrid extends StatelessWidget {
  final List<MetricCard> cards;

  const MetricCardGrid({super.key, required this.cards});

  /// Fixed card height rather than an aspect ratio.
  ///
  /// The card's contents are a constant height — a 34 dp icon box, two pinned
  /// text lines and 14 dp padding — so tying height to width made cells too
  /// short on narrow devices and overflowed the column. 112 dp reproduces the
  /// prototype's content-driven height (14 + 34 + 10 + 20.4 + 2 + 13.2 + 14
  /// ≈ 108) with a little slack, and stays constant at every width.
  static const double cardHeight = 112;

  /// Shared grid geometry, so the shimmer placeholder cannot drift from the
  /// real grid.
  static const SliverGridDelegateWithFixedCrossAxisCount delegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // childAspectRatio deliberately not used — see [cardHeight].
        mainAxisExtent: cardHeight,
      );

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: delegate,
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }
}

/// Shimmer stand-in for a [MetricCardGrid], keeping the design's card geometry
/// so nothing shifts when real values land (blueprint §12).
///
/// Promoted from `dashboard_tab_bodies.dart`'s private `_MetricGridShimmer` in
/// Phase 6 so the Network hub shows the identical placeholder rather than a
/// second copy that could drift from it.
class MetricCardGridShimmer extends StatelessWidget {
  final int count;

  const MetricCardGridShimmer({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      // Reuses the real grid's geometry so nothing shifts when values land.
      gridDelegate: MetricCardGrid.delegate,
      itemCount: count,
      itemBuilder: (context, _) => Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          ),
        ),
      ),
    );
  }
}
