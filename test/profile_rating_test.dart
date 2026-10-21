// Phase 5 — rating write path.
//
// `ProfileRatingService` is a companion: `RatingsService` stays read-only and
// untouched, as it has since Phase 1.
//
// What is asserted is the client's half of the contract with RLS and the unique
// index. The database already refuses a self-rating
// (`auth.uid() <> rated_user_id`) and a duplicate (`unique (rated_user_id,
// rater_id)`), so the guards here are about not making a round-trip that can only
// fail, and about turning a `23505` into a message a user can act on.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/builder_project_model.dart';
import 'package:propcid_app/models/profile_review.dart';
import 'package:propcid_app/models/property_model.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/public_profile_provider.dart';
import 'package:propcid_app/services/network_service.dart';
import 'package:propcid_app/services/profile_connection_service.dart';
import 'package:propcid_app/services/profile_content_service.dart';
import 'package:propcid_app/services/profile_rating_service.dart';
import 'package:propcid_app/services/profile_view_service.dart';
import 'package:propcid_app/services/user_profile_service.dart';

class _FakeProfileService extends UserProfileService {
  _FakeProfileService(this.profile);
  final UserProfile? profile;

  @override
  Future<UserProfile?> fetchOwn(String userId) async => profile;

  @override
  Future<UserProfile?> fetchPublic(
    String userId, {
    required bool viewerSignedIn,
  }) async =>
      profile;
}

class _FakeContentService extends ProfileContentService {
  int ratingFetches = 0;

  @override
  Future<List<PropertyModel>> fetchProperties(String userId) async => const [];

  @override
  Future<List<BuilderProjectModel>> fetchBuilderProjects(
    String builderId, {
    required bool viewerIsOwner,
  }) async =>
      const [];

  @override
  Future<RatingBreakdown> fetchRatings(String userId) async {
    ratingFetches++;
    return RatingBreakdown.zero;
  }
}

class _FakeConnectionService extends ProfileConnectionService {
  @override
  Future<ProfileConnectionStatus> getStatus({
    required String? viewerId,
    required String profileUserId,
  }) async =>
      ProfileConnectionStatus.none;
}

class _FakeNetworkService extends NetworkService {
  @override
  Future<int> getAcceptedCount(String userId) async => 0;
}

class _FakeViewService extends ProfileViewService {
  @override
  Future<void> recordView({
    required String? viewerId,
    required String profileUserId,
  }) async {}
}

/// Records calls and returns a scripted outcome.
class _FakeRatingService extends ProfileRatingService {
  _FakeRatingService({this.existing, this.error});

  MyRating? existing;
  RatingWriteError? error;

  int inserts = 0;
  int updates = 0;
  int? lastRating;
  String? lastReview;
  String? lastRatingId;

  @override
  Future<MyRating?> fetchMyRating({
    required String? viewerId,
    required String ratedUserId,
  }) async =>
      existing;

  @override
  Future<RatingWriteError?> submitRating({
    required String? viewerId,
    required String ratedUserId,
    required int rating,
    String? review,
  }) async {
    inserts++;
    lastRating = rating;
    lastReview = review;
    return error;
  }

  @override
  Future<RatingWriteError?> updateRating({
    required String? viewerId,
    required String ratedUserId,
    required String ratingId,
    required int rating,
    String? review,
  }) async {
    updates++;
    lastRating = rating;
    lastReview = review;
    lastRatingId = ratingId;
    return error;
  }
}

UserProfile _row({String userId = 'owner', String role = 'broker'}) =>
    UserProfile.fromMap({
      'user_id': userId,
      'display_name': 'Asha Menon',
      'user_type': role,
    });

Future<PublicProfileProvider> _provider({
  required String? viewerId,
  required _FakeRatingService rating,
  String ownerId = 'owner',
  _FakeContentService? content,
}) async {
  final provider = PublicProfileProvider(
    profileService: _FakeProfileService(_row(userId: ownerId)),
    contentService: content ?? _FakeContentService(),
    connectionService: _FakeConnectionService(),
    networkService: _FakeNetworkService(),
    profileViewService: _FakeViewService(),
    ratingService: rating,
  );
  await provider.load(userId: ownerId, viewerId: viewerId);
  return provider;
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

  group('guard — writes that could only fail are not attempted', () {
    test('a self-rating is refused', () {
      expect(
        ProfileRatingService.guardFor(
          viewerId: 'me',
          ratedUserId: 'me',
          rating: 5,
        ),
        RatingWriteError.notAllowed,
      );
    });

    test('an anonymous viewer is refused', () {
      for (final viewer in [null, '']) {
        expect(
          ProfileRatingService.guardFor(
            viewerId: viewer,
            ratedUserId: 'owner',
            rating: 5,
          ),
          RatingWriteError.notAllowed,
        );
      }
    });

    test('a rating outside 1..5 is refused', () {
      for (final value in [0, -1, 6, 99]) {
        expect(
          ProfileRatingService.guardFor(
            viewerId: 'me',
            ratedUserId: 'owner',
            rating: value,
          ),
          RatingWriteError.failed,
          reason: '$value',
        );
      }
    });

    test('a legitimate write passes', () {
      for (final value in [1, 2, 3, 4, 5]) {
        expect(
          ProfileRatingService.guardFor(
            viewerId: 'me',
            ratedUserId: 'owner',
            rating: value,
          ),
          isNull,
          reason: '$value',
        );
      }
    });
  });

  group('review normalisation', () {
    test('blank and whitespace become null, not an empty string', () {
      // The portal stores `review.trim() || null` and its review list filters on
      // `review is not null` — an empty string would render a card with no words.
      for (final input in [null, '', '   ', '\n\t']) {
        expect(ProfileRatingService.normaliseReview(input), isNull,
            reason: '"$input"');
      }
    });

    test('text is trimmed', () {
      expect(ProfileRatingService.normaliseReview('  good  '), 'good');
    });

    test('text is capped at the portal\'s 500 characters', () {
      final long = 'x' * 600;
      final result = ProfileRatingService.normaliseReview(long);
      expect(result!.length, ProfileRatingService.maxReviewLength);
      expect(ProfileRatingService.maxReviewLength, 500);
    });

    test('exactly 500 is kept whole', () {
      final exact = 'y' * 500;
      expect(ProfileRatingService.normaliseReview(exact)!.length, 500);
    });
  });

  group('provider chooses insert vs update', () {
    test('no existing rating inserts', () async {
      final rating = _FakeRatingService();
      final p = await _provider(viewerId: 'me', rating: rating);

      expect(p.myRating, isNull);
      expect(await p.submitRating(rating: 4, review: 'Solid'), isNull);
      expect(rating.inserts, 1);
      expect(rating.updates, 0);
      expect(rating.lastRating, 4);
      expect(rating.lastReview, 'Solid');
    });

    test('an existing rating updates, carrying its row id', () async {
      final rating = _FakeRatingService(
        existing: const MyRating(id: 'r-9', rating: 3, review: 'Was ok'),
      );
      final p = await _provider(viewerId: 'me', rating: rating);

      expect(p.myRating, isNotNull);
      expect(await p.submitRating(rating: 5, review: 'Better now'), isNull);
      expect(rating.updates, 1);
      expect(rating.inserts, 0);
      expect(rating.lastRatingId, 'r-9');
    });

    test('aggregates are re-read after a successful write', () async {
      // Otherwise the summary, the distribution and the review list would all
      // still show the pre-write numbers.
      final content = _FakeContentService();
      final rating = _FakeRatingService();
      final p = await _provider(
        viewerId: 'me',
        rating: rating,
        content: content,
      );

      final afterLoad = content.ratingFetches;
      await p.submitRating(rating: 5);
      expect(content.ratingFetches, afterLoad + 1);
    });

    test('aggregates are NOT re-read after a failed write', () async {
      final content = _FakeContentService();
      final rating = _FakeRatingService(error: RatingWriteError.failed);
      final p = await _provider(
        viewerId: 'me',
        rating: rating,
        content: content,
      );

      final afterLoad = content.ratingFetches;
      expect(await p.submitRating(rating: 5), isNotNull);
      expect(content.ratingFetches, afterLoad);
    });
  });

  group('canRate gates the button', () {
    test('false for an anonymous viewer', () async {
      final p = await _provider(viewerId: null, rating: _FakeRatingService());
      expect(p.canRate, isFalse);
    });

    test('false when viewing your own profile', () async {
      final p = await _provider(
        viewerId: 'owner',
        rating: _FakeRatingService(),
      );
      expect(p.isSelf, isTrue);
      expect(p.canRate, isFalse);
    });

    test('true for a signed-in viewer on someone else\'s profile', () async {
      final p = await _provider(viewerId: 'me', rating: _FakeRatingService());
      expect(p.canRate, isTrue);
    });

    test('submitRating refuses when canRate is false', () async {
      final rating = _FakeRatingService();
      final p = await _provider(viewerId: 'owner', rating: rating);
      expect(await p.submitRating(rating: 5), isNotNull);
      expect(rating.inserts, 0);
      expect(rating.updates, 0);
    });
  });

  group('error messages', () {
    test('a unique violation reads as already rated', () async {
      final p = await _provider(
        viewerId: 'me',
        rating: _FakeRatingService(error: RatingWriteError.alreadyRated),
      );
      expect(await p.submitRating(rating: 5), contains('already rated'));
    });

    test('a refusal reads as not allowed', () async {
      final p = await _provider(
        viewerId: 'me',
        rating: _FakeRatingService(error: RatingWriteError.notAllowed),
      );
      expect(await p.submitRating(rating: 5), contains('cannot rate'));
    });

    test('anything else reads as try again', () async {
      final p = await _provider(
        viewerId: 'me',
        rating: _FakeRatingService(error: RatingWriteError.failed),
      );
      expect(await p.submitRating(rating: 5), contains('try again'));
    });
  });

  group('concurrency', () {
    test('a second submit while one is in flight is ignored', () async {
      final rating = _FakeRatingService();
      final p = await _provider(viewerId: 'me', rating: rating);

      // Not awaited, so the second call lands while the first is still running.
      final first = p.submitRating(rating: 4);
      final second = p.submitRating(rating: 5);
      await Future.wait([first, second]);

      expect(rating.inserts, 1, reason: 'double-submit must not double-write');
    });
  });
}
