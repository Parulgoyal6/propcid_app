import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/constants/app_constants.dart';

class StatusTag extends StatelessWidget {
  final String label;

  const StatusTag({super.key, required this.label});

  /// `label` is a raw listing hashtag with no length limit at the source, but
  /// this badge always sits unbounded inside a `Positioned(top, left)` in a
  /// `Stack` — the tightest host (the Search list row's 112 dp image column)
  /// leaves under this much room, so an overlong hashtag now ellipsizes
  /// instead of overflowing the image and getting hard-clipped by the card.
  static const double _maxWidth = 100;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.getStatusChipBg(label),
          borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.chip.copyWith(
            color: AppColors.getStatusChipText(label),
          ),
        ),
      ),
    );
  }
}
