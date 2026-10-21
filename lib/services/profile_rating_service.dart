// services/profile_rating_service.dart
//
// Writing a rating: submit, update, and read back the viewer's own.
//
// A COMPANION, NOT AN EXTENSION OF RatingsService
// -----------------------------------------------
// `RatingsService.getRatingSummary()` is consumed by `ProfileProvider` for the
// own-profile Reviews tile. It is read-only, unmodified, and stays that way — the
// same choice Phase 1 made when `ProfileContentService` took on the public
// profile's rating read rather than extending it.
//
// Reads live elsewhere by design: `ProfileContentService.fetchRatings` already
// folds every aggregate the Reviews section needs out of one query. The only read
// here is [fetchMyRating], because "has the viewer already rated?" is a
// write-path question — it decides between an insert and an update.
//
// RLS, VERIFIED — no backend change is needed:
//   INSERT  WITH CHECK (auth.uid() = rater_id AND auth.uid() <> rated_user_id)
//   UPDATE  USING      (auth.uid() = rater_id)
//   SELECT  USING      (true)
// (20251207160017_*.sql, tightened by 20260710123600_audit_optimize_rls_initplan.sql)
//
// So the database already refuses a self-rating and already refuses editing
// someone else's. The guards below exist to avoid a pointless round-trip and to
// produce a sensible message, not to provide the security.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The viewer's own rating of a profile, when one exists.
@immutable
class MyRating {
  final String id;
  final int rating;
  final String? review;

  const MyRating({required this.id, required this.rating, this.review});
}

/// Why a rating write failed, so the UI can say something useful.
enum RatingWriteError {
  /// The unique (rated_user_id, rater_id) index rejected a second insert.
  ///
  /// Reachable when two devices submit at once, or when a stale `myRating` made
  /// the caller choose insert over update.
  alreadyRated,

  /// Self-rating, or no signed-in viewer. Blocked before the round-trip.
  notAllowed,

  /// Anything else — network, RLS, unexpected shape.
  failed,
}

class ProfileRatingService {
  ProfileRatingService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'user_ratings';

  /// Postgres `unique_violation`.
  ///
  /// The portal checks for `'23505'` (UserRatingModal.tsx:94) and shows
  /// "Already Rated". 23505 is indeed `unique_violation`, so the same code is
  /// matched here rather than a different one being guessed at.
  static const String _uniqueViolation = '23505';

  /// Bound the review text at the same 500 characters the portal's textarea
  /// enforces (UserRatingModal.tsx:177). The column is unbounded, so without this
  /// the app could store text the portal's editor would silently truncate.
  static const int maxReviewLength = 500;

  /// The viewer's existing rating of [ratedUserId], or null.
  ///
  /// Mirrors `fetchMyRating` (UserProfile.tsx:484-501): `maybeSingle`, and a
  /// no-op for anonymous viewers and self-views.
  ///
  /// Never throws — a failed lookup returns null, which makes the sheet open in
  /// "new rating" mode. The worst outcome is an insert that hits the unique index
  /// and is reported as [RatingWriteError.alreadyRated], which is recoverable.
  Future<MyRating?> fetchMyRating({
    required String? viewerId,
    required String ratedUserId,
  }) async {
    if (viewerId == null || viewerId.isEmpty) return null;
    if (ratedUserId.isEmpty || viewerId == ratedUserId) return null;

    try {
      final row = await _supabase
          .from(_table)
          .select('id, rating, review')
          .eq('rated_user_id', ratedUserId)
          .eq('rater_id', viewerId)
          .maybeSingle();

      if (row == null) return null;
      return MyRating(
        id: row['id']?.toString() ?? '',
        rating: (row['rating'] as num?)?.toInt() ?? 0,
        review: row['review'] as String?,
      );
    } catch (e) {
      debugPrint('ProfileRatingService.fetchMyRating failed: $e');
      return null;
    }
  }

  /// Inserts a new rating.
  ///
  /// Returns null on success, or the reason it failed. `rater_id` is taken from
  /// [viewerId] rather than left to a default, because the RLS check compares it
  /// against `auth.uid()` — a mismatch is rejected, not silently corrected.
  Future<RatingWriteError?> submitRating({
    required String? viewerId,
    required String ratedUserId,
    required int rating,
    String? review,
  }) async {
    final guard = _guard(viewerId, ratedUserId, rating);
    if (guard != null) return guard;

    try {
      await _supabase.from(_table).insert({
        'rated_user_id': ratedUserId,
        'rater_id': viewerId,
        'rating': rating,
        'review': _normaliseReview(review),
      });
      return null;
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolation) return RatingWriteError.alreadyRated;
      debugPrint('ProfileRatingService.submitRating failed: ${e.message}');
      return RatingWriteError.failed;
    } catch (e) {
      debugPrint('ProfileRatingService.submitRating failed: $e');
      return RatingWriteError.failed;
    }
  }

  /// Updates an existing rating by row id.
  ///
  /// Only `rating` and `review` are sent. `rated_user_id` and `rater_id` are
  /// deliberately omitted: they identify the row, changing either would move a
  /// rating to a different person, and RLS would reject it anyway.
  Future<RatingWriteError?> updateRating({
    required String? viewerId,
    required String ratedUserId,
    required String ratingId,
    required int rating,
    String? review,
  }) async {
    final guard = _guard(viewerId, ratedUserId, rating);
    if (guard != null) return guard;
    if (ratingId.isEmpty) return RatingWriteError.failed;

    try {
      await _supabase
          .from(_table)
          .update({'rating': rating, 'review': _normaliseReview(review)})
          .eq('id', ratingId);
      return null;
    } catch (e) {
      debugPrint('ProfileRatingService.updateRating failed: $e');
      return RatingWriteError.failed;
    }
  }

  /// Shared pre-flight. Returns null when the write may proceed.
  @visibleForTesting
  static RatingWriteError? guardFor({
    required String? viewerId,
    required String ratedUserId,
    required int rating,
  }) => _guard(viewerId, ratedUserId, rating);

  static RatingWriteError? _guard(
    String? viewerId,
    String ratedUserId,
    int rating,
  ) {
    if (viewerId == null || viewerId.isEmpty)
      return RatingWriteError.notAllowed;
    if (ratedUserId.isEmpty) return RatingWriteError.notAllowed;
    // The RLS check enforces this too; catching it here avoids a round-trip that
    // can only fail.
    if (viewerId == ratedUserId) return RatingWriteError.notAllowed;
    if (rating < 1 || rating > 5) return RatingWriteError.failed;
    return null;
  }

  /// Blank becomes null, and text is capped.
  ///
  /// The portal stores `review.trim() || null` (UserRatingModal.tsx:73), and its
  /// review list filters on `review is not null` — so writing an empty string
  /// would produce a review card with no words in it.
  @visibleForTesting
  static String? normaliseReview(String? review) => _normaliseReview(review);

  static String? _normaliseReview(String? review) {
    final trimmed = review?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return trimmed.length <= maxReviewLength
        ? trimmed
        : trimmed.substring(0, maxReviewLength);
  }
}
