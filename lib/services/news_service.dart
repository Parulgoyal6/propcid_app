// services/news_service.dart
//
// Read-only access to `public.news`. No write path exists here in any form.
//
// The query is the portal's `hooks/useNews.ts` verbatim — the same column list
// and the same two-key ordering. `display_order` ascending is the admin's manual
// sequence; `published_at` descending breaks ties so two items sharing an order
// value still land newest-first rather than in arbitrary row order.
//
// No `is_active` filter is *needed* — the RLS policy is
// `USING (is_active = true)` (20260717120000:20-23) — but it is sent anyway, so
// the query states its own intent and does not silently depend on a policy a
// future migration might widen.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/news_item_model.dart';

class NewsService {
  NewsService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'news';

  /// Column list from `useNews.ts:23`.
  static const String columns =
      'id, title, summary, image_url, video_url, link_url, source, '
      'display_order, published_at';

  /// Every active news item, in the portal's order.
  ///
  /// Rethrows so the section can tell a failure apart from an empty table: an
  /// empty table hides the section, a failure keeps it hidden too but is worth
  /// a log line rather than being silently indistinguishable.
  Future<List<NewsItemModel>> listActive() async {
    try {
      final rows = await _supabase
          .from(_table)
          .select(columns)
          .eq('is_active', true)
          .order('display_order', ascending: true)
          .order('published_at', ascending: false);

      return rows
          .map(
            (row) => NewsItemModel.fromSupabase(Map<String, dynamic>.from(row)),
          )
          .where((item) => item.id.isNotEmpty && item.title.isNotEmpty)
          .toList(growable: false);
    } catch (e) {
      debugPrint('NewsService.listActive failed: $e');
      rethrow;
    }
  }
}
