import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shown in place of a property rail's cards when its slice of
/// `PropertyProvider.properties` is empty, so the section keeps its shape on
/// the Home feed instead of vanishing entirely.
///
/// Sections opt in (`showWhenEmpty: true`) rather than getting this by
/// default — a page of "nothing here yet" panels reads worse than a shorter
/// page, so only the rails that anchor the layout use it.
class EmptyRailPlaceholder extends StatelessWidget {
  const EmptyRailPlaceholder({
    super.key,
    required this.height,
    this.message = 'No listings here yet',
    this.detail = 'New properties show up here as they go live.',
    this.icon = Icons.home_work_outlined,
  });

  final double height;
  final String message;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DottedOutline(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.primary),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  detail,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft outlined surface used behind the placeholder content.
class DottedOutline extends StatelessWidget {
  const DottedOutline({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      child: child,
    );
  }
}
