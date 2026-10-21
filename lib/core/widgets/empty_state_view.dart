import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'scale_tap.dart';

/// Centred icon + title + message + optional call-to-action, matching the
/// redesign's empty states ("No content yet", "No posts yet", "No channels
/// yet") and reused for the Coming Soon stubs in blueprint §16.12.
///
/// One parameterised widget rather than a per-screen reimplementation — see
/// blueprint §7 and §12.
///
/// Prototype spec: a soft `#EEEDFE` circle behind a primary-coloured icon, a
/// bold `#1A1A2E` title, a muted `#6B7280` message at 1.5 line-height, and an
/// optional solid primary button.
class EmptyStateView extends StatelessWidget {
  final IconData icon;

  /// Bold heading. Optional: a few in-card states in the design — the Network
  /// hub's "Recent Activity" block — are a circle above a single muted line
  /// with no heading at all. When null the [message] takes its place and sits
  /// 12 dp below the circle rather than 16 + 6.
  final String? title;

  /// Supporting line beneath the title. Optional — some empty states in the
  /// prototype are title-only.
  final String? message;

  /// When both [actionLabel] and [onAction] are supplied, a solid primary
  /// button is rendered beneath the message.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Diameter of the circle behind the icon. The prototype uses 56 for the My
  /// Content state, 60 for Channels/stubs and 64 for the Content Manager.
  final double iconCircleSize;

  /// Prototype uses 14.5 for My Content, 15 for Channels/Content Manager and
  /// 16 for the generic stub.
  final double titleFontSize;

  /// Outer padding. Defaults to the generous spacing the prototype uses when
  /// an empty state owns the full viewport.
  final EdgeInsetsGeometry padding;

  const EmptyStateView({
    super.key,
    required this.icon,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.iconCircleSize = AppConstants.emptyStateIconCircleSize,
    this.titleFontSize = 15,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppConstants.spacingXXL,
      vertical: AppConstants.spacingXXL,
    ),
  });

  bool get _hasAction => actionLabel != null && onAction != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: iconCircleSize,
            height: iconCircleSize,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: iconCircleSize * 0.47,
              color: AppColors.primary,
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: AppConstants.spacingL),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: AppTextStyles.heading3.copyWith(
                fontSize: titleFontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (message != null) ...[
            SizedBox(height: title == null ? 12 : 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
          if (_hasAction) ...[
            const SizedBox(height: 18),
            _EmptyStateAction(label: actionLabel!, onTap: onAction!),
          ],
        ],
      ),
    );
  }
}

/// The prototype's solid primary CTA: `#5B50E8`, 44 dp tall, 12 dp radius,
/// `0 4px 12px rgba(91,80,232,0.28)`.
///
/// Deliberately not `PremiumButton`, which is a 52 dp gradient button carrying
/// `primaryGlow` — a visibly different control. Per the approved decision to
/// follow the prototype where it conflicts with an existing primitive,
/// `PremiumButton` is left untouched for the screens already using it.
class _EmptyStateAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _EmptyStateAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          height: AppConstants.emptyStateActionHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingXL,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            boxShadow: AppColors.primaryActionShadow,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.button.copyWith(fontSize: 13.5),
            ),
          ),
        ),
      ),
    );
  }
}
