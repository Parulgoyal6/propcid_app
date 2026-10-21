// services/profile_write_service.dart
//
// The single writer for the Edit Profile screen.
//
// DELEGATES, DOES NOT DUPLICATE
// ----------------------------
// `AuthService.updateProfileFields()` is the app's established `profiles` writer
// and is what `ProfileService` and the registration wizards already use. This
// service builds the payload and hands it over; it never issues its own
// `.update()`. A second writer would be a second place for the merge rules below
// to drift.
//
// THREE RULES THIS FILE EXISTS TO ENFORCE
// ---------------------------------------
// 1. `social_media` is MERGED, never replaced. The column holds ~35 keys written
//    by four different flows (three registration wizards and the portal's edit
//    form). Sending a fresh object deletes every key this screen does not model —
//    including values the portal owns and this app has no UI for.
//
// 2. Paired columns are written TOGETHER. The portal keeps five pairs in sync
//    (`website`/`website_url`, `bio`/`company_description`,
//    `years_experience`/`years_of_experience`, `rera_number`/`license_number`,
//    `city`/`work_city`) because different read sites prefer different halves.
//    Writing one alone makes the two platforms disagree about the same profile.
//
// 3. Four columns are OMITTED entirely: `user_type`, `user_role`, `is_blocked`,
//    `approval_status`. The `can_update_profile_fields()` BEFORE UPDATE trigger
//    silently reverts them for a non-admin owner — it does not raise — so sending
//    them produces a save that reports success and changes nothing.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

/// Columns the database trigger reverts for an owner. Asserted by test.
const Set<String> kTriggerGuardedColumns = <String>{
  'user_type',
  'user_role',
  'is_blocked',
  'approval_status',
};

class ProfileWriteService {
  ProfileWriteService({AuthService? authService, SupabaseClient? client})
    : _authService = authService ?? AuthService(),
      _supabase = client ?? Supabase.instance.client;

  final AuthService _authService;
  final SupabaseClient _supabase;

  /// Merges [changes] into [existing] without dropping unmodelled keys.
  ///
  /// Mirrors EditProfile.tsx's `{...socialMedia, ...}` spread (line 355). A key
  /// whose new value is null is written as null rather than removed — that is what
  /// the portal does, and it is how a user clears a field.
  ///
  /// Static and pure so the merge can be asserted without a database.
  static Map<String, dynamic> mergeSocialMedia(
    Map<String, dynamic> existing,
    Map<String, dynamic> changes,
  ) {
    return <String, dynamic>{...existing, ...changes};
  }

  /// Strips the trigger-guarded columns from a payload.
  ///
  /// Belt and braces: the builders below never add them, and this guarantees it
  /// even if one later does.
  static Map<String, dynamic> stripGuarded(Map<String, dynamic> payload) {
    return Map<String, dynamic>.fromEntries(
      payload.entries.where((e) => !kTriggerGuardedColumns.contains(e.key)),
    );
  }

  /// Writes the profile.
  ///
  /// [socialMediaExisting] must be the row's current `social_media` map, so
  /// unmodelled keys survive. Pass `{}` only when the column is genuinely empty.
  ///
  /// Throws on failure — `AuthService.updateProfileFields` logs and rethrows, and
  /// the provider surfaces it. A silent failure here would be the worst outcome:
  /// the user would believe their edit saved.
  Future<void> saveProfile({
    required String userId,
    required Map<String, dynamic> columns,
    required Map<String, dynamic> socialMediaExisting,
    required Map<String, dynamic> socialMediaChanges,
  }) async {
    final payload = stripGuarded(<String, dynamic>{
      ...columns,
      'social_media': mergeSocialMedia(socialMediaExisting, socialMediaChanges),
    });

    await _authService.updateProfileFields(userId, payload);
  }

  /// Mirrors the chosen city onto `user_preferences`.
  ///
  /// EditProfile.tsx:452-463 does exactly this, for builders and brokers only:
  /// select the row, update when it exists, insert when it does not. There is no
  /// unique constraint to upsert against, which is why it is two statements
  /// rather than one.
  ///
  /// Best-effort by design: the profile has already been written by the time this
  /// runs, and a failed preference mirror must not report the profile save as
  /// failed. The portal does not check its result either.
  Future<void> syncCityPreference({
    required String userId,
    required String city,
  }) async {
    if (city.trim().isEmpty) return;

    try {
      final existing = await _supabase
          .from('user_preferences')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('user_preferences')
            .update({'city': city})
            .eq('user_id', userId);
      } else {
        await _supabase.from('user_preferences').insert({
          'user_id': userId,
          'city': city,
        });
      }
    } catch (e) {
      debugPrint('ProfileWriteService.syncCityPreference failed: $e');
    }
  }
}
