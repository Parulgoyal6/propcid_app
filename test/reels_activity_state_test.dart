// Listing-video reel Like/Save state — disagreement between the player,
// property screens and My Activity.
//
// Root cause fixed here: a listing-video reel's `id` is the same as its
// underlying property's `id` (ReelModel.isPropertyVideo's doc), and its
// like/save is recorded via `user_likes.property_id`/`saved_properties`
// (through PropertyProvider), never through this reel's own
// `user_likes.reel_id`/`saved_reels` row. But `ReelsProvider.getLikedReels`/
// `getSavedReels` — which back My Activity's "Reels" filter — checked only
// this provider's own `_likedIds`/`_savedIds` (backed by the reel-id tables),
// so a liked/saved listing-video reel could never appear there, no matter
// how many times it was liked via the player or the property detail screen.
//
// Fixed by branching on `ReelModel.isPropertyVideo`: a property-video reel's
// state now comes from the caller-supplied `likedPropertyIds`/
// `shortlistedPropertyIds` (PropertyProvider's real state); every other
// (influencer) reel keeps checking this provider's own id sets, unchanged.
//
// A second, related fix: `my_activity_section.dart` must not also count that
// same property in the plain Properties list once it's reclassified into
// Reels — `excludePropertyVideoListings` is the pure filter that prevents
// the duplicate entry/inflated header total.
//
// Neither fix touches `ReelsProvider`/`PropertyProvider`'s network layer —
// both are exercised here as pure functions with hand-built fixtures, the
// same boundary this suite's other provider-adjacent tests draw (neither
// provider accepts an injected client).
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/models/reel_model.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/screens/profile/widgets/my_activity_section.dart';

ReelModel _influencerReel(String id) => ReelModel(
  id: id,
  title: 'Influencer reel $id',
  description: '',
  videoUrl: 'https://example.com/$id.mp4',
);

ReelModel _propertyVideoReel(String id) => ReelModel(
  id: id,
  title: 'Listing video $id',
  description: '',
  videoUrl: 'https://example.com/$id.mp4',
  propertyId: id,
  isPropertyVideo: true,
);

PropertyModel _property(String id) => PropertyModel(
  id: id,
  title: 'Property $id',
  locality: '',
  city: '',
  price: 0,
  priceDisplay: '',
  pricePerSqft: '',
  beds: 0,
  baths: 0,
  sqft: 0,
  parking: 0,
  isVerified: false,
  isFeatured: false,
  isShortlisted: false,
  photoCount: 0,
  statusTags: const [],
  amenities: const [],
  nearbyPlaces: const [],
  description: '',
  imageUrl: '',
  builderName: '',
);

void main() {
  group('ReelsProvider.selectByLikedState', () {
    test('a liked listing-video reel is included via likedPropertyIds, not '
        'this provider\'s own reel-id set — the exact bug: it never appeared '
        'here before', () {
      final reels = [_propertyVideoReel('p1'), _influencerReel('r1')];

      final result = ReelsProvider.selectByLikedState(
        reels: reels,
        likedReelIds: const {}, // never populated for a property-video
        likedPropertyIds: {'p1'}, // liked via PropertyProvider
      );

      expect(result.map((r) => r.id), ['p1']);
    });

    test('an influencer reel keeps checking this provider\'s own liked-reel '
        'ids, unchanged', () {
      final reels = [_influencerReel('r1'), _influencerReel('r2')];

      final result = ReelsProvider.selectByLikedState(
        reels: reels,
        likedReelIds: {'r1'},
        likedPropertyIds: const {'r1'}, // must be ignored for this reel
      );

      expect(result.map((r) => r.id), ['r1']);
    });

    test('a property-video reel not actually liked is excluded, even if its '
        'id happens to sit in the (irrelevant) reel-id set', () {
      final reels = [_propertyVideoReel('p1')];

      final result = ReelsProvider.selectByLikedState(
        reels: reels,
        likedReelIds: {'p1'}, // must be ignored for a property-video
        likedPropertyIds: const {},
      );

      expect(result, isEmpty);
    });

    test(
      'the default (no propertyIds passed) never includes a property-video '
      'reel — pre-existing behaviour for any caller that does not opt in',
      () {
        final reels = [_propertyVideoReel('p1'), _influencerReel('r1')];

        final result = ReelsProvider.selectByLikedState(
          reels: reels,
          likedReelIds: {'p1', 'r1'},
          likedPropertyIds: const {},
        );

        expect(result.map((r) => r.id), ['r1']);
      },
    );
  });

  group('ReelsProvider.selectBySavedState', () {
    test(
      'a saved listing-video reel is included via shortlistedPropertyIds',
      () {
        final reels = [_propertyVideoReel('p1'), _influencerReel('r1')];

        final result = ReelsProvider.selectBySavedState(
          reels: reels,
          savedReelIds: const {},
          shortlistedPropertyIds: {'p1'},
        );

        expect(result.map((r) => r.id), ['p1']);
      },
    );

    test('an influencer reel keeps checking this provider\'s own saved-reel '
        'ids, unchanged', () {
      final reels = [_influencerReel('r1')];

      final result = ReelsProvider.selectBySavedState(
        reels: reels,
        savedReelIds: {'r1'},
        shortlistedPropertyIds: const {},
      );

      expect(result.map((r) => r.id), ['r1']);
    });
  });

  group('excludePropertyVideoListings', () {
    test('drops a property that is also a listing-video reel — prevents a '
        'duplicate entry across the Properties and Reels filters', () {
      final properties = [_property('p1'), _property('p2')];

      final result = excludePropertyVideoListings(properties, {'p1'});

      expect(result.map((p) => p.id), ['p2']);
    });

    test('keeps every property when none is a listing-video reel', () {
      final properties = [_property('p1'), _property('p2')];

      final result = excludePropertyVideoListings(properties, const {});

      expect(result.map((p) => p.id), ['p1', 'p2']);
    });

    test('an empty property list stays empty', () {
      expect(excludePropertyVideoListings(const [], {'p1'}), isEmpty);
    });
  });
}
