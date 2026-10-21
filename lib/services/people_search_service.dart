// services/people_search_service.dart
//
// People Search's only data path. Read-only: this service has no write method in
// any form.
//
// A COMPANION SERVICE, NOT AN EXTENSION
// -------------------------------------
// `UserProfileService` (Public Profile) and `PropertyService` (property search)
// are both untouched. Nothing here changes an existing method, an existing
// signature or an existing caller.
//
// WHICH PORTAL QUERY THIS REPRODUCES
// ----------------------------------
// The portal has six people-search implementations and they disagree with each
// other; `docs/PEOPLE_SEARCH_PORTAL_COMPARISON.md` tabulates all six. This one
// combines:
//
//   * the row filter of `profiles_public`
//     (20260421110000_add_user_presence.sql:25-26) —
//     `COALESCE(is_blocked,false) = false AND approval_status = 'approved'`;
//   * the text matcher of the global search modal
//     (features/search/SearchModal.tsx:115-117) — an OR across
//     `display_name`, `company_name` and `bio`;
//   * the base table, `public.profiles`, which is what the three directory pages
//     and both people pickers already query.
//
// WHY NOT THE `profiles_public` VIEW
// ----------------------------------
// The view exposes 14 columns and omits `username`, `work_city`, `city`,
// `rera_number` and `verification_status` — four of the fields a result card has
// to show. Its row filter is reproduced here instead, which is precisely what
// `NewChatModal.tsx:53-54` already does against the base table.
//
// WHY NOT THE `global_search` RPC
// -------------------------------
// It is `SECURITY DEFINER` and its profiles branch has no `approval_status` or
// `is_blocked` predicate (20260402111500_restore_coordinates.sql:141-156), so it
// returns pending, rejected and blocked profiles to anonymous callers. It is also
// limited to `builder | dealer | broker` and shares one `LIMIT 20` with cities,
// properties and projects.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/people_search_result.dart';
import '../models/profile_review.dart';
import '../models/user_profile.dart';

class PeopleSearchService {
  PeopleSearchService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'profiles';
  static const String _ratingsTable = 'user_ratings';

  /// The card's column list.
  ///
  /// Every name here appears in the `anon` GRANT
  /// (20270311000000_profiles_hide_contact_from_anon.sql:16-26), so the query is
  /// legal signed-in **and** signed-out. That is a hard requirement, not an
  /// optimisation: `anon` holds no table-level SELECT grant, and naming one
  /// ungranted column fails the whole query rather than returning null.
  ///
  /// A subset of `UserProfileService.publicColumns`, not a reference to it — this
  /// service must be free to request fewer columns than the profile screen
  /// without either list constraining the other.
  ///
  /// `license_number` is here only because `UserProfile.isVerified` and
  /// `effectiveRera` read it (`rera_number || license_number`); it is never
  /// displayed on its own.
  static const String columns =
      'user_id, display_name, username, avatar_url, user_type, company_name, '
      'agency_name, work_city, city, years_experience, years_of_experience, '
      'rera_number, license_number, verification_status, bio';

  /// One page of people matching [query].
  ///
  /// [role] narrows by `user_type`; [PeopleRole.all] adds no predicate.
  /// [offset]/[limit] page through the result set. An empty or whitespace-only
  /// [query] returns [PeopleSearchPage.empty] without a round-trip, matching
  /// `SearchModal.tsx:63-71`, which clears its results rather than searching for
  /// nothing.
  Future<PeopleSearchPage> searchPeople({
    required String query,
    PeopleRole role = PeopleRole.all,
    int offset = 0,
    int limit = 20,
  }) async {
    final term = query.trim();
    if (term.isEmpty) return PeopleSearchPage.empty;

    try {
      var filter = _supabase
          .from(_table)
          .select(columns)
          .eq('approval_status', 'approved')
          // `is_blocked IS NOT TRUE`, NOT `= false`.
          //
          // The view and the anonymous RLS policy both write
          // `COALESCE(is_blocked, false) = false`, which keeps rows where the
          // column is NULL. `.eq('is_blocked', false)` would drop every one of
          // them — SQL equality against NULL is never true — and the column was
          // added to an existing table, so NULL is the value most rows carry.
          // `NewChatModal.tsx:54` uses `.eq(...)` and has that defect; the view's
          // predicate is reproduced instead.
          .not('is_blocked', 'is', true)
          .or(buildTextFilter(term));

      final String? userType = role.userType;
      if (userType != null) {
        filter = filter.eq('user_type', userType);
      }

      // .order() returns the parent PostgrestTransformBuilder, so every filter
      // above has to be applied before this point — the same constraint
      // PropertyService.searchProperties documents.
      final ordered = filter
          // The portal does not order any of its people queries; rows arrive in
          // whatever order Postgres happens to return. That is tolerable there
          // because nothing paginates. It is not tolerable here: PostgreSQL
          // guarantees no row order between two unordered queries, so `.range()`
          // paging over one can repeat or skip rows. Alphabetical by name is the
          // portal's only people-ordering precedent — `global_search`'s
          // `ORDER BY type, label` where label is
          // `COALESCE(company_name, display_name)`.
          .order('display_name', ascending: true)
          // Makes the order total, so paging is stable across duplicate names.
          // Same reasoning, and the same fix, as PropertyService's `.order('id')`
          // tiebreaker.
          .order('user_id', ascending: true);

      final PostgrestResponse<PostgrestList> response = await ordered
          .range(offset, offset + limit - 1)
          .count(CountOption.exact);

      return PeopleSearchPage(
        rows: response.data
            .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
            .where((profile) => profile.userId.isNotEmpty)
            .toList(growable: false),
        totalCount: response.count,
      );
    } catch (e) {
      debugPrint('PeopleSearchService.searchPeople failed: $e');
      rethrow;
    }
  }

  /// Approved brokers and influencers for the Home "Popular Brokers" /
  /// "Popular Influencers" rails.
  ///
  /// Mirrors the portal's home-page `agentsQuery`
  /// (`PublicHomePage.tsx`/`AuthenticatedHomePage.tsx`, `fetchProjects`): one
  /// round trip covering both roles (`user_type IN ('broker','influencer')`),
  /// left for the caller to split by [UserProfile.isBroker] /
  /// [UserProfile.isInfluencer] — same as the portal's own
  /// `mappedAgents.filter(...)` split. The portal sends no `.order()` here
  /// either, so row order is left as Postgres returns it.
  Future<List<UserProfile>> listPopularAgents({int limit = 20}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(columns)
          .inFilter('user_type', const ['broker', 'influencer'])
          .eq('approval_status', 'approved')
          .not('is_blocked', 'is', true)
          .limit(limit);

      return List<Map<String, dynamic>>.from(rows)
          .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
          .where((profile) => profile.userId.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('PeopleSearchService.listPopularAgents failed: $e');
      rethrow;
    }
  }

  /// Rating aggregates for [userIds], keyed by `user_id`.
  ///
  /// `pages/ExploreCity.tsx:212-215` verbatim — one batched read of
  /// `user_ratings`, then a fold per user. `user_ratings` SELECT is
  /// `USING (true)` (20251207160017:19-20), so this needs no session.
  ///
  /// Averaging is delegated to `RatingSummary.fromValues`, which rounds to one
  /// decimal exactly as the portal's `Number((sum / count).toFixed(1))` does — so
  /// a person cannot show 4.7 here and 4.6 on their profile.
  ///
  /// Degrades to an empty map on failure rather than throwing: a rating is
  /// decoration on a search card, and losing it must not turn a good result list
  /// into an error screen. Users with no ratings are simply absent from the
  /// result, which the card renders as no rating at all.
  Future<Map<String, RatingSummary>> fetchRatings(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from(_ratingsTable)
          .select('rated_user_id, rating')
          .inFilter('rated_user_id', ids);

      return aggregateRatings(rows);
    } catch (e) {
      debugPrint('PeopleSearchService.fetchRatings failed: $e');
      return const {};
    }
  }

  /// Folds raw `(rated_user_id, rating)` rows into one summary per user.
  ///
  /// `ExploreCity.tsx:217-224`'s `ratingsMap` fold. Rows with a missing id or a
  /// non-numeric rating are skipped rather than counted as zero — a zero would
  /// drag the average down, which is worse than not counting a corrupt row.
  ///
  /// Exposed so the arithmetic can be asserted against the portal's without a
  /// database.
  @visibleForTesting
  static Map<String, RatingSummary> aggregateRatings(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<int>>{};
    for (final row in rows) {
      final id = row['rated_user_id']?.toString();
      final value = row['rating'];
      if (id == null || id.isEmpty || value is! num) continue;
      grouped.putIfAbsent(id, () => <int>[]).add(value.round());
    }

    return {
      for (final entry in grouped.entries)
        entry.key: RatingSummary.fromValues(entry.value),
    };
  }

  /// The `or=` filter string for [term].
  ///
  /// `display_name.ilike.%term%,company_name.ilike.%term%,bio.ilike.%term%` —
  /// `SearchModal.tsx:115-117`'s three columns, in its order.
  ///
  /// Exposed for tests: this is the one piece of the query that is a string the
  /// user helped build, so it is worth asserting on directly.
  @visibleForTesting
  static String buildTextFilter(String term) {
    final value = filterValue(term.trim());
    return 'display_name.ilike.$value,'
        'company_name.ilike.$value,'
        'bio.ilike.$value';
  }

  /// One `ilike` operand, quoted only when it has to be.
  ///
  /// PostgREST parses `or=(...)` by splitting on commas and parentheses, so raw
  /// user text carrying either changes the filter's *structure* instead of being
  /// matched literally. The portal interpolates unescaped
  /// (`SearchModal.tsx:116`), which is how a query like `Sharma, Rahul` ends up
  /// as four conditions rather than three.
  ///
  /// Terms without a metacharacter emit the portal's exact unquoted form, so the
  /// common path is byte-identical to the reference. Anything else is
  /// double-quoted — PostgREST's own escape hatch — with `"` and `\` backslashed.
  /// Note `.` is not a metacharacter inside a value: an operand runs to the next
  /// comma or closing paren, so periods need no quoting and are left alone.
  @visibleForTesting
  static String filterValue(String term) {
    if (!term.contains(RegExp(r'[,()"\\]'))) return '%$term%';
    final escaped = term.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"%$escaped%"';
  }
}
