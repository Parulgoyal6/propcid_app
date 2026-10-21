import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/broker_dashboard_model.dart';
import '../../models/dashboard_analytics.dart';
import '../../models/property_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/property_service.dart';
import '../../providers/dashboard_analytics_provider.dart';
import '../../services/broker_dashboard_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../widgets/broker_recent_properties_widget.dart';
import '../widgets/broker_stats_widget.dart';
import 'my_listings_section.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import 'widgets/broker_leads_section.dart';
import 'widgets/broker_listing_summary.dart';
import 'widgets/broker_visit_bookings_section.dart';
import 'widgets/outgoing_site_visits_section.dart';
import '../../widgets/shared/section_header_back_button.dart';
import 'widgets/dashboard_primitives.dart';
import 'widgets/dashboard_tab_bodies.dart';

// Retained accents used by the loading and error states.
class _BrandGradient {
  static const Color c2 = AppColors.primary;
  static const Color c4 = Color(0xFFC2410C);
}

/// Broker Manage Dashboard.
///
/// Presentation rebuilt to the approved mobile design. Everything behind it is
/// unchanged: `BrokerDashboardService`, `BrokerDashboardModel`,
/// `BrokerStatsWidget`, `BrokerRecentPropertiesWidget`, `MyListingsSection`
/// and the route that reaches this screen all behave exactly as before.
///
/// [DashboardAnalyticsProvider] is additive — it supplies the Analytics and
/// Audience metrics the design shows, ported from the React portal's
/// `BrokerAnalytics.tsx` / `BrokerAudienceInsights.tsx`.
/// The Broker dashboard's five sections.
///
/// `BrokerDashboardManage.tsx:270-309` — Analytics · Inventory · Leads · Visits ·
/// Audience. Note the portal labels its content tab **"Inventory"**, not "Content
/// Manager".
///
/// Its own enum for the same reason the builder has one: `DashboardTab` and
/// `DashboardTabSelector` are shared with Influencer and Individual, and
/// re-labelling them would change those roles. Nothing shared is modified.
enum BrokerSection { analytics, inventory, leads, visits, audience }

/// Five labels over the app's existing segmented pill.
class BrokerSectionSelector extends StatelessWidget {
  const BrokerSectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final BrokerSection selected;
  final ValueChanged<BrokerSection> onChanged;

  static const _labels = <BrokerSection, String>{
    BrokerSection.analytics: 'Analytics',
    BrokerSection.inventory: 'Inventory',
    BrokerSection.leads: 'Leads',
    BrokerSection.visits: 'Visits',
    BrokerSection.audience: 'Audience',
  };

  @override
  Widget build(BuildContext context) {
    // Five labels wrap onto two rows at 320 dp. The pill handles that; the portal's
    // own `hidden sm:inline` / `sm:hidden` pairs show it does the same on narrow
    // viewports.
    return SegmentedTabPill(
      labels: BrokerSection.values.map((s) => _labels[s]!).toList(),
      selectedIndex: BrokerSection.values.indexOf(selected),
      onChanged: (i) => onChanged(BrokerSection.values[i]),
      labelFontSize: 11,
    );
  }
}

class BrokerDashboardScreen extends StatelessWidget {
  const BrokerDashboardScreen({super.key, this.initialSection});

  /// A `DashboardSection` value (`'leads'`/`'visits'`) to open on, from
  /// `ManageDashboardDispatcher`. Anything else, including `null`, keeps the
  /// ordinary Analytics default.
  final String? initialSection;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardAnalyticsProvider(
        // Broker content lives in `properties` on both tabs.
        analyticsSource: AnalyticsContentSource.properties,
        audienceSource: AnalyticsContentSource.properties,
        // BrokerAnalytics.tsx hard-codes growth to 0, noting it needs
        // historical engagement tracking that does not exist yet.
        growthFromContent: false,
        // Spec C: the six metrics BrokerAnalytics.tsx computes that the shared
        // body had no field for, plus the three lead metrics
        // BrokerAudienceInsights.tsx computes. Both read `property_inquiries`.
        includeListingMetrics: true,
        includeLeadMetrics: true,
      ),
      child: _BrokerDashboardView(initialSection: initialSection),
    );
  }
}

class _BrokerDashboardView extends StatefulWidget {
  const _BrokerDashboardView({this.initialSection});

  final String? initialSection;

  @override
  State<_BrokerDashboardView> createState() => _BrokerDashboardViewState();
}

class _BrokerDashboardViewState extends State<_BrokerDashboardView> {
  late Future<BrokerDashboardModel> _dashboardFuture;

  /// Opens on Analytics, matching the portal's `defaultValue="analytics"` —
  /// unless `widget.initialSection` names one of this dashboard's own
  /// sections (e.g. `'leads'`/`'visits'`); unrecognised values (including
  /// `null`, every existing caller's default) fall back to Analytics exactly
  /// as before.
  late BrokerSection _section = BrokerSection.values.firstWhere(
    (s) => s.name == widget.initialSection,
    orElse: () => BrokerSection.analytics,
  );
  String? _loadedUserId;

  // ── Spec I ────────────────────────────────────────────────────────────────
  //
  // Leads, Visit Bookings and the lead stats are all scoped by "this broker's
  // listings", because neither `property_inquiries` nor `property_visit_bookings`
  // has a broker column — the listing set *is* the scope.
  //
  // The portal's three components each open with their own identical
  // `.from('properties').eq('user_id', …)` fetch. Here it runs once, through the
  // `PropertyService` method Spec D verified against that query byte for byte, and
  // the result is shared down.
  List<PropertyModel> _properties = const [];

  /// Loads the listings the Spec I sections are scoped by.
  ///
  /// A failure leaves the list empty, which each section renders as its own "once
  /// you publish a listing" message rather than as an error — the dashboard's own
  /// stats and listings sections have their own error states, and a second failure
  /// banner for the same cause would be noise.
  Future<void> _loadProperties() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    try {
      final rows = await PropertyService().getPropertiesByUser(userId);
      if (!mounted) return;
      setState(() => _properties = rows);
    } catch (e) {
      debugPrint('BrokerDashboard property scope failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAnalytics();
      _loadProperties();
    });
  }

  Future<BrokerDashboardModel> _loadDashboard() {
    final auth = context.read<AuthProvider>();
    return BrokerDashboardService().getDashboardStats(auth.userId!);
  }

  /// Deferred to after the frame: `load()` notifies synchronously before its
  /// first await, which would mark this element dirty mid-build.
  void _loadAnalytics() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || userId == _loadedUserId) return;
    _loadedUserId = userId;
    context.read<DashboardAnalyticsProvider>().load(userId);
  }

  Future<void> _refresh() async {
    setState(() {
      _dashboardFuture = _loadDashboard();
    });
    await Future.wait([
      _dashboardFuture,
      context.read<DashboardAnalyticsProvider>().refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.userId == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      // Design places an icon-only square FAB on the Content tab only.
      floatingActionButton: _section == BrokerSection.inventory
          // Design insets the FAB 20 dp from the right edge; Scaffold's
          // endFloat location defaults to 16.
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DashboardCreateFab(
                semanticLabel: 'Add property',
                onPressed: _onCreateProperty,
              ),
            )
          : null,
      body: FutureBuilder<BrokerDashboardModel>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState(context);
          }

          final stats = snapshot.data;
          if (snapshot.hasError || stats == null) {
            return _buildErrorState(context);
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const DashboardHeaderBar(
                            title: 'Manage Dashboard',
                            subtitle:
                                'Manage your content and track performance',
                          ),
                          const SizedBox(height: 18),
                          BrokerSectionSelector(
                            selected: _section,
                            onChanged: (s) => setState(() => _section = s),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    child: _buildTabBody(context, stats, auth),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }

  /// The create action this role already exposed, unchanged.
  void _onCreateProperty() {
    Navigator.pushNamed(context, AppConstants.postPropertyScreen);
  }

  /// One of the portal's five sections.
  ///
  /// Every section reuses the widgets Specs D and I already built. The Spec I
  /// sections that used to be stacked under one Content tab are now their own
  /// destinations, which is how the portal arranges them.
  Widget _buildTabBody(
    BuildContext context,
    BrokerDashboardModel stats,
    AuthProvider auth,
  ) {
    final analytics = context.watch<DashboardAnalyticsProvider>();

    switch (_section) {
      // ── Analytics — `BrokerAnalytics.tsx` ───────────────────────────────
      case BrokerSection.analytics:
        return DashboardAnalyticsBody(
          analytics: analytics.analytics,
          loading: analytics.analyticsLoading,
          failed: analytics.analyticsFailed,
          onRetry: analytics.refresh,
          // Read off the provider rather than hard-coded, so the flag that decides
          // whether `saved_properties` is queried is the same one that decides
          // whether the tile appears.
          showSavedProperties: analytics.includeSavedProperties,
        );

      // ── Inventory — `BrokerContentManager.tsx` ──────────────────────────
      //
      // The portal labels this tab "Inventory" and shows three summary cards over a
      // listing table. The table's five columns are covered per-card by
      // `MyListingsSection`; the summary strip was the gap.
      case BrokerSection.inventory:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Overview'),
            const SizedBox(height: 10),
            BrokerStatsWidget(stats: stats),
            const SizedBox(height: 22),
            const DashboardSectionLabel('Recent Properties'),
            const SizedBox(height: 10),
            // Kept from the pre-redesign Content tab. A read-only rail, and it
            // predates this phase — dropping it would remove existing functionality.
            DashboardCard(
              child: BrokerRecentPropertiesWidget(brokerId: auth.userId!),
            ),
            const SizedBox(height: 22),
            const DashboardSectionLabel('My Listings'),
            const SizedBox(height: 10),
            BrokerListingSummary(properties: _properties),
            const SizedBox(height: 12),
            MyListingsSection(userId: auth.userId!),
          ],
        );

      // ── Leads — `BrokerLeadsManager.tsx` ────────────────────────────────
      //
      // Unchanged scope (incoming `property_inquiries` + incoming
      // `property_visit_bookings` on this broker's OWN properties) — Leads
      // was never the bug here, only Visits was (see below). `
      // BrokerVisitBookingsSection` is additionally mounted below the
      // unified list, unchanged itself: it is the only place in the app
      // with the full confirm/reschedule (date+time+status) edit sheet for
      // an incoming booking, and it must stay reachable from Leads now that
      // Visits no longer shows incoming data at all.
      case BrokerSection.leads:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Leads'),
            const SizedBox(height: 10),
            BrokerLeadsSection(properties: _properties),
            const SizedBox(height: AppConstants.spacingL),
            const DashboardSectionLabel('Manage Visit Bookings'),
            const SizedBox(height: 10),
            BrokerVisitBookingsSection(properties: _properties),
          ],
        );

      // ── Visits — requests THIS broker made on OTHER people's listings ───
      //
      // Was `BrokerVisitBookingsSection` fed this broker's own properties,
      // i.e. the identical incoming data Leads already showed (the root bug
      // this fix addresses) — replaced with the dashboard-shared outgoing
      // widget, backed by the existing `my-visit-requests` endpoint rather
      // than any locally-known property id list.
      case BrokerSection.visits:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardSectionLabel('Visit Bookings'),
            SizedBox(height: 10),
            OutgoingSiteVisitsSection(),
          ],
        );

      // ── Audience — `BrokerAudienceInsights.tsx` ─────────────────────────
      case BrokerSection.audience:
        return DashboardAudienceBody(
          audience: analytics.audience,
          loading: analytics.audienceLoading,
          failed: analytics.audienceFailed,
          onRetry: analytics.refresh,
        );
    }
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _BrandGradient.c2),
          const SizedBox(height: 16),
          Text(
            "Loading your dashboard...",
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ---------------- ERROR STATE ----------------

  Widget _buildErrorState(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFFE4E4),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFE53935),
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "Something went wrong",
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1C1530),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "We couldn't load your dashboard. Pull down to try again.",
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [_BrandGradient.c2, _BrandGradient.c4],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _BrandGradient.c2.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FilledButton.icon(
                onPressed: _refresh,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                label: const Text(
                  "Retry",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
