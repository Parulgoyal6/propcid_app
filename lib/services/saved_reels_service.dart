import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists reel "save" state to the existing `saved_reels(user_id, reel_id)`
/// table — the same dedicated table the reference portal's `useSaveProperty`
/// hook writes to for reels (kept separate from `saved_properties`, mirroring
/// the portal's schema) — so a save survives app restarts and is consistent
/// everywhere it's shown.
class SavedReelsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchSavedReelIds(String userId) async {
    try {
      final rows = await _supabase
          .from('saved_reels')
          .select('reel_id')
          .eq('user_id', userId);

      return (rows as List)
          .map((r) => (r as Map)['reel_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('SavedReelsService.fetchSavedReelIds failed: $e');
      rethrow;
    }
  }

  Future<void> save(String userId, String reelId) async {
    try {
      await _supabase
          .from('saved_reels')
          .upsert(
            {'user_id': userId, 'reel_id': reelId},
            onConflict: 'user_id,reel_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('SavedReelsService.save failed: $e');
      rethrow;
    }
  }

  Future<void> unsave(String userId, String reelId) async {
    try {
      await _supabase
          .from('saved_reels')
          .delete()
          .eq('user_id', userId)
          .eq('reel_id', reelId);
    } catch (e) {
      debugPrint('SavedReelsService.unsave failed: $e');
      rethrow;
    }
  }
}
