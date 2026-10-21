import 'package:flutter/material.dart';

import '../../../core/widgets/frosted_glass.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';

/// "Create Content" tile grid (blueprint §4.1). Two-up normally; a third
/// "Add Video" tile appears when [onAddVideo] is supplied — mirrors the
/// portal's `CreateContent.tsx`, which only widens this grid to
/// `grid-cols-3` for `userType === 'influencer'` (lines 379-390).
///
/// [onAddArticle] is likewise nullable: a builder has no article-writing
/// surface anywhere else in the app (`builder_projects` is their whole
/// content model), so passing null there drops the tile instead of pointing
/// at a feature the role doesn't have.
class CreateContentGrid extends StatelessWidget {
  final VoidCallback onAddProperty;
  final VoidCallback? onAddArticle;
  final VoidCallback? onAddVideo;

  /// The first tile's label. Defaults to 'Add Property'; the Profile screen
  /// passes 'Add Project' for a builder — [onAddProperty] already routes a
  /// builder to the project wizard regardless (`PostPropertyRouteGate` swaps
  /// it server-side-of-the-UI), so only the label was ever out of step with
  /// what actually opens.
  final String propertyTileLabel;

  const CreateContentGrid({
    super.key,
    required this.onAddProperty,
    this.onAddArticle,
    this.onAddVideo,
    this.propertyTileLabel = 'Add Property',
  });

  @override
  Widget build(BuildContext context) {
    // `CrossAxisAlignment.stretch` sizes children along the *cross* axis,
    // which for a Row is vertical. This Row lives in a Column inside the
    // Profile screen's SingleChildScrollView, so its incoming height
    // constraint is 0..Infinity — stretch cannot resolve against an infinite
    // maximum, and RenderFlex ends up with no size at all.
    //
    // IntrinsicHeight bounds the cross axis to the taller of the two tiles,
    // which is what stretch needs and what keeps the pair equal-height like
    // the prototype's `1fr 1fr` grid. Same pattern already used by
    // ProfileStatsRow in this scroll view. Two shallow tiles, so the extra
    // measuring pass costs nothing meaningful.
    final addArticle = onAddArticle;
    final addVideo = onAddVideo;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ContentTile(
              icon: Icons.apartment_rounded,
              label: propertyTileLabel,
              tint: AppColors.primary,
              onTap: onAddProperty,
            ),
          ),
          if (addArticle != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _ContentTile(
                icon: Icons.article_outlined,
                label: 'Add Article',
                tint: AppColors.amenityBlue,
                onTap: addArticle,
              ),
            ),
          ],
          if (addVideo != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _ContentTile(
                icon: Icons.videocam_rounded,
                label: 'Add Video',
                tint: AppColors.amenityGreen,
                onTap: addVideo,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact row tile — icon badge, label, trailing chevron — rather than
/// the previous icon-stacked-above-label layout, and each tile now carries
/// its own accent colour instead of every icon sharing the one brand tint.
class _ContentTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _ContentTile({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        // Transparent backing still hit-tests the full tile.
        child: ColoredBox(
          color: Colors.transparent,
          child: FrostedGlass(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            borderRadius: 22,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: tint.withValues(alpha: 0.2)),
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
