import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/reel_model.dart';
import '../../../providers/property_provider.dart';
import '../../../providers/reels_provider.dart';
import 'reel_action_button.dart';

/// Horizontal like / comment / share / save row shown inside the bordered
/// box on the white property card — a direct layout swap for the old
/// vertical right-rail. All state (like/save counts, toggles) still comes
/// straight from [ReelsProvider]; only the presentation changed.
class ReelActionRow extends StatelessWidget {
  const ReelActionRow({
    super.key,
    required this.reel,
    required this.onComment,
    required this.onShare,
    this.bordered = true,
    this.mainAxisAlignment = MainAxisAlignment.spaceEvenly,
    this.spacing = 0,
  });

  final ReelModel reel;
  final VoidCallback onComment;
  final VoidCallback onShare;

  /// The original card design wrapped this row in a bordered box. The
  /// compact card (video ~80%, card ~20%) drops the border for a plainer
  /// inline row — pass `false` there.
  final bool bordered;

  /// `spaceEvenly` (original, full-width card) vs. `start` with explicit
  /// [spacing] (compact card, left-aligned next to the CTA buttons).
  final MainAxisAlignment mainAxisAlignment;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Consumer<ReelsProvider>(
      builder: (context, provider, _) {
        // A listing-video reel is liked/saved as its property, via
        // PropertyProvider (see ReelModel.isPropertyVideo). Only looked up
        // for those, so influencer reels never depend on it being in scope.
        final isProperty = reel.isPropertyVideo;
        final PropertyProvider? properties = isProperty
            ? context.watch<PropertyProvider>()
            : null;
        final liked = isProperty
            ? properties!.isLiked(reel.id)
            : provider.isLiked(reel.id);
        final saved = isProperty
            ? properties!.isShortlisted(reel.id)
            : provider.isSaved(reel.id);

        final buttons = <Widget>[
          ReelActionButton(
            axis: Axis.horizontal,
            showIconBackground: false,
            iconBoxSize: 22,
            iconSize: 22,
            baseColor: AppColors.textSecondary,
            labelColor: AppColors.textSecondary,
            icon: Icons.favorite_border_rounded,
            activeIcon: Icons.favorite_rounded,
            // `reel.likes` for a listing-video reel is the property's own
            // `properties.likes` — already the true, current total, which
            // already includes the current viewer's own like whenever
            // `liked` is true. No "+1 when liked" adjustment belongs here
            // (unlike the influencer branch's `likeCount`) — that used to
            // double-count a property the viewer had already liked before
            // this reel loaded.
            label: _formatCount(
              isProperty ? reel.likes : provider.likeCount(reel),
            ),
            isActive: liked,
            activeColor: AppColors.error,
            onTap: () => isProperty
                ? properties!.toggleLike(reel.id)
                : provider.toggleLike(reel.id),
          ),
          ReelActionButton(
            axis: Axis.horizontal,
            showIconBackground: false,
            iconBoxSize: 22,
            iconSize: 22,
            baseColor: AppColors.textSecondary,
            labelColor: AppColors.textSecondary,
            icon: Icons.mode_comment_outlined,
            label: 'Comment',
            onTap: onComment,
          ),
          ReelActionButton(
            axis: Axis.horizontal,
            showIconBackground: false,
            iconBoxSize: 22,
            iconSize: 22,
            baseColor: AppColors.textSecondary,
            labelColor: AppColors.textSecondary,
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: onShare,
          ),
          ReelActionButton(
            axis: Axis.horizontal,
            showIconBackground: false,
            iconBoxSize: 22,
            iconSize: 22,
            baseColor: AppColors.textSecondary,
            labelColor: AppColors.textSecondary,
            icon: Icons.bookmark_border_rounded,
            activeIcon: Icons.bookmark_rounded,
            label: 'Save',
            isActive: saved,
            activeColor: AppColors.primary,
            onTap: () => isProperty
                ? properties!.toggleShortlist(reel.id)
                : provider.toggleSave(reel.id),
          ),
        ];

        final row = Row(
          mainAxisAlignment: mainAxisAlignment,
          mainAxisSize: mainAxisAlignment == MainAxisAlignment.spaceEvenly
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: spacing <= 0
              ? buttons
              : [
                  for (int i = 0; i < buttons.length; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    buttons[i],
                  ],
                ],
        );

        if (!bordered) return row;

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.textHint.withOpacity(0.4)),
          ),
          child: row,
        );
      },
    );
  }

  static String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
