import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists reel "like" state to the existing `user_likes(user_id, reel_id)`
/// table — confirmed present alongside `influencer_video_likes`/`saved_reels`
/// in this project's Supabase schema — so a like survives app restarts and
/// contributes to `influencer_videos.likes` the same way the reference
/// portal's ReelView does via `user_likes.reel_id`.
class ReelLikesService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchLikedReelIds(String userId) async {
    try {
      final rows = await _supabase
          .from('user_likes')
          .select('reel_id')
          .eq('user_id', userId)
          .not('reel_id', 'is', null);

      return (rows as List)
          .map((r) => (r as Map)['reel_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('ReelLikesService.fetchLikedReelIds failed: $e');
      rethrow;
    }
  }

  Future<void> like(String userId, String reelId) async {
    try {
      await _supabase
          .from('user_likes')
          .upsert(
            {'user_id': userId, 'reel_id': reelId},
            onConflict: 'user_id,reel_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('ReelLikesService.like failed: $e');
      rethrow;
    }
  }

  Future<void> unlike(String userId, String reelId) async {
    try {
      await _supabase
          .from('user_likes')
          .delete()
          .eq('user_id', userId)
          .eq('reel_id', reelId);
    } catch (e) {
      debugPrint('ReelLikesService.unlike failed: $e');
      rethrow;
    }
  }
}
