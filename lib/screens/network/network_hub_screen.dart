import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/network_stats.dart';
import '../../providers/auth_provider.dart';
import '../../providers/network_hub_provider.dart';
import '../../widgets/manage_list_tile.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/section_header_back_button.dart';
import '../../widgets/shared/stat_kpi_card.dart';

/// Network — the hub for memberships, leads and referrals.
///
/// Design: the `showNetwork` screen. Four KPI tiles over four navigation
/// cards, then an Overview section holding Recent Activity and Performance
/// Summary.
///
/// Functionally this is `features/network/NetworkDashboard.tsx`: the same four
/// statistics, resolved through the same builder/member branch, from the same
/// three tables. Each of the four cards reaches its real screen — My Networks,
/// My Leads, My Referrals and Communication — delivered in Phase 9.
class NetworkHubScreen extends StatelessWidget {
  const NetworkHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkHubProvider(),
      child: const _NetworkHubView(),
    );
  }
}

class _NetworkHubView extends StatefulWidget {
  const _NetworkHubView();

  @override
  State<_NetworkHubView> createState() => _NetworkHubViewState();
}

class _NetworkHubViewState extends State<_NetworkHubView> {
  /// De-dup key, folding in the resolved role — see the note below and
  /// `DeferredSectionLoader.reloadOnRoleChange`'s doc for the underlying race
  /// this guards against (this screen predates that mixin's promotion out of
  /// Social, so it never adopted it and carries the same fix inline).
  String? _loadedKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) return;
    // `userType` only lands once the `profiles` fetch resolves; loading with
    // whatever role happened to be available before that (always "not a
    // builder", since `userType` starts null) would cache a builder as a
    // member for the rest of this screen's lifetime, since `userId` alone
    // never changes again.
    if (auth.isResolving) return;

    final key = '$userId::${auth.userType ?? ''}';
    if (key == _loadedKey) return;
    _loadedKey = key;

    // `load()` raises its loading flag and notifies before its first `await`,
    // and this runs from didChangeDependencies — inside the build phase — so
    // calling it directly would mark this element dirty while it is still
    // building and trip `assert(!_dirty)`. Deferring to the end of the frame
    // lets the first build complete against the provider's initial state. The
    // provider is captured now, not looked up in the callback, so nothing
    // touches this context after the widget may have been deactivated. Same
    // fix as Profile and Messages.
    final provider = context.read<NetworkHubProvider>();
    final isBuilder = auth.userType?.toLowerCase() == 'builder';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId, isBuilder: isBuilder);
    });
  }

  /// Re-derives `isBuilder` fresh from `AuthProvider` rather than calling
  /// `provider.refresh()` directly — that method reuses whichever `isBuilder`
  /// the last `load()` call was given (see its own doc), which after an
  /// invitation accept/decline is the one value already known to be current,
  /// but making that assumption explicit here means this call site can never
  /// silently go stale if the role were ever resolved late.
  void _refreshWithCurrentRole() {
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) return;
    context.read<NetworkHubProvider>().load(
      userId,
      isBuilder: auth.userType?.toLowerCase() == 'builder',
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NetworkHubProvider>();

    return NetworkHubBody(
      stats: provider.stats,
      loading: provider.loading,
      failed: provider.failed,
      isBuilder: provider.isBuilder,
      // Spec F. `context.watch<AuthProvider>()` rather than the cached
      // `_loadedKey`: that field exists to make the load idempotent and is null
      // until the first frame, whereas the invitations section needs the id on the
      // build that renders it.
      userId: context.watch<AuthProvider>().userId,
      onNetworkChanged: _refreshWithCurrentRole,
    );
  }
}

/// The hub's visuals, separated from the provider that feeds them.
///
/// Split out so the layout is testable on its own: reaching the screen through
/// [NetworkHubScreen] requires an [AuthProvider], which cannot be constructed
/// without an initialised Supabase client, and a 2×2 metric grid with long
/// labels is exactly the shape that overflowed during Phase 5.
class NetworkHubBody extends StatelessWidget {
  final NetworkStats stats;
  final bool loading;
  final bool failed;

  /// Whether the signed-in user is a builder — `stats.totalNetworks` means
  /// "Network Members" (their own owned network) for a builder and
  /// "Networks Joined" (networks they belong to) for everyone else; the two
  /// are not interchangeable labels for the same number.
  final bool isBuilder;

  /// Spec F: whose invitations to show.
  ///
  /// Optional so the existing design-parity tests, which pump this body with just
  /// stats, keep compiling and keep passing. Null renders the hub exactly as it was
  /// before Spec F — no Invitations section at all.
  final String? userId;

  /// Called after an invitation is accepted or declined, so the stats grid can
  /// re-read. An accepted invitation becomes a `builder_networks` row, which is what
  /// the corrected relationship classification counts.
  final VoidCallback? onNetworkChanged;

  const NetworkHubBody({
    super.key,
    required this.stats,
    required this.loading,
    required this.failed,
    this.isBuilder = false,
    this.userId,
    this.onNetworkChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeaderBar(
                title: 'Network',
                subtitle: 'Memberships, leads & referrals',
              ),
              const SizedBox(height: 18),
              _StatsGrid(
                stats: stats,
                loading: loading,
                failed: failed,
                isBuilder: isBuilder,
              ),
              const SizedBox(height: 22),
              _NavCards(
                stats: stats,
                loading: loading,
                failed: failed,
                isBuilder: isBuilder,
              ),

              // The Invitations section (Spec F's NetworkInvitationsSection)
              // was removed from this dashboard by request — no longer
              // needed here. [userId]/[onNetworkChanged] are kept on the
              // constructor unused rather than touching every call site that
              // still passes them.
              const SizedBox(height: 26),
              const DashboardSectionLabel('Overview'),
              const SizedBox(height: 10),
              const DashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CardHeading('Recent Activity'),
                    SizedBox(height: AppConstants.spacingL),
                    // No activity feed exists on either platform yet, so this
                    // states that plainly instead of inventing rows.
                    EmptyStateView(
                      icon: Icons.grid_view_rounded,
                      message: 'Recent network activity will appear here',
                      iconCircleSize: 52,
                      padding: EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingS,
                        vertical: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingM),
              _PerformanceSummary(stats: stats),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card heading — 14.5 dp bold, the design's weight for the Overview cards.
///
/// Deliberately not [DashboardCardTitle], which is the dashboards' 13.5 dp
/// semi-bold heading; these two cards are visibly heavier in the design.
class _CardHeading extends StatelessWidget {
  final String text;

  const _CardHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.heading3.copyWith(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final NetworkStats stats;
  final bool loading;
  final bool failed;
  final bool isBuilder;

  const _StatsGrid({
    required this.stats,
    required this.loading,
    required this.failed,
    required this.isBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const MetricCardGridShimmer(count: 4);

    // An em dash rather than a zero when the query failed, so "no data" is
    // never mistaken for "you have no networks".
    String count(int value) => failed ? '—' : '$value';

    return MetricCardGrid(
      cards: [
        MetricCard(
          icon: Icons.people_outline,
          value: count(stats.totalNetworks),
          // A builder's own owned network vs. the networks someone else
          // belongs to are not the same count — see `NetworkHubBody.isBuilder`.
          label: isBuilder ? 'Network Members' : 'Networks Joined',
        ),
        MetricCard(
          icon: Icons.track_changes,
          value: count(stats.activeLeads),
          label: 'Active Leads',
        ),
        MetricCard(
          icon: Icons.trending_up_rounded,
          value: count(stats.totalReferrals),
          label: 'Total Referrals',
        ),
        MetricCard(
          icon: Icons.currency_rupee,
          value: failed ? '—' : stats.monthlyCommissionsDisplay,
          label: 'Monthly Commissions',
        ),
      ],
    );
  }
}

class _NavCards extends StatelessWidget {
  final NetworkStats stats;
  final bool loading;
  final bool failed;
  final bool isBuilder;

  const _NavCards({
    required this.stats,
    required this.loading,
    required this.failed,
    required this.isBuilder,
  });

  /// The design's subtitles carry live counts ("3 active networks"). They are
  /// only shown once a query has actually returned — while loading or after a
  /// failure the card falls back to a plain descriptor rather than "0".
  String _subtitle(String withCount, String fallback) {
    if (loading || failed) return fallback;
    return withCount;
  }

  @override
  Widget build(BuildContext context) {
    return ManageListTile.group([
      ManageListTile(
        icon: Icons.people_outline,
        label: 'My Networks',
        subtitle: isBuilder
            ? _subtitle(
                '${stats.totalNetworks} network members',
                'Brokers and influencers in your network',
              )
            : _subtitle(
                '${stats.totalNetworks} networks joined',
                'Builder networks you belong to',
              ),
        onTap: () =>
            Navigator.of(context).pushNamed(AppConstants.myNetworksScreen),
      ),
      ManageListTile(
        icon: Icons.trending_up_rounded,
        label: 'My Referrals',
        subtitle: _subtitle(
          '${stats.totalReferrals} referrals tracked',
          'Referrals and commissions',
        ),
        onTap: () =>
            Navigator.of(context).pushNamed(AppConstants.myReferralsScreen),
      ),
      // No channel count is shown: the design's "2 channels" is placeholder
      // copy and nothing queries a channel count for this surface yet.
      ManageListTile(
        icon: Icons.chat_bubble_outline,
        label: 'Communication',
        subtitle: 'Channels, messaging & settings',
        onTap: () => Navigator.of(
          context,
        ).pushNamed(AppConstants.networkCommunicationScreen),
      ),
      // Builder-only — matches the portal's `analytics` tab, which is only
      // registered/rendered for `profile?.user_type === 'builder'`
      // (`NetworkDashboard.tsx`'s `getTabsForUserType`).
      if (isBuilder)
        ManageListTile(
          icon: Icons.bar_chart_rounded,
          label: 'Analytics',
          subtitle: 'Performance, trends & insights',
          onTap: () => Navigator.of(
            context,
          ).pushNamed(AppConstants.networkAnalyticsScreen),
        ),
    ]);
  }
}

/// Performance Summary — three labelled rows with a dark value pill.
///
/// React renders `85%`, `2.3 hrs` and `4.8/5` as hardcoded literals in
/// `NetworkDashboard.tsx` with no query behind any of them. Rather than
/// perpetuate that gap, [stats] carries real figures computed from
/// `network_leads` (success rate, response time — see
/// `NetworkService.getPerformanceMetrics`) and from this user's own ratings
/// (network rating, the same figure the Profile screen's Reviews tile shows).
/// A row whose figure has no data yet (no leads, no ratings, or the load
/// failed) still shows an em dash rather than a zero or the portal's
/// invented number — [NetworkStats]'s three display getters already encode
/// that fallback, so this widget only has to read them.
class _PerformanceSummary extends StatelessWidget {
  const _PerformanceSummary({required this.stats});

  final NetworkStats stats;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Success Rate', stats.successRateDisplay),
      ('Response Time', stats.avgResponseTimeDisplay),
      ('Network Rating', stats.networkRatingDisplay),
    ];

    return DashboardCard(
      padding: const EdgeInsets.symmetric(
        horizontal: 4,
        vertical: AppConstants.spacingL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
            child: _CardHeading('Performance Summary'),
          ),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingM,
                vertical: AppConstants.spacingM,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  _ValuePill(value),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Dark rounded value chip — 22 dp tall, `#1A1A2E`, 11 dp bold white label.
class _ValuePill extends StatelessWidget {
  final String text;

  const _ValuePill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
