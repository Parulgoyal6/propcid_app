import 'package:flutter/material.dart';

/// One row of the Features tab.
class FeatureAccess {
  final IconData icon;
  final String label;
  final bool included;

  const FeatureAccess(this.icon, this.label, {required this.included});
}

/// Per-plan feature access, ported verbatim from `src/config/planConfig.ts`.
///
/// Keyed by the values actually stored in `subscriptions.plan` — `free`, `pro`,
/// `builder`, `enterprise` — because the Features tab has to describe the plan
/// the account is really on.
///
/// Note this is a different taxonomy from the Upgrade screen's ladder
/// ([PlanCatalogue]: free / plus / pro / concierge at ₹0/9/19/49), which comes
/// from the approved design. The two disagree, and neither is derivable from
/// the other; the mismatch is inherited from the source material, not
/// introduced here. Flagged for a product decision.
///
/// The icons are the design's `featureAccessList` glyphs. React's config has no
/// per-feature icon, so they are assigned by position, which is exactly what
/// the design does.
class PlanFeatures {
  PlanFeatures._();

  static const List<FeatureAccess> _free = [
    FeatureAccess(
      Icons.apartment_rounded,
      '5 active property listings',
      included: true,
    ),
    FeatureAccess(
      Icons.visibility_outlined,
      'Track property views and basic enquiries',
      included: true,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      'Standard email support (48hr response)',
      included: true,
    ),
    FeatureAccess(
      Icons.phone_iphone,
      'Mobile app access for on-the-go management',
      included: true,
    ),
    FeatureAccess(
      Icons.track_changes,
      'Priority placement across premium property searches',
      included: false,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Generate SEO-optimized property descriptions using AI',
      included: false,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      'Priority builder support channel',
      included: false,
    ),
    FeatureAccess(
      Icons.verified_user_outlined,
      'Verified builder badge for credibility',
      included: false,
    ),
    FeatureAccess(
      Icons.trending_up_rounded,
      'Advanced conversion and sales performance insights',
      included: false,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Custom branding & white-label solution',
      included: false,
    ),
  ];

  static const List<FeatureAccess> _pro = [
    FeatureAccess(
      Icons.apartment_rounded,
      '50 active property listings',
      included: true,
    ),
    FeatureAccess(
      Icons.visibility_outlined,
      'Track property views, enquiries, conversions and sales performance',
      included: true,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      'Priority email support (24hr response time)',
      included: true,
    ),
    FeatureAccess(
      Icons.phone_iphone,
      'Mobile app access for on-the-go management',
      included: true,
    ),
    FeatureAccess(
      Icons.track_changes,
      'Priority placement across premium property searches (5/month)',
      included: true,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Generate SEO-optimized property descriptions using AI',
      included: true,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      '24/7 dedicated builder support channel',
      included: false,
    ),
    FeatureAccess(
      Icons.verified_user_outlined,
      'Verified builder badge for credibility',
      included: false,
    ),
    FeatureAccess(
      Icons.trending_up_rounded,
      'Custom branding & white-label solution',
      included: false,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'API access for custom integrations',
      included: false,
    ),
  ];

  static const List<FeatureAccess> _builder = [
    FeatureAccess(
      Icons.apartment_rounded,
      'Unlimited active property listings',
      included: true,
    ),
    FeatureAccess(
      Icons.visibility_outlined,
      'Advanced analytics dashboard with lead insights',
      included: true,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      '24/7 priority builder support with dedicated account manager',
      included: true,
    ),
    FeatureAccess(
      Icons.phone_iphone,
      'Mobile app access for on-the-go management',
      included: true,
    ),
    FeatureAccess(
      Icons.track_changes,
      'Unlimited priority placement across premium property searches',
      included: true,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Generate SEO-optimized property descriptions using AI',
      included: true,
    ),
    FeatureAccess(
      Icons.verified_user_outlined,
      'Verified builder badge for credibility',
      included: true,
    ),
    FeatureAccess(
      Icons.trending_up_rounded,
      'Custom branding & white-label solution',
      included: true,
    ),
    FeatureAccess(
      Icons.groups_outlined,
      'Team collaboration tools for agencies',
      included: true,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'API access for custom integrations',
      included: true,
    ),
  ];

  static const List<FeatureAccess> _enterprise = [
    FeatureAccess(
      Icons.apartment_rounded,
      'Unlimited active property listings, users, and features',
      included: true,
    ),
    FeatureAccess(
      Icons.visibility_outlined,
      'Custom enterprise analytics dashboard with real-time insights',
      included: true,
    ),
    FeatureAccess(
      Icons.headset_mic_outlined,
      'Dedicated account manager & 24/7 priority support',
      included: true,
    ),
    FeatureAccess(
      Icons.phone_iphone,
      'White-label solution with custom domain and branding',
      included: true,
    ),
    FeatureAccess(
      Icons.track_changes,
      'Unlimited priority placement across premium property searches',
      included: true,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Generate SEO-optimized property descriptions using AI',
      included: true,
    ),
    FeatureAccess(
      Icons.verified_user_outlined,
      'Verified enterprise builder badge for credibility',
      included: true,
    ),
    FeatureAccess(
      Icons.trending_up_rounded,
      'Custom branding & white-label solution',
      included: true,
    ),
    FeatureAccess(
      Icons.security_outlined,
      'SSO, advanced security & compliance certifications',
      included: true,
    ),
    FeatureAccess(
      Icons.article_outlined,
      'Custom integrations & API access with dedicated support',
      included: true,
    ),
  ];

  /// The feature list for a stored plan id. Unknown ids fall back to free,
  /// which is the conservative reading — it never over-promises access.
  static List<FeatureAccess> forPlan(String plan) {
    switch (plan.toLowerCase()) {
      case 'pro':
        return _pro;
      case 'builder':
        return _builder;
      case 'enterprise':
        return _enterprise;
      default:
        return _free;
    }
  }

  static int includedCount(String plan) =>
      forPlan(plan).where((f) => f.included).length;

  static int totalCount(String plan) => forPlan(plan).length;

  static int lockedCount(String plan) => totalCount(plan) - includedCount(plan);
}
