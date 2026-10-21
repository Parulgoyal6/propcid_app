import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/scale_tap.dart';
import '../../widgets/shared/section_header_back_button.dart';

/// A collapsible policy section.
class _PolicySection {
  final String key;
  final String title;
  final IconData icon;

  /// Null for the FAQ section, which renders [_faqItems] instead of prose.
  final String? body;

  const _PolicySection(this.key, this.title, this.icon, this.body);
}

class _Faq {
  final String question;
  final String answer;

  const _Faq(this.question, this.answer);
}

/// Billing Policies — the design's `isBillingPolicies` screen.
///
/// Nine collapsible sections of static policy copy, taken verbatim from the
/// approved design. Purely informational: no queries, no state beyond which
/// sections are open.
class BillingPoliciesScreen extends StatefulWidget {
  const BillingPoliciesScreen({super.key});

  @override
  State<BillingPoliciesScreen> createState() => _BillingPoliciesScreenState();
}

class _BillingPoliciesScreenState extends State<BillingPoliciesScreen> {
  final Set<String> _open = <String>{};

  static const List<_PolicySection> _sections = [
    _PolicySection(
      'subscription',
      'Subscription Policy',
      Icons.article_outlined,
      'Your subscription starts immediately after payment and remains active '
          'until the end of the billing period. Premium features stay '
          'available the whole time.',
    ),
    _PolicySection(
      'billing',
      'Billing Policy',
      Icons.credit_card_outlined,
      'Monthly billing runs 30 days, yearly runs 365 days. Invoices generate '
          'automatically with GST breakdown and are downloadable anytime.',
    ),
    _PolicySection(
      'cancellation',
      'Cancellation Policy',
      Icons.track_changes,
      'Cancelling stops future renewals only — it is not a refund. You keep '
          'access until your current period ends, and no automatic refund is '
          'issued.',
    ),
    _PolicySection(
      'refund',
      'Refund Policy',
      Icons.refresh,
      'Refund requests are reviewed case-by-case. Valid reasons include '
          'duplicate payments, technical issues, and billing errors. Review '
          'takes 3-5 business days.',
    ),
    _PolicySection(
      'upgrade',
      'Upgrade & Downgrade',
      Icons.trending_up_rounded,
      'Upgrades apply immediately with a prorated charge. Downgrades take '
          'effect next billing cycle with no additional payment and no refund '
          'for the remaining period.',
    ),
    _PolicySection(
      'renewal',
      'Auto Renewal',
      Icons.refresh,
      'With auto-renewal on, your plan renews automatically and payment is '
          'charged to your saved method. Turn it off to let your subscription '
          'end at expiry with no future charges.',
    ),
    _PolicySection(
      'security',
      'Payment Security',
      Icons.verified_user_outlined,
      'All transactions are encrypted with 256-bit SSL and processed through a '
          'trusted payment gateway. Your data is never shared or sold.',
    ),
    _PolicySection(
      'faq',
      'Frequently Asked Questions',
      Icons.settings_outlined,
      null,
    ),
    _PolicySection(
      'support',
      'Contact Billing Support',
      Icons.chat_bubble_outline,
      'Email support@propcid.com (24-hour response) or submit a ticket from '
          'your dashboard. Phone support: Mon-Fri, 9AM-6PM IST.',
    ),
  ];

  static const List<_Faq> _faqItems = [
    _Faq(
      'Will I receive a refund?',
      'Cancellations do not automatically qualify for refunds. Refunds '
          'require a separate request and are reviewed case-by-case.',
    ),
    _Faq(
      'Can I upgrade later?',
      'Yes, upgrades take effect immediately and require payment of the '
          'prorated difference.',
    ),
    _Faq(
      'What happens if payment fails?',
      'We retry failed payments 3 times over 7 days. If all attempts fail, '
          'your subscription is downgraded to Free.',
    ),
  ];

  void _toggle(String key) {
    setState(() {
      if (!_open.remove(key)) _open.add(key);
    });
  }

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
              const DashboardHeaderBar(title: 'Billing Policies'),
              const SizedBox(height: AppConstants.spacingL),
              for (var i = 0; i < _sections.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _PolicyCard(
                  section: _sections[i],
                  open: _open.contains(_sections[i].key),
                  onTap: () => _toggle(_sections[i].key),
                  faqItems: _faqItems,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final _PolicySection section;
  final bool open;
  final VoidCallback onTap;
  final List<_Faq> faqItems;

  const _PolicyCard({
    required this.section,
    required this.open,
    required this.onTap,
    required this.faqItems,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: section.title,
            button: true,
            expanded: open,
            child: ScaleTap(
              onTap: onTap,
              child: ColoredBox(
                color: AppColors.cardBackground,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          section.icon,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          section.title,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      // 200 ms rotation, matching the design's transition.
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              // Indented to align with the title, past the 36 dp glyph box.
              padding: const EdgeInsets.fromLTRB(
                62,
                0,
                14,
                AppConstants.spacingL,
              ),
              child: section.body != null
                  ? Text(
                      section.body!,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < faqItems.length; i++) ...[
                          if (i > 0) const SizedBox(height: 14),
                          Text(
                            faqItems[i].question,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            faqItems[i].answer,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
