import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../widgets/shared/app_surface_card.dart';
import '../../../widgets/shared/section_header_back_button.dart';

/// The chrome every Network leaf screen shares: canvas, safe area, the design's
/// `16px 20px 28px` padding and the standard header.
class NetworkScreenShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const NetworkScreenShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DashboardHeaderBar(title: title, subtitle: subtitle),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// The tinted intro banner the Leads, Referrals and Communication screens open
/// with: `#EEEDFE`, 16 dp radius, a 14.5 dp bold title over 11.5 dp copy, and an
/// optional trailing control or action row.
class NetworkIntroBanner extends StatelessWidget {
  final String title;
  final String description;

  /// Rendered to the right of the copy — the design's "Settings" pill.
  final Widget? trailing;

  /// Rendered beneath the copy — the design's action buttons.
  final Widget? action;

  const NetworkIntroBanner({
    super.key,
    required this.title,
    required this.description,
    this.trailing,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AppTextStyles.heading3.copyWith(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: AppTextStyles.caption.copyWith(fontSize: 11.5, height: 1.4),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null)
            copy
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 10),
                trailing!,
              ],
            ),
          if (action != null) ...[
            const SizedBox(height: AppConstants.spacingM),
            action!,
          ],
        ],
      ),
    );
  }
}

/// White card with a tinted glyph, a 14.5 dp bold heading and a body.
///
/// The Network leaves all use this shape — "Current Networks", "Network Leads",
/// "Network Channels" — so the heading row lives here once.
class NetworkTitledCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const NetworkTitledCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 9),
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
            ],
          ),
          child,
        ],
      ),
    );
  }
}

/// A labelled value row inside a Network card — label left, value right.
class NetworkDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const NetworkDetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // Both sides are flexible and ellipsised. The values here are stored
      // tokens — a commission status or a member-type list — which can be long
      // enough to push an unbounded Text past the card on a narrow screen.
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          Expanded(
            flex: 4,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTextStyles.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status pill. Green when [positive], neutral otherwise.
class NetworkStatusPill extends StatelessWidget {
  final String text;
  final bool positive;

  const NetworkStatusPill(this.text, {super.key, this.positive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: positive ? AppColors.success : AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: positive ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
