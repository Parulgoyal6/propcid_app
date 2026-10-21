import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import '../../models/dashboard_analytics.dart';
import '../../models/network_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_section_provider.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_chart_wrapper.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/stat_kpi_card.dart';
import '../shared/section_loader.dart';
import 'widgets/network_screen_shell.dart';

/// Network ▸ My Referrals — the design's `isMyReferrals` screen.
///
/// Four sub-tabs (Overview / Referrals / Commissions / Performance) over
/// `network_referrals`, `network_commissions` and `network_performance`.
///
/// Read-only: "Create Referral" is a write and opens the shared placeholder.
class MyReferralsScreen extends StatelessWidget {
  const MyReferralsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkReferralsSection(),
      child: const _MyReferralsView(),
    );
  }
}

class _MyReferralsView extends StatefulWidget {
  const _MyReferralsView();

  @override
  State<_MyReferralsView> createState() => _MyReferralsViewState();
}

class _MyReferralsViewState extends State<_MyReferralsView>
    with DeferredSectionLoader<_MyReferralsView> {
  // Branches on `AuthProvider.userType` (builder vs. member column pair) —
  // see `loadSection` below and `DeferredSectionLoader.reloadOnRoleChange`'s
  // own doc for why this must not be cached against a role read too early.
  @override
  bool get reloadOnRoleChange => true;

  @override
  void loadSection(String userId) {
    final isBuilder =
        context.read<AuthProvider>().userType?.toLowerCase() == 'builder';
    context.read<NetworkReferralsSection>().loadFor(
      userId,
      isBuilder: isBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<NetworkReferralsSection>();

    return MyReferralsBody(
      bundle: section.value,
      loading: section.loading,
      failed: section.failed,
      onCreateReferral: () =>
          openSectionPlaceholder(context, 'Create Referral'),
    );
  }
}

class MyReferralsBody extends StatefulWidget {
  final ReferralBundle bundle;
  final bool loading;
  final bool failed;
  final VoidCallback onCreateReferral;

  const MyReferralsBody({
    super.key,
    required this.bundle,
    required this.loading,
    required this.failed,
    required this.onCreateReferral,
  });

  @override
  State<MyReferralsBody> createState() => _MyReferralsBodyState();
}

class _MyReferralsBodyState extends State<MyReferralsBody> {
  int _tab = 0;

  static const List<String> _tabs = [
    'Overview',
    'Referrals',
    'Commissions',
    'Performance',
  ];

  @override
  Widget build(BuildContext context) {
    return NetworkScreenShell(
      title: 'My Referrals',
      subtitle: 'Track referrals and commissions',
      children: [
        const SizedBox(height: 18),
        NetworkIntroBanner(
          title: 'Referral & Commission System',
          description:
              'Track referrals, manage commissions, and reward your network',
          action: AppActionButton(
            label: 'Create Referral',
            height: 40,
            icon: Icons.add,
            onTap: widget.onCreateReferral,
          ),
        ),
        const SizedBox(height: AppConstants.spacingL),
        // The design's segmented track — reused from the existing primitive
        // rather than rebuilt: 11 dp labels, 8 dp vertical padding.
        SegmentedTabPill(
          labels: _tabs,
          selectedIndex: _tab,
          onChanged: (index) => setState(() => _tab = index),
          labelFontSize: 11,
          itemVerticalPadding: 8,
        ),
        _buildTab(),
      ],
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 1:
        return _ReferralListTab(
          referrals: widget.bundle.referrals,
          loading: widget.loading,
          failed: widget.failed,
        );
      case 2:
        return _CommissionsTab(
          commissions: widget.bundle.commissions,
          loading: widget.loading,
          failed: widget.failed,
        );
      case 3:
        return _PerformanceTab(
          performance: widget.bundle.performance,
          loading: widget.loading,
          failed: widget.failed,
        );
      default:
        return _OverviewTab(
          bundle: widget.bundle,
          loading: widget.loading,
          failed: widget.failed,
        );
    }
  }
}

class _OverviewTab extends StatelessWidget {
  final ReferralBundle bundle;
  final bool loading;
  final bool failed;

  const _OverviewTab({
    required this.bundle,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final summary = bundle.summary;
    String count(int value) => failed ? '—' : '$value';
    String money(String value) => failed ? '—' : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppConstants.spacingL),
        if (loading)
          const MetricCardGridShimmer(count: 4)
        else
          MetricCardGrid(
            cards: [
              MetricCard(
                icon: Icons.card_giftcard_outlined,
                value: count(summary.totalReferrals),
                label: 'Total Referrals',
              ),
              MetricCard(
                icon: Icons.check_circle_outline,
                value: count(summary.converted),
                label: 'Converted',
              ),
              MetricCard(
                icon: Icons.currency_rupee,
                value: money(summary.totalCommissionsDisplay),
                label: 'Total Commissions',
              ),
              MetricCard(
                icon: Icons.track_changes,
                value: money(summary.paidOutDisplay),
                label: 'Paid Out',
              ),
            ],
          ),
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Recent Referral Activity',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingL),
              if (failed)
                const EmptyStateView(
                  icon: Icons.error_outline,
                  message: "Couldn't load referral activity",
                  iconCircleSize: 52,
                  padding: EdgeInsets.symmetric(vertical: 4),
                )
              else if (bundle.referrals.isEmpty)
                const EmptyStateView(
                  icon: Icons.card_giftcard_outlined,
                  message: 'No referral activity yet',
                  iconCircleSize: 52,
                  padding: EdgeInsets.symmetric(vertical: 4),
                )
              else
                for (var i = 0; i < bundle.referrals.take(5).length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _ReferralRow(referral: bundle.referrals[i]),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReferralListTab extends StatelessWidget {
  final List<NetworkReferral> referrals;
  final bool loading;
  final bool failed;

  const _ReferralListTab({
    required this.referrals,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingL),
      child: DashboardCard(
        child: _SubTabBody(
          loading: loading,
          failed: failed,
          isEmpty: referrals.isEmpty,
          emptyIcon: Icons.card_giftcard_outlined,
          emptyMessage: 'No referrals yet',
          failedMessage: "Couldn't load referrals",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < referrals.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _ReferralRow(referral: referrals[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommissionsTab extends StatelessWidget {
  final List<NetworkCommission> commissions;
  final bool loading;
  final bool failed;

  const _CommissionsTab({
    required this.commissions,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingL),
      child: DashboardCard(
        child: _SubTabBody(
          loading: loading,
          failed: failed,
          isEmpty: commissions.isEmpty,
          emptyIcon: Icons.currency_rupee,
          emptyMessage: 'No commissions yet',
          failedMessage: "Couldn't load commissions",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < commissions.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _CommissionRow(commission: commissions[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PerformanceTab extends StatelessWidget {
  final List<NetworkPerformance> performance;
  final bool loading;
  final bool failed;

  const _PerformanceTab({
    required this.performance,
    required this.loading,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    // The design draws the same 2.5 dp primary line with a fading area fill as
    // the dashboard chart, so it reuses that widget rather than a second
    // painter. One point per scored period.
    final points = <ChartPoint>[
      for (final row in performance)
        if (row.periodStart != null)
          ChartPoint(
            date: row.periodStart!,
            value: (row.performanceScore ?? row.referralsConverted).toDouble(),
          ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingL),
      child: DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Referral Performance',
              style: AppTextStyles.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),
            if (loading)
              const SizedBox(
                height: 100,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              DashboardLineChart(
                points: points,
                height: 100,
                showDayLabels: false,
                emptyMessage: failed
                    ? "Couldn't load performance"
                    : 'No performance data yet',
              ),
          ],
        ),
      ),
    );
  }
}

/// Shared loading / failed / empty / content switch for the three list sub-tabs.
class _SubTabBody extends StatelessWidget {
  final bool loading;
  final bool failed;
  final bool isEmpty;
  final IconData emptyIcon;
  final String emptyMessage;
  final String failedMessage;
  final Widget child;

  const _SubTabBody({
    required this.loading,
    required this.failed,
    required this.isEmpty,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.failedMessage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 128,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (failed || isEmpty) {
      return ConstrainedBox(
        // The design gives these sub-tab cards a 160 dp minimum so the three
        // read as the same block while switching between them.
        constraints: const BoxConstraints(minHeight: 128),
        child: Center(
          child: EmptyStateView(
            icon: failed ? Icons.error_outline : emptyIcon,
            message: failed ? failedMessage : emptyMessage,
            iconCircleSize: 52,
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
        ),
      );
    }

    return child;
  }
}

class _ReferralRow extends StatelessWidget {
  final NetworkReferral referral;

  const _ReferralRow({required this.referral});

  @override
  Widget build(BuildContext context) {
    final amount = referral.commissionAmount;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  referral.referralType.isEmpty
                      ? 'Referral'
                      : referral.referralType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              NetworkStatusPill(
                referral.status,
                positive: referral.isConverted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (amount != null)
            NetworkDetailRow(
              label: 'Commission',
              value: formatRupeeAmount(amount),
            ),
          NetworkDetailRow(
            label: 'Commission status',
            value: referral.commissionStatus,
          ),
        ],
      ),
    );
  }
}

class _CommissionRow extends StatelessWidget {
  final NetworkCommission commission;

  const _CommissionRow({required this.commission});

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
                  commission.commissionType.isEmpty
                      ? 'Commission'
                      : commission.commissionType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  commission.amountDisplay,
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          NetworkStatusPill(commission.status, positive: commission.isPaid),
        ],
      ),
    );
  }
}
