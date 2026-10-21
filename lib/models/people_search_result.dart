// models/people_search_result.dart
//
// People Search's row and page types.
//
// WHY THERE IS NO NEW ROW MODEL
// -----------------------------
// A result row is a `UserProfile`. That model already carries every derived rule
// the card needs — `effectiveCity` (`city || work_city`), `effectiveExperience`
// (`years_experience || years_of_experience || social_media.years_of_experience`),
// `isVerified`, `effectiveRera` (`rera_number || license_number`) and `initials` —
// each ported from `pages/UserProfile.tsx` and pinned by
// `test/user_profile_model_test.dart`. A second, leaner row model would mean a
// second copy of those rules, and the search card and the profile screen would
// eventually disagree about the same person.
//
// `PeopleSearchService.columns` requests a subset of `UserProfile`'s fields, so
// the unrequested ones parse as null. That is exactly how `fetchProfilesByIds`
// already uses the model with its five-column `summaryColumns`.
import 'package:flutter/foundation.dart';

import 'profile_review.dart';
import 'user_profile.dart';

/// The role filter chips.
///
/// `all` sends no `user_type` predicate, which reproduces the portal's three
/// role-agnostic people surfaces (`SearchModal.tsx:112`, `Search.tsx:1264`,
/// `NewChatModal.tsx:49`) exactly — including their behaviour of returning
/// `seller` and `dealer` rows, which render with the generic MEMBER badge.
///
/// The four named roles are the ones requested. They are all valid `user_type`
/// values under the current CHECK constraint
/// (`20260326000000_fix_admin_user_types.sql:21`:
/// `builder | broker | influencer | individual | seller | dealer`).
///
/// Deliberately absent: `agent` and `developer`. `BrokersList.tsx:58` filters on
/// `agent` and `BuildersList.tsx:53` on `developer`, but neither is a legal
/// `user_type`, so both match nothing. Copying them would only add dead
/// predicates.
enum PeopleRole {
  all(null, 'All'),
  builder('builder', 'Builders'),
  broker('broker', 'Brokers'),
  influencer('influencer', 'Influencers'),
  individual('individual', 'Individuals');

  const PeopleRole(this.userType, this.label);

  /// The `profiles.user_type` value, or null for [all].
  final String? userType;

  /// Chip copy.
  final String label;
}

/// One page of people, plus the total the query reports.
///
/// Mirrors `PropertySearchPage` — the same `(rows, totalCount)` shape the
/// property paging path already returns, so `PeopleSearchProvider` can follow
/// `PropertyProvider`'s accounting without inventing a second convention.
@immutable
class PeopleSearchPage {
  final List<UserProfile> rows;

  /// From `CountOption.exact`. Null when the database did not report one.
  final int? totalCount;

  const PeopleSearchPage({required this.rows, this.totalCount});

  static const PeopleSearchPage empty = PeopleSearchPage(
    rows: <UserProfile>[],
    totalCount: 0,
  );
}

/// A profile paired with the rating aggregate for its card, if one arrived.
///
/// Ratings load in a second round-trip after the page lands (see
/// [PeopleSearchService.fetchRatings]), so `rating` is null both while that is
/// in flight and for anyone who has never been rated. The card treats both the
/// same way and shows nothing, which is what `ExploreCity.tsx:228-230` does with
/// its `undefined` average.
@immutable
class PersonResult {
  final UserProfile profile;
  final RatingSummary? rating;

  const PersonResult({required this.profile, this.rating});

  PersonResult withRating(RatingSummary? value) =>
      PersonResult(profile: profile, rating: value);

  String get userId => profile.userId;
}
