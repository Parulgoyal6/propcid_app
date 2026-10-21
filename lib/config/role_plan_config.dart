// config/role_plan_config.dart
//
// Role-based plan catalogue, mirroring the web portal 1:1.
//
// SOURCES OF TRUTH
// ----------------
//   * display copy, names, features, CTAs → `src/config/planConfig.ts`
//     (`ROLE_PLANS_CONFIG`)
//   * the prices below                    → `supabase/functions/_shared/planPricing.ts`
//     (`ROLE_PLAN_PRICING`), which is the table `create-order` charges from and
//     `manage-subscription` validates downgrades against.
//
// Both are read-only reference. If pricing changes it changes there first; this file
// follows.
//
// THE YEARLY PRICE IS A FLAT ANNUAL CHARGE
// ----------------------------------------
// [PlanDefinition.yearlyPrice] is the whole annual amount, **not** a monthly
// equivalent to be multiplied by twelve. Owner Plus is `monthly: 9, yearly: 7`, and
// the yearly option charges and displays **₹7/year**.
//
// `planPricing.ts` says so in as many words — "yearly is not 12x monthly … the
// existing frontend already charges the yearlyPrice figure directly as the annual
// amount" — and the server recomputes from that same table, so any other
// interpretation here would disagree with what the account is actually billed.
//
// This deliberately differs from `plan_catalogue.dart`, which modelled yearly as a
// discounted per-month rate plus a `yearlyTotal` (₹7/month → ₹84/year). That model
// does not match the deployed charge table. `PlanCatalogue` is left in place
// untouched for any screen still referencing it.
//
// NO AMOUNT IS EVER SENT TO THE SERVER
// ------------------------------------
// These figures are for display only. `create-order` receives `planId`,
// `billingCycle`, `currency` and an idempotency key, and resolves the charge itself
// from the caller's own `profiles.user_type` (`resolvePriceInr`). A client that sent
// an amount could understate it; one that computed a different figure would simply
// be showing the user the wrong number.
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The four canonical plan ids.
///
/// The wire values must match `planPricing.ts`'s `PlanId` union exactly — they are
/// the keys `create-order` and `manage-subscription` look the price up by, and an
/// unrecognised id is rejected by `isValidPlanId`.
///
/// Note the ids are role-independent while the *display names* are not: a broker's
/// `pro` is "Broker Pro" and an individual's is "Owner Plus", but both send `pro`.
enum PlanId {
  free,
  pro,
  builder,
  enterprise;

  /// The value put on the wire.
  String get wire => name;

  /// Tier order, matching `PLAN_TIER` — free 0 … enterprise 3.
  ///
  /// Used to tell an upgrade from a downgrade, the same comparison
  /// `manage-subscription` makes server-side.
  int get tier => index;

  /// Parses a stored plan value, e.g. `subscriptions.plan`.
  ///
  /// Falls back to [PlanId.free] for anything unrecognised, which is how
  /// `SubscriptionSummary` already treats a missing row.
  static PlanId fromWire(String? value) {
    final match = value?.trim().toLowerCase();
    for (final id in PlanId.values) {
      if (id.wire == match) return id;
    }
    return PlanId.free;
  }
}

/// The four roles that have their own plan ladder.
///
/// `planPricing.ts`'s `Role` union. Anything else — an admin, an unset
/// `user_type` — falls back to [individual], mirroring `getPlansForRole`'s own
/// fallback.
enum UserRole {
  individual,
  broker,
  builder,
  influencer;

  String get wire => name;

  static UserRole? fromWire(String? value) {
    final match = value?.trim().toLowerCase();
    for (final role in UserRole.values) {
      if (role.wire == match) return role;
    }
    return null;
  }
}

/// One feature line on a plan card.
///
/// `included: false` renders struck-through/greyed, which is how the portal shows a
/// feature the tier does *not* carry — those lines are part of the sell, so they are
/// listed rather than omitted.
class PlanFeatureLine {
  const PlanFeatureLine(this.label, {this.included = true});

  final String label;
  final bool included;
}

/// One plan, for one role.
class PlanDefinition {
  const PlanDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.features,
    required this.cta,
    this.tint = AppColors.primary,
    this.tintBackground = AppColors.primaryLight,
    this.badge,
    this.badgeColor,
  });

  /// What goes on the wire. Shared across roles.
  final PlanId id;

  /// Role-specific display name — "Owner Plus", "Broker Pro", "Launch", "Creator".
  final String name;

  final String description;
  final IconData icon;

  /// Icon tint and its 38 dp tile background, matching the card design.
  final Color tint;
  final Color tintBackground;

  /// Rupees per month on monthly billing.
  final int monthlyPrice;

  /// The **whole annual charge** on yearly billing. Not `monthlyPrice * 12`, and
  /// not a per-month equivalent. See this file's header.
  final int yearlyPrice;

  final List<PlanFeatureLine> features;

  /// Role-specific button copy — "Choose Owner Plus", "Start Pro Trial", …
  final String cta;

  /// Floating pill above the card. The portal sets `popular: true` on the `pro`
  /// tier only, which is where "Most Popular" comes from.
  final String? badge;
  final Color? badgeColor;

  /// True for the free tier, which has no checkout.
  bool get isFree => id == PlanId.free;

  /// The figure to display for [yearly], and the figure the server will charge.
  int priceFor({required bool yearly}) => yearly ? yearlyPrice : monthlyPrice;
}

// ── Shared visual identity ──────────────────────────────────────────────────
//
// The portal maps one icon per tier (`User`, `Briefcase`, `Building2`, `Crown`) and
// keeps it across roles, so a `pro` plan looks like a `pro` plan whoever is looking.
// Same here, with the app's own icon set.

const _freeTint = AppColors.success;
const _freeTintBackground = Color(0xFFE7F8ED);
const _popularBadge = 'Most Popular';
const _popularBadgeColor = Color(0xFFF59E0B);

const IconData _iconFree = Icons.person_outline;
const IconData _iconPro = Icons.work_outline;
const IconData _iconBuilder = Icons.apartment_rounded;
const IconData _iconEnterprise = Icons.workspace_premium_outlined;

// ── individual (ROLE_PLANS_CONFIG.individual) ───────────────────────────────

const List<PlanDefinition> _individualPlans = [
  PlanDefinition(
    id: PlanId.free,
    name: 'Free',
    description: 'For individual owners & seekers',
    icon: _iconFree,
    tint: _freeTint,
    tintBackground: _freeTintBackground,
    monthlyPrice: 0,
    yearlyPrice: 0,
    cta: 'Get Started Free',
    features: [
      PlanFeatureLine('2 active property listings'),
      PlanFeatureLine('Save searches & favourites'),
      PlanFeatureLine('Basic enquiry alerts'),
      PlanFeatureLine('Mobile app access'),
      PlanFeatureLine('Featured listing placement', included: false),
      PlanFeatureLine('Dedicated relationship manager', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.pro,
    name: 'Owner Plus',
    description: 'List and sell your property faster',
    icon: _iconPro,
    monthlyPrice: 9,
    yearlyPrice: 7,
    cta: 'Choose Owner Plus',
    badge: _popularBadge,
    badgeColor: _popularBadgeColor,
    features: [
      PlanFeatureLine('10 active property listings'),
      PlanFeatureLine('Priority enquiry alerts'),
      PlanFeatureLine('1 featured listing / month'),
      PlanFeatureLine('Listing view analytics'),
      PlanFeatureLine('AI-written property descriptions'),
      PlanFeatureLine('Dedicated relationship manager', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.builder,
    name: 'Owner Pro',
    description: 'For sellers with multiple properties',
    icon: _iconBuilder,
    monthlyPrice: 19,
    yearlyPrice: 15,
    cta: 'Choose Owner Pro',
    features: [
      PlanFeatureLine('25 active property listings'),
      PlanFeatureLine('5 featured listings / month'),
      PlanFeatureLine('Advanced view & enquiry analytics'),
      PlanFeatureLine('AI-written property descriptions'),
      PlanFeatureLine('Verified owner badge'),
      PlanFeatureLine('Priority support'),
    ],
  ),
  PlanDefinition(
    id: PlanId.enterprise,
    name: 'Concierge',
    description: 'White-glove selling assistance',
    icon: _iconEnterprise,
    monthlyPrice: 49,
    yearlyPrice: 39,
    cta: 'Contact Us',
    features: [
      PlanFeatureLine('Unlimited property listings'),
      PlanFeatureLine('Unlimited featured placement'),
      PlanFeatureLine('Personal relationship manager'),
      PlanFeatureLine('End-to-end selling assistance'),
      PlanFeatureLine('Verified owner badge'),
      PlanFeatureLine('24/7 priority support'),
    ],
  ),
];

// ── broker (ROLE_PLANS_CONFIG.broker) ───────────────────────────────────────

const List<PlanDefinition> _brokerPlans = [
  PlanDefinition(
    id: PlanId.free,
    name: 'Free',
    description: 'For solo brokers getting started',
    icon: _iconFree,
    tint: _freeTint,
    tintBackground: _freeTintBackground,
    monthlyPrice: 0,
    yearlyPrice: 0,
    cta: 'Get Started Free',
    features: [
      PlanFeatureLine('5 active listings'),
      PlanFeatureLine('Basic lead capture'),
      PlanFeatureLine('Enquiry tracking'),
      PlanFeatureLine('Mobile app access'),
      PlanFeatureLine('Client CRM', included: false),
      PlanFeatureLine('Team members', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.pro,
    name: 'Broker Pro',
    description: 'For growing real estate brokers',
    icon: _iconPro,
    monthlyPrice: 29,
    yearlyPrice: 23,
    cta: 'Start Pro Trial',
    badge: _popularBadge,
    badgeColor: _popularBadgeColor,
    features: [
      PlanFeatureLine('50 active listings'),
      PlanFeatureLine('Lead management & follow-ups'),
      PlanFeatureLine('Featured placement (5/month)'),
      PlanFeatureLine('Client enquiry CRM'),
      PlanFeatureLine('AI property descriptions'),
      PlanFeatureLine('Team members', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.builder,
    name: 'Broker Growth',
    description: 'For high-volume brokers & small teams',
    icon: _iconBuilder,
    monthlyPrice: 99,
    yearlyPrice: 79,
    cta: 'Upgrade to Growth',
    features: [
      PlanFeatureLine('Unlimited listings'),
      PlanFeatureLine('Full CRM with site-visit tracking'),
      PlanFeatureLine('Team collaboration (up to 10)'),
      PlanFeatureLine('Unlimited featured placement'),
      PlanFeatureLine('Verified broker badge'),
      PlanFeatureLine('Priority support'),
    ],
  ),
  PlanDefinition(
    id: PlanId.enterprise,
    name: 'Brokerage',
    description: 'For established brokerage firms',
    icon: _iconEnterprise,
    monthlyPrice: 199,
    yearlyPrice: 159,
    cta: 'Contact Sales',
    features: [
      PlanFeatureLine('Unlimited listings & agents'),
      PlanFeatureLine('White-label brokerage portal'),
      PlanFeatureLine('Dedicated account manager'),
      PlanFeatureLine('API & CRM integrations'),
      PlanFeatureLine('Advanced performance analytics'),
      PlanFeatureLine('24/7 priority support'),
    ],
  ),
];

// ── builder (ROLE_PLANS_CONFIG.builder) ─────────────────────────────────────

const List<PlanDefinition> _builderPlans = [
  PlanDefinition(
    id: PlanId.free,
    name: 'Free',
    description: 'For developers listing a first project',
    icon: _iconFree,
    tint: _freeTint,
    tintBackground: _freeTintBackground,
    monthlyPrice: 0,
    yearlyPrice: 0,
    cta: 'Get Started Free',
    features: [
      PlanFeatureLine('1 active project'),
      PlanFeatureLine('Up to 10 unit listings'),
      PlanFeatureLine('Basic lead capture'),
      PlanFeatureLine('Mobile app access'),
      PlanFeatureLine('Project analytics', included: false),
      PlanFeatureLine('Verified builder badge', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.pro,
    name: 'Launch',
    description: 'For active project launches',
    icon: _iconPro,
    monthlyPrice: 49,
    yearlyPrice: 39,
    cta: 'Start Launch',
    badge: _popularBadge,
    badgeColor: _popularBadgeColor,
    features: [
      PlanFeatureLine('5 active projects'),
      PlanFeatureLine('100 unit listings'),
      PlanFeatureLine('Lead management dashboard'),
      PlanFeatureLine('Featured project placement'),
      PlanFeatureLine('AI property descriptions'),
      PlanFeatureLine('Dedicated account manager', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.builder,
    name: 'Scale',
    description: 'For developers & agencies at scale',
    icon: _iconBuilder,
    monthlyPrice: 149,
    yearlyPrice: 119,
    cta: 'Upgrade to Scale',
    features: [
      PlanFeatureLine('Unlimited projects & units'),
      PlanFeatureLine('Advanced sales & lead analytics'),
      PlanFeatureLine('Verified builder badge'),
      PlanFeatureLine('Dedicated account manager'),
      PlanFeatureLine('Team collaboration tools'),
      PlanFeatureLine('Custom branding'),
    ],
  ),
  PlanDefinition(
    id: PlanId.enterprise,
    name: 'Developer Enterprise',
    description: 'For large development houses',
    icon: _iconEnterprise,
    monthlyPrice: 399,
    yearlyPrice: 319,
    cta: 'Contact Sales',
    features: [
      PlanFeatureLine('Unlimited everything'),
      PlanFeatureLine('White-label sales microsites'),
      PlanFeatureLine('Enterprise analytics suite'),
      PlanFeatureLine('API & CRM integrations'),
      PlanFeatureLine('SSO & compliance'),
      PlanFeatureLine('24/7 dedicated support'),
    ],
  ),
];

// ── influencer (ROLE_PLANS_CONFIG.influencer) ───────────────────────────────

const List<PlanDefinition> _influencerPlans = [
  PlanDefinition(
    id: PlanId.free,
    name: 'Free',
    description: 'For creators starting out',
    icon: _iconFree,
    tint: _freeTint,
    tintBackground: _freeTintBackground,
    monthlyPrice: 0,
    yearlyPrice: 0,
    cta: 'Get Started Free',
    features: [
      PlanFeatureLine('Creator profile'),
      PlanFeatureLine('Up to 5 property reels'),
      PlanFeatureLine('Basic reel analytics'),
      PlanFeatureLine('Mobile app access'),
      PlanFeatureLine('Monetization tools', included: false),
      PlanFeatureLine('Priority support', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.pro,
    name: 'Creator',
    description: 'For growing property creators',
    icon: _iconPro,
    monthlyPrice: 19,
    yearlyPrice: 15,
    cta: 'Start Creator',
    badge: _popularBadge,
    badgeColor: _popularBadgeColor,
    features: [
      PlanFeatureLine('30 property reels'),
      PlanFeatureLine('Audience & engagement analytics'),
      PlanFeatureLine('Featured on discovery feed'),
      PlanFeatureLine('Brand collaboration inbox'),
      PlanFeatureLine('AI captions & descriptions'),
      PlanFeatureLine('Payout tools', included: false),
    ],
  ),
  PlanDefinition(
    id: PlanId.builder,
    name: 'Pro Creator',
    description: 'For creators monetizing their audience',
    icon: _iconBuilder,
    monthlyPrice: 59,
    yearlyPrice: 47,
    cta: 'Upgrade to Pro Creator',
    features: [
      PlanFeatureLine('Unlimited reels'),
      PlanFeatureLine('Monetization & payout tools'),
      PlanFeatureLine('Priority discovery placement'),
      PlanFeatureLine('Verified creator badge'),
      PlanFeatureLine('Advanced audience insights'),
      PlanFeatureLine('Priority support'),
    ],
  ),
  PlanDefinition(
    id: PlanId.enterprise,
    name: 'Partner',
    description: 'For top creators & agencies',
    icon: _iconEnterprise,
    monthlyPrice: 149,
    yearlyPrice: 119,
    cta: 'Contact Us',
    features: [
      PlanFeatureLine('Everything in Pro Creator'),
      PlanFeatureLine('Managed brand-deal marketplace'),
      PlanFeatureLine('Dedicated partnerships manager'),
      PlanFeatureLine('Cross-promotion campaigns'),
      PlanFeatureLine('Custom analytics reports'),
      PlanFeatureLine('24/7 priority support'),
    ],
  ),
];

/// The four ladders, keyed by role.
const Map<UserRole, List<PlanDefinition>> kRolePlans = {
  UserRole.individual: _individualPlans,
  UserRole.broker: _brokerPlans,
  UserRole.builder: _builderPlans,
  UserRole.influencer: _influencerPlans,
};

/// The plans to show for a `profiles.user_type`.
///
/// `getPlansForRole` (planConfig.ts:512-518) falls back to the generic
/// `PLANS_CONFIG` for an unknown role. This falls back to the **individual** ladder
/// instead, deliberately: the generic set is priced in a different currency band
/// (`GENERIC_PLAN_PRICING` — pro at 29 rather than 9) and showing it to a user whose
/// role did not resolve would quote a price the server would not charge them.
/// `resolvePriceInr` uses the generic table for an unknown role too, so the two
/// disagree only for a role this app does not recognise at all — and in that case
/// quoting the lowest ladder is the safer error.
///
/// Also used with a null argument while `AuthProvider.userType` is still resolving,
/// which is why null is a supported input rather than an assertion.
List<PlanDefinition> plansForRole(String? userType) {
  final role = UserRole.fromWire(userType);
  return kRolePlans[role] ?? _individualPlans;
}

/// Looks a plan up by id within a role's ladder.
///
/// Returns null when the role's ladder has no such tier, which cannot happen today —
/// every role defines all four — but keeps the caller honest if one ever omits one.
PlanDefinition? planFor(String? userType, PlanId id) {
  for (final plan in plansForRole(userType)) {
    if (plan.id == id) return plan;
  }
  return null;
}
