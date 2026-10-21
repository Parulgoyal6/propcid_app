// screens/home/widgets/smart_tools_section.dart
//
// Home's "Smart Tools" rail — Area Converter, EMI Calculator, Stamp Duty.
//
// LAID OUT AS A RAIL, NOT THREE ACROSS
// ------------------------------------
// Three equal cards on a 320 dp phone leave (320 − 32 gutter − 24 gaps) / 3 =
// 88 dp each, which cannot hold a title, a description and a CTA without
// clipping. A horizontal rail is also what `QuickActionsSection` directly above
// already does, so this reads as its sibling rather than a new layout idea. Card
// radius, shadow, gradient badge and text sizes are that section's, scaled for
// the extra description line.
//
// EMI reuses the existing screen and route. There is deliberately no second EMI
// implementation here — the other two tools have no screen of their own, so they
// open as sheets.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../widgets/area_converter_sheet.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/stamp_duty_calculator_sheet.dart';

/// Rail height and card width, sized for the tallest card content (badge +
/// title + two description lines + CTA).
const double _kToolRailHeight = 168;
const double _kToolCardWidth = 158;

class _Tool {
  const _Tool({
    required this.title,
    required this.description,
    required this.cta,
    required this.icon,
    required this.gradient,
  });

  final String title;
  final String description;
  final String cta;
  final IconData icon;

  /// Two-stop badge gradient. Declared per card exactly as
  /// `QuickActionsSection._actions` does, so the shared palette in
  /// `AppColors` does not grow for three local badges.
  final List<Color> gradient;
}

class SmartToolsSection extends StatelessWidget {
  const SmartToolsSection({super.key});

  static const List<_Tool> _tools = [
    _Tool(
      title: 'Area Converter',
      description: 'Convert area units instantly.',
      cta: 'Open Converter',
      icon: Icons.grid_view_rounded,
      // The brand primary pair (AppColors.primaryGradient's own stops).
      gradient: [Color(0xFFF97316), Color(0xFFFDBA74)],
    ),
    _Tool(
      title: 'EMI Calculator',
      description: 'Calculate your home loan EMI.',
      cta: 'Calculate EMI',
      icon: Icons.calculate_rounded,
      // Blue, built from the existing `AppColors.statusNewLaunch` (#3B82F6).
      gradient: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
    ),
    _Tool(
      title: 'Stamp Calculator',
      description: 'Stamp duty and registration.',
      cta: 'Calculate Duty',
      icon: Icons.receipt_long_rounded,
      // The green pair QuickActionsSection uses for Visits.
      gradient: [Color(0xFF10B981), Color(0xFF34D399)],
    ),
  ];

  void _openTool(BuildContext context, int index) {
    switch (index) {
      case 0:
        showAreaConverterSheet(context);
        break;
      case 1:
        Navigator.pushNamed(context, AppConstants.emiCalculatorScreen);
        break;
      case 2:
        showStampDutyCalculatorSheet(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Smart Tools'),
        SizedBox(
          height: _kToolRailHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingL,
            ),
            itemCount: _tools.length,
            itemBuilder: (context, i) {
              final tool = _tools[i];
              return Padding(
                padding: const EdgeInsets.only(right: AppConstants.spacingM),
                child: ScaleTap(
                  onTap: () => _openTool(context, i),
                  child: _ToolCard(tool: tool),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kToolCardWidth,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: tool.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: tool.gradient.first.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(tool.icon, color: Colors.white, size: 20),
          ),
          const Spacer(),
          Text(
            tool.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tool.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 10.5, height: 1.3),
          ),
          const SizedBox(height: AppConstants.spacingS),
          Row(
            children: [
              Flexible(
                child: Text(
                  tool.cta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 12,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
