// services/trending_cities_service.dart
//
// Read-only access to `public.trending_cities`. No write path exists here in
// any form.
//
// Query ported verbatim from the portal's `useTrendingCities.ts`: same
// column list, same `is_active` filter, same `display_order` ascending sort.
// Unlike the portal, this does NOT fall back to a hardcoded sample city list
// when the table is empty — that fallback is a purely visual placeholder on
// the web side, and this app must never substitute admin-controlled content
// with invented data. An empty table means the section stays hidden, exactly
// like `NewsSection`.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trending_city.dart';

class TrendingCitiesService {
  TrendingCitiesService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'trending_cities';

  static const String columns =
      'id, city_name, state, country, featured_image_url, '
      'growth_percentage, avg_property_price, total_properties, '
      'description, display_order';

  /// Active trending cities, in the admin's configured order.
  ///
  /// Rethrows so the section can tell a failure apart from a genuinely empty
  /// table, mirroring [NewsService.listActive]'s reasoning.
  Future<List<TrendingCity>> listActive({int limit = 10}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(columns)
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .limit(limit);

      return rows
          .map(
            (row) => TrendingCity.fromSupabase(Map<String, dynamic>.from(row)),
          )
          .where((city) => city.id.isNotEmpty && city.cityName.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('TrendingCitiesService.listActive failed: $e');
      rethrow;
    }
  }
}
