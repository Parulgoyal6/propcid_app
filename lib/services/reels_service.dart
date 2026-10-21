import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReelsService {
  final _supabase = Supabase.instance.client;

  /// Fetches active, approved reels ordered newest-first, and merges in the
  /// two things `influencer_videos` itself does NOT store:
  ///
  ///   1. Builder/uploader identity — comes from `profiles` (keyed by
  ///      `user_id`), fetched as a separate query and merged client-side.
  ///      This mirrors the website's own `InfluencerVideoFeed.tsx`, which
  ///      does the exact same two-query merge (there's no FK from
  ///      `influencer_videos` to `profiles` for Postgrest to embed).
  ///
  ///   2. Linked property specs (price/location/beds/baths/parking/area/
  ///      amenities) — only present when a reel has a non-null
  ///      `property_id`. Fetched from `properties` (+ its
  ///      `properties_residential` / `properties_commercial` subtype rows,
  ///      the same embed already used by [PropertyService.getProperties]),
  ///      filtered to just the ids this batch of reels actually needs.
  ///
  /// Reels with no linked property, or whose uploader has a thin profile,
  /// simply get `null` for those nested keys — [ReelModel.fromSupabase]
  /// handles that gracefully.
  Future<List<Map<String, dynamic>>> getReels() async {
    final videos = await _supabase
        .from('influencer_videos')
        .select('*')
        .eq('status', 'active')
        .eq('approval_status', 'approved')
        .order('created_at', ascending: false);

    final videoRows = List<Map<String, dynamic>>.from(videos);

    // Listing videos: the portal's reel feed (reels-feed-list,
    // "reels-and-property-videos" mode) also shows every active, approved
    // `properties` row whose `media_urls` holds a video. Appended here in
    // the same `influencer_videos`-like shape so everything below (profile
    // merge, ReelModel.fromSupabase) handles both kinds unchanged.
    videoRows.addAll(await _getPropertyVideoRows());
    if (videoRows.isEmpty) return videoRows;

    // Newest first across both sources, as the portal's merge-sort does.
    videoRows.sort(
      (a, b) => (b['created_at']?.toString() ?? '').compareTo(
        a['created_at']?.toString() ?? '',
      ),
    );

    // ── Builder identity (profiles, keyed by user_id) ──────────────────
    final userIds = videoRows
        .map((v) => v['user_id'])
        .whereType<String>()
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> profilesByUserId = {};
    if (userIds.isNotEmpty) {
      final profiles = await _supabase
          .from('profiles')
          .select(
            'user_id,display_name,avatar_url,phone,verification_status,user_type,company_name,company_logo_url,comments_enabled',
          )
          .inFilter('user_id', userIds);

      for (final p in List<Map<String, dynamic>>.from(profiles)) {
        profilesByUserId[p['user_id'] as String] = p;
      }
    }

    // ── Linked property specs (properties + residential/commercial) ────
    final propertyIds = videoRows
        .where((v) => v['_property'] == null)
        .map((v) => v['property_id'])
        .whereType<String>()
        .toSet()
        .toList();

    final Map<String, Map<String, dynamic>> propertiesById = {};
    if (propertyIds.isNotEmpty) {
      final properties = await _supabase
          .from('properties')
          .select('*,properties_residential(*),properties_commercial(*)')
          .inFilter('id', propertyIds);

      for (final p in List<Map<String, dynamic>>.from(properties)) {
        propertiesById[p['id'] as String] = p;
      }
    }

    // Merge onto each video row under underscore-prefixed keys so they can
    // never collide with a real `influencer_videos` column name.
    for (final v in videoRows) {
      final userId = v['user_id'] as String?;
      final propertyId = v['property_id'] as String?;
      if (userId != null) v['_profile'] = profilesByUserId[userId];
      // A listing-video row already carries its own property as `_property`.
      if (propertyId != null && v['_property'] == null) {
        v['_property'] = propertiesById[propertyId];
      }
    }

    return videoRows;
  }

  /// Same video test as the portal's reels-feed-list `isVideoUrl`, which is
  /// also what the web wizard uses when it files a video into `media_urls`.
  static final RegExp _videoExtension = RegExp(
    r'\.(mp4|webm|ogg|mov|avi|m4v|mkv|3gp)$',
    caseSensitive: false,
  );
  static bool _isVideoUrl(String url) =>
      url.startsWith('data:video/') ||
      _videoExtension.hasMatch(url.split('?').first);

  /// Active, approved listings that have a video in `media_urls`, shaped
  /// like `influencer_videos` rows and tagged `_type: 'property_video'`.
  ///
  /// Bounded to the newest 200 listings — the same worst-case scan the
  /// portal's reels-feed-list allows (5 candidate pages × 40). A failure
  /// here only drops listing videos; influencer reels still load.
  Future<List<Map<String, dynamic>>> _getPropertyVideoRows() async {
    try {
      final rows = await _supabase
          .from('properties')
          .select('*,properties_residential(*),properties_commercial(*)')
          .eq('status', 'active')
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false)
          .limit(200);

      final result = <Map<String, dynamic>>[];
      for (final p in List<Map<String, dynamic>>.from(rows)) {
        final media = List<dynamic>.from(p['media_urls'] ?? const [])
            .map((u) => u?.toString() ?? '')
            .where((u) => u.trim().isNotEmpty)
            .toList();
        final videoUrl = media.where(_isVideoUrl).firstOrNull;
        if (videoUrl == null) continue;
        // Cover image: the listing's first photo (never the video itself).
        final cover = media.where((u) => !_isVideoUrl(u)).firstOrNull ?? '';

        result.add({
          'id': p['id'],
          'title': p['title'],
          'description': p['description'],
          'video_url': videoUrl,
          'thumbnail_url': cover,
          'video_type': 'property_listing',
          'views': p['views'],
          'likes': p['likes'],
          'comments': p['comments'],
          'hashtags': p['hashtags'] is List
              ? (p['hashtags'] as List).map((h) => h.toString()).toList()
              : null,
          'user_id': p['user_id'],
          'property_id': p['id'],
          'created_at': p['created_at'],
          '_type': 'property_video',
          '_property': p,
        });
      }
      return result;
    } catch (e) {
      debugPrint('ReelsService: listing videos failed to load: $e');
      return const [];
    }
  }
}
