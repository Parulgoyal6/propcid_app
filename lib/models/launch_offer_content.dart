import 'package:flutter/material.dart';

/// Single source of truth for the "PropCID Pro" launch-offer copy.
///
/// Both [PremiumLaunchBanner] (home screen) and [PremiumLaunchBottomSheet]
/// (session prompt) read from here so the offer's price/benefits/copy never
/// drift out of sync between the two surfaces.
class LaunchOfferContent {
  LaunchOfferContent._();

  static const String badgeLabel = 'Launch Offer';
  static const String title = 'PropCID Pro for Builders & Brokers';
  static const String priceLabel = '₹0/month';

  /// Raw amount for the offer — free during early access.
  static const String amountLabel = '₹0';

  static const String tagline = 'Free During Early Access';
  static const String valueProposition =
      'Get discovered faster and close more deals with PropCID Pro.';

  // ── Presentation-only copy for the V2.1 banner ───────────────────────────
  // Additive: nothing above changed, so PremiumLaunchBottomSheet is unaffected.
  // NOTE: the three marketing claims below (social proof, discount, scarcity)
  // come from the design mockup, not from any backend value — confirm they are
  // accurate before shipping, and edit here rather than in the widget.
  static const String offerChipLabel = 'LIMITED TIME LAUNCH OFFER';
  static const String trustedByCount = '10K+';
  static const String trustedByCaption = 'PROFESSIONALS';
  static const String savingsLabel = 'Save 60%';
  static const String scarcityLead = 'Offer valid for';
  static const String scarcityHighlight = '1000';
  static const String ctaLabel = 'Upgrade to Pro';
  static const List<String> assurances = [
    'Secure Checkout',
    'Cancel Anytime',
    'No Hidden Charges',
  ];

  static const List<LaunchOfferBenefit> benefits = [
    LaunchOfferBenefit(
      'Unlimited Property Listings',
      Icons.all_inclusive_rounded,
    ),
    LaunchOfferBenefit('Verified Business Badge', Icons.verified_rounded),
    LaunchOfferBenefit('Priority Search Visibility', Icons.trending_up_rounded),
    LaunchOfferBenefit('Featured Listings', Icons.star_rounded),
    LaunchOfferBenefit(
      'AI Listing Insights (Coming Soon)',
      Icons.auto_awesome_rounded,
    ),
    LaunchOfferBenefit(
      'Early Access to New Features',
      Icons.rocket_launch_rounded,
    ),
    LaunchOfferBenefit('Premium Customer Support', Icons.support_agent_rounded),
  ];
}

class LaunchOfferBenefit {
  final String label;
  final IconData icon;

  const LaunchOfferBenefit(this.label, this.icon);
}
