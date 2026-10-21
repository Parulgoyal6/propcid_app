// services/city_roi_service.dart
//
// Read-only access to `public.city_roi_index`. Mirrors the portal's
// `useCityROIIndex.ts`: `is_active` filter, `roi_percentage` descending
// order, capped at 10 — the banner itself further slices to the top 5,
// reproduced by the caller rather than baked in here so the service's
// contract stays "everything active" like the rest of this app's services.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/city_roi.dart';

class CityRoiService {
  CityRoiService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'city_roi_index';

  Future<List<CityRoi>> listActive({int limit = 10}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(
            'id, city_name, state, roi_percentage, yoy_growth, '
            'avg_property_price, rental_yield, featured_image_url, '
            'display_order',
          )
          .eq('is_active', true)
          .order('roi_percentage', ascending: false)
          .limit(limit);

      return rows
          .map((row) => CityRoi.fromSupabase(Map<String, dynamic>.from(row)))
          .where((item) => item.id.isNotEmpty && item.cityName.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('CityRoiService.listActive failed: $e');
      rethrow;
    }
  }
}
