import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists property "Like" state to the existing `user_likes` table via its
/// `property_id` column — the same polymorphic table already used for reel
/// likes (`user_likes.reel_id`, see `ReelLikesService`), just the property
/// side of it. Distinct from Save/Shortlist, which uses `saved_properties`
/// (see `SavedPropertiesService`) — the reference keeps these as two
/// separate, independently-toggleable actions, and so does this.
class PropertyLikesService {
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<Set<String>> fetchLikedPropertyIds(String userId) async {
    try {
      final rows = await _supabase
          .from('user_likes')
          .select('property_id')
          .eq('user_id', userId)
          .not('property_id', 'is', null);

      return (rows as List)
          .map((r) => (r as Map)['property_id'].toString())
          .toSet();
    } catch (e) {
      debugPrint('PropertyLikesService.fetchLikedPropertyIds failed: $e');
      rethrow;
    }
  }

  Future<void> like(String userId, String propertyId) async {
    try {
      await _supabase
          .from('user_likes')
          .upsert(
            {'user_id': userId, 'property_id': propertyId},
            onConflict: 'user_id,property_id',
            ignoreDuplicates: true,
          );
    } catch (e) {
      debugPrint('PropertyLikesService.like failed: $e');
      rethrow;
    }
  }

  Future<void> unlike(String userId, String propertyId) async {
    try {
      await _supabase
          .from('user_likes')
          .delete()
          .eq('user_id', userId)
          .eq('property_id', propertyId);
    } catch (e) {
      debugPrint('PropertyLikesService.unlike failed: $e');
      rethrow;
    }
  }
}
