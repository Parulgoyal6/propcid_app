// models/profile_review.dart
//
// Ratings a profile has received: one review row, plus the aggregate the Reviews
// section renders.
//
// WHY THE AGGREGATE IS MODELLED HERE AND NOT FETCHED TWICE
// -------------------------------------------------------
// The portal makes two passes over `user_ratings`: `useUserRatings` computes the
// customer / broker / total averages, and `UserProfile.fetchUserReviews` fetches
// the five most recent rows that carry review text. The rating *distribution* the
// redesigned screen shows (5 bars, 5★ down to 1★) needs per-star counts, which
// neither pass produces.
//
// All three are folds over the same rows, so `ProfileContentService` fetches the
// rating rows once and [RatingBreakdown.fromRatings] derives everything. No extra
// round-trip, and no new query beyond the one the portal already issues.
//
// `RatingsService.getRatingSummary` is untouched and remains the own-profile
// path. It cannot be reused here: it returns only (count, average) and adding a
// method to it would modify an existing service, which the approved rules
// forbid. The averaging arithmetic below is deliberately identical to it —
// 1 decimal place via `toStringAsFixed(1)` — so the same profile never shows a
// different number on the two screens.
import 'package:flutter/foundation.dart';

import 'user_profile.dart';

/// Mean and count for one slice of a profile's ratings.
@immutable
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary({required this.average, required this.count});

  static const RatingSummary zero = RatingSummary(average: 0, count: 0);

  bool get hasRatings => count > 0;

  /// Rounded to one decimal, matching `RatingsService.getRatingSummary`'s
  /// `double.parse(toStringAsFixed(1))`.
  factory RatingSummary.fromValues(Iterable<int> values) {
    final list = values.toList(growable: false);
    if (list.isEmpty) return zero;
    final sum = list.fold<int>(0, (acc, v) => acc + v);
    return RatingSummary(
      average: double.parse((sum / list.length).toStringAsFixed(1)),
      count: list.length,
    );
  }
}

/// One review, with its author resolved.
@immutable
class ProfileReview {
  final String id;
  final int rating;

  /// Null when the rater left stars but no words. The portal's review list
  /// filters those out (`.not('review', 'is', null)`); the histogram counts them.
  final String? review;

  final DateTime? createdAt;
  final String raterId;

  /// Resolved from `profiles` in a second query — `user_ratings` references
  /// `auth.users`, so there is no PostgREST relationship to embed.
  final String raterName;
  final String? raterAvatarUrl;
  final String? raterUserType;

  const ProfileReview({
    required this.id,
    required this.rating,
    required this.raterId,
    required this.raterName,
    this.review,
    this.createdAt,
    this.raterAvatarUrl,
    this.raterUserType,
  });

  bool get hasText => review != null && review!.trim().isNotEmpty;

  /// First letter of the rater's name, for the avatar fallback.
  String get raterInitial =>
      raterName.trim().isEmpty ? 'A' : raterName.trim()[0].toUpperCase();

  /// Builds from a `user_ratings` row, taking the author from [raterProfile]
  /// when it was resolved.
  ///
  /// Falls back to "Anonymous" exactly as the portal does
  /// (UserProfile.tsx:521, 531) — a rater whose profile row is missing or
  /// unreadable must not blank the review.
  factory ProfileReview.fromRow(
    Map<String, dynamic> row, {
    UserProfile? raterProfile,
  }) {
    final rawReview = row['review'];
    final text = rawReview is String && rawReview.trim().isNotEmpty
        ? rawReview.trim()
        : null;

    final resolvedName = raterProfile?.displayTitle;

    return ProfileReview(
      id: row['id']?.toString() ?? '',
      rating: (row['rating'] as num?)?.toInt() ?? 0,
      review: text,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse(row['created_at'].toString()),
      raterId: row['rater_id']?.toString() ?? '',
      raterName: (resolvedName == null || resolvedName.isEmpty)
          ? 'Anonymous'
          : resolvedName,
      raterAvatarUrl: raterProfile?.avatarUrl,
      raterUserType: raterProfile?.userType,
    );
  }
}

/// Everything the Reviews section needs, derived from one fetch.
@immutable
class RatingBreakdown {
  /// Ratings left by anyone who is **not** a broker.
  ///
  /// The portal's rule verbatim (useUserRatings.ts:62-67): "individual, seller,
  /// or any non-broker is considered a customer rating".
  final RatingSummary customer;

  /// Ratings left by brokers — a builder's "Broker Trust Score".
  final RatingSummary broker;

  /// Every rating, regardless of who left it.
  final RatingSummary total;

  /// Star value (1–5) to how many ratings gave it. Always contains all five
  /// keys, so a bar renders at zero rather than vanishing.
  final Map<int, int> distribution;

  /// Reviews that carry text, newest first, already capped by the service.
  final List<ProfileReview> reviews;

  const RatingBreakdown({
    required this.customer,
    required this.broker,
    required this.total,
    required this.distribution,
    required this.reviews,
  });

  static const Map<int, int> _emptyDistribution = {
    5: 0,
    4: 0,
    3: 0,
    2: 0,
    1: 0,
  };

  static const RatingBreakdown zero = RatingBreakdown(
    customer: RatingSummary.zero,
    broker: RatingSummary.zero,
    total: RatingSummary.zero,
    distribution: _emptyDistribution,
    reviews: [],
  );

  /// The figure shown as *the* rating for this profile.
  ///
  /// UserProfile.tsx:193 — a builder is scored by its customers, everyone else by
  /// everyone. This is why a builder's headline number can differ from the mean
  /// of all its ratings.
  RatingSummary displayFor({required bool isBuilder}) =>
      isBuilder ? customer : total;

  /// True when the builder-only "Broker Trust Score" block should render
  /// (UserProfile.tsx:1855).
  bool get hasBrokerTrustScore => broker.count > 0;

  /// The largest single bar, used to scale the distribution rows. Never zero, so
  /// callers can divide safely.
  int get distributionPeak {
    var peak = 0;
    for (final count in distribution.values) {
      if (count > peak) peak = count;
    }
    return peak == 0 ? 1 : peak;
  }

  /// Folds raw `user_ratings` rows into every aggregate at once.
  ///
  /// [raterTypes] maps `rater_id` to that rater's `user_type`; an id missing from
  /// it counts as a customer, matching the portal's
  /// `profileMap[r.rater_id] || 'individual'` default.
  factory RatingBreakdown.fromRatings(
    List<Map<String, dynamic>> rows, {
    required Map<String, String?> raterTypes,
    required List<ProfileReview> reviews,
  }) {
    if (rows.isEmpty) {
      return RatingBreakdown(
        customer: RatingSummary.zero,
        broker: RatingSummary.zero,
        total: RatingSummary.zero,
        distribution: Map<int, int>.unmodifiable(_emptyDistribution),
        reviews: List.unmodifiable(reviews),
      );
    }

    final customerValues = <int>[];
    final brokerValues = <int>[];
    final allValues = <int>[];
    final distribution = <int, int>{5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

    for (final row in rows) {
      final value = (row['rating'] as num?)?.toInt();
      if (value == null) continue;

      allValues.add(value);

      // Only 1–5 are meaningful; anything else still counts toward the average
      // (the portal averages whatever the column holds) but has no bar to land
      // in.
      if (distribution.containsKey(value)) {
        distribution[value] = distribution[value]! + 1;
      }

      final raterId = row['rater_id']?.toString() ?? '';
      final raterType = raterTypes[raterId]?.toLowerCase() ?? 'individual';
      if (raterType == 'broker') {
        brokerValues.add(value);
      } else {
        customerValues.add(value);
      }
    }

    return RatingBreakdown(
      customer: RatingSummary.fromValues(customerValues),
      broker: RatingSummary.fromValues(brokerValues),
      total: RatingSummary.fromValues(allValues),
      distribution: Map<int, int>.unmodifiable(distribution),
      reviews: List.unmodifiable(reviews),
    );
  }
}
