import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Back button + title + subtitle, shown atop every reskinned dashboard
/// (blueprint §16.5).
///
/// One widget, four call sites — it replaces each dashboard's own bespoke
/// gradient hero block so the roles stop diverging visually.
///
/// Prototype spec: a 36 dp circular white button carrying
/// `0 2px 8px rgba(26,26,46,0.08)`, a 17 dp bold title and a 12 dp muted
/// subtitle.
class DashboardHeaderBar extends StatelessWidget {
  final String title;

  /// Optional: the Subscription & Billing header in the design is a single
  /// title line with no supporting copy. Omitting it drops the second line
  /// entirely rather than reserving empty space for it.
  final String? subtitle;

  /// Defaults to popping the current route, which is what every dashboard's
  /// previous back button did.
  final VoidCallback? onBack;

  const DashboardHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          label: 'Back',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack ?? () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.cardBackground,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x141A1A2E),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                // Design shows a thin chevron, matching the prototype's
                // `back` glyph (M15 18l-6-6 6-6) rather than a filled arrow.
                Icons.chevron_left,
                size: 22,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading2.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
