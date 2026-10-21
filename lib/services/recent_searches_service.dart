// services/recent_searches_service.dart
//
// Persistence for the Search Entry screen's recent-search list.
//
// Two backends, chosen by auth state:
//   signed in  -> `ai_user_memory.recent_searches` (jsonb), shared with the
//                 React portal
//   signed out -> `shared_preferences`, because `ai_user_memory`'s RLS policy
//                 (`ai_user_memory_rw`: auth.uid() = user_id) is
//                 authenticated-only and would reject an anonymous write
//
// This deliberately introduces NO new persistence abstraction. A codebase-wide
// audit found no storage/cache/prefs utility to extend — `shared_preferences`
// is called directly in 11 places and `flutter_secure_storage` is declared in
// pubspec but unused — so this file mirrors the closest established pattern,
// `voice_agent/services/conversation_manager.dart`: an in-memory list of models,
// jsonEncode/jsonDecode round-tripping, a cap enforced on write, and
// best-effort persistence that never throws. A generic StorageService was
// rejected on purpose (Blueprint §12: do not add an architectural pattern the
// rest of the app doesn't use).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/recent_search.dart';

class RecentSearchesService {
  /// Matches the portal's `CAP` in src/services/rag/memoryService.ts. The two
  /// apps write the same row, so the cap has to agree or each would truncate
  /// the other's list differently.
  static const int maxRecent = 10;

  /// `propcid_`-prefixed to match the convention SessionService established.
  static const String _prefsKey = 'propcid_recent_searches';

  static const String _table = 'ai_user_memory';
  static const String _column = 'recent_searches';

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Prepends [item], drops any earlier entry with the same [RecentSearch.q],
  /// and caps the result — a direct port of the portal's `prepend()` helper so
  /// both platforms converge on the same list contents.
  static List<RecentSearch> merge(
    List<RecentSearch> existing,
    RecentSearch item,
  ) {
    final rest = existing.where((e) => e.q != item.q);
    return <RecentSearch>[item, ...rest].take(maxRecent).toList();
  }

  // ── Local backend (signed out) ─────────────────────────────────────────────

  Future<List<RecentSearch>> loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return const [];
      return _decode(jsonDecode(raw));
    } catch (e) {
      debugPrint('[RecentSearchesService] loadLocal failed: $e');
      return const [];
    }
  }

  Future<void> saveLocal(List<RecentSearch> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      // Best-effort, exactly as ConversationManager._persist does: a failed
      // save must never surface to the user or block a search.
      debugPrint('[RecentSearchesService] saveLocal failed: $e');
    }
  }

  Future<void> clearLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('[RecentSearchesService] clearLocal failed: $e');
    }
  }

  // ── Remote backend (signed in) ─────────────────────────────────────────────

  /// Selects ONLY [_column]; the row's other keys are none of this feature's
  /// business and are never read.
  Future<List<RecentSearch>> loadRemote(String userId) async {
    try {
      final row = await _supabase
          .from(_table)
          .select(_column)
          .eq('user_id', userId)
          .maybeSingle();
      return _decode(row?[_column]);
    } catch (e) {
      debugPrint('[RecentSearchesService] loadRemote failed: $e');
      return const [];
    }
  }

  /// Writes ONLY `user_id` + [_column].
  ///
  /// This is the whole point of the method: `ai_user_memory` also holds
  /// `budget_min/max`, `favorite_property_types`, `preferred_city`,
  /// `preferred_language`, `recent_properties`, `recent_routes` and
  /// `last_entity`, none of which this app collects. Sending a fuller object
  /// would blank whatever the portal had stored there — the same destructive
  /// overwrite that Phase 0 of the listing migration had to fix for
  /// `properties.metadata`. A two-key payload physically cannot do that,
  /// because an UPDATE only touches the columns present in it.
  Future<void> saveRemote(String userId, List<RecentSearch> items) async {
    try {
      await _supabase.from(_table).upsert({
        'user_id': userId,
        _column: items.map((e) => e.toJson()).toList(),
      }, onConflict: 'user_id');
    } catch (e) {
      // Swallowed on purpose. RLS rejects the write outright for an expired or
      // mid-refresh session, and that must not break the search the user just
      // ran — the list simply stays local to this session.
      debugPrint('[RecentSearchesService] saveRemote failed: $e');
    }
  }

  // ── Shared decode ──────────────────────────────────────────────────────────

  /// Tolerates anything that is not a well-formed list of objects, since the
  /// portal is a second writer of this data.
  static List<RecentSearch> _decode(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => RecentSearch.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.q.isNotEmpty)
        .take(maxRecent)
        .toList();
  }
}
