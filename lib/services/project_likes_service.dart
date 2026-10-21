import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists project "like" state to the existing `user_likes(user_id,
/// project_id)` table — the same polymorphic like table already used for
/// properties (`PropertyLikesService`) and reels (`ReelLikesService`),
/// mirroring the reference portal's `IndividualUserActivity.tsx` liked-
/// projects query (`user_likes.project_id`).
class ProjectLikesService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchLikedProjectIds(String userId) async {
    try {
      final rows = await _supabase
          .from('user_likes')
          .select('project_id')
          .eq('user_id', userId)
          .not('project_id', 'is', null);

      return (rows as List)
          .map((r) => (r as Map)['project_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('ProjectLikesService.fetchLikedProjectIds failed: $e');
      rethrow;
    }
  }

  Future<void> like(String userId, String projectId) async {
    try {
      await _supabase
          .from('user_likes')
          .upsert(
            {'user_id': userId, 'project_id': projectId},
            onConflict: 'user_id,project_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('ProjectLikesService.like failed: $e');
      rethrow;
    }
  }

  Future<void> unlike(String userId, String projectId) async {
    try {
      await _supabase
          .from('user_likes')
          .delete()
          .eq('user_id', userId)
          .eq('project_id', projectId);
    } catch (e) {
      debugPrint('ProjectLikesService.unlike failed: $e');
      rethrow;
    }
  }
}
