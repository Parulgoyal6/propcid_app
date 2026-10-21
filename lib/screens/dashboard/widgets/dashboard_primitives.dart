import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';

// DashboardCard, DashboardCardTitle and DashboardSectionLabel were promoted to
// the shared component library in Phase 6 so the Network, Social and Upgrade
// modules can build on the same surface primitives without importing from a
// dashboard screen folder.
//
// This re-export keeps every existing `dashboard_primitives.dart` import
// working untouched — the classes are the same classes, moved verbatim.
export '../../../widgets/shared/app_surface_card.dart';

/// "Content Library" heading with a "＋ Create Post" pill on the right.
///
/// Prototype spec: title 14.5 dp bold; button 36 dp tall, 14 dp horizontal
/// padding, 10 dp radius, solid primary, 14 dp plus icon, 12.5 dp semi-bold
/// white label.
class ContentLibraryHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  const ContentLibraryHeader({
    super.key,
    this.title = 'Content Library',
    this.actionLabel = 'Create Post',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.heading3.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Semantics(
          label: actionLabel,
          button: true,
          child: ScaleTap(
            onTap: onAction,
            child: ColoredBox(
              color: AppColors.background,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      actionLabel,
                      style: AppTextStyles.button.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Centred empty state used by the Content Manager and Audience tabs.
///
/// Prototype spec: 64 dp `#EEEDFE` circle with a 28 dp primary icon, 15 dp bold
/// title 16 dp below, 12.5 dp muted body at 1.5 line-height 6 dp below, and an
/// optional 44 dp primary CTA 18 dp below carrying
/// `0 4px 12px rgba(91,80,232,0.28)`.
class DashboardEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: AppConstants.spacingL),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading3.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(fontSize: 12.5, height: 1.5),
          ),
          if (hasAction) ...[
            const SizedBox(height: 18),
            Semantics(
              label: actionLabel,
              button: true,
              child: ScaleTap(
                onTap: onAction,
                child: ColoredBox(
                  color: AppColors.background,
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingXL,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(
                        AppConstants.buttonRadius,
                      ),
                      boxShadow: AppColors.primaryActionShadow,
                    ),
                    child: Center(
                      child: Text(
                        actionLabel!,
                        style: AppTextStyles.button.copyWith(fontSize: 13.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Square-round create FAB.
///
/// Prototype spec: 56×56, 16 dp radius, 135° `#5B50E8 → #7C72F0` gradient,
/// `0 8px 20px rgba(91,80,232,0.4)`, 24 dp white plus icon. Icon-only — the
/// design has no extended label.
class DashboardCreateFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final String semanticLabel;

  const DashboardCreateFab({
    super.key,
    required this.onPressed,
    this.semanticLabel = 'Create',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: ScaleTap(
        onTap: onPressed,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x665B50E8),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}
