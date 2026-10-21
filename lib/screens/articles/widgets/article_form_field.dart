import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Labelled field wrapper used throughout the Article Editor.
///
/// Prototype spec: a 12.5 dp semi-bold label, an optional right-aligned
/// counter, and a white 12 dp-radius input surface with a `#EDEDF2` border.
class ArticleFormField extends StatelessWidget {
  final String label;
  final bool required;

  /// Right-aligned helper, e.g. "128/300".
  final String? counter;

  final Widget child;

  const ArticleFormField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.counter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  children: required
                      ? [
                          TextSpan(
                            text: ' *',
                            style: AppTextStyles.body.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.error,
                            ),
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            if (counter != null)
              Text(
                counter!,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingS),
        child,
      ],
    );
  }
}

/// The white bordered surface the editor's inputs sit on.
class ArticleInputSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ArticleInputSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: Border.all(color: const Color(0xFFEDEDF2)),
      ),
      child: child,
    );
  }
}
