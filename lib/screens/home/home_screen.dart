import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/app_glass_backdrop.dart';
import '../../providers/navigation_provider.dart';
import '../../services/in_app_update_service.dart';
import '../../widgets/category_icon_grid.dart';
import '../../widgets/bottom_nav_bar.dart';
import '../../widgets/premium_launch_bottom_sheet.dart';
import 'widgets/home_header.dart';
import 'widgets/premium_search_section.dart';
import 'widgets/quick_actions_section.dart';
import 'widgets/hero_banner_section.dart';
import 'widgets/property_reels_section.dart';
import 'widgets/featured_properties_section.dart';
import 'widgets/trending_section.dart';
import 'widgets/budget_section.dart';
import 'widgets/property_rail_section.dart';
import 'widgets/property_verification_section.dart';
import 'widgets/news_section.dart';
import 'widgets/tell_your_needs_section.dart';
import 'widgets/smart_tools_section.dart';
import 'widgets/trending_cities_section.dart';
import 'widgets/latest_articles_section.dart';
import 'widgets/popular_agents_section.dart';
import 'widgets/featured_projects_section.dart';
import 'widgets/latest_projects_section.dart';
import 'widgets/top_builders_section.dart';
import 'widgets/investors_corner_section.dart';
import 'widgets/city_roi_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<NavigationProvider>(context, listen: false).setIndex(0);
        PremiumLaunchBottomSheet.showOnce(context);
        // Fire-and-forget: Android-only, silently no-ops if there's no
        // update, no Play Store (flutter run / sideloaded APK), or the user
        // declines — see InAppUpdateService's own doc comment.
        unawaited(InAppUpdateService.checkOnce(context));
      }
    });
  }

  // Every rail below is a pure client-side slice/sort of the properties
  // already loaded by PropertyProvider — no new queries. Thresholds/proxies
  // are documented alongside each selector since PropertyModel has no
  // dedicated isLuxury/isNewLaunch/isInvestment flags to read instead.
  //
  // Spacing between sections is deliberately uneven — tight near the top
  // (Hero/Reels feel immediate), calmer and more generous the deeper the
  // page goes (New Launches/Investment) — plain vertical rhythm rather than
  // one flat gap repeated between every section.

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      const SizedBox(height: 6),
      const PremiumSearchSection(),
      const SizedBox(height: 18),

      // Hero Banner bleeds its own gradient tail into the page, so it needs
      // almost no gap after it.
      const HeroBannerSection(),
      const SizedBox(height: 6),

      const QuickActionsSection(),
      const SizedBox(height: 18),

      const CategoryIconGrid(),
      const SizedBox(height: 18),

      // Trending Cities — mirrors the web home page's position for this rail,
      // right after the category tiles. Renders nothing (no trailing gap
      // left behind either) when the admin table has no active cities; see
      // TrendingCitiesSection's own bottom padding.
      const TrendingCitiesSection(),

      // Property Verification — one of the first "do something" moments on the
      // page, mirroring its high position on the web home page.
      const PropertyVerificationSection(),
      const SizedBox(height: 24),

      const PropertyReelsSection(),
      const SizedBox(height: 4),

      // Latest Articles. Same "renders nothing, owns its own trailing gap"
      // convention as Latest News below — see LatestArticlesSection.
      const LatestArticlesSection(),

      const SizedBox(height: 24),

      // Featured Projects (builder_projects, via the admin-curated
      // `featured_projects` table) sits directly before Featured Properties
      // (properties, via `hot_properties`) — the same order the web home
      // page uses for its "Featured Projects" / "Hot Properties" pair. Kept
      // as two separate sections/queries/cards on purpose: projects and
      // properties are different entities ([ProjectModel] vs
      // [PropertyModel]) and must never be shown as if they were the same
      // list.
      const FeaturedProjectsSection(),
      const FeaturedPropertiesSection(),
      const SizedBox(height: 24),

      // Latest News. Renders nothing at all — not even its header — when the
      // `news` table has no active rows, so it carries its own trailing 24 dp
      // internally; a spacer entry here would outlive the section and leave a
      // hole in the feed. See `_kNewsBottomGap`.
      const NewsSection(),

      // Top Builders — mirrors the web home page's sidebar position, right
      // after Latest News.
      const TopBuildersSection(),

      // "New Listings" — individual property listings, newest first. This is
      // deliberately titled differently from the section below: it renders
      // `properties` rows, not `builder_projects` rows, and the two used to
      // share the title "Latest Projects" while showing entirely different
      // data — exactly the property/project conflation this pass fixes.
      PropertyRailSection(
        title: 'New Listings',
        showWhenEmpty: true,
        emptyMessage: 'No properties listed yet',
        selector: (all) {
          final newest = List.of(all)
            ..sort(
              (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                a.createdAt ?? DateTime(0),
              ),
            );
          return newest.take(8).toList();
        },
      ),
      const SizedBox(height: 24),

      // The genuine "Latest Projects" rail — `builder_projects`, not
      // `properties`. Sits right after New Listings, mirroring the web home
      // page's Latest-Projects-in-city → Top Brokers → Top Influencers order.
      const LatestProjectsSection(),

      // Popular Brokers / Popular Influencers — mirrors the web home page's
      // "Top Brokers" / "Top Influencers" position, right after the latest
      // listings. Each renders nothing (and owns its own trailing gap) when
      // there are no matching approved profiles.
      const PopularBrokersSection(),
      const PopularInfluencersSection(),

      const TrendingSection(),
      const SizedBox(height: 24),

      // Tell Your Needs — mid-page, after the main listings content, mirroring
      // where the web home page sits its lead form.
      const TellYourNeedsSection(),
      const SizedBox(height: 28),

      const SmartToolsSection(),
      const SizedBox(height: 28),

      // Investor's Corner, then City ROI Index — mirrors the web home
      // page's order right after its "Useful Tools" block. Each renders
      // nothing when the admin table has no active rows.
      const InvestorsCornerSection(),
      const CityRoiSection(),

      const BudgetSection(),
      const SizedBox(height: 100),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen, fixed (non-scrolling) backdrop behind the whole
          // page — the glassmorphism header/search/quick-actions above sit
          // on top of it, and it also shows faintly through the gaps
          // between the ordinary opaque section cards further down the
          // scroll, without any of those ~20 other sections needing to
          // change. (The header needs this: its `GlassCard` is a real
          // translucent blur, which reads as flat, pointless glass with
          // nothing but plain background behind it — this backdrop is what
          // that glass is actually showing through.)
          const AppGlassBackdrop(),
          SafeArea(
            child: Column(
              children: [
                const HomeHeader(),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => sections[index],
                          childCount: sections.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 0),
    );
  }
}
