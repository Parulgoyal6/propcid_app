// Home screen — reel cover images and the five category shortcuts.
//
// Both of these failed silently rather than loudly, which is why they need
// pinning:
//
//   * a reel card whose `thumbnail_url` is empty rendered a near-white box.
//     `CachedNetworkImage` given `''` never resolves *and* never reaches
//     `errorWidget`, so it sits on the placeholder forever — it looks like a
//     styling choice, not a failure;
//   * the category shortcuts called `onCategoryTap?.call(...)` against a null
//     callback. Every tap was a no-op with no error anywhere.
//
// The filter values pinned below come from the portal's own
// `PropertyCategories.handleCardClick` (`PropertyCategories.tsx:54-59`), read
// from the reference repo at `c:\Users\USER\Desktop\Flutter\propcid`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/models/reel_model.dart';
import 'package:propcid_app/providers/filter_provider.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/screens/home/widgets/property_reels_section.dart';
import 'package:propcid_app/screens/reels/widgets/reel_controller_manager.dart';
import 'package:propcid_app/services/property_service.dart';
import 'package:propcid_app/widgets/category_icon_grid.dart';

/// Stubs the live category-count fetch so these widget tests never touch the
/// network — only the tap/filter behaviour below is under test, not the
/// count badges.
class _FakePropertyService extends PropertyService {
  @override
  Future<Map<String, int>> getCategoryCounts() async => const {};
}

/// One `influencer_videos` row as `ReelsService.getReels` hands it over, with
/// the joined property merged under `_property`.
Map<String, dynamic> _row({
  String? thumbnailUrl,
  List<String>? mediaUrls,
  bool withProperty = true,
}) => {
  'id': 'v-1',
  'title': 'Sea-facing 3BHK',
  'description': '',
  'video_url': 'https://cdn.test/v-1.mp4',
  'thumbnail_url': thumbnailUrl,
  'property_id': withProperty ? 'p-1' : null,
  if (withProperty)
    '_property': <String, dynamic>{
      'price': '2.4 Cr',
      'location': 'Bandra West',
      'media_urls': mediaUrls,
    },
};

class _FakeReels extends ReelsProvider {
  _FakeReels(this._rows);

  final List<ReelModel> _rows;

  @override
  List<ReelModel> get reels => _rows;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // `ReelsProvider`'s constructor self-loads and `FilterProvider` is plain,
    // but both live behind a client that must exist. Nothing here hits a server.
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  group('PropertyModel.parseMediaUrls', () {
    test('is null-safe and drops blank entries', () {
      expect(PropertyModel.parseMediaUrls(null), isEmpty);
      expect(PropertyModel.parseMediaUrls(const <String>[]), isEmpty);
      expect(
        PropertyModel.parseMediaUrls(const ['', '  ', 'https://cdn/a.jpg']),
        ['https://cdn/a.jpg'],
      );
    });
  });

  group('ReelModel.previewImageUrl', () {
    test('prefers the uploader thumbnail when there is one', () {
      final reel = ReelModel.fromSupabase(
        _row(
          thumbnailUrl: 'https://cdn/thumb.jpg',
          mediaUrls: const ['https://cdn/property.jpg'],
        ),
      );
      expect(reel.previewImageUrl, 'https://cdn/thumb.jpg');
    });

    test('falls back to the linked property photo when it is null', () {
      // The common case: `thumbnail_url` is optional at upload, so most rows
      // have none — and this is the whole reason the rail rendered blank.
      final reel = ReelModel.fromSupabase(
        _row(
          mediaUrls: const ['https://cdn/property.jpg', 'https://cdn/b.jpg'],
        ),
      );
      expect(reel.propertyImageUrl, 'https://cdn/property.jpg');
      expect(reel.previewImageUrl, 'https://cdn/property.jpg');
    });

    test('treats an empty-string thumbnail as absent, not as a URL', () {
      // Older rows store '' rather than NULL — the exact value that made
      // CachedNetworkImage hang on its placeholder.
      final reel = ReelModel.fromSupabase(
        _row(thumbnailUrl: '', mediaUrls: const ['https://cdn/property.jpg']),
      );
      expect(reel.previewImageUrl, 'https://cdn/property.jpg');
    });

    test('skips blank media entries rather than returning one', () {
      final reel = ReelModel.fromSupabase(
        _row(mediaUrls: const ['', 'https://cdn/real.jpg']),
      );
      expect(reel.previewImageUrl, 'https://cdn/real.jpg');
    });

    test('is empty when there is neither a thumbnail nor a property', () {
      final reel = ReelModel.fromSupabase(_row(withProperty: false));
      expect(reel.propertyImageUrl, isNull);
      expect(reel.previewImageUrl, '');
    });

    test('is empty when the property carries no photos', () {
      final reel = ReelModel.fromSupabase(_row(mediaUrls: const []));
      expect(reel.previewImageUrl, '');
    });
  });

  group('Property Reels rail', () {
    Future<void> pumpRail(WidgetTester tester, List<ReelModel> reels) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels(reels),
          child: const MaterialApp(
            home: Scaffold(body: PropertyReelsSection()),
          ),
        ),
      );
      await tester.pump();
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    }

    testWidgets('renders an image when a cover is resolvable', (tester) async {
      await pumpRail(tester, [
        ReelModel.fromSupabase(
          _row(mediaUrls: const ['https://cdn/property.jpg']),
        ),
      ]);

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, 'https://cdn/property.jpg');
    });

    testWidgets('renders no image widget at all when there is no cover', (
      tester,
    ) async {
      await pumpRail(tester, [
        ReelModel.fromSupabase(_row(withProperty: false)),
      ]);

      // The bug: an empty imageUrl was still handed to CachedNetworkImage,
      // which then sat on its near-white placeholder forever. It must not be
      // constructed at all.
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    test('the centre card is picked from the scroll offset', () {
      // 130 dp card + 12 dp gap = 142 dp extent, 16 dp leading pad.
      int at(double offset, {double viewport = 400, int count = 10}) =>
          PropertyReelsSection.centreIndexFor(
            offset: offset,
            viewportWidth: viewport,
            itemCount: count,
          );

      // Resting at the start of a 400 dp viewport, the midpoint sits over card 1.
      expect(at(0), 1);
      // Scrolled exactly three cards along, the midpoint moves three along too.
      expect(at(142 * 3), 4);

      // Never leaves the list, whichever way the offset overshoots — a bounce
      // past either end would otherwise index out of range.
      expect(at(-500), 0);
      expect(at(999999), 9);
      expect(at(0, viewport: 60), 0);
    });

    test('an empty rail asks for no window', () {
      // Guards the `_reelCount == 0` short-circuit: without it this would index
      // an empty list the moment the section built before its first fetch.
      expect(
        PropertyReelsSection.centreIndexFor(
          offset: 0,
          viewportWidth: 400,
          itemCount: 0,
        ),
        0,
      );
    });

    test('the full-screen feed is not switched into rail mode', () {
      // The rail shares this manager. `previewMode` changes the playback policy
      // from "one card with audio" to "every card, muted", so the feed's own
      // construction must keep defaulting to off.
      expect(ReelControllerManager().previewMode, isFalse);
      expect(
        ReelControllerManager(windowRadius: 1, previewMode: true).previewMode,
        isTrue,
      );
    });

    testWidgets('a card still opens the reels screen when tapped', (
      tester,
    ) async {
      final pushed = <String?>[];
      await tester.pumpWidget(
        ChangeNotifierProvider<ReelsProvider>.value(
          value: _FakeReels([
            ReelModel.fromSupabase(
              _row(mediaUrls: const ['https://cdn/property.jpg']),
            ),
          ]),
          child: MaterialApp(
            home: const Scaffold(body: PropertyReelsSection()),
            onGenerateRoute: (settings) {
              pushed.add(settings.name);
              return MaterialPageRoute(builder: (_) => const SizedBox());
            },
          ),
        ),
      );
      await tester.pump();
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();

      expect(pushed, contains(AppConstants.reelsScreen));
    });
  });

  group('Category shortcuts', () {
    /// Taps one shortcut and reports the filter state it left behind plus the
    /// routes it pushed.
    Future<(FilterProvider, List<String?>)> tapShortcut(
      WidgetTester tester,
      String label, {
      void Function(FilterProvider)? seed,
    }) async {
      final filters = FilterProvider();
      seed?.call(filters);
      final pushed = <String?>[];

      await tester.pumpWidget(
        ChangeNotifierProvider<FilterProvider>.value(
          value: filters,
          child: MaterialApp(
            home: Scaffold(
              body: CategoryIconGrid(service: _FakePropertyService()),
            ),
            onGenerateRoute: (settings) {
              pushed.add(settings.name);
              return MaterialPageRoute(builder: (_) => const SizedBox());
            },
          ),
        ),
      );

      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      return (filters, pushed);
    }

    testWidgets('renders all five', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<FilterProvider>.value(
          value: FilterProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: CategoryIconGrid(service: _FakePropertyService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final label in const [
        'Land',
        'Residential',
        'Commercial',
        'Rent',
        'For Sale',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('Land filters by category', (tester) async {
      final (filters, pushed) = await tapShortcut(tester, 'Land');
      expect(filters.category, 'land');
      expect(filters.listingType, isNull);
      expect(pushed, contains(AppConstants.searchResultsScreen));
    });

    testWidgets('Residential filters by category', (tester) async {
      final (filters, pushed) = await tapShortcut(tester, 'Residential');
      expect(filters.category, 'residential');
      expect(filters.listingType, isNull);
      expect(pushed, contains(AppConstants.searchResultsScreen));
    });

    testWidgets('Commercial filters by category', (tester) async {
      final (filters, pushed) = await tapShortcut(tester, 'Commercial');
      expect(filters.category, 'commercial');
      expect(pushed, contains(AppConstants.searchResultsScreen));
    });

    testWidgets('Rent filters by listing type', (tester) async {
      final (filters, pushed) = await tapShortcut(tester, 'Rent');
      expect(filters.listingType, 'rent');
      expect(filters.category, isNull);
      expect(pushed, contains(AppConstants.searchResultsScreen));
    });

    testWidgets('For Sale filters by listing type, not category', (
      tester,
    ) async {
      // `PropertyCategories.tsx:55-59` — For Sale sets `property_type=sell`
      // and no category, so a plot listed for sale belongs under it too.
      final (filters, pushed) = await tapShortcut(tester, 'For Sale');
      expect(filters.listingType, 'sell');
      expect(filters.category, isNull);
      expect(pushed, contains(AppConstants.searchResultsScreen));
    });

    testWidgets('a shortcut clears whatever was filtered before it', (
      tester,
    ) async {
      // Commercial, then For Sale. Without the reset the leftover category
      // would survive and "For Sale" would show commercial-only results.
      final (filters, _) = await tapShortcut(
        tester,
        'For Sale',
        seed: (f) {
          f.setCategory('commercial');
          f.setSubtype('Office');
        },
      );

      expect(filters.listingType, 'sell');
      expect(filters.category, isNull);
      expect(filters.subtype, isNull);
    });

    // The four role/project tiles push their own "browse all" screen's
    // route directly — no filter state involved, and no more "coming soon"
    // snackbar now that those screens exist.
    for (final entry in const {
      'Verified Brokers': AppConstants.brokersDirectoryScreen,
      'Builders': AppConstants.buildersDirectoryScreen,
      'Influencers': AppConstants.influencersDirectoryScreen,
      'Premium Projects': AppConstants.latestProjectsScreen,
    }.entries) {
      testWidgets('${entry.key} opens its directory screen, not a snackbar', (
        tester,
      ) async {
        final (_, pushed) = await tapShortcut(tester, entry.key);
        expect(pushed, contains(entry.value));
        expect(find.textContaining('coming soon'), findsNothing);
      });
    }
  });
}
