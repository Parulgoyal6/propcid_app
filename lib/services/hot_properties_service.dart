// services/hot_properties_service.dart
//
// Read-only access to `public.hot_properties`, the admin-curated join table
// that decides which `properties` rows are "Featured" — mirrors the portal's
// `hot_properties -> properties(*)` query in `PublicHomePage.tsx` /
// `AuthenticatedHomePage.tsx` (`fetchProjects`) and its render path,
// `HotPropertiesGrid.tsx`.
//
// WHY THIS EXISTS SEPARATELY FROM `PropertyProvider.getFeaturedProperties()`
// ---------------------------------------------------------------------------
// The existing `getFeaturedProperties()` treats any property with
// `views >= 1` as "featured" — a client-side proxy, not a real admin flag.
// That proxy is left untouched here because `PropertyModel.isFeatured` (and
// the "Featured" ribbon it drives on `PropertyCardVertical` everywhere it's
// used — search results, reels, property detail) is a separate, pre-existing
// concern outside the Home screen's scope.
//
// The portal has no `is_featured` column on `properties` at all — curation
// happens entirely through this join table, keyed by `property_id`. This
// service reproduces that exactly, so the Home "Featured Properties" rail
// shows genuinely admin-curated listings instead of "whatever got opened at
// least once".
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/property_model.dart';

class HotPropertiesService {
  HotPropertiesService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'hot_properties';

  /// Mirrors `HotPropertiesGrid`'s row filter: `status` must be `active` or
  /// `sold` (a curated listing may legitimately have just sold and still be
  /// worth showing with a "sold" treatment) and `approval_status` must be
  /// `approved`.
  static const List<String> _allowedStatuses = ['active', 'sold'];

  /// Active-admin-curated properties, in the admin's configured order.
  ///
  /// Rethrows on failure so the caller can distinguish "no curated listings
  /// yet" from "the request failed", same reasoning as [NewsService].
  Future<List<PropertyModel>> listActive({int limit = 10}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(
            'id, property_id, display_order, '
            'properties(*,properties_residential(*),properties_commercial(*),properties_land(*))',
          )
          .order('display_order', ascending: true)
          .limit(limit);

      final result = <PropertyModel>[];
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final propertyRow = row['properties'] as Map<String, dynamic>?;
        if (propertyRow == null) continue;

        final status = propertyRow['status']?.toString();
        final approvalStatus = propertyRow['approval_status']?.toString();
        if (approvalStatus != 'approved') continue;
        if (!_allowedStatuses.contains(status)) continue;

        result.add(PropertyModel.fromSupabase(propertyRow));
      }
      return result;
    } catch (e) {
      debugPrint('HotPropertiesService.listActive failed: $e');
      rethrow;
    }
  }
}
