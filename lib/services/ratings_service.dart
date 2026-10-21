import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ratings a user has received, backing the Profile screen's "Reviews" tile.
class RatingsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Every rating value left for [userId].
  ///
  /// Mirrors ProfileDashboardShell.tsx's `fetchAvgRating` — see blueprint §9.
  /// React issues one query and derives both the count and the average from
  /// it, so this does the same rather than paying for two round-trips.
  Future<List<int>> _fetchRatings(String userId) async {
    final rows = await _supabase
        .from('user_ratings')
        .select('rating')
        .eq('rated_user_id', userId);

    return List<Map<String, dynamic>>.from(
      rows as List,
    ).map((r) => (r['rating'] as num?)?.toInt() ?? 0).toList();
  }

  /// Count and average in one round-trip.
  ///
  /// The average is rounded to one decimal place, matching React's
  /// `Number((sum / data.length).toFixed(1))`. Returns `(0, 0)` when the user
  /// has no ratings — React leaves both at their `useState(0)` initial value
  /// in that case, so an unrated profile reads as 0 rather than "—".
  Future<({int count, double average})> getRatingSummary(String userId) async {
    try {
      final ratings = await _fetchRatings(userId);
      if (ratings.isEmpty) return (count: 0, average: 0.0);

      final sum = ratings.fold<int>(0, (acc, r) => acc + r);
      final average = double.parse((sum / ratings.length).toStringAsFixed(1));
      return (count: ratings.length, average: average);
    } catch (e) {
      debugPrint('RatingsService.getRatingSummary failed: $e');
      rethrow;
    }
  }
}
