import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// One removable filter chip.
class ActiveFilterChip {
  final String label;
  final VoidCallback onRemove;

  const ActiveFilterChip({required this.label, required this.onRemove});
}

/// Horizontally-scrolling row of the currently-applied filters, each clearable
/// in one tap.
///
/// The chips shown mirror exactly the facets `FilterProvider.activeFilterCount`
/// counts — category, listing type, non-default budget, bhk, subtype and posted
/// by — so the row and the filter button's badge can never disagree. Search
/// text, cities, sort and near-me are deliberately excluded, matching the
/// website's own filter-badge rule.
///
/// Redesign spec: 28 dp tall, `padding 0 6 0 12`, fully rounded, `#EEEDFE`
/// fill, an 11/600 primary label and a 13/700 primary multiplication sign.
class ActiveFilterChipRow extends StatelessWidget {
  final List<ActiveFilterChip> chips;

  const ActiveFilterChipRow({super.key, required this.chips});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (context, index) => const SizedBox(width: 7),
        itemBuilder: (context, index) => _buildChip(chips[index]),
      ),
    );
  }

  Widget _buildChip(ActiveFilterChip chip) {
    return Semantics(
      label: 'Remove filter ${chip.label}',
      button: true,
      child: GestureDetector(
        onTap: () {
          // Removing a filter is a discrete, consequential change — confirm it
          // physically, since the row it lives in also shrinks underneath it.
          HapticFeedback.selectionClick();
          chip.onRemove();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.only(left: AppConstants.spacingM, right: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chip.label,
                style: AppTextStyles.chip.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '×',
                style: AppTextStyles.chip.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
