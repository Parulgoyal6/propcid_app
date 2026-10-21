// Pins the fix for "project public cards: comment count not updating" —
// `FeedItem.fromProject` previously never set `comments` at all (it
// defaulted to 0 regardless of the real value), because `FeedService`'s own
// `builder_projects` select omitted the column entirely. Both halves are
// pinned here: the model actually reading the field once present, and
// (separately, in feed_service_test.dart-less fashion — no network layer to
// fake here) that a property row's parsing — which already worked — is
// unaffected by the same change.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/feed_item.dart';

void main() {
  group('FeedItem.fromProject', () {
    test('reads comments off the row, the same as fromProperty already did', () {
      final item = FeedItem.fromProject({
        'id': 'proj-1',
        'title': 'Skyline Towers',
        'location': 'Pune',
        'media_urls': <String>[],
        'builder_id': 'b-1',
        'created_at': '2026-01-01T00:00:00Z',
        'views': 10,
        'likes': 2,
        'comments': 7,
      }, null);

      expect(item.comments, 7);
    });

    test('a row with no comments column at all defaults to 0, not a crash', () {
      final item = FeedItem.fromProject({
        'id': 'proj-2',
        'title': 'Green Valley',
        'location': 'Mumbai',
        'media_urls': <String>[],
        'builder_id': 'b-1',
        'created_at': '2026-01-01T00:00:00Z',
        'views': 0,
        'likes': 0,
      }, null);

      expect(item.comments, 0);
    });

    test('a string-typed count (as PostgREST sometimes serves one) still parses', () {
      final item = FeedItem.fromProject({
        'id': 'proj-3',
        'title': 'Lakeview Residency',
        'location': 'Nashik',
        'media_urls': <String>[],
        'builder_id': 'b-1',
        'created_at': '2026-01-01T00:00:00Z',
        'views': 0,
        'likes': 0,
        'comments': '12',
      }, null);

      expect(item.comments, 12);
    });
  });

  group('FeedItem.fromProperty — unaffected by the project-side fix', () {
    test('still reads comments exactly as before', () {
      final item = FeedItem.fromProperty({
        'id': 'prop-1',
        'title': 'Sea View 3BHK',
        'price': '9500000',
        'location': 'Bandra',
        'media_urls': <String>[],
        'user_id': 'u-1',
        'created_at': '2026-01-01T00:00:00Z',
        'views': 5,
        'likes': 1,
        'comments': 3,
      }, null);

      expect(item.comments, 3);
    });
  });
}
