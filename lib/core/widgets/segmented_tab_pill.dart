import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'scale_tap.dart';

/// The pill-style segmented tab selector used throughout the redesign:
/// All / Properties / Articles (My Content), Chats / Channels (Messages), and
/// Analytics / Content Manager / Audience (Manage Dashboard).
///
/// Built once and parameterised so those surfaces share one implementation
/// rather than four near-duplicates — see blueprint §7.
///
/// Prototype spec: a `#EEEDFE` track with `4dp` padding and gaps, `12dp`
/// radius; the selected item is a white `9dp` pill carrying
/// `0 2px 6px rgba(26,26,46,0.1)` with primary-coloured text, unselected items
/// are transparent with secondary-coloured text.
class SegmentedTabPill extends StatelessWidget {
  /// Visible label for each tab, in order.
  final List<String> labels;

  /// Index into [labels] of the currently selected tab.
  final int selectedIndex;

  /// Called with the tapped tab's index. Not called for the already-selected
  /// tab.
  final ValueChanged<int> onChanged;

  /// Prototype uses 12 for the content/dashboard tracks and 12.5 for
  /// Messages.
  final double labelFontSize;

  /// Prototype uses 8 for the My Content track and 9 elsewhere.
  final double itemVerticalPadding;

  /// Lines a label may wrap onto. The dashboard's "Content Manager" tab wraps
  /// onto two; every other track is single-line.
  final int maxLines;

  /// Shrinks a label to fit one line instead of letting [maxLines] wrap it.
  ///
  /// Wrapping only helps a label with a space to break at ("Content
  /// Manager" → "Content" / "Manager"). A single long word ("Overview",
  /// "Inventory") has no such point, so `maxLines: 2` breaks it mid-letter —
  /// "Overvie" / "w" — instead. Builder's six-tab track is the one place
  /// that happens, so it opts into this; every other caller keeps the
  /// existing wrap-or-ellipsis behaviour untouched.
  final bool fitSingleLine;

  const SegmentedTabPill({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.labelFontSize = 12,
    this.itemVerticalPadding = 9,
    this.maxLines = 1,
    this.fitSingleLine = false,
  }) : assert(labels.length > 0, 'SegmentedTabPill needs at least one tab');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingXS),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      ),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: AppConstants.spacingXS),
            Expanded(child: _buildTab(i)),
          ],
        ],
      ),
    );
  }

  Widget _buildTab(int index) {
    final isSelected = index == selectedIndex;

    return Semantics(
      label: labels[index],
      button: true,
      selected: isSelected,
      child: ScaleTap(
        onTap: isSelected ? null : () => onChanged(index),
        // A DecoratedBox alone does not hit-test its own bounds, which would
        // leave an unselected tab's padding dead to taps. Painting the track
        // colour behind the pill makes the full slot tappable and is
        // invisible: it is the exact colour already sitting behind it.
        child: ColoredBox(
          color: AppColors.primaryLight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.cardBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(
                AppConstants.segmentedTabItemRadius,
              ),
              boxShadow: isSelected ? AppColors.raisedPillShadow : null,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: itemVerticalPadding,
                horizontal: AppConstants.spacingXS,
              ),
              child: fitSingleLine
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[index],
                        maxLines: 1,
                        softWrap: false,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    )
                  : Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
