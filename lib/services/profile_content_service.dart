// services/profile_content_service.dart
//
// The content shown on someone else's profile: their listings or projects, and
// their ratings.
//
// WHY NOT REUSE THE EXISTING SERVICES
// -----------------------------------
// Both were inspected first, and neither can serve this screen without being
// changed — which is not permitted:
//
//   * `PropertyService.getPropertiesByUser()` applies NO status filter, and
//     `PropertyModel` carries no `status` field, so its result cannot be filtered
//     down to the portal's `status in ('active','sold')` afterwards. A profile
//     would show drafts and inactive listings to strangers.
//   * `BuilderProjectService.getProjects()` applies neither `status = 'active'`
//     nor the visitor-only `approval_status = 'approved'`, and
//     `BuilderProjectModel` carries no `approval_status`, so unapproved projects
//     could not be filtered out client-side either.
//   * `RatingsService.getRatingSummary()` returns only (count, average). The
//     redesigned Reviews section needs per-star counts and the review text.
//
// So the queries live here, with the portal's filters. What IS reused is the
// existing model layer — `PropertyModel.fromSupabase` and
// `BuilderProjectModel.fromSupabase` map every row, so no parsing is duplicated
// and cards render from the same models the rest of the app uses.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/builder_project_model.dart';
import '../models/profile_review.dart';
import '../models/property_model.dart';
import 'user_profile_service.dart';

class ProfileContentService {
  ProfileContentService({
    SupabaseClient? client,
    UserProfileService? profileService,
  }) : _supabase = client ?? Supabase.instance.client,
       _profileService = profileService ?? UserProfileService();

  final SupabaseClient _supabase;
  final UserProfileService _profileService;

  /// How many text reviews to carry. The UI shows three; the rest are kept so a
  /// future "See all reviews" screen needs no second fetch.
  ///
  /// The portal limits its review list to 5 (UserProfile.tsx:512). Ten is a
  /// superset, and the extra rows are already in memory from the ratings fetch —
  /// no additional query.
  static const int reviewsToKeep = 10;

  /// A user's active listings, newest first.
  ///
  /// Portal parity (UserProfile.tsx:386-393): `status in ('active','sold')` and
  /// `created_at desc`. Sold rows are kept deliberately — the portal renders them
  /// behind its sold overlay rather than hiding them.
  Future<List<PropertyModel>> fetchProperties(String userId) async {
    try {
      final rows = await _supabase
          .from('properties')
          .select()
          .eq('user_id', userId)
          .inFilter('status', ['active', 'sold'])
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        rows,
      ).map(PropertyModel.fromSupabase).toList(growable: false);
    } catch (e) {
      debugPrint('ProfileContentService.fetchProperties($userId) failed: $e');
      rethrow;
    }
  }

  /// A builder's projects, newest first.
  ///
  /// Portal parity (UserProfile.tsx:406-419): always `status = 'active'`, plus
  /// `approval_status = 'approved'` **only when the viewer is not the owner**, so
  /// a builder can see their own pending projects but visitors cannot.
  Future<List<BuilderProjectModel>> fetchBuilderProjects(
    String builderId, {
    required bool viewerIsOwner,
  }) async {
    try {
      var query = _supabase
          .from('builder_projects')
          .select()
          .eq('builder_id', builderId)
          .eq('status', 'active');

      if (!viewerIsOwner) {
        query = query.eq('approval_status', 'approved');
      }

      final rows = await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(
        rows,
      ).map(BuilderProjectModel.fromSupabase).toList(growable: false);
    } catch (e) {
      debugPrint(
        'ProfileContentService.fetchBuilderProjects($builderId) failed: $e',
      );
      rethrow;
    }
  }

  /// Every aggregate the Reviews section needs, from one fetch.
  ///
  /// The portal issues three queries for this — all ratings for the averages
  /// (useUserRatings.ts:29), the recent text reviews (UserProfile.tsx:506), and
  /// the rater profiles for both. This issues two: the ratings, then the rater
  /// profiles. The averages, the 5-bar distribution and the review list are all
  /// folds over the same rows.
  ///
  /// Deliberately **unbounded**, matching `useUserRatings`, which also fetches
  /// every row. Capping would silently change the average relative to the portal
  /// — the two platforms must not disagree about a user's rating.
  Future<RatingBreakdown> fetchRatings(String userId) async {
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('user_ratings')
            .select('id, rating, review, created_at, rater_id')
            .eq('rated_user_id', userId)
            .order('created_at', ascending: false),
      );

      if (rows.isEmpty) return RatingBreakdown.zero;

      // One profiles round-trip for every rater at once. `user_ratings`
      // references auth.users, so there is no relationship to embed — the portal
      // resolves names the same way.
      final raterIds = rows
          .map((r) => r['rater_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final raterProfiles = await _profileService.fetchProfilesByIds(raterIds);

      final raterTypes = <String, String?>{
        for (final entry in raterProfiles.entries)
          entry.key: entry.value.userType,
      };

      // Rows already arrive newest-first, so the first N with text are the most
      // recent ones — the portal's ordering.
      final reviews = <ProfileReview>[];
      for (final row in rows) {
        if (reviews.length >= reviewsToKeep) break;
        final review = ProfileReview.fromRow(
          row,
          raterProfile: raterProfiles[row['rater_id']?.toString()],
        );
        if (review.hasText) reviews.add(review);
      }

      return RatingBreakdown.fromRatings(
        rows,
        raterTypes: raterTypes,
        reviews: reviews,
      );
    } catch (e) {
      debugPrint('ProfileContentService.fetchRatings($userId) failed: $e');
      rethrow;
    }
  }
}
