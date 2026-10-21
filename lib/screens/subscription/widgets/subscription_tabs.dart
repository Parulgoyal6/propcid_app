import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/subscription_summary.dart';
import '../../../widgets/shared/app_action_button.dart';
import '../../../widgets/shared/app_surface_card.dart';
import '../plan_features.dart';
import 'plan_usage_donut.dart';
import 'subscription_primitives.dart';

/// Formats a rupee amount the way the design does — `₹0`, `₹1,999`.
String formatRupees(num amount) {
  final whole = amount.round().abs();
  final digits = whole.toString();

  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final lastThree = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final pairs = <String>[];
    while (rest.length > 2) {
      pairs.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) pairs.insert(0, rest);
    grouped = '${pairs.join(',')},$lastThree';
  }

  return '${amount < 0 ? '-' : ''}₹$grouped';
}

/// Everything the tabs need, so each one is a pure function of its inputs and
/// testable without a provider.
class SubscriptionTabData {
  final SubscriptionSummary subscription;
  final BillingProfile? billingProfile;
  final List<BillingHistoryItem> payments;
  final List<BillingHistoryItem> refunds;
  final double totalBilled;
  final bool historyFailed;
  final bool subscriptionFailed;

  const SubscriptionTabData({
    required this.subscription,
    required this.payments,
    required this.refunds,
    required this.totalBilled,
    required this.historyFailed,
    required this.subscriptionFailed,
    this.billingProfile,
  });

  String get plan => subscription.plan;

  /// The monthly price actually on record: the most recent completed payment.
  ///
  /// Free is genuinely ₹0. For a paid plan there is no price column on
  /// `subscriptions`, and the two plan catalogues disagree on price, so the
  /// amount the user was really charged is the only trustworthy source. Falls
  /// back to an em dash rather than guessing.
  String get priceLabel {
    if (subscriptionFailed) return '—';
    if (subscription.isFree) return '₹0';
    if (payments.isNotEmpty) {
      return formatRupees(payments.first.finalAmount ?? payments.first.amount);
    }
    return '—';
  }
}

/// Tab 1 — Overview.
class OverviewTab extends StatelessWidget {
  final SubscriptionTabData data;

  const OverviewTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final plan = data.plan;
    final included = PlanFeatures.includedCount(plan);
    final total = PlanFeatures.totalCount(plan);
    final locked = PlanFeatures.lockedCount(plan);
    final sub = data.subscription;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.spacingL),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SubKpiCard.delegate,
          children: [
            SubKpiCard(
              icon: Icons.person_outline,
              label: 'Current Plan',
              value: data.subscriptionFailed
                  ? '—'
                  : sub.planLabel.replaceAll(' Plan', ''),
              sub: data.subscriptionFailed
                  ? 'Unavailable'
                  : '${sub.status} • ${sub.billingCycle}',
            ),
            SubKpiCard(
              icon: Icons.currency_rupee,
              label: 'Monthly Price',
              value: data.priceLabel,
              sub: 'Billed ${sub.billingCycle}',
            ),
            SubKpiCard(
              icon: Icons.check_circle_outline,
              label: 'Available Features',
              value: '$included',
              sub: 'of $total total',
            ),
            SubKpiCard(
              icon: Icons.lock_outline,
              label: 'Premium Features',
              value: '$locked',
              sub: locked == 0
                  ? 'All features unlocked'
                  : 'Locked • Upgrade to unlock',
            ),
          ],
        ),
        const SizedBox(height: 14),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SubCardHeader('Billing History', 'Payments over time'),
              const SizedBox(height: AppConstants.spacingL),
              if (data.historyFailed)
                const BillingEmptyState(
                  icon: Icons.error_outline,
                  message: "Couldn't load your billing history.",
                )
              else if (data.payments.isEmpty)
                const BillingEmptyState(
                  icon: Icons.schedule,
                  message:
                      'No payments yet. Your billing history will appear here.',
                )
              else
                _PaymentList(items: data.payments),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SubCardHeader(
                'Plan Usage',
                'Features unlocked on your plan',
              ),
              const SizedBox(height: 14),
              Center(
                child: PlanUsageDonut(unlocked: included, total: total),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tab 2 — Billing.
class BillingTab extends StatelessWidget {
  final SubscriptionTabData data;
  final VoidCallback onUpgrade;
  final VoidCallback onCancel;

  /// Undoes a pending cancellation. Shares the cancel button's slot rather than
  /// adding a fifth control: a subscription is either running or already set to
  /// end, so only one of the two actions is ever available.
  final VoidCallback onResume;
  final VoidCallback onSaveDetails;

  const BillingTab({
    super.key,
    required this.data,
    required this.onUpgrade,
    required this.onCancel,
    required this.onResume,
    required this.onSaveDetails,
  });

  @override
  Widget build(BuildContext context) {
    final sub = data.subscription;
    final profile = data.billingProfile;
    final renewal = sub.renewalLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SubSectionTitle(
          'Billing Information',
          'Manage your billing cycle and renewal settings',
        ),
        const SizedBox(height: 14),
        BillingInfoRow(
          label: 'Current Plan',
          value: data.subscriptionFailed
              ? '—'
              : sub.planLabel.replaceAll(' Plan', ''),
          chip: _capitalise(sub.billingCycle),
        ),
        const SizedBox(height: 10),
        BillingInfoRow(
          label: 'Monthly Price',
          value: data.priceLabel,
          chip: 'per ${sub.billingCycle == 'yearly' ? 'year' : 'month'}',
        ),
        const SizedBox(height: 10),
        BillingInfoRow(
          label: 'Renewal Date',
          // No expiry recorded means nothing renews — the design's "N/A".
          value: renewal ?? 'N/A',
          chip: _daysUntil(sub.expiresAt),
        ),
        const SizedBox(height: 10),
        BillingInfoRow(
          label: 'Auto Renewal',
          value: sub.autoRenew ? 'Enabled' : 'Disabled',
          chip: sub.autoRenew ? 'Active' : 'Inactive',
        ),
        const SizedBox(height: AppConstants.spacingL),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                label: 'Upgrade Plan',
                icon: Icons.add,
                onTap: onUpgrade,
              ),
            ),
            const SizedBox(width: 10),
            // Already cancelling at period end → the only useful action left is
            // to undo it. `CancelSubscriptionModal` / `ResumeSubscriptionModal`
            // are the portal's equivalent pair, switched on the same flag.
            Expanded(
              child: sub.cancelAtPeriodEnd
                  ? AppActionButton(
                      label: 'Resume Subscription',
                      variant: AppActionButtonVariant.outline,
                      onTap: onResume,
                    )
                  : AppActionButton(
                      label: 'Cancel Subscription',
                      variant: AppActionButtonVariant.danger,
                      onTap: onCancel,
                    ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      size: 19,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: SubCardHeader(
                      'Billing Details',
                      'Used on your invoices — company name, GSTIN, and address',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ReadOnlyField(
                label: 'Company Name',
                value: profile?.companyName,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'GSTIN',
                value: profile?.gstNumber,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'Address',
                value: profile?.address,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'City',
                value: profile?.city,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'State',
                value: profile?.state,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'Postal Code',
                value: profile?.postalCode,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'Country',
                value: profile?.country,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'Phone',
                value: profile?.phone,
                placeholder: 'Not set',
              ),
              const SizedBox(height: 10),
              ReadOnlyField(
                label: 'Billing Email',
                value: profile?.email,
                placeholder: 'Not set',
              ),
              const SizedBox(height: AppConstants.spacingL),
              AppActionButton(
                label: 'Edit Billing Details',
                height: 44,
                onTap: onSaveDetails,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  /// "30 days" — how long until the period ends. Null-safe: no expiry means no
  /// countdown to show.
  static String? _daysUntil(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final days = expiresAt.difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired';
    return '$days days';
  }
}

/// Tab 3 — Payments.
class PaymentsTab extends StatelessWidget {
  final SubscriptionTabData data;

  const PaymentsTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.spacingL),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SubCardHeader(
                'Recent Payments',
                'Your most recent billing transactions',
              ),
              const SizedBox(height: AppConstants.spacingXL),
              if (data.historyFailed)
                const BillingEmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load payments.",
                  message: 'Pull to refresh or try again in a moment.',
                )
              else if (data.payments.isEmpty)
                const BillingEmptyState(
                  icon: Icons.description_outlined,
                  title: 'No transactions available.',
                  message:
                      'Upgrade to a paid plan to view invoices and payment '
                      'history.',
                )
              else
                _PaymentList(items: data.payments),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tab 4 — Features.
class FeaturesTab extends StatelessWidget {
  final SubscriptionTabData data;
  final VoidCallback onUpgrade;

  const FeaturesTab({super.key, required this.data, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    final features = PlanFeatures.forPlan(data.plan);
    final allUnlocked = PlanFeatures.lockedCount(data.plan) == 0;
    final planName = data.subscription.planLabel.replaceAll(' Plan', '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        SubSectionTitle(
          'Feature Access',
          'Everything included in your $planName plan',
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < features.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _FeatureAccessRow(feature: features[i]),
        ],
        if (!allUnlocked) ...[
          const SizedBox(height: 18),
          AppActionButton(
            label: 'Upgrade to Unlock All Features',
            trailingIcon: Icons.chevron_right,
            onTap: onUpgrade,
          ),
        ],
      ],
    );
  }
}

class _FeatureAccessRow extends StatelessWidget {
  final FeatureAccess feature;

  const _FeatureAccessRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    final included = feature.included;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: included ? AppColors.primaryLight : AppColors.hairlineStrong,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: included ? AppColors.primaryLight : AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              feature.icon,
              size: 18,
              color: included ? AppColors.primary : AppColors.textHint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              feature.label,
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: included ? AppColors.textPrimary : AppColors.textHint,
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          Icon(
            included ? Icons.check : Icons.lock_outline,
            size: 16,
            color: included ? AppColors.success : AppColors.textHint,
          ),
        ],
      ),
    );
  }
}

/// Tab 5 — Invoices.
class InvoicesTab extends StatelessWidget {
  final SubscriptionTabData data;
  final ValueChanged<BillingHistoryItem> onDownload;

  const InvoicesTab({super.key, required this.data, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final invoiced = data.payments
        .where((i) => i.invoiceNumber != null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.spacingL),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SubCardHeader(
                'Invoices',
                'Download your invoices and receipts',
              ),
              const SizedBox(height: AppConstants.spacingXL),
              if (data.historyFailed)
                const BillingEmptyState(
                  icon: Icons.error_outline,
                  title: "Couldn't load invoices.",
                  message: 'Pull to refresh or try again in a moment.',
                )
              else if (invoiced.isEmpty)
                const BillingEmptyState(
                  icon: Icons.currency_rupee,
                  title: 'No invoices yet.',
                  message:
                      'Invoices will appear after your first successful '
                      'payment.',
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < invoiced.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _InvoiceRow(
                        item: invoiced[i],
                        onDownload: () => onDownload(invoiced[i]),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tab 6 — Usage.
class UsageTab extends StatelessWidget {
  final SubscriptionTabData data;

  const UsageTab({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final plan = data.plan;
    final included = PlanFeatures.includedCount(plan);
    final total = PlanFeatures.totalCount(plan);
    final planName = data.subscription.planLabel.replaceAll(' Plan', '');

    // The listing allowance is stated by the plan's first feature line, which
    // is where React sources it too — there is no usage table to count against.
    final listingFeature = PlanFeatures.forPlan(plan).first.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SubSectionTitle(
          'Usage Analytics',
          'Track your subscription usage and limits',
        ),
        const SizedBox(height: 14),
        _UsageCard(
          icon: Icons.apartment_rounded,
          label: 'Listings',
          value: 'Included',
          sub: listingFeature,
        ),
        const SizedBox(height: 10),
        _UsageCard(
          icon: Icons.person_outline,
          label: 'Plan Features',
          value: '$included/$total',
          sub: 'Unlocked on $planName',
        ),
        const SizedBox(height: 10),
        _UsageCard(
          icon: Icons.article_outlined,
          label: 'AI Features',
          value:
              PlanFeatures.forPlan(
                plan,
              ).any((f) => f.included && f.label.contains('AI'))
              ? 'Included'
              : 'Not included',
          sub: 'Based on your plan',
        ),
        const SizedBox(height: 14),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SubCardHeader(
                'Monthly Spending',
                'Total amount billed per month',
              ),
              const SizedBox(height: AppConstants.spacingL),
              if (data.historyFailed || data.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      data.historyFailed
                          ? "Couldn't load spending data."
                          : 'No spending data yet.',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                )
              else
                BillingInfoRow(
                  label: 'Total billed to date',
                  value: formatRupees(data.totalBilled),
                  chip: '${data.payments.length} payments',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;

  const _UsageCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading2.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10.5,
                    color: AppColors.textHint,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab 7 — Security.
class SecurityTab extends StatelessWidget {
  final SubscriptionTabData data;
  final VoidCallback onUpgrade;
  final VoidCallback onComparePlans;
  final VoidCallback onPolicies;
  final VoidCallback onContactSupport;
  final VoidCallback onManagePaymentMethod;

  const SecurityTab({
    super.key,
    required this.data,
    required this.onUpgrade,
    required this.onComparePlans,
    required this.onPolicies,
    required this.onContactSupport,
    required this.onManagePaymentMethod,
  });

  @override
  Widget build(BuildContext context) {
    final autoRenew = data.subscription.autoRenew;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SubSectionTitle(
          'Security Settings',
          'Manage your subscription security and payment methods',
        ),
        const SizedBox(height: 14),
        _SecurityRow(
          icon: Icons.refresh,
          tint: AppColors.success,
          chipBg: const Color(0xFFE7F8ED),
          label: 'Auto Renewal',
          sub: 'Automatic subscription renewal',
          badge: autoRenew ? 'Enabled' : 'Disabled',
        ),
        const SizedBox(height: 10),
        _SecurityRow(
          icon: Icons.credit_card_outlined,
          tint: AppColors.primary,
          chipBg: AppColors.primaryLight,
          label: 'Payment Method',
          sub: 'Razorpay Secure Payments',
          link: 'Manage',
          onLink: onManagePaymentMethod,
        ),
        const SizedBox(height: 10),
        const _SecurityRow(
          icon: Icons.verified_user_outlined,
          tint: AppColors.amenityBlue,
          chipBg: Color(0xFFE8F1FE),
          label: 'Billing Security',
          sub: 'End-to-end encrypted transactions',
          badge: 'Secure',
        ),
        const SizedBox(height: AppConstants.spacingXL),
        Text(
          'Quick Actions',
          style: AppTextStyles.body.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 48,
          ),
          children: [
            _QuickAction(
              icon: Icons.trending_up_rounded,
              label: 'Upgrade Plan',
              onTap: onUpgrade,
            ),
            _QuickAction(
              icon: Icons.bar_chart_rounded,
              label: 'Compare Plans',
              onTap: onComparePlans,
            ),
            _QuickAction(
              icon: Icons.article_outlined,
              label: 'Billing Policies',
              onTap: onPolicies,
            ),
            _QuickAction(
              icon: Icons.headset_mic_outlined,
              label: 'Contact Support',
              onTap: onContactSupport,
            ),
          ],
        ),
      ],
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color chipBg;
  final String label;
  final String sub;
  final String? badge;
  final String? link;
  final VoidCallback? onLink;

  const _SecurityRow({
    required this.icon,
    required this.tint,
    required this.chipBg,
    required this.label,
    required this.sub,
    this.badge,
    this.link,
    this.onLink,
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
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: AppConstants.spacingS),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              ),
              child: Text(
                badge!,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (link != null) ...[
            const SizedBox(width: AppConstants.spacingS),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLink,
              child: Text(
                link!,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(color: AppColors.primaryLight),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab 8 — Refunds.
class RefundsTab extends StatelessWidget {
  final SubscriptionTabData data;
  final VoidCallback onViewPlans;

  const RefundsTab({super.key, required this.data, required this.onViewPlans});

  @override
  Widget build(BuildContext context) {
    final refunds = data.refunds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.spacingL),
        DashboardCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          child: refunds.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.currency_rupee,
                        size: 21,
                        color: AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No Refund Requests',
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Refund requests are only available for paid '
                      'subscriptions. Upgrade to a paid plan to access refund '
                      'options.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingL),
                    AppActionButton(
                      label: 'View Pricing Plans',
                      height: 44,
                      trailingIcon: Icons.chevron_right,
                      onTap: onViewPlans,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SubCardHeader(
                      'Refunds',
                      'Requests raised against your payments',
                    ),
                    const SizedBox(height: AppConstants.spacingL),
                    for (var i = 0; i < refunds.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      BillingInfoRow(
                        label:
                            refunds[i].invoiceNumber ??
                            refunds[i].transactionId,
                        value: formatRupees(
                          refunds[i].refundAmount ?? refunds[i].amount,
                        ),
                        chip: refunds[i].refundStatus,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Tab 9 — Help & Support.
class HelpTab extends StatelessWidget {
  final VoidCallback onPolicies;
  final VoidCallback onContactSupport;
  final VoidCallback onRaiseTicket;

  const HelpTab({
    super.key,
    required this.onPolicies,
    required this.onContactSupport,
    required this.onRaiseTicket,
  });

  static const List<String> _trustPoints = [
    'Secure Payments',
    'No Hidden Charges',
    'Cancel Anytime',
    'Continue Access Until Billing Ends',
    'Billing History Available',
    'Transparent Pricing',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SubSectionTitle(
          'Help & Support',
          'Get help with your subscription and billing',
        ),
        const SizedBox(height: 14),
        _HelpRow(
          icon: Icons.error_outline,
          tint: AppColors.primary,
          label: 'FAQs',
          sub: 'Frequently asked questions',
          onTap: onPolicies,
        ),
        const SizedBox(height: 10),
        _HelpRow(
          icon: Icons.article_outlined,
          tint: AppColors.primary,
          label: 'Billing Policies',
          sub: 'Payments, cancellations & refunds',
          onTap: onPolicies,
        ),
        const SizedBox(height: 10),
        _HelpRow(
          icon: Icons.headset_mic_outlined,
          tint: AppColors.success,
          label: 'Contact Support',
          sub: 'Get help from our team',
          onTap: onContactSupport,
        ),
        const SizedBox(height: 10),
        _HelpRow(
          icon: Icons.error_outline,
          tint: AppColors.primary,
          label: 'Raise a Ticket',
          sub: 'Submit a support request',
          onTap: onRaiseTicket,
        ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Trusted & Transparent Billing',
                          style: AppTextStyles.heading3.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'We believe in complete transparency with no hidden '
                          'charges or surprises.',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  mainAxisExtent: 34,
                ),
                children: [
                  for (final point in _trustPoints)
                    Row(
                      children: [
                        const Icon(
                          Icons.check,
                          size: 14,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            point,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelpRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _HelpRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared payment list used by Overview and Payments.
class _PaymentList extends StatelessWidget {
  final List<BillingHistoryItem> items;

  const _PaymentList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          BillingInfoRow(
            label: items[i].invoiceNumber ?? items[i].plan,
            value: formatRupees(items[i].finalAmount ?? items[i].amount),
            chip: items[i].hasRefund
                ? items[i].refundStatus
                : items[i].paymentStatus,
          ),
        ],
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final BillingHistoryItem item;
  final VoidCallback onDownload;

  const _InvoiceRow({required this.item, required this.onDownload});

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
                  item.invoiceNumber ?? 'Invoice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatRupees(item.finalAmount ?? item.amount),
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          Semantics(
            label: 'Download invoice',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDownload,
              child: const Icon(
                Icons.download_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
