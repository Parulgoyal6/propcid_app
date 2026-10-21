import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists property "save"/shortlist state to the existing
/// `saved_properties(user_id, property_id)` table — the same table already
/// read by `DashboardAnalyticsService` — so a save survives app restarts and
/// is consistent everywhere it's shown, mirroring the reference portal's
/// `useSaveProperty` hook.
class SavedPropertiesService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchSavedPropertyIds(String userId) async {
    try {
      final rows = await _supabase
          .from('saved_properties')
          .select('property_id')
          .eq('user_id', userId);

      return (rows as List)
          .map((r) => (r as Map)['property_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('SavedPropertiesService.fetchSavedPropertyIds failed: $e');
      rethrow;
    }
  }

  Future<void> save(String userId, String propertyId) async {
    try {
      await _supabase
          .from('saved_properties')
          .upsert(
            {'user_id': userId, 'property_id': propertyId},
            onConflict: 'user_id,property_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('SavedPropertiesService.save failed: $e');
      rethrow;
    }
  }

  Future<void> unsave(String userId, String propertyId) async {
    try {
      await _supabase
          .from('saved_properties')
          .delete()
          .eq('user_id', userId)
          .eq('property_id', propertyId);
    } catch (e) {
      debugPrint('SavedPropertiesService.unsave failed: $e');
      rethrow;
    }
  }
}
