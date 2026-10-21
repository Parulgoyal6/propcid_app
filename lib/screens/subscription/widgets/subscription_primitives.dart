import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Tab-level heading — 15 dp bold over a 12 dp muted line.
class SubSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const SubSectionTitle(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTextStyles.heading3.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTextStyles.caption.copyWith(fontSize: 12)),
      ],
    );
  }
}

/// Heading inside a card — 14 dp bold over an 11.5 dp muted line.
class SubCardHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const SubCardHeader(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTextStyles.heading3.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}

/// Overview KPI tile — 32 dp glyph box, uppercase micro-label, 16 dp value.
///
/// Deliberately not [MetricCard]: that tile is icon → 17 dp value → 11 dp
/// label, while this one is icon → 9.5 dp uppercase label → 16 dp value →
/// 10 dp sub. Different structure and four different type sizes, so reusing it
/// would mean parameterising almost every value.
class SubKpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;

  const SubKpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });

  /// Constant cell height, for the same reason [MetricCardGrid] uses one: the
  /// contents are a fixed stack of a glyph box and three pinned text lines, so
  /// tying height to width overflows on narrow devices.
  static const double cardHeight = 118;

  static const SliverGridDelegateWithFixedCrossAxisCount delegate =
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: cardHeight,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value $sub',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.surfaceCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: AppColors.primary),
            ),
            const SizedBox(height: 9),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint,
                letterSpacing: 0.4,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTextStyles.heading2.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Flexible(
              child: Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10,
                  color: AppColors.textHint,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inset row: label over value on the left, tinted chip on the right.
class BillingInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final String? chip;

  const BillingInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.chip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (chip != null) ...[
            const SizedBox(width: AppConstants.spacingS),
            TintChip(chip!),
          ],
        ],
      ),
    );
  }
}

/// 24 dp `#EEEDFE` pill with an 11 dp semi-bold primary label.
class TintChip extends StatelessWidget {
  final String text;

  const TintChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Read-only billing-detail field: label above a filled, bordered box.
///
/// Rendered as static text rather than a `TextField`: this phase does not write
/// to `billing_profiles`, and an editable-looking box that silently discards
/// input would be worse than an honest read-only one.
class ReadOnlyField extends StatelessWidget {
  final String label;
  final String? value;
  final String placeholder;

  const ReadOnlyField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Text(
            hasValue ? value! : placeholder,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              color: hasValue ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }
}

/// Centred in-card empty state: neutral circle, bold line, muted line.
///
/// The billing tabs' empty states use a `#F4F4F8` circle rather than the
/// primary-tinted one [EmptyStateView] paints, and several are message-only, so
/// this stays local to the module.
class BillingEmptyState extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String message;

  const BillingEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingS,
        vertical: AppConstants.spacingL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: AppColors.textHint),
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            Text(
              title!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
          ] else
            const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11.5,
              color: AppColors.textHint,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
