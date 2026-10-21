import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

class FilterChipRow extends StatelessWidget {
  final List<String> chips;
  final String? selected;
  final Function(String)? onSelect;

  const FilterChipRow({
    super.key,
    required this.chips,
    this.selected,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppConstants.filterChipHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSelected = selected == chip;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: AppConstants.filterChipHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryLight
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textHint.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: () => onSelect?.call(chip),
                borderRadius: BorderRadius.circular(20),
                child: Center(
                  child: Text(
                    chip,
                    style: AppTextStyles.chip.copyWith(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
