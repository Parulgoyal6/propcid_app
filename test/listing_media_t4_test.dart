// T4 media-parity guard.
//
// Covers final-architecture-review NEW-5 and Q10:
//   * metadata.mediaCategories must be assembled as existing + new, in the same
//     order as media_urls, and survive an edit;
//   * main_display_media_url must honour the starred photo, falling back to the
//     first — React's dbText(mainDisplayMediaUrl, allMediaUrls[0] ?? '');
//   * land uses a different photo-category set from every other category.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_constants.dart';

/// A listing with three photos, each tagged, as the web would have written it.
Map<String, dynamic> rowWithMedia() => {
      'category': 'residential',
      'property_type': 'sell',
      'title': 'Has photos',
      'media_urls': <String>[
        'https://cdn/a.jpg',
        'https://cdn/b.jpg',
        'https://cdn/c.jpg',
      ],
      'main_display_media_url': 'https://cdn/b.jpg',
      'metadata': <String, dynamic>{
        'mediaCategories': <String>['exterior', 'interior', 'floor_plan'],
      },
    };

/// Mirrors PropertyService: existing categories first, then new ones.
List<String> mediaCategoriesFor(PostPropertyProvider p) => <String>[
      ...p.existingMedia.map((m) => m.category),
      ...p.mediaItems.map((m) => m.category),
    ];

/// Mirrors PropertyService._mainDisplayUrl.
String mainDisplayUrl(PostPropertyProvider p, List<String> allUrls) {
  final starred = p.mainDisplayMediaUrl;
  if (starred.isNotEmpty && allUrls.contains(starred)) return starred;
  return allUrls.isNotEmpty ? allUrls.first : '';
}

void main() {
  late PostPropertyProvider p;

  setUp(() {
    WidgetsFlutterBinding.ensureInitialized();
    p = PostPropertyProvider();
  });

  group('Edit hydration pairs urls with categories by index', () {
    test('each photo keeps the category it was uploaded under', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());

      expect(p.existingMedia.map((m) => m.url).toList(),
          ['https://cdn/a.jpg', 'https://cdn/b.jpg', 'https://cdn/c.jpg']);
      expect(p.existingMedia.map((m) => m.category).toList(),
          ['exterior', 'interior', 'floor_plan']);
    });

    test('missing or short mediaCategories defaults to other', () {
      final row = rowWithMedia();
      (row['metadata'] as Map<String, dynamic>)['mediaCategories'] = ['exterior'];
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: row);

      expect(p.existingMedia.map((m) => m.category).toList(),
          ['exterior', 'other', 'other']);
    });

    test('absent mediaCategories key still yields one ref per url', () {
      final row = rowWithMedia()..['metadata'] = <String, dynamic>{};
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: row);

      expect(p.existingMedia.length, 3);
      expect(p.existingMedia.every((m) => m.category == 'other'), isTrue);
    });

    test('starred main image hydrates', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      expect(p.mainDisplayMediaUrl, 'https://cdn/b.jpg');
    });
  });

  group('mediaCategories stays aligned with media_urls (NEW-5)', () {
    test('existing categories come first, in order', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());

      final urls = [...p.existingMediaUrls, 'https://cdn/new1.jpg'];
      final cats = [...mediaCategoriesFor(p), 'amenities'];

      expect(cats.length, urls.length);
      expect(cats.take(3).toList(), ['exterior', 'interior', 'floor_plan']);
    });

    test('the OLD behaviour would have mislabelled every photo', () {
      // Documents the defect: building the array from new items only produced
      // a list shorter than media_urls, so index 0 of media_urls (an existing
      // photo) took the first NEW photo's category.
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());

      final urls = [...p.existingMediaUrls, 'https://cdn/new1.jpg'];
      final broken = <String>['amenities']; // new items only

      expect(broken.length, isNot(urls.length));
      expect(broken[0], isNot(p.existingMedia[0].category));
    });

    test('removing an existing photo keeps the arrays in step', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      p.removeExistingMedia(1); // drop b.jpg / interior

      expect(p.existingMediaUrls, ['https://cdn/a.jpg', 'https://cdn/c.jpg']);
      expect(mediaCategoriesFor(p), ['exterior', 'floor_plan']);
      expect(mediaCategoriesFor(p).length, p.existingMediaUrls.length);
    });

    test('re-tagging an existing photo does not reorder it', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      p.setExistingMediaCategory(0, 'amenities');

      expect(p.existingMediaUrls.first, 'https://cdn/a.jpg');
      expect(mediaCategoriesFor(p), ['amenities', 'interior', 'floor_plan']);
    });
  });

  group('main_display_media_url', () {
    test('honours the starred photo', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      expect(mainDisplayUrl(p, p.existingMediaUrls), 'https://cdn/b.jpg');
    });

    test('falls back to the first photo when nothing is starred', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      p.setMainDisplayMediaUrl('');
      expect(mainDisplayUrl(p, p.existingMediaUrls), 'https://cdn/a.jpg');
    });

    test('a starred photo that was removed falls back rather than dangling', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      p.removeExistingMedia(1); // b.jpg was the starred one

      expect(p.mainDisplayMediaUrl, isEmpty, reason: 'star cleared on removal');
      expect(mainDisplayUrl(p, p.existingMediaUrls), 'https://cdn/a.jpg');
    });

    test('empty string, never null, when there are no photos at all', () {
      expect(mainDisplayUrl(p, const <String>[]), '');
    });

    test('a stale starred url not in the list is ignored', () {
      p.setMainDisplayMediaUrl('https://cdn/gone.jpg');
      expect(mainDisplayUrl(p, ['https://cdn/a.jpg']), 'https://cdn/a.jpg');
    });
  });

  group('Photo category sets', () {
    test('default set matches React, including property_video', () {
      // Flutter previously omitted property_video entirely (review A4).
      expect(kDefaultImageCategories.map((c) => c.id).toList(), [
        'interior', 'exterior', 'amenities', 'floor_plan', 'property_video',
        'other',
      ]);
    });

    test('land uses a different set entirely', () {
      expect(kLandImageCategories.map((c) => c.id).toList(),
          ['sajra', 'land_video', 'land_images', 'other']);
      expect(kLandImageCategories.map((c) => c.id),
          isNot(contains('interior')));
    });

    test('the two sets only overlap on other', () {
      final d = kDefaultImageCategories.map((c) => c.id).toSet();
      final l = kLandImageCategories.map((c) => c.id).toSet();
      expect(d.intersection(l), {'other'});
    });
  });

  group('Reset', () {
    test('clears existing media and the star', () {
      p.initFromRawData(editingPropertyId: 'p1', propertyRow: rowWithMedia());
      expect(p.existingMedia, isNotEmpty);

      p.reset();
      expect(p.existingMedia, isEmpty);
      expect(p.mainDisplayMediaUrl, isEmpty);
    });
  });
}
