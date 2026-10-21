import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists project "save" state to the existing `saved_projects(user_id,
/// project_id)` table — the same dedicated-table pattern as
/// `SavedPropertiesService`/`SavedReelsService`, mirroring the reference
/// portal's `IndividualUserActivity.tsx` saved-projects query
/// (`saved_projects.project_id`).
class SavedProjectsService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchSavedProjectIds(String userId) async {
    try {
      final rows = await _supabase
          .from('saved_projects')
          .select('project_id')
          .eq('user_id', userId);

      return (rows as List)
          .map((r) => (r as Map)['project_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('SavedProjectsService.fetchSavedProjectIds failed: $e');
      rethrow;
    }
  }

  Future<void> save(String userId, String projectId) async {
    try {
      await _supabase
          .from('saved_projects')
          .upsert(
            {'user_id': userId, 'project_id': projectId},
            onConflict: 'user_id,project_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('SavedProjectsService.save failed: $e');
      rethrow;
    }
  }

  Future<void> unsave(String userId, String projectId) async {
    try {
      await _supabase
          .from('saved_projects')
          .delete()
          .eq('user_id', userId)
          .eq('project_id', projectId);
    } catch (e) {
      debugPrint('SavedProjectsService.unsave failed: $e');
      rethrow;
    }
  }
}
