import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/frosted_glass.dart';
import '../core/widgets/scale_tap.dart';

/// Which surface a [ManageListTile] is being rendered on.
enum ManageListTileVariant {
  /// Standalone white card with a tinted icon box, subtitle and chevron —
  /// the Profile screen's "Manage" list.
  card,

  /// Flat row with a bare icon and no chevron — the Workspace Drawer and the
  /// More bottom sheet.
  plain,
}

/// The icon + label (+ subtitle + chevron) row shared by the Profile screen's
/// Manage list, the Workspace Drawer and the More bottom sheet.
///
/// Generalised from `_buildSectionCard`'s per-item `ListTile` in
/// `profile_screen.dart` so all three surfaces share one implementation —
/// see blueprint §7.
///
/// Prototype spec — [ManageListTileVariant.card]: white card, 16 dp radius,
/// `0 2px 10px rgba(26,26,46,0.05)`, 14 dp padding, 13 dp gap, a 42 dp
/// `#EEEDFE` icon box at 12 dp radius, a 14.5 dp semi-bold label over an
/// 11.5 dp muted subtitle, and a hint-coloured chevron.
/// [ManageListTileVariant.plain]: 11 dp/10 dp padding, 12 dp radius, a 22 dp
/// icon slot and a 13.5 dp medium label.
class ManageListTile extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Secondary line. Rendered by [ManageListTileVariant.card] only — the
  /// drawer and sheet rows in the prototype are label-only.
  final String? subtitle;

  final VoidCallback? onTap;

  final ManageListTileVariant variant;

  /// Renders the icon and label in the error colour, for Logout.
  final bool isDestructive;

  /// The colour of the surface this tile sits on.
  ///
  /// Painted behind the tile purely so the full row is hit-testable: a
  /// `DecoratedBox` does not hit-test its own bounds, which would otherwise
  /// leave the padding ring and the gaps between icon, label and chevron dead
  /// to taps. It is never visible — it is the colour already behind the tile.
  /// Defaults to the app canvas; pass [AppColors.cardBackground] inside the
  /// drawer or the More sheet.
  final Color surfaceColor;

  const ManageListTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.variant = ManageListTileVariant.card,
    this.isDestructive = false,
    this.surfaceColor = AppColors.background,
  });

  Color get _foreground =>
      isDestructive ? AppColors.error : AppColors.textPrimary;

  Color get _iconColor => isDestructive ? AppColors.error : AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: ColoredBox(
          // The card variant is frosted glass, so an opaque backing square
          // would show at its rounded corners. A transparent ColoredBox still
          // hit-tests its full bounds.
          color: variant == ManageListTileVariant.card
              ? Colors.transparent
              : surfaceColor,
          child: variant == ManageListTileVariant.card
              ? _buildCard()
              : _buildPlain(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return FrostedGlass(
      borderRadius: 22,
      blur: 14,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: [
            Container(
              width: AppConstants.manageTileIconBoxSize,
              height: AppConstants.manageTileIconBoxSize,
              decoration: BoxDecoration(
                color: isDestructive
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDestructive
                      ? AppColors.error.withValues(alpha: 0.18)
                      : AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Icon(icon, size: 20, color: _iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: _foreground,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppConstants.spacingS),
            // Small glass chevron bubble.
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
              ),
              child: const Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vertical run of [ManageListTile]s separated by the design's 10 dp gap.
  ///
  /// The Network and Social hubs are both a header above a list of these cards;
  /// this keeps the spacing in one place instead of each hub re-deriving it.
  static Widget group(List<ManageListTile> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          tiles[i],
        ],
      ],
    );
  }

  Widget _buildPlain() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Icon(
              icon,
              size: 20,
              color: isDestructive ? AppColors.error : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: _foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
