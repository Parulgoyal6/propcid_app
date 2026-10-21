// Home scroll-performance pass — regression tests for the surgical fix.
//
// What broke silently before this pass, and what these pin instead:
//
//   * every section wrapped in `ScrollReveal`/`flutter_animate` re-ran its
//     entrance animation and re-measured its render box on every scroll
//     frame — removed outright, so the section order below must be exactly
//     what `home_screen.dart` renders, unwrapped;
//   * the Home reels rail auto-scrolled itself via a 40ms `Timer.periodic`
//     for as long as the (keep-alive) widget existed, whether or not it was
//     ever on screen — replaced with purely manual dragging and a single
//     debounced, cancellable `Timer`;
//   * data-backed sections (`late final Future<...>`) lost their fetched
//     data and re-queried the moment they scrolled outside the sliver
//     list's cache extent — `AutomaticKeepAliveClientMixin` now keeps their
//     State alive for as long as Home itself is mounted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/city_roi.dart';
import 'package:propcid_app/models/reel_model.dart';
import 'package:propcid_app/providers/compare_provider.dart';
import 'package:propcid_app/providers/filter_provider.dart';
import 'package:propcid_app/providers/navigation_provider.dart';
import 'package:propcid_app/providers/notification_provider.dart';
import 'package:propcid_app/providers/property_provider.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/screens/home/home_screen.dart';
import 'package:propcid_app/screens/home/widgets/budget_section.dart';
import 'package:propcid_app/screens/home/widgets/city_roi_section.dart';
import 'package:propcid_app/screens/home/widgets/featured_projects_section.dart';
import 'package:propcid_app/screens/home/widgets/featured_properties_section.dart';
import 'package:propcid_app/screens/home/widgets/hero_banner_section.dart';
import 'package:propcid_app/screens/home/widgets/investors_corner_section.dart';
import 'package:propcid_app/screens/home/widgets/latest_articles_section.dart';
import 'package:propcid_app/screens/home/widgets/latest_projects_section.dart';
import 'package:propcid_app/screens/home/widgets/news_section.dart';
import 'package:propcid_app/screens/home/widgets/popular_agents_section.dart';
import 'package:propcid_app/screens/home/widgets/premium_search_section.dart';
import 'package:propcid_app/screens/home/widgets/property_rail_section.dart';
import 'package:propcid_app/screens/home/widgets/property_reels_section.dart';
import 'package:propcid_app/screens/home/widgets/property_verification_section.dart';
import 'package:propcid_app/screens/home/widgets/quick_actions_section.dart';
import 'package:propcid_app/screens/home/widgets/smart_tools_section.dart';
import 'package:propcid_app/screens/home/widgets/tell_your_needs_section.dart';
import 'package:propcid_app/screens/home/widgets/top_builders_section.dart';
import 'package:propcid_app/screens/home/widgets/trending_cities_section.dart';
import 'package:propcid_app/screens/home/widgets/trending_section.dart';
import 'package:propcid_app/services/city_roi_service.dart';
import 'package:propcid_app/widgets/category_icon_grid.dart';
import 'package:propcid_app/widgets/premium_launch_bottom_sheet.dart';

/// Exactly `home_screen.dart`'s own `sections` list, spacers left out —
/// this is the order that must survive removing every `ScrollReveal` wrapper.
const List<Type> kExpectedHomeSectionOrder = [
  PremiumSearchSection,
  HeroBannerSection,
  QuickActionsSection,
  CategoryIconGrid,
  TrendingCitiesSection,
  PropertyVerificationSection,
  PropertyReelsSection,
  LatestArticlesSection,
  FeaturedProjectsSection,
  FeaturedPropertiesSection,
  NewsSection,
  TopBuildersSection,
  PropertyRailSection,
  LatestProjectsSection,
  PopularBrokersSection,
  PopularInfluencersSection,
  TrendingSection,
  TellYourNeedsSection,
  SmartToolsSection,
  InvestorsCornerSection,
  CityRoiSection,
  BudgetSection,
];

/// One `influencer_videos` row, same shape `ReelsService.getReels` hands over.
Map<String, dynamic> _reelRow({String id = 'v-1', List<String>? mediaUrls}) => {
  'id': id,
  'title': 'Sea-facing 3BHK',
  'description': '',
  'video_url': 'https://cdn.test/$id.mp4',
  'thumbnail_url': null,
  'property_id': 'p-1',
  '_property': <String, dynamic>{
    'price': '2.4 Cr',
    'location': 'Bandra West',
    'media_urls': mediaUrls ?? const ['https://cdn/property.jpg'],
  },
};

class _FakeReels extends ReelsProvider {
  _FakeReels(this._rows);

  final List<ReelModel> _rows;

  @override
  List<ReelModel> get reels => _rows;
}

/// Counts calls so the keep-alive fix can be checked directly: scrolling this
/// rail away and back must not increment [calls] a second time.
class _CountingCityRoiService extends CityRoiService {
  int calls = 0;

  @override
  Future<List<CityRoi>> listActive({int limit = 10}) async {
    calls++;
    return const [
      CityRoi(id: 'c-1', cityName: 'Pune', roiPercentage: 8.4, displayOrder: 0),
    ];
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() {
    // Irrelevant to this pass and would otherwise cover the very content
    // these tests inspect — every test in this file gets a clean skip.
    LaunchOfferSessionGate.markShown();
  });

  Widget pumpableHome() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => FilterProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => CompareProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ReelsProvider()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  group('Home section order', () {
    testWidgets('renders every section in the same order, unwrapped', (
      tester,
    ) async {
      // Wide enough that `PremiumSearchSection`'s unwrapped heading Row never
      // overflows on the fallback font widget tests render with (Google
      // Fonts has no network access here), and tall enough that the whole
      // feed is within the sliver list's build range on a single frame — no
      // scrolling needed to see every section.
      tester.view.physicalSize = const Size(800, 20000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pumpableHome());
      await tester.pump();

      final found = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) => kExpectedHomeSectionOrder.contains(w.runtimeType),
            ),
          )
          .map((w) => w.runtimeType)
          .toList();

      expect(found, kExpectedHomeSectionOrder);
    });
  });

  group('Home scroll gestures', () {
    testWidgets('scrolling all the way down and back up throws nothing', (
      tester,
    ) async {
      // See the width note on the section-order test above.
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(pumpableHome());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final feed = find.byType(CustomScrollView);
      expect(feed, findsOneWidget);

      for (var i = 0; i < 15; i++) {
        await tester.drag(feed, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);

      for (var i = 0; i < 15; i++) {
        await tester.drag(feed, const Offset(0, 600));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Keep-alive prevents refetch', () {
    testWidgets(
      'a data-backed section does not re-query after scrolling away and back',
      (tester) async {
        final service = _CountingCityRoiService();
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 3000),
                      CityRoiSection(service: service),
                      const SizedBox(height: 3000),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        // Scrolls the section into view for the first time — a
        // `SliverList` never builds a child that sits outside the initial
        // viewport, so this is what actually creates its State and fires
        // its Future.
        controller.jumpTo(3000);
        await tester.pumpAndSettle();
        expect(service.calls, 1);

        // Back out of view, far enough past the sliver's default cache
        // extent that without AutomaticKeepAliveClientMixin its State would
        // be disposed here...
        controller.jumpTo(0);
        await tester.pump();
        // ...then back again.
        controller.jumpTo(3000);
        await tester.pumpAndSettle();

        expect(
          service.calls,
          1,
          reason:
              'AutomaticKeepAliveClientMixin must preserve the loaded Future '
              'instead of the section re-querying on the way back',
        );
      },
    );
  });

  group('Property Reels rail — manual scrolling and navigation', () {
    Future<void> pumpRail(
      WidgetTester tester,
      List<ReelModel> reels, {
      RouteFactory? onGenerateRoute,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels(reels),
          child: MaterialApp(
            home: const Scaffold(body: PropertyReelsSection()),
            onGenerateRoute: onGenerateRoute,
          ),
        ),
      );
      await tester.pump();
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    }

    testWidgets('manual horizontal dragging still moves the rail', (
      tester,
    ) async {
      final reels = List.generate(
        8,
        (i) => ReelModel.fromSupabase(_reelRow(id: 'v-$i')),
      );
      await pumpRail(tester, reels);

      final scrollable = find.descendant(
        of: find.byType(PropertyReelsSection),
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.pixels, 0);

      await tester.drag(scrollable, const Offset(-300, 0));
      await tester.pump();

      expect(state.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('"See all" opens the same route a card tap does', (
      tester,
    ) async {
      final pushed = <String?>[];
      await pumpRail(
        tester,
        [ReelModel.fromSupabase(_reelRow())],
        onGenerateRoute: (settings) {
          pushed.add(settings.name);
          return MaterialPageRoute(builder: (_) => const SizedBox());
        },
      );

      await tester.tap(find.text('See all ›'));
      await tester.pump();

      expect(pushed, contains(AppConstants.reelsScreen));
    });

    testWidgets('disposing the rail leaves no pending timer behind', (
      tester,
    ) async {
      final reels = [ReelModel.fromSupabase(_reelRow())];
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels(reels),
          child: const MaterialApp(
            home: Scaffold(body: PropertyReelsSection()),
          ),
        ),
      );
      await tester.pump();

      // Nudges the rail so it schedules its debounced window-sync `Timer`,
      // then tears the whole tree down before that timer would fire. The
      // 40ms `Timer.periodic` this pass removed would leave one running here.
      final scrollable = find.descendant(
        of: find.byType(PropertyReelsSection),
        matching: find.byType(Scrollable),
      );
      await tester.drag(scrollable, const Offset(-200, 0));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      // A Timer still pending at this point fails the test automatically.
    });
  });
}
