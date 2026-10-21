// Feature 1 — "Most Liked Content" navigation.
//
// `crossContentPushRoute` is the pure decision `InfluencerDashboardScreen
// ._openCrossContentItem` defers to for the two content types with a named
// route: a reel id must never be sent as `propertyId`, and a property id
// must never be sent as `reelId` — exactly the mistake a single shared
// route would make. Article has no named route (see the app's article
// bottom-sheet reader) and is asserted to fall through to null, which is
// `_openCrossContentItem`'s own signal to fetch and show that sheet instead.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/screens/dashboard/influencer_dashboard_screen.dart';

void main() {
  test('a property item routes to propertyDetailScreen with propertyId', () {
    const item = CrossContentItem(
      id: 'prop-9',
      type: CrossContentType.property,
      title: 'A property',
    );

    final route = crossContentPushRoute(item);

    expect(route, isNotNull);
    expect(route!.name, AppConstants.propertyDetailScreen);
    expect(route.arguments, {'propertyId': 'prop-9'});
    expect(route.arguments.containsKey('reelId'), isFalse);
  });

  test('a reel item routes to reelsScreen with reelId', () {
    const item = CrossContentItem(
      id: 'reel-3',
      type: CrossContentType.reel,
      title: 'A reel',
    );

    final route = crossContentPushRoute(item);

    expect(route, isNotNull);
    expect(route!.name, AppConstants.reelsScreen);
    expect(route.arguments, {'reelId': 'reel-3'});
    expect(route.arguments.containsKey('propertyId'), isFalse);
  });

  test(
    'an article item has no named route — the caller must fetch and show the sheet',
    () {
      const item = CrossContentItem(
        id: 'article-5',
        type: CrossContentType.article,
        title: 'An article',
      );

      expect(crossContentPushRoute(item), isNull);
    },
  );

  test('a reel id is never mistaken for a property id, or vice versa', () {
    // The failure mode this whole function exists to prevent: two items
    // that share nothing but an id string must never resolve to the same
    // route+argument pair.
    const sharedId = 'x-1';
    final propertyRoute = crossContentPushRoute(
      const CrossContentItem(
        id: sharedId,
        type: CrossContentType.property,
        title: 'p',
      ),
    )!;
    final reelRoute = crossContentPushRoute(
      const CrossContentItem(
        id: sharedId,
        type: CrossContentType.reel,
        title: 'r',
      ),
    )!;

    expect(propertyRoute.name, isNot(reelRoute.name));
    expect(propertyRoute.arguments, isNot(reelRoute.arguments));
  });
}
