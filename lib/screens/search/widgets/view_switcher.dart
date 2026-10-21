import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';

/// Which results surface is showing.
///
/// Public, and declared here rather than in the screen, because the screen and
/// this widget both need it and a `_`-prefixed enum cannot cross a file
/// boundary. Replaces the old private `_ViewMode { list, map }`; `grid` is the
/// net-new member.
enum SearchViewMode { list, grid, map }

/// The List / Grid / Map segmented control.
///
/// Deliberately NOT built on `core/widgets/segmented_tab_pill.dart`, even though
/// that widget renders the identical track and pill treatment: it takes labels
/// only and has no icon slot, and adding one would change a widget already
/// rendering on My Content, Messages and the Manage Dashboard. Duplicating ~40
/// lines here is the cheaper trade than touching three unrelated surfaces.
///
/// Redesign spec: `#EEEDFE` track at a 12 dp radius with 4 dp padding and gaps;
/// each item 32 dp tall at a 9 dp radius; the active item is a white pill
/// carrying `raisedPillShadow` with a primary-coloured icon and label,
/// inactive items are transparent with secondary-coloured content.
class ViewSwitcher extends StatelessWidget {
  final SearchViewMode value;
  final ValueChanged<SearchViewMode> onChanged;

  const ViewSwitcher({super.key, required this.value, required this.onChanged});

  static const Map<SearchViewMode, ({String label, IconData icon})> _items = {
    SearchViewMode.list: (label: 'List', icon: Icons.list),
    SearchViewMode.grid: (label: 'Grid', icon: Icons.grid_view),
    SearchViewMode.map: (label: 'Map', icon: Icons.map_outlined),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingXS),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          for (final entry in _items.entries) ...[
            if (entry.key != _items.keys.first)
              const SizedBox(width: AppConstants.spacingXS),
            Expanded(
              child: _buildItem(
                mode: entry.key,
                label: entry.value.label,
                icon: entry.value.icon,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem({
    required SearchViewMode mode,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = mode == value;
    final Color content = isSelected ? Colors.white : AppColors.textSecondary;

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      child: ScaleTap(
        onTap: isSelected ? null : () => onChanged(mode),
        // A DecoratedBox does not hit-test its own bounds, which would leave an
        // unselected item's padding dead to taps. Painting the track colour
        // behind the pill makes the whole slot tappable and is invisible — it is
        // the exact colour already sitting there.
        child: ColoredBox(
          color: AppColors.primaryLight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Selected: the brand orange gradient with a soft glow.
              gradient: isSelected ? AppColors.ctaGradient : null,
              borderRadius: BorderRadius.circular(
                AppConstants.segmentedTabItemRadius,
              ),
              boxShadow: isSelected ? AppColors.ctaShadow : null,
            ),
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: content),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: content,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
