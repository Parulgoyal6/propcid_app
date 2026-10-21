// services/feed_service.dart
//
// Fetches the "Feed" screen's content: the same three tables the portal's
// CombinedFeed merges (propcid/src/features/content/CombinedFeed.tsx) —
// `properties`, `builder_projects`, `influencer_videos` — each filtered to
// active/approved rows and capped at the portal's own limits (50/30/50),
// plus a single bulk `profiles` lookup for every poster involved, exactly
// mirroring the portal's own separate profiles query rather than relying on
// a PostgREST embed (builder_projects/influencer_videos have no embed
// relationship to `profiles` proven elsewhere in this codebase; `properties`
// does, in property_service.dart's searchProperties, but this method stays
// consistent with the portal's actual approach instead of assuming the same
// embed resolves for the other two tables too).
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_item.dart';

class FeedService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<FeedItem>> fetchFeed() async {
    final results = await Future.wait([
      _supabase
          .from('properties')
          .select(
            'id, title, price, location, media_urls, user_id, created_at, views, likes, comments, category, property_type',
          )
          .inFilter('status', ['active', 'sold'])
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(50),
      _supabase
          .from('influencer_videos')
          .select(
            'id, user_id, title, thumbnail_url, video_url, created_at, views, likes',
          )
          .eq('status', 'active')
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(50),
      _supabase
          .from('builder_projects')
          .select(
            'id, title, location, media_urls, builder_id, created_at, views, '
            'likes, comments, project_type, price_range_min, price_range_max',
          )
          .eq('status', 'active')
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(30),
    ]);

    final propertyRows = List<Map<String, dynamic>>.from(results[0]);
    final videoRows = List<Map<String, dynamic>>.from(results[1]);
    final projectRows = List<Map<String, dynamic>>.from(results[2]);

    final posterIds = <String>{
      for (final r in propertyRows)
        if (r['user_id'] != null) r['user_id'].toString(),
      for (final r in videoRows)
        if (r['user_id'] != null) r['user_id'].toString(),
      for (final r in projectRows)
        if (r['builder_id'] != null) r['builder_id'].toString(),
    };

    final profilesById = <String, Map<String, dynamic>>{};
    if (posterIds.isNotEmpty) {
      final profileRows = await _supabase
          .from('profiles')
          .select('user_id, display_name, avatar_url, user_type')
          .inFilter('user_id', posterIds.toList());
      for (final row in List<Map<String, dynamic>>.from(profileRows)) {
        final id = row['user_id']?.toString();
        if (id != null) profilesById[id] = row;
      }
    }

    final items = <FeedItem>[
      for (final r in propertyRows)
        FeedItem.fromProperty(r, profilesById[r['user_id']?.toString()]),
      for (final r in videoRows)
        FeedItem.fromVideo(r, profilesById[r['user_id']?.toString()]),
      for (final r in projectRows)
        FeedItem.fromProject(r, profilesById[r['builder_id']?.toString()]),
    ];

    items.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return items;
  }

  /// The Exclusive tab's offers — the portal's exact call:
  /// `combined-feed-list` with `category: 'exclusive-offers'`. The function
  /// itself enforces who sees what (brokers: active offers from builders in
  /// their accepted network; admins: all; anyone else: none), so no access
  /// logic is duplicated here. One page of the function's max (50), matching
  /// this feed's existing single-fetch loading.
  Future<List<FeedOffer>> fetchExclusiveOffers() async {
    final response = await _supabase.functions.invoke(
      'combined-feed-list',
      body: {'category': 'exclusive-offers', 'limit': 50},
    );
    final data = response.data;
    if (data is! Map) return const [];
    final items = data['items'];
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['type'] == 'offer' && item['data'] is Map)
          FeedOffer.fromJson(Map<String, dynamic>.from(item['data'] as Map)),
    ];
  }

  /// Feed-shaped property items for specific [ids] - the same columns, poster
  /// lookup and [FeedItem.fromProperty] mapping [fetchFeed] uses, so another
  /// screen (Property Detail's Related Properties) can show the exact card the
  /// Feed shows. Returned in [ids] order; an id that cannot be loaded (or is
  /// not approved) is simply absent.
  Future<List<FeedItem>> fetchPropertyItems(List<String> ids) async {
    if (ids.isEmpty) return const [];

    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('properties')
          .select(
            'id, title, price, location, media_urls, user_id, created_at, views, likes, comments, category, property_type',
          )
          .inFilter('id', ids)
          .eq('approval_status', 'approved'),
    );

    final posterIds = <String>{
      for (final r in rows)
        if (r['user_id'] != null) r['user_id'].toString(),
    };

    final profilesById = <String, Map<String, dynamic>>{};
    if (posterIds.isNotEmpty) {
      final profileRows = await _supabase
          .from('profiles')
          .select('user_id, display_name, avatar_url, user_type')
          .inFilter('user_id', posterIds.toList());
      for (final row in List<Map<String, dynamic>>.from(profileRows)) {
        final id = row['user_id']?.toString();
        if (id != null) profilesById[id] = row;
      }
    }

    final byId = <String, FeedItem>{
      for (final r in rows)
        r['id'].toString(): FeedItem.fromProperty(
          r,
          profilesById[r['user_id']?.toString()],
        ),
    };
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
  }
}
