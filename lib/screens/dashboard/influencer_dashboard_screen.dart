import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/dashboard_analytics.dart';
import '../../providers/dashboard_analytics_provider.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../providers/auth_provider.dart';
import '../../models/influencer_dashboard_model.dart';
import '../../models/property_model.dart';
import '../../services/article_service.dart';
import '../../services/influencer_dashboard_service.dart';
import '../../services/property_service.dart';
import '../home/widgets/latest_articles_section.dart'
    show showArticleDetailSheet;
import '../widgets/influencer_stats_widget.dart';
import '../widgets/influencer_quick_actions_widget.dart';
import 'my_listings_section.dart';
import '../../widgets/shared/section_header_back_button.dart';
import 'widgets/broker_leads_section.dart';
import 'widgets/broker_visit_bookings_section.dart';
import 'widgets/outgoing_site_visits_section.dart';
import 'widgets/dashboard_primitives.dart';
import 'widgets/dashboard_tab_bodies.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import '../network/widgets/network_invitations_section.dart';
import 'widgets/my_videos_section.dart';

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

/// The Influencer dashboard's six sections.
///
/// `InfluencerDashboardManage.tsx` — Analytics · Content · **Leads** ·
/// **Visits** · Audience · Collaboration. Leads/Visits are the same
/// `property_inquiries`/`property_visit_bookings` pair every other role's
/// manage dashboard has — an influencer lists properties too
/// (`MyListingsSection` below, per `CreateContent.tsx:379-402`), so the same
/// scope-by-my-properties logic applies unchanged.
///
/// Its own enum, like the builder's and the broker's, so the shared
/// `DashboardTabSelector` keeps serving Individual unchanged.
enum InfluencerSection {
  analytics,
  content,
  leads,
  visits,
  audience,
  collaboration,
}

/// The named route + arguments for a "Most Liked Content" tap, for the two
/// content types that already have one — [CrossContentType.article] has no
/// equivalent (see `_InfluencerDashboardViewState._openCrossContentItem`)
/// and returns null so the caller knows to fall back to fetching and
/// showing the article sheet instead.
///
/// A pure function so this routing decision — a reel id must reach
/// [AppConstants.reelsScreen]'s `reelId` argument, a property id must reach
/// [AppConstants.propertyDetailScreen]'s `propertyId` argument, and neither
/// is ever confused with the other — is unit-testable without mounting the
/// dashboard screen.
({String name, Map<String, dynamic> arguments})? crossContentPushRoute(
  CrossContentItem item,
) => switch (item.type) {
  CrossContentType.property => (
    name: AppConstants.propertyDetailScreen,
    arguments: {'propertyId': item.id},
  ),
  CrossContentType.reel => (
    name: AppConstants.reelsScreen,
    arguments: {'reelId': item.id},
  ),
  CrossContentType.article => null,
  // Never actually returned by `influencer-audience-insights` — only
  // `builder-audience-insights` emits this type (see
  // `BuilderDashboardScreen.crossContentPushRoute` for its real routing).
  // Required for exhaustiveness only.
  CrossContentType.project => null,
};

/// Six labels over the app's existing segmented pill.
class InfluencerSectionSelector extends StatelessWidget {
  const InfluencerSectionSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final InfluencerSection selected;
  final ValueChanged<InfluencerSection> onChanged;

  static const _labels = <InfluencerSection, String>{
    InfluencerSection.analytics: 'Analytics',
    InfluencerSection.content: 'Content',
    InfluencerSection.leads: 'Leads',
    InfluencerSection.visits: 'Visits',
    InfluencerSection.audience: 'Audience',
    InfluencerSection.collaboration: 'Collabs',
  };

  @override
  Widget build(BuildContext context) {
    // "Collaboration" shortened to "Collabs" for the pill only; the section heading
    // inside the tab keeps the portal's full word.
    return SegmentedTabPill(
      labels: InfluencerSection.values.map((s) => _labels[s]!).toList(),
      selectedIndex: InfluencerSection.values.indexOf(selected),
      onChanged: (i) => onChanged(InfluencerSection.values[i]),
      labelFontSize: 11.5,
    );
  }
}

class InfluencerDashboardScreen extends StatelessWidget {
  const InfluencerDashboardScreen({super.key, this.initialSection});

  /// A `DashboardSection` value (`'leads'`/`'visits'`) to open on, from
  /// `ManageDashboardDispatcher`. Anything else, including `null`, keeps the
  /// ordinary Analytics default.
  final String? initialSection;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardAnalyticsProvider(
        // InfluencerAnalytics.tsx and InfluencerAudienceInsights.tsx both
        // read `influencer_videos`.
        analyticsSource: AnalyticsContentSource.influencerVideos,
        audienceSource: AnalyticsContentSource.influencerVideos,
        // Spec C: avgWatchTime and avgCompletionRate, the two metrics
        // InfluencerAnalytics.tsx derives from `influencer_video_views`.
        includeWatchMetrics: true,
        // Cross-content Reach/Likes/Comments, Content Breakdown and Most
        // Liked Content spanning reels + properties + articles — the one
        // section `influencer_videos` alone cannot answer, so it comes from
        // the `influencer-audience-insights` edge function instead.
        includeCrossContentInsights: true,
      ),
      child: _InfluencerDashboardView(initialSection: initialSection),
    );
  }
}

class _InfluencerDashboardView extends StatefulWidget {
  const _InfluencerDashboardView({this.initialSection});

  final String? initialSection;

  @override
  State<_InfluencerDashboardView> createState() =>
      _InfluencerDashboardViewState();
}

class _InfluencerDashboardViewState extends State<_InfluencerDashboardView> {
  late Future<InfluencerDashboardModel> _dashboardFuture;

  /// Opens on Analytics, as the portal's Tabs default does — unless
  /// `widget.initialSection` names one of this dashboard's own sections
  /// (e.g. `'leads'`/`'visits'`); unrecognised values (including `null`,
  /// every existing caller's default) fall back to Analytics exactly as
  /// before.
  late InfluencerSection _section = InfluencerSection.values.firstWhere(
    (s) => s.name == widget.initialSection,
    orElse: () => InfluencerSection.analytics,
  );
  String? _loadedUserId;

  /// The scope for the Leads/Visits tabs — same reasoning as
  /// `BrokerDashboardScreen._properties`: neither `property_inquiries` nor
  /// `property_visit_bookings` has a role column, so "my own properties" is
  /// the whole scope regardless of user type.
  List<PropertyModel> _properties = const [];

  Future<void> _loadProperties() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) return;
    try {
      final rows = await PropertyService().getPropertiesByUser(userId);
      if (!mounted) return;
      setState(() => _properties = rows);
    } catch (e) {
      debugPrint('InfluencerDashboard property scope failed: $e');
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

  Future<InfluencerDashboardModel> _loadDashboard() {
    final auth = context.read<AuthProvider>();
    return InfluencerDashboardService().getDashboardStats(auth.userId!);
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
      floatingActionButton: _section == InfluencerSection.content
          // Design insets the FAB 20 dp from the right edge; Scaffold's
          // endFloat location defaults to 16.
          ? Padding(
              padding: const EdgeInsets.only(right: 4),
              child: DashboardCreateFab(
                semanticLabel: 'Upload video',
                onPressed: _onCreate,
              ),
            )
          : null,
      body: FutureBuilder<InfluencerDashboardModel>(
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
                          InfluencerSectionSelector(
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

  /// Opens the influencer video form.
  ///
  /// Was [AppConstants.postPropertyScreen]. Every affordance this feeds already
  /// promised video — the FAB's semantic label is "Upload video" (:117), the
  /// Content tab's button reads "Upload Video" and its empty state reads "Upload
  /// Your First Video" (:203-204) — and all three opened the property listing
  /// wizard instead.
  void _onCreate() {
    Navigator.pushNamed(context, AppConstants.influencerVideoFormScreen);
  }

  /// Routes a "Most Liked Content" tap to the right detail screen for its
  /// own content type — a reel id and an article id are never property ids.
  /// The property/reel cases resolve through the pure [crossContentPushRoute]
  /// so that routing decision is unit-testable without mounting this screen;
  /// article has no equivalent named route (see below) and is handled here
  /// directly.
  Future<void> _openCrossContentItem(
    BuildContext context,
    CrossContentItem item,
  ) async {
    final route = crossContentPushRoute(item);
    if (route != null) {
      Navigator.pushNamed(context, route.name, arguments: route.arguments);
      return;
    }

    // Only CrossContentType.article reaches here — no dedicated article
    // route exists (only the editor and Home's own read-only bottom sheet),
    // reused rather than building a second reader, per
    // `latest_articles_section.dart`'s own header comment.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final article = await ArticleService().getById(item.id);
      if (!context.mounted) return;
      showArticleDetailSheet(context, article);
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text("Couldn't open this article. Please try again."),
          ),
        );
    }
  }

  /// One of the portal's four sections.
  Widget _buildTabBody(
    BuildContext context,
    InfluencerDashboardModel stats,
    AuthProvider auth,
  ) {
    final analytics = context.watch<DashboardAnalyticsProvider>();

    switch (_section) {
      // ── Analytics — `InfluencerAnalytics.tsx` ───────────────────────────
      case InfluencerSection.analytics:
        return DashboardAnalyticsBody(
          analytics: analytics.analytics,
          loading: analytics.analyticsLoading,
          failed: analytics.analyticsFailed,
          onRetry: analytics.refresh,
          showSavedProperties: analytics.includeSavedProperties,
        );

      // ── Content — `InfluencerContentManager.tsx` ────────────────────────
      case InfluencerSection.content:
        return DashboardContentBody(
          createLabel: 'Upload Video',
          emptyActionLabel: 'Upload Your First Video',
          onCreate: _onCreate,
          sections: [
            const DashboardSectionLabel('Overview'),
            const SizedBox(height: 10),
            InfluencerStatsWidget(stats: stats),
            const SizedBox(height: 22),
            const DashboardSectionLabel('Quick Actions'),
            const SizedBox(height: 10),
            DashboardCard(
              child: InfluencerQuickActionsWidget(
                onAnalyticsTap: () =>
                    setState(() => _section = InfluencerSection.analytics),
              ),
            ),
            const SizedBox(height: 22),
            const DashboardSectionLabel('My Videos'),
            const SizedBox(height: 10),
            MyVideosSection(userId: auth.userId!),
            const SizedBox(height: 22),
            // An influencer may list properties too — CreateContent.tsx:379-402
            // gives them three create buttons where other roles get two — so this
            // stays.
            const DashboardSectionLabel('My Listings'),
            const SizedBox(height: 10),
            MyListingsSection(userId: auth.userId!),
          ],
        );

      // ── Leads — same unified property_inquiries + property_visit_bookings
      // pair Broker's dashboard already has, scoped to this influencer's own
      // listings via `_properties`. `BrokerVisitBookingsSection` is
      // additionally mounted below the unified list, unchanged itself: it
      // is the only place in the app with the full confirm/reschedule
      // (date+time+status) edit sheet for an incoming booking, and it must
      // stay reachable from Leads now that Visits no longer shows incoming
      // data at all.
      case InfluencerSection.leads:
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

      // ── Visits — requests THIS influencer made on OTHER people's
      // listings. Was `BrokerVisitBookingsSection` fed this influencer's own
      // properties, i.e. the identical incoming data Leads already showed
      // (the root bug this fix addresses) — replaced with the
      // dashboard-shared outgoing widget, backed by the existing
      // `my-visit-requests` endpoint rather than any locally-known property
      // id list.
      case InfluencerSection.visits:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DashboardSectionLabel('Visit Bookings'),
            SizedBox(height: 10),
            OutgoingSiteVisitsSection(),
          ],
        );

      // ── Audience — `InfluencerAudienceInsights.tsx` ─────────────────────
      case InfluencerSection.audience:
        return DashboardAudienceBody(
          audience: analytics.audience,
          loading: analytics.audienceLoading,
          failed: analytics.audienceFailed,
          onRetry: analytics.refresh,
          crossContentLoading: analytics.crossContentLoading,
          crossContentFailed: analytics.crossContentFailed,
          onCrossContentRetry: analytics.retryCrossContentInsights,
          onContentTap: (item) => _openCrossContentItem(context, item),
        );

      // ── Collaboration — `InfluencerCollaborationHub.tsx` ────────────────
      //
      // The portal's fourth tab, which the shared three-tab selector had no room
      // for. Both halves of that component already exist:
      //
      //   pending invitations + accept/reject → NetworkInvitationsSection (Spec F)
      //   accepted collaborations            → NetworkMembershipsSection, the same
      //                                        provider My Networks uses
      //
      // Reused as they are. Nothing new fetches anything.
      case InfluencerSection.collaboration:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Collaboration Invitations'),
            const SizedBox(height: 10),
            NetworkInvitationsSection(
              userId: auth.userId,
              // An accepted invitation becomes a `builder_networks` row, which is
              // what the memberships list below reads.
              onChanged: () => setState(() {}),
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
