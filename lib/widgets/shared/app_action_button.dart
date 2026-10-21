import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/scale_tap.dart';

/// How an [AppActionButton] is painted.
enum AppActionButtonVariant {
  /// Solid `#5B50E8` with white label.
  solid,

  /// White with a 1.5 dp primary border and primary label.
  outline,

  /// White with a 1.5 dp `#FCA5A5` border and `#EF4444` label — the design's
  /// "Cancel Subscription" treatment.
  danger,

  /// White with a soft shadow and a dark label, no border — the Social
  /// module's "Refresh" / "Export CSV" pair.
  surface,
}

/// The design's rectangular action button.
///
/// Deliberately not `PremiumButton`: that is a 52 dp gradient control carrying
/// `primaryGlow`, a visibly different element that the redesign does not use.
/// This one is the flat 12 dp-radius button that appears throughout the
/// Subscription & Billing screens at 40, 44 and 46 dp tall, so the height is a
/// parameter rather than three near-identical widgets.
class AppActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final AppActionButtonVariant variant;
  final double height;

  /// Optional glyph before the label.
  final IconData? icon;

  /// Optional glyph after the label — the design puts a chevron here on the
  /// "Upgrade" and "View Pricing Plans" buttons.
  final IconData? trailingIcon;

  /// The design carries the action shadow on the full-width primary CTAs but
  /// not on the inline pair inside the Billing tab.
  final bool elevated;

  /// Label size. The design uses 13 dp on the 44/46 dp buttons and 12.5 dp on
  /// the 40 dp toolbar pair.
  final double fontSize;

  const AppActionButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = AppActionButtonVariant.solid,
    this.height = 46,
    this.icon,
    this.trailingIcon,
    this.elevated = false,
    this.fontSize = 13,
  });

  bool get _isSolid => variant == AppActionButtonVariant.solid;

  Color get _foreground {
    switch (variant) {
      case AppActionButtonVariant.solid:
        return Colors.white;
      case AppActionButtonVariant.outline:
        return AppColors.primary;
      case AppActionButtonVariant.danger:
        return AppColors.error;
      case AppActionButtonVariant.surface:
        return AppColors.textPrimary;
    }
  }

  Color? get _border {
    switch (variant) {
      case AppActionButtonVariant.solid:
        return null;
      case AppActionButtonVariant.outline:
        return AppColors.primary;
      case AppActionButtonVariant.danger:
        return AppColors.errorBorder;
      case AppActionButtonVariant.surface:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _border;

    final body = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      decoration: BoxDecoration(
        color: _isSolid ? AppColors.primary : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor, width: 1.5),
        boxShadow: variant == AppActionButtonVariant.surface
            ? const [
                BoxShadow(
                  color: Color(0x0F1A1A2E),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ]
            : (_isSolid && elevated ? AppColors.primaryActionShadow : null),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: _foreground),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.button.copyWith(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: _foreground,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            Icon(trailingIcon, size: 16, color: _foreground),
          ],
        ],
      ),
    );

    if (onTap == null) return body;

    return Semantics(
      label: label,
      button: true,
      child: ScaleTap(onTap: onTap, child: body),
    );
  }
}
