// services/investors_corner_service.dart
//
// Read-only access to `public.investors_corner`. Mirrors the portal's
// `useInvestorsCorner.ts`: same column filter, same `display_order` sort.
// No hardcoded sample opportunities are substituted when the table is empty
// — that fallback is a purely visual placeholder on the web side; this app
// must never show invented data in place of admin-controlled content.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/investor_opportunity.dart';

class InvestorsCornerService {
  InvestorsCornerService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'investors_corner';

  Future<List<InvestorOpportunity>> listActive({int limit = 10}) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(
            'id, title, description, location, investment_amount, '
            'expected_roi_percentage, rental_yield_percentage, '
            'appreciation_percentage, time_period_months, '
            'featured_image_url, display_order',
          )
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .limit(limit);

      return rows
          .map(
            (row) => InvestorOpportunity.fromSupabase(
              Map<String, dynamic>.from(row),
            ),
          )
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('InvestorsCornerService.listActive failed: $e');
      rethrow;
    }
  }
}
