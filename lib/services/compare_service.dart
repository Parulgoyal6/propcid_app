// services/compare_service.dart
//
// Local-only persistence for the Compare Properties selection.
//
// Unlike shortlist/likes, Compare is a temporary, device-local selection —
// not an account-tied concept the portal syncs server-side either (its
// `CompareContext.tsx` persists the exact same way, to `localStorage`, with
// no Supabase table). So this stays plain `shared_preferences`, no new
// backend table, matching the existing Provider -> Service convention (see
// `RecentSearchesService`) rather than putting `SharedPreferences` calls
// directly in `CompareProvider`.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompareService {
  /// `propcid_`-prefixed to match the convention `RecentSearchesService`/
  /// `SessionService` established.
  static const String _prefsKey = 'propcid_compare_property_ids';

  Future<List<String>> loadIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsKey) ?? const [];
    } catch (e) {
      debugPrint('[CompareService] loadIds failed: $e');
      return const [];
    }
  }

  Future<void> saveIds(List<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, ids);
    } catch (e) {
      // Best-effort, same as RecentSearchesService.saveLocal: a failed save
      // must never surface to the user or block the toggle they just tapped.
      debugPrint('[CompareService] saveIds failed: $e');
    }
  }
}
