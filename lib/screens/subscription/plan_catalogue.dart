import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// How a plan's call-to-action is painted.
enum PlanCtaStyle {
  /// Muted green — the plan the account is already on. Not tappable.
  current,

  /// Solid primary with the design's action shadow — the recommended plan.
  solid,

  /// White with a 1.5 dp primary border.
  outline,
}

class PlanFeature {
  final String label;
  final bool included;

  const PlanFeature(this.label, {this.included = true});
}

/// One plan card on the Upgrade screen.
class PlanDefinition {
  final String key;
  final String name;
  final String description;
  final IconData icon;

  /// Icon tint and its 38 dp tile background.
  final Color tint;
  final Color tintBackground;

  /// Rupees per month. [yearlyPricePerMonth] is the discounted monthly rate
  /// when billed annually, matching how the design labels yearly pricing.
  final int monthlyPrice;
  final int yearlyPricePerMonth;

  /// Total charged up front on the yearly plan, shown as "Billed annually".
  /// Null for Free, which has no annual charge.
  final int? yearlyTotal;

  /// Floating pill above the card, e.g. "Most Popular".
  final String? badge;
  final Color? badgeColor;

  final List<PlanFeature> features;
  final String cta;
  final PlanCtaStyle ctaStyle;

  const PlanDefinition({
    required this.key,
    required this.name,
    required this.description,
    required this.icon,
    required this.monthlyPrice,
    required this.yearlyPricePerMonth,
    required this.features,
    required this.cta,
    required this.ctaStyle,
    this.tint = AppColors.primary,
    this.tintBackground = AppColors.primaryLight,
    this.yearlyTotal,
    this.badge,
    this.badgeColor,
  });
}

/// The Upgrade screen's plan catalogue.
///
/// Presentation config only — no table, no query, nothing derived from the
/// account. React keeps the same data in `src/config/planConfig.ts`, so this is
/// the equivalent layer rather than a new backend surface.
///
/// The catalogue follows the approved design's `planDefs` (Free / Owner Plus /
/// Owner Pro / Concierge at ₹0/9/19/49), which is the owner-facing ladder.
/// React's `planConfig.ts` still lists an older builder-facing set
/// (free/pro/builder/enterprise in dollars); where the two disagree on product
/// copy the design wins, per the approved rule.
class PlanCatalogue {
  PlanCatalogue._();

  /// Discount pill shown beside the billing-period switch when Yearly is on.
  static const String yearlySavingLabel = 'Save 20%';

  static const List<PlanDefinition> plans = [
    PlanDefinition(
      key: 'free',
      name: 'Free',
      description: 'For individual owners & seekers',
      icon: Icons.person_outline,
      tint: AppColors.success,
      tintBackground: Color(0xFFE7F8ED),
      monthlyPrice: 0,
      yearlyPricePerMonth: 0,
      // The design badges this card "Current Plan". Deliberately omitted:
      // nothing in this phase reads the account's subscription, so claiming a
      // plan would be asserting billing state we have not looked up.
      features: [
        PlanFeature('2 active property listings'),
        PlanFeature('Save searches & favourites'),
        PlanFeature('Basic enquiry alerts'),
        PlanFeature('Mobile app access'),
        PlanFeature('Featured listing placement', included: false),
      ],
      cta: 'Free plan',
      ctaStyle: PlanCtaStyle.current,
    ),
    PlanDefinition(
      key: 'plus',
      name: 'Owner Plus',
      description: 'List and sell your property faster',
      icon: Icons.work_outline,
      monthlyPrice: 9,
      yearlyPricePerMonth: 7,
      yearlyTotal: 84,
      badge: 'Most Popular',
      badgeColor: Color(0xFFF59E0B),
      features: [
        PlanFeature('10 active property listings'),
        PlanFeature('Priority enquiry alerts'),
        PlanFeature('1 featured listing / month'),
        PlanFeature('Listing view analytics'),
        PlanFeature('AI-written property descriptions'),
      ],
      cta: 'Choose Owner Plus',
      ctaStyle: PlanCtaStyle.solid,
    ),
    PlanDefinition(
      key: 'pro',
      name: 'Owner Pro',
      description: 'For sellers with multiple properties',
      icon: Icons.apartment_rounded,
      monthlyPrice: 19,
      yearlyPricePerMonth: 15,
      yearlyTotal: 180,
      features: [
        PlanFeature('25 active property listings'),
        PlanFeature('5 featured listings / month'),
        PlanFeature('Advanced view & enquiry analytics'),
        PlanFeature('AI-written property descriptions'),
        PlanFeature('Verified owner badge'),
      ],
      cta: 'Choose Owner Pro',
      ctaStyle: PlanCtaStyle.outline,
    ),
    PlanDefinition(
      key: 'concierge',
      name: 'Concierge',
      description: 'White-glove selling assistance',
      icon: Icons.workspace_premium_outlined,
      monthlyPrice: 49,
      yearlyPricePerMonth: 39,
      yearlyTotal: 468,
      features: [
        PlanFeature('Unlimited property listings'),
        PlanFeature('Unlimited featured placement'),
        PlanFeature('Personal relationship manager'),
        PlanFeature('End-to-end selling assistance'),
        PlanFeature('Verified owner badge'),
      ],
      cta: 'Contact Us',
      ctaStyle: PlanCtaStyle.outline,
    ),
  ];
}
