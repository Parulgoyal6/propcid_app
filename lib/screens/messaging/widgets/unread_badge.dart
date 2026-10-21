import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The brand-coloured unread pill used on conversation and channel rows.
///
/// Prototype spec: minimum 18 dp wide, fully rounded, primary background,
/// 10.5 dp bold white numerals.
class UnreadBadge extends StatelessWidget {
  final int count;

  /// Counts above this render as "99+" so the pill cannot stretch a row.
  final int cap;

  const UnreadBadge({super.key, required this.count, this.cap = 99});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Center(
        child: Text(
          count > cap ? '$cap+' : '$count',
          style: AppTextStyles.caption.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
