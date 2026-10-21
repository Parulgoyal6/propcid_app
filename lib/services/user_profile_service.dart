// services/user_profile_service.dart
//
// Reads from `profiles` for the Public Profile screen. Read-only: this service
// has no write path in any phase.
//
// THE COLUMN LISTS ARE A SECURITY CONTRACT, NOT AN OPTIMISATION
// ------------------------------------------------------------
// 20270311000000_profiles_hide_contact_from_anon.sql REVOKEs the table-level
// SELECT grant from `anon` and re-grants SELECT on named columns only. `email`,
// `phone` and `mobile_number` are deliberately excluded:
//
//   "Note: email, phone and mobile_number are deliberately omitted from the anon
//    grant. New columns added later are NOT auto-granted to anon (fail-safe)."
//
// A column-level grant is not a row filter. Naming an ungranted column in a
// SELECT makes the whole query FAIL for that role — it does not return null. So
// `select('*')` is illegal for a logged-out viewer, and the two lists below are
// the difference between a working screen and a hard error. This mirrors
// `pages/UserProfile.tsx:328-340`, which builds its column list the same way and
// for the same reason.
//
// `authenticated` still holds the table-level grant, so a signed-in viewer may
// request the contact columns; RLS then decides which *rows* are visible.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import 'auth_service.dart';

class UserProfileService {
  UserProfileService({AuthService? authService, SupabaseClient? client})
    : _authService = authService ?? AuthService(),
      _supabase = client ?? Supabase.instance.client;

  final AuthService _authService;
  final SupabaseClient _supabase;

  static const String _table = 'profiles';

  /// Columns readable by **any** viewer, including anonymous.
  ///
  /// Copied from `publicCols` in pages/UserProfile.tsx:331. Do not add a column
  /// here without first confirming it appears in the `anon` GRANT — an ungranted
  /// column fails the entire query for logged-out visitors.
  ///
  /// DOCUMENTED DEVIATION — `background_image_url` is appended.
  /// The portal omits it from `publicCols` while its own cover hero renders
  /// `profile.background_image_url` (UserProfile.tsx:964), so on the web a
  /// visitor never sees anyone's cover: the value is simply absent and the
  /// hardcoded Unsplash fallback always wins. That looks like an oversight
  /// rather than an intent. The column **is** granted to `anon`
  /// (20270311000000, grant list line 26), so requesting it is safe, and without
  /// it the redesigned cover hero could never display a real cover. Flagged in
  /// the Phase 0 Impact Report for confirmation.
  static const String publicColumns =
      'user_id, display_name, username, avatar_url, user_type, company_name, '
      'agency_name, website_url, years_experience, specialization, '
      'business_hours, created_at, bio, work_city, city, license_number, '
      'rera_number, social_media, years_of_experience, office_address, state, '
      'pincode, website, company_description, verification_status, '
      'fb_followers_count, ig_followers_count, ig_follows_count, '
      'ig_media_count, social_followers_synced_at, background_image_url';

  /// The three PII columns a signed-in viewer may additionally request.
  ///
  /// `pages/UserProfile.tsx:332`: `${publicCols}, phone, email, mobile_number`.
  static const String contactColumns = 'phone, email, mobile_number';

  /// Full column list for a signed-in viewer looking at someone else.
  static const String authenticatedColumns = '$publicColumns, $contactColumns';

  /// Columns needed to label a rater, viewer or reviewer.
  ///
  /// Matches the portal's `profilesMap` projections (useProfileViews.ts:113,
  /// useUserRatings.ts:48) — `profile_views` and `user_ratings` reference
  /// `auth.users`, not `profiles`, so there is no PostgREST relationship to
  /// embed and the names must be resolved in a second round-trip.
  static const String summaryColumns =
      'user_id, display_name, avatar_url, user_type, username';

  /// The signed-in user's own profile.
  ///
  /// Delegates to [AuthService.getUserProfile] rather than issuing its own
  /// `select('*')`: that method is the app's established own-profile read and is
  /// what `AuthProvider` already uses, so both paths return identical data.
  ///
  /// Inherits its contract — it logs and returns `null` on failure rather than
  /// throwing — so a null here means "no row **or** the read failed". Callers
  /// that must tell those apart should use [fetchPublic] with the viewer's own
  /// id instead.
  Future<UserProfile?> fetchOwn(String userId) async {
    final row = await _authService.getUserProfile(userId);
    if (row == null) return null;
    return UserProfile.fromMap(row);
  }

  /// Another user's profile, with the column list chosen by [viewerSignedIn].
  ///
  /// Pass `viewerSignedIn: false` whenever there is no session. Passing `true`
  /// without one makes the query request `phone`/`email`/`mobile_number` and the
  /// database rejects it outright.
  ///
  /// Returns `null` when no row matches. Throws on any real failure, so a
  /// provider can show a retry state instead of an empty profile — the
  /// `debugPrint` + `rethrow` convention `RatingsService` and
  /// `ProfileViewService` already use.
  Future<UserProfile?> fetchPublic(
    String userId, {
    required bool viewerSignedIn,
  }) async {
    try {
      final row = await _supabase
          .from(_table)
          .select(viewerSignedIn ? authenticatedColumns : publicColumns)
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return null;
      return UserProfile.fromMap(row);
    } catch (e) {
      debugPrint('UserProfileService.fetchPublic($userId) failed: $e');
      rethrow;
    }
  }

  /// Display names and avatars for [userIds], keyed by `user_id`.
  ///
  /// Used to label review authors and profile viewers. Returns an empty map for
  /// an empty input without touching the network. Duplicate ids are collapsed.
  ///
  /// Failures degrade to an empty map rather than throwing: a missing rater name
  /// falls back to "Anonymous" in the UI (the portal's behaviour,
  /// UserProfile.tsx:531) and must not take down the reviews section.
  Future<Map<String, UserProfile>> fetchProfilesByIds(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from(_table)
          .select(summaryColumns)
          .inFilter('user_id', ids);

      final result = <String, UserProfile>{};
      for (final row in rows) {
        final profile = UserProfile.fromMap(row);
        if (profile.userId.isNotEmpty) {
          result[profile.userId] = profile;
        }
      }
      return result;
    } catch (e) {
      debugPrint('UserProfileService.fetchProfilesByIds failed: $e');
      return const {};
    }
  }
}
