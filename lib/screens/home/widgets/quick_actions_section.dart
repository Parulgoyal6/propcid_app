import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/scale_tap.dart';

class _QuickAction {
  const _QuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.route,
    this.args,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String route;
  final Map<String, dynamic>? args;
}

/// Premium quick-action cards — Compare, Visits, Post Property, with a
/// gradient icon badge and a subtitle.
///
/// EMI Calculator used to be a 4th card here, duplicating the EMI Calculator
/// tool that also lives in `SmartToolsSection`'s "Smart Tools" rail (the
/// portal's "Useful Tools" grouping) further down the same page — the exact
/// duplicate this list existed to avoid. That entry was removed; Smart Tools
/// is now the Homepage's single EMI Calculator entry point.
class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({super.key});

  static const List<_QuickAction> _actions = [
    _QuickAction(
      label: 'Compare',
      subtitle: 'Find better deals',
      icon: Icons.compare_arrows_rounded,
      gradient: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
      route: AppConstants.comparePropertiesScreen,
      args: {'propertyIds': <String>[]},
    ),
    _QuickAction(
      label: 'Visits',
      subtitle: 'Manage site visits',
      icon: Icons.calendar_month_rounded,
      gradient: [Color(0xFF10B981), Color(0xFF34D399)],
      route: AppConstants.visitsScreen,
    ),
    _QuickAction(
      label: 'Post Property',
      subtitle: 'List in minutes',
      icon: Icons.add_home_rounded,
      gradient: [Color(0xFFF97316), Color(0xFFFB923C)],
      route: AppConstants.postPropertyScreen,
    ),
  ];

  static const double _cardSpacing = 12;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < _actions.length; i++) ...[
            if (i != 0) const SizedBox(width: _cardSpacing),
            Expanded(child: _QuickActionCard(action: _actions[i])),
          ],
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    // Post Property is the primary action, so only its badge is solid brand
    // orange; Compare/Visits use a translucent orange-tinted glass badge —
    // one accent colour, not three competing ones.
    final filled = action.route == AppConstants.postPropertyScreen;

    return ScaleTap(
      onTap: () =>
          Navigator.pushNamed(context, action.route, arguments: action.args),
      child: GlassCard(
        height: 94,
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
        // Real frosted glass — the warm light behind shows through.
        opacity: 0.52,
        blurSigma: 14,
        highlight: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: filled ? AppColors.ctaGradient : null,
                color: filled ? null : AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: filled
                      ? Colors.white.withOpacity(0.4)
                      : AppColors.primary.withOpacity(0.18),
                ),
                boxShadow: filled ? AppColors.ctaShadow : null,
              ),
              child: Icon(
                action.icon,
                color: filled ? Colors.white : AppColors.primary,
                size: 18,
              ),
            ),
            const Spacer(),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              action.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 10, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}
