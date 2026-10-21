import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/dashboard_analytics_provider.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../providers/auth_provider.dart';
import '../../models/builder_dashboard_model.dart';
import '../../models/builder_section_models.dart';
import '../../models/project_model.dart';
import '../../services/builder_dashboard_service.dart';
import '../../services/builder_sections_service.dart';
import '../../services/project_service.dart';
import '../../widgets/shared/section_header_back_button.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import 'widgets/builder_listings_block.dart';
import 'widgets/builder_inventory_summary.dart';
import 'widgets/builder_overview_body.dart';
import 'widgets/builder_offers_section.dart';
import 'widgets/builder_site_visits_section.dart';
import 'widgets/outgoing_site_visits_section.dart';
import 'widgets/builder_team_section.dart';
import 'widgets/my_projects_section.dart';
import 'widgets/dashboard_primitives.dart';
import 'widgets/dashboard_tab_bodies.dart';

/// The Builder dashboard's own six sections.
///
/// The portal's `BuilderTopNav.tsx` — Overview · Inventory · Marketed Offers ·
/// Team · Leads · Visits (it also has a seventh, Negotiation, which is out of
/// scope here — no Flutter surface reads `builder_project_negotiation_keys`
/// yet, and adding a first one is a separate feature, not a tab move). It has
/// no Analytics or Audience tab at all.
///
/// WHY NOT `DashboardTab`
/// ---------------------
/// `DashboardTabSelector` and its `DashboardTab` enum are shared by Broker,
/// Influencer and Individual. Re-labelling them for the builder would change the
/// other three roles' navigation, so the builder gets its own enum here and its own
/// selector below, both built on the same `SegmentedTabPill` primitive the shared
/// selector uses. Nothing shared is modified.
///
/// The Analytics body is folded into Overview, which is where the portal
/// puts performance. Audience is its own section (below), matching the
/// portal's own separate "Audience" tab (`BuilderTopNav.tsx`) — it used to be
/// appended under Team instead, see `BuilderSection.team`'s own comment.
enum BuilderSection { overview, inventory, offers, team, leads, visits, audience }

/// Seven labels over the app's existing segmented pill.
class BuilderSectionSelector extends StatelessWidget {
  const BuilderSectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final BuilderSection selected;
  final ValueChanged<BuilderSection> onChanged;

  static const _labels = <BuilderSection, String>{
    BuilderSection.overview: 'Overview',
    BuilderSection.inventory: 'Inventory',
    BuilderSection.offers: 'Offers',
    BuilderSection.team: 'Team',
    BuilderSection.leads: 'Leads',
    BuilderSection.visits: 'Visits',
    BuilderSection.audience: 'Audience',
  };

  @override
  Widget build(BuildContext context) {
    // "Marketed Offers" shortened to "Offers" for the pill only — the section's own
    // heading inside the tab keeps the portal's full wording. "Overview" and
    // "Inventory" are single words with no space to wrap at, so the usual
    // two-line allowance (Individual/Influencer's own multi-tab selectors) would
    // break them mid-letter instead — "Overvie" / "w" — at six segments' width.
    // Shrinking to fit one line avoids that regardless of device width.
    return SegmentedTabPill(
      labels: BuilderSection.values.map((s) => _labels[s]!).toList(),
      selectedIndex: BuilderSection.values.indexOf(selected),
      onChanged: (i) => onChanged(BuilderSection.values[i]),
      labelFontSize: 11,
      fitSingleLine: true,
    );
  }
}

/// The named route + arguments for a "Most Liked Content" tap on the
/// Audience tab — a builder's only cross-content type is `project`, routed
/// the same way `BuilderOverviewBody`'s "Top Performing Projects" already
/// does (see `onOpenProject` below). A pure function for the same reason as
/// influencer's `crossContentPushRoute`: unit-testable without mounting the
/// dashboard screen.
({String name, Map<String, dynamic> arguments})? builderCrossContentPushRoute(
  CrossContentItem item,
) => switch (item.type) {
  CrossContentType.project => (
    name: AppConstants.projectDetailScreen,
    arguments: {'projectId': item.id},
  ),
  // Never actually returned by `builder-audience-insights` — only
  // `influencer-audience-insights` emits these. Required for exhaustiveness.
  CrossContentType.property || CrossContentType.reel || CrossContentType.article =>
    null,
};

// ---------------------------------------------------------------------------
// PREMIUM PALETTE — keep this rich/deep across the whole gradient, no fading.
// ---------------------------------------------------------------------------
class _BrandGradient {
  // All four stay deep/saturated — c4 is only used for small accents
  // (icons, badges, glow blobs), never as a large gradient endpoint,
  // since a light endpoint is exactly what reads as "faded" at scale.
  // NOTE: the c1 anchor and the hero gradient were removed in Phase 3 with
  // the bespoke gradient header they existed for; DashboardHeaderBar replaced
  // it. c2/c3/c4 are still used by the FAB, cards and loading/error states.
  static const Color c2 = AppColors.primary; // base brand orange
  static const Color c4 = Color(0xFFC2410C); // accent only — icons/glows
}

class BuilderDashboardScreen extends StatelessWidget {
  const BuilderDashboardScreen({super.key, this.initialSection});

  /// A `DashboardSection` value (`'leads'`/`'visits'`) to open on, from
  /// `ManageDashboardDispatcher` — e.g. a tapped visit-booking notification.
  /// Anything else, including `null`, keeps the ordinary Overview default.
  final String? initialSection;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardAnalyticsProvider(
        // BuilderTopNav.tsx:5-11 gives a builder Overview / Inventory /
        // Marketed Offers / Team / Leads / Visits / Audience (plus
        // Negotiation, out of scope elsewhere in this file). There is no
        // separate Analytics tab — its content is folded into Overview here,
        // same as the portal folds it into Overview's own stat cards/charts.
        // What the source must not be is `properties`.
        //
        // It was, until Spec C. A builder publishes to `builder_projects`, never
        // to `properties` — BuilderListingsBlock hides My Listings when empty for
        // exactly that reason, and the only `properties` rows a builder holds are
        // legacy ones from the routing bug B3 fixed. Both tabs therefore rendered
        // all zeros for every correctly-behaving builder.
        //
        // `builder_projects` carries `views`, `likes` and `created_at`, which is
        // every column the shared service reads, and the portal's own builder
        // Overview sums `views` off that table
        // (BuilderDashboardManage.tsx:250-256). Same formulas, right table.
        analyticsSource: AnalyticsContentSource.builderProjects,
        audienceSource: AnalyticsContentSource.builderProjects,
        // Content Breakdown + Most Liked Content on the Audience tab, from the
        // deployed `builder-audience-insights` edge function — the portal's
        // own `BuilderAudienceInsights.tsx` calls the same one. A builder's
        // only content type is projects, unlike influencer's three tables.
        includeCrossContentInsights: true,
        crossContentFunction: 'builder-audience-insights',
      ),
      child: _BuilderDashboardView(initialSection: initialSection),
    );
  }
}

class _BuilderDashboardView extends StatefulWidget {
  const _BuilderDashboardView({this.initialSection});

  final String? initialSection;

  @override
  State<_BuilderDashboardView> createState() => _BuilderDashboardViewState();
}

class _BuilderDashboardViewState extends State<_BuilderDashboardView> {
  late Future<BuilderDashboardModel> _dashboardFuture;

  /// Opens on Overview, as the portal does (`activeSection` defaults to
  /// `'overview'`) — unless `widget.initialSection` names one of this
  /// dashboard's own sections (e.g. `'leads'`/`'visits'` from a tapped
  /// visit-booking notification), unrecognised values (including `null`,
  /// every existing caller's default) fall back to Overview exactly as
  /// before. The old default was `DashboardTab.analytics`, which is what
  /// showed a bare Analytics failure state as the first thing a builder saw.
  late BuilderSection _section = BuilderSection.values.firstWhere(
    (s) => s.name == widget.initialSection,
    orElse: () => BuilderSection.overview,
  );
  String? _loadedUserId;

  /// Reported upward by `BuilderSiteVisitsSection.onCountChanged`, so Overview's
  /// stat card can show it without a second read of `project_visit_bookings`.
  int _siteVisitCount = 0;

  // ── Spec H ────────────────────────────────────────────────────────────────
  //
  // Three of the four new sections are scoped by project, and `MyProjectsSection`
  // already loads the projects. Rather than have each section run its own
  // `builder_projects` query — which is what the portal's four components do,
  // four times over — the project list is reported up once and shared down.
  //
  // `_projects` is the loaded rows; `_unitCounts` is the one extra query Spec H
  // adds, run here because it is keyed by the ids only this level holds.
  List<ProjectModel> _projects = const [];
  Map<String, InventoryCounts> _unitCounts = const {};
  final ProjectInventoryService _inventory = ProjectInventoryService();

  /// Loads the inventory tallies once the project ids are known.
  ///
  /// A failure is swallowed to a silent empty map on purpose: the tallies are a
  /// chip on a card that renders perfectly well without them, and failing the
  /// whole projects list because a secondary count did not arrive would be a
  /// worse outcome than a missing chip.
  Future<void> _onProjectsLoaded(List<String> ids) async {
    if (!mounted) return;
    // Held even when the tallies fail, because the Team and Site Visits sections
    // are scoped by these ids and do not depend on the counts.
    final loaded = await _resolveProjects(ids);
    if (!mounted) return;
    setState(() => _projects = loaded);

    try {
      final counts = await _inventory.countsByProject(ids);
      if (!mounted) return;
      setState(() => _unitCounts = counts);
    } catch (e) {
      debugPrint('BuilderDashboard inventory tallies failed: $e');
    }
  }

  /// The full rows behind [ids].
  ///
  /// `MyProjectsSection` reports ids rather than models to keep its callback
  /// contract narrow, so they are resolved once here — through the same
  /// `ProjectService.listMine` it used, which is served from the same round trip
  /// in practice and keeps `ProjectService` the only reader of that table.
  Future<List<ProjectModel>> _resolveProjects(List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final rows = await ProjectService().listMine(
        context.read<AuthProvider>().userId!,
      );
      return rows.where((p) => ids.contains(p.id)).toList(growable: false);
    } catch (e) {
      debugPrint('BuilderDashboard project resolve failed: $e');
      return const [];
    }
  }

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAnalytics());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadProjectsIndependently(),
    );
  }

  /// Populates [_projects] without waiting for `MyProjectsSection` (the
  /// Inventory tab) to mount and call [_onProjectsLoaded] — that only
  /// happens if Inventory is actually opened this session, but Offers'
  /// "Create" button and the Site Visits section both key off [_projects]
  /// regardless of which tab is opened first. A user landing on Offers
  /// directly saw "Publish a project first" — with a real Create button
  /// hidden behind it — purely because Inventory hadn't been visited yet.
  ///
  /// Costs one extra `builder_projects` read if the user does visit
  /// Inventory afterward (`MyProjectsSection` still runs its own), which is
  /// the trade-off for Offers/Site Visits never depending on tab order.
  ///
  /// For the same reason, this also eagerly loads [_unitCounts] and
  /// [_siteVisitCount] — Overview (the landing tab) shows both as stat
  /// cards, but each was previously only populated by `MyProjectsSection`/
  /// `BuilderSiteVisitsSection` reporting upward once the Inventory/Visits
  /// tab was actually opened, so a builder landing on Overview and never
  /// switching tabs saw "0" for both even with real data behind them.
  Future<void> _loadProjectsIndependently() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;

    try {
      final rows = await ProjectService().listMine(userId);
      if (!mounted) return;
      setState(() => _projects = rows);

      final ids = rows.map((p) => p.id).toList(growable: false);
      await Future.wait([_loadInventoryTallies(ids), _loadSiteVisitCount(ids)]);
    } catch (e) {
      debugPrint('BuilderDashboard independent project load failed: $e');
    }
  }

  /// The same tally [_onProjectsLoaded] computes when Inventory is opened —
  /// run here too so Overview's stat card is correct even if Inventory is
  /// never visited this session. Failure is swallowed the same way: a
  /// missing chip is a better outcome than failing the whole dashboard.
  Future<void> _loadInventoryTallies(List<String> ids) async {
    try {
      final counts = await _inventory.countsByProject(ids);
      if (!mounted) return;
      setState(() => _unitCounts = counts);
    } catch (e) {
      debugPrint('BuilderDashboard inventory tallies failed: $e');
    }
  }

  /// The same count `BuilderSiteVisitsSection.onCountChanged` reports when
  /// Visits is opened — run here too so Overview's stat card is correct even
  /// if Visits is never visited this session.
  Future<void> _loadSiteVisitCount(List<String> ids) async {
    try {
      final bookings = await SiteVisitService().listForProjects(ids);
      if (!mounted) return;
      setState(() => _siteVisitCount = bookings.length);
    } catch (e) {
      debugPrint('BuilderDashboard site visit count failed: $e');
    }
  }

  Future<BuilderDashboardModel> _loadDashboard() {
    final auth = context.read<AuthProvider>();
    return BuilderDashboardService().getDashboardStats(auth.userId!);
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
      // Add Project belongs with Inventory now, which is where the portal's project
      // list lives.
      floatingActionButton: _section == BuilderSection.inventory
          // Design insets the FAB 20 dp from the right edge; Scaffold's
          // endFloat location defaults to 16.
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DashboardCreateFab(
                semanticLabel: 'Add project',
                onPressed: _onCreate,
              ),
            )
          : null,
      body: FutureBuilder<BuilderDashboardModel>(
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
                          BuilderSectionSelector(
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

  /// Opens the builder project wizard.
  ///
  /// This used to push [AppConstants.postPropertyScreen] — the **property
  /// listing** wizard — so every "Add Project" affordance on this screen wrote a
  /// row to `properties`. No builder surface in the portal does that: a builder
  /// publishes to `builder_projects` and nothing else.
  ///
  /// One method feeds all three entry points — the Content tab's FAB, its
  /// "Add Project" button and its "Add Your First Project" empty-state button —
  /// so this is the whole of the fix.
  void _onCreate() {
    Navigator.pushNamed(context, AppConstants.addProjectScreen);
  }

  /// Routes a "Most Liked Content" tap on the Audience tab to that project's
  /// detail screen — resolved through the pure
  /// [builderCrossContentPushRoute] so the routing decision stays
  /// unit-testable without mounting this screen (matches influencer's own
  /// `_openCrossContentItem`).
  void _openCrossContentItem(CrossContentItem item) {
    final route = builderCrossContentPushRoute(item);
    if (route == null) return;
    Navigator.pushNamed(context, route.name, arguments: route.arguments);
  }

  /// One of the portal's four sections.
  ///
  /// Every section reuses the widgets Specs H and I already built; this method only
  /// chooses which to show. No section fetches anything it did not fetch before.
  Widget _buildTabBody(
    BuildContext context,
    BuilderDashboardModel stats,
    AuthProvider auth,
  ) {
    final analytics = context.watch<DashboardAnalyticsProvider>();

    switch (_section) {
      // ── Overview — the portal's default landing section ────────────────
      //
      // Absorbs what the old Analytics and Audience tabs showed, which is where the
      // portal puts performance: stat cards, the project performance line, the
      // inventory donut, the three progress bars and top projects.
      case BuilderSection.overview:
        return BuilderOverviewBody(
          stats: stats,
          analytics: analytics.analytics,
          analyticsLoading: analytics.analyticsLoading,
          analyticsFailed: analytics.analyticsFailed,
          onRetryAnalytics: analytics.refresh,
          unitCounts: _unitCounts,
          siteVisitCount: _siteVisitCount,
          onOpenInventory: () =>
              setState(() => _section = BuilderSection.inventory),
          onOpenProject: (projectId) => Navigator.pushNamed(
            context,
            AppConstants.projectDetailScreen,
            arguments: {'projectId': projectId},
          ),
        );

      // ── Inventory — `BuilderInventoryManager.tsx` ───────────────────────
      //
      // The portal's "Inventory" is a project list with unit tallies and a status
      // picker; it has no unit-level CRUD. So this is `MyProjectsSection` in its
      // inventory mode, exactly as Spec H built it — plus the legacy listings block,
      // which collapses for any builder without pre-fix `properties` rows.
      case BuilderSection.inventory:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Projects & Inventory'),
            const SizedBox(height: 10),
            // The portal's six summary cards (`BuilderInventoryManager.tsx:327-400`),
            // folded from the two collections this screen already holds.
            BuilderInventorySummary(
              projects: _projects,
              unitCounts: _unitCounts,
            ),
            const SizedBox(height: 12),
            MyProjectsSection(
              key: const ValueKey('builder-inventory'),
              userId: auth.userId!,
              unitCounts: _unitCounts,
              showStatusPicker: true,
              onProjectsLoaded: _onProjectsLoaded,
            ),
            BuilderListingsBlock(userId: auth.userId!),
          ],
        );

      // ── Marketed Offers — `FilteredOffersList` + `MarketToBrokersModal` ──
      case BuilderSection.offers:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The portal's full wording, which the pill abbreviates to "Offers".
            const DashboardSectionLabel('Marketed Offers'),
            const SizedBox(height: 10),
            BuilderOffersSection(builderId: auth.userId!, projects: _projects),
          ],
        );

      // ── Leads — incoming requests on this builder's OWN projects —────────
      //
      // Was `BuilderLeadsSection` (a deliberately read-only summary of the
      // same read Visits used, per that widget's own prior doc comment).
      // Swapped for `BuilderSiteVisitsSection` itself: for a builder, Leads
      // and (pre-fix) Visits always queried the identical incoming
      // `project_visit_bookings` rows (`SiteVisitService.listForProjects`),
      // so this preserves exactly the same incoming scope while also moving
      // the only confirm/reschedule/status-edit UI in the app for this
      // table onto the tab that now actually owns incoming requests — see
      // the fix's own requirement that owner-side management controls
      // remain reachable from Leads once Visits stops being "incoming".
      case BuilderSection.leads:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Leads'),
            const SizedBox(height: 10),
            BuilderSiteVisitsSection(
              projectIds: _projects.map((p) => p.id).toList(growable: false),
              projectTitles: {
                for (final project in _projects) project.id: project.title,
              },
              projects: _projects,
              onCountChanged: (count) {
                // Feeds Overview's Site Visits stat card — an incoming-lead
                // volume metric, unrelated to and unchanged by this fix, so
                // it stays fed from the incoming widget rather than moving
                // to the new outgoing one below. Guarded because the
                // section reports on every load and setState during build
                // would throw.
                if (mounted && count != _siteVisitCount) {
                  setState(() => _siteVisitCount = count);
                }
              },
            ),
          ],
        );

      // ── Visits — requests THIS builder made on OTHER builders' projects ──
      //
      // Was `BuilderSiteVisitsSection` fed the builder's own project ids,
      // i.e. the identical incoming data Leads already showed (the root bug
      // this fix addresses) — replaced with the dashboard-shared outgoing
      // widget, backed by the existing `my-visit-requests` endpoint rather
      // than any locally-known id list.
      case BuilderSection.visits:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardSectionLabel('Site Visits'),
            SizedBox(height: 10),
            OutgoingSiteVisitsSection(),
          ],
        );

      // ── Team — `BuilderTeamManager.tsx` ────────────────────────────────
      case BuilderSection.team:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Team'),
            const SizedBox(height: 10),
            BuilderTeamSection(builderId: auth.userId!, projects: _projects),
          ],
        );

      // ── Audience — `BuilderAudienceInsights.tsx` ────────────────────────
      //
      // Used to be appended under Team instead of its own tab (there was no
      // `BuilderSection.audience` case) — the data was always real
      // (`DashboardAnalyticsProvider`), it just wasn't surfaced as its own
      // section the way the portal's separate "Audience" nav item is.
      case BuilderSection.audience:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Audience'),
            const SizedBox(height: 10),
            DashboardAudienceBody(
              audience: analytics.audience,
              loading: analytics.audienceLoading,
              failed: analytics.audienceFailed,
              onRetry: analytics.refresh,
              crossContentLoading: analytics.crossContentLoading,
              crossContentFailed: analytics.crossContentFailed,
              onCrossContentRetry: analytics.retryCrossContentInsights,
              onContentTap: _openCrossContentItem,
            ),
          ],
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFE4E4),
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
                    color: _BrandGradient.c2.withOpacity(0.35),
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
