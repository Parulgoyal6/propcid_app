import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../widgets/shared/section_header_back_button.dart';

/// The chrome every Social leaf screen shares: canvas, safe area, the design's
/// `16px 20px 28px` padding and the standard header.
///
/// One shell rather than the same twelve lines in six files.
class SocialScreenShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  /// Preferences uses a taller bottom inset in the design (100 dp) because its
  /// last card sits close to the gesture bar.
  final double bottomPadding;

  const SocialScreenShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.bottomPadding = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
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

/// Card heading — 14 dp bold, the weight the Social cards use.
class SocialCardTitle extends StatelessWidget {
  final String text;

  const SocialCardTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.heading3.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Section heading inside a card — 14 dp bold over an 11.5 dp muted line.
class SocialCardHeading extends StatelessWidget {
  final String title;
  final String description;

  const SocialCardHeading(this.title, this.description, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SocialCardTitle(title),
        const SizedBox(height: 3),
        Text(
          description,
          style: AppTextStyles.caption.copyWith(fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}

/// A read-only value box — 44 dp, 12 dp radius, hairline border.
///
/// Preferences renders its caption defaults this way rather than as text
/// fields: this phase does not write to `social_share_preferences`, and an
/// editable-looking box that discards input would be worse than an honest
/// read-only one.
class SocialValueBox extends StatelessWidget {
  final String? value;
  final String placeholder;
  final IconData? trailingIcon;

  const SocialValueBox({
    super.key,
    required this.value,
    required this.placeholder,
    this.trailingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              hasValue ? value! : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                color: hasValue ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 18, color: AppColors.textHint),
        ],
      ),
    );
  }
}

/// Field label above a [SocialValueBox] — 12 dp semi-bold.
class SocialFieldLabel extends StatelessWidget {
  final String text;

  const SocialFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
