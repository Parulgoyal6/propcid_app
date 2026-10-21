import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/public_media_url.dart';
import '../models/social_models.dart';

/// Reads and writes for the Social module.
///
/// Ports both halves of `src/services/social/*`:
///   - `socialAccountsService` — `getAccount`/`getPreferences`/`savePreferences`/
///     `setAutoRefresh`/`syncFollowers`
///   - `analyticsService.getAnalytics`
///   - `campaignsService.listCampaigns` + `metaAdsService`'s campaign writes
///   - `adLeadsService` — `listLeads`/`updateLeadStatus`
///   - `shareLoggerService` — `listLogs`/`retryQueueItem`
///   - `queueService.enqueue` (the "Publish Everywhere" queue insert)
///   - `captionGeneratorService.generateCaption`
///
/// Every write here calls the *exact same* Supabase table or `meta-*` Edge
/// Function the portal does — no new backend, no secrets, no service-role
/// key. `MetaOAuthService` (a separate file) owns the connect/select-page/
/// disconnect calls specifically, since those also drive the mobile-only
/// OAuth redirect dance.
class SocialService {
  /// Resolved lazily so the class can be referenced without an initialised
  /// Supabase client.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Same "a 200 response can still carry `{error}`" unwrap as
  /// `EdgeFunctionsService`/`MetaOAuthService`/`edgeError.ts`.
  Future<Map<String, dynamic>> _invoke(
    String function, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _supabase.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ??
          'Could not reach the server. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  /// The caller's Meta connection.
  ///
  /// Reads `social_accounts_safe`, never the base table: the base table carries
  /// the encrypted OAuth tokens and their IVs, and those must not reach a
  /// client. React reads the same view for the same reason.
  Future<SocialAccount?> getAccount(String userId) async {
    try {
      final row = await _supabase
          .from('social_accounts_safe')
          .select()
          .eq('user_id', userId)
          .eq('provider', 'meta')
          .maybeSingle();

      if (row == null) return null;
      return SocialAccount.fromJson(row);
    } catch (e) {
      debugPrint('SocialService.getAccount failed: $e');
      rethrow;
    }
  }

  /// Share preferences, falling back to React's `DEFAULT_PREFERENCES` when the
  /// user has never saved a row.
  Future<SocialPreferences> getPreferences(String userId) async {
    try {
      final row = await _supabase
          .from('social_share_preferences')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return SocialPreferences.defaults;
      return SocialPreferences.fromJson(row);
    } catch (e) {
      debugPrint('SocialService.getPreferences failed: $e');
      rethrow;
    }
  }

  /// The most recent publish records, newest first.
  Future<List<ShareLog>> listLogs(String userId, {int limit = 100}) async {
    try {
      final rows = await _supabase
          .from('social_share_logs')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => ShareLog.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('SocialService.listLogs failed: $e');
      rethrow;
    }
  }

  /// The live publish queue, newest first — `queueService.listQueue`. This is
  /// what the Activity screen renders: `social_share_logs` (above) never
  /// carries a `queued` or `canceled` row, only what a worker attempt already
  /// resolved to.
  Future<List<ShareQueueItem>> listQueue(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _supabase
          .from('social_share_queue')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map(
            (r) => ShareQueueItem.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('SocialService.listQueue failed: $e');
      rethrow;
    }
  }

  /// Publishing analytics.
  ///
  /// React reads up to 500 logs and counts the queue separately; both are done
  /// here so the derivation stays identical.
  Future<SocialAnalytics> getAnalytics(String userId) async {
    try {
      final logs = await listLogs(userId, limit: 500);

      // `head: true` with an exact count returns the number without the rows.
      final pending = await _supabase
          .from('social_share_queue')
          .select('id')
          .eq('user_id', userId)
          .inFilter('status', ['queued', 'processing'])
          .count(CountOption.exact);

      return SocialAnalytics.fromLogs(logs, pending: pending.count);
    } catch (e) {
      debugPrint('SocialService.getAnalytics failed: $e');
      rethrow;
    }
  }

  Future<List<AdCampaign>> listCampaigns(String userId) async {
    try {
      final rows = await _supabase
          .from('social_ad_campaigns')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((r) => AdCampaign.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('SocialService.listCampaigns failed: $e');
      rethrow;
    }
  }

  Future<List<AdLead>> listLeads(String userId) async {
    try {
      final rows = await _supabase
          .from('social_ad_leads')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((r) => AdLead.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      debugPrint('SocialService.listLeads failed: $e');
      rethrow;
    }
  }

  /// Subscribes to every change on this user's `social_ad_leads` rows — a
  /// direct port of `adLeadsService.subscribeLeads`. The portal re-fetches the
  /// whole list on any event rather than diffing, and so does the caller here;
  /// this just hands back the channel.
  ///
  /// Follows the same open/hand-back/dispose contract as
  /// `NotificationService.subscribe`: the caller supplies [channelSuffix] (a
  /// per-instance discriminator) since two widgets on one channel name would
  /// otherwise receive each other's events.
  RealtimeChannel subscribeLeads({
    required String userId,
    required String channelSuffix,
    required VoidCallback onChange,
  }) {
    return _supabase
        .channel('ad-leads-$userId-$channelSuffix')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'social_ad_leads',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Stops a subscription started by [subscribeLeads]. Swallows its own
  /// failure: this is called from `dispose`, which must not throw.
  Future<void> unsubscribeChannel(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (e) {
      debugPrint('SocialService.unsubscribeChannel failed: $e');
    }
  }

  // ── Accounts / connection writes ────────────────────────────────────────

  Future<void> setAutoRefresh(String userId, bool enabled) async {
    await _supabase
        .from('social_accounts')
        .update({'auto_refresh': enabled})
        .eq('user_id', userId)
        .eq('provider', 'meta');
  }

  /// Upserts the caller's preferences row, matching
  /// `socialAccountsService.savePreferences`'s `onConflict: user_id`.
  Future<void> savePreferences(String userId, SocialPreferences prefs) async {
    await _supabase.from('social_share_preferences').upsert({
      'user_id': userId,
      'auto_share_property': prefs.autoShareProperty,
      'auto_share_projects': prefs.autoShareProjects,
      'auto_share_videos': prefs.autoShareVideos,
      'auto_share_reels': prefs.autoShareReels,
      'auto_share_blogs': prefs.autoShareBlogs,
      'auto_share_promotions': prefs.autoSharePromotions,
      'auto_share_open_houses': prefs.autoShareOpenHouses,
      'fb_enabled': prefs.fbEnabled,
      'ig_enabled': prefs.igEnabled,
      'ig_feed': prefs.igFeed,
      'ig_reel': prefs.igReel,
      'fb_story': prefs.fbStory,
      'ig_story': prefs.igStory,
      'default_caption_template': prefs.defaultCaptionTemplate,
      'default_hashtags': prefs.defaultHashtags,
      'default_cta': prefs.defaultCta,
      'auto_share_rule': prefs.autoShareRule,
    }, onConflict: 'user_id');
  }

  /// Pulls fresh FB/IG follower counts — `meta-followers-sync`.
  Future<SocialAccount?> syncFollowers(String userId) async {
    await _invoke('meta-followers-sync');
    return getAccount(userId);
  }

  // ── Ad account selection ─────────────────────────────────────────────────

  Future<List<MetaAdAccount>> listAdAccounts() async {
    final result = await _invoke('meta-list-ad-accounts');
    return (result['accounts'] as List? ?? const [])
        .whereType<Map>()
        .map((a) => MetaAdAccount.fromJson(Map<String, dynamic>.from(a)))
        .toList();
  }

  Future<void> selectAdAccount(String adAccountId) =>
      _invoke('meta-select-ad-account', body: {'ad_account_id': adAccountId});

  // ── Campaigns ────────────────────────────────────────────────────────────

  /// Creates a Meta campaign + ad set + creative + ad, always PAUSED —
  /// `meta-campaign-create`. `body` is the same shape as the portal's
  /// `CreateCampaignInput` (content_type, content_id, objective,
  /// daily_budget_minor, start_time, end_time, targeting_overrides,
  /// creative_overrides, name) — built by the caller so this stays a thin
  /// passthrough, same as `metaAdsService.createCampaign`.
  Future<AdCampaign> createCampaign(Map<String, dynamic> body) async {
    final result = await _invoke('meta-campaign-create', body: body);
    return AdCampaign.fromJson(
      Map<String, dynamic>.from(result['campaign'] as Map),
    );
  }

  Future<AdCampaign> updateCampaign(
    String campaignId, {
    String? action,
    int? dailyBudgetMinor,
  }) async {
    final result = await _invoke(
      'meta-campaign-update',
      body: {
        'campaign_id': campaignId,
        if (action != null) 'action': action,
        if (dailyBudgetMinor != null) 'daily_budget_minor': dailyBudgetMinor,
      },
    );
    return AdCampaign.fromJson(
      Map<String, dynamic>.from(result['campaign'] as Map),
    );
  }

  /// Pulls live spend/impressions/clicks/leads/effective_status —
  /// `meta-campaign-sync`.
  Future<int> syncCampaigns() async {
    final result = await _invoke('meta-campaign-sync');
    final synced = result['synced'];
    return synced is int ? synced : int.tryParse('$synced') ?? 0;
  }

  Future<List<GeoSearchResult>> searchTargeting(String query) async {
    if (query.trim().length < 2) return const [];
    final result = await _invoke('meta-targeting-search', body: {'q': query});
    final list = result['results'] ?? result['data'];
    final raw = list is List ? list : const [];
    return raw
        .whereType<Map>()
        .map((r) => GeoSearchResult.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Leads ────────────────────────────────────────────────────────────────

  Future<void> updateLeadStatus(String leadId, String status) async {
    await _supabase
        .from('social_ad_leads')
        .update({'status': status})
        .eq('id', leadId);
  }

  /// Pulls new Meta lead-form submissions — `meta-leads-sync`.
  Future<int> syncLeads() async {
    final result = await _invoke('meta-leads-sync');
    final ingested = result['ingested'];
    return ingested is int ? ingested : int.tryParse('$ingested') ?? 0;
  }

  // ── Publishing (queue) ───────────────────────────────────────────────────

  /// Inserts one `social_share_queue` row per platform — inserting fires the
  /// DB dispatch trigger (`pg_net` → `social-publish-worker`) server-side, so
  /// this insert *is* the publish call, same as `queueService.enqueue`.
  Future<void> enqueuePublish({
    required String userId,
    required String contentType,
    required String contentId,
    required List<Map<String, dynamic>> jobs,
  }) async {
    if (jobs.isEmpty) return;
    await _supabase.from('social_share_queue').insert([
      for (final job in jobs)
        {
          'user_id': userId,
          'content_type': contentType,
          'content_id': contentId,
          'platform': job['platform'],
          'targets': job['targets'],
          'payload': job['payload'],
        },
    ]);
  }

  /// Clones a failed job into a brand-new queued row rather than updating the
  /// old one in place — a direct port of `shareLoggerService.retryQueueItem`,
  /// so the insert trigger fires again immediately.
  ///
  /// Takes the queue item itself (not a finished log row): `targets` and
  /// `payload` are cloned verbatim from what actually failed, rather than
  /// guessed (the previous version of this method took a `ShareLog`, which
  /// never carried `targets` at all, and hardcoded `['feed']`).
  Future<void> retryQueueItem(ShareQueueItem item) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _supabase.from('social_share_queue').insert({
      'user_id': item.userId,
      'platform': item.platform,
      'content_type': item.contentType,
      'content_id': item.contentId,
      'targets': item.targets,
      'payload': item.payload,
      'status': 'queued',
      'scheduled_at': now,
      'next_attempt_at': now,
    });
  }

  /// Turns a platform/destination selection into queue jobs and enqueues them
  /// — a direct port of `socialShareService.publish`. One job per
  /// platform+target combination, exactly as the portal builds them.
  ///
  /// Also writes the `social_publish_started` notification row the portal
  /// writes after enqueuing (`socialShareService.ts:59-65`), using a direct
  /// insert rather than a shared helper — matching this app's existing
  /// convention of each write-service owning its own `notifications` insert
  /// (`project_share_service`, `profile_connection_service` ×2,
  /// `builder_sections_service`, `broker_sections_service`); see
  /// `NotificationService`'s doc comment for why a sixth copy there would be
  /// wrong but a direct insert here is the established pattern. Best-effort:
  /// a failed notification must not block a queued publish.
  ///
  /// Returns the number of jobs queued.
  Future<int> publishEverywhere({
    required String userId,
    required String contentType,
    required String contentId,
    required List<String> facebook,
    required List<String> instagram,
    required Map<String, String> captions,
    required List<String> mediaUrls,
    String? cta,
    String? scheduledAt,
  }) async {
    final media = mediaUrls.where((u) => u.isNotEmpty).toList();
    final jobs = <Map<String, dynamic>>[
      for (final target in facebook)
        {
          'platform': 'facebook',
          'targets': [target],
          'payload': {
            'caption': captions['facebook'] ?? '',
            'media_urls': media,
            if (cta != null) 'cta': cta,
          },
          if (scheduledAt != null) 'scheduled_at': scheduledAt,
        },
    ];

    // Instagram Feed — unlike Story, and unlike Facebook Feed/Story — rejects
    // images outside a 4:5-1.91:1 aspect ratio ("The aspect ratio is not
    // supported"). Only the `feed` target routes media through
    // `_instagramFeedMediaUrls`; `story` keeps using the same URLs as
    // Facebook, exactly as before.
    for (final target in instagram) {
      final targetMedia = target == 'feed'
          ? await _instagramFeedMediaUrls(userId, media)
          : media;
      jobs.add({
        'platform': 'instagram',
        'targets': [target],
        'payload': {
          'caption': captions['instagram'] ?? '',
          'media_urls': targetMedia,
          if (cta != null) 'cta': cta,
        },
        if (scheduledAt != null) 'scheduled_at': scheduledAt,
      });
    }

    if (jobs.isEmpty) return 0;

    await enqueuePublish(
      userId: userId,
      contentType: contentType,
      contentId: contentId,
      jobs: jobs,
    );

    final platforms = [
      if (facebook.isNotEmpty) 'Facebook',
      if (instagram.isNotEmpty) 'Instagram',
    ].join(' & ');
    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'type': 'social_publish_started',
        'title': 'Publishing started',
        'message': 'Publishing your $contentType to $platforms…',
        'data': {
          'route': '/social-media',
          'content_type': contentType,
          'content_id': contentId,
        },
      });
    } catch (e) {
      debugPrint('SocialService.publishEverywhere notification failed: $e');
    }

    return jobs.length;
  }

  // ── Instagram Feed aspect-ratio normalisation ───────────────────────────

  /// Instagram Feed's accepted image aspect-ratio range (width/height). Meta
  /// only enforces this for Feed — Facebook Feed/Story and Instagram Story
  /// have no such restriction, which is why only the `feed` target above
  /// calls [_instagramFeedMediaUrls].
  static const double _kIgFeedMinRatio = 0.8; // 4:5 portrait
  static const double _kIgFeedMaxRatio = 1.91; // widest landscape Feed allows

  static const Set<String> _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
  };

  /// True for a recognised image extension, false for anything else
  /// (mp4/mov/... or no extension) — videos must never be downloaded/decoded
  /// as an image.
  bool _looksLikeImage(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot == -1) return false;
    return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  /// Returns [urls] unchanged for videos and for images already inside
  /// Instagram Feed's 4:5-1.91:1 range (no re-upload, no extra file). For an
  /// out-of-range image — e.g. the 864x1920 property photo that fails with
  /// "The aspect ratio is not supported" — downloads it, center-crops to the
  /// nearest in-range boundary (4:5 portrait for a too-tall source, which is
  /// the common case for property photos), re-encodes as JPEG, and uploads
  /// the derived copy into the same `property-media` bucket the property
  /// upload flow already writes to (`PropertyService._uploadMedia`) — same
  /// bucket, same authenticated Storage access, no new policy or Edge
  /// Function involved. The original property image is never modified or
  /// overwritten.
  ///
  /// Throws (rather than silently falling back to the original URL) if a
  /// source image can't be downloaded, decoded, or the derived copy can't be
  /// uploaded — a bad image must surface as a visible publish failure via
  /// the caller's existing error handling, not queue an Instagram Feed job
  /// Meta is certain to reject anyway.
  Future<List<String>> _instagramFeedMediaUrls(
    String userId,
    List<String> urls,
  ) async {
    final result = <String>[];
    for (final url in urls) {
      if (!_looksLikeImage(url)) {
        result.add(url); // video — left untouched
        continue;
      }

      final http.Response res;
      try {
        res = await http.get(Uri.parse(url));
      } catch (e) {
        throw 'Could not download the image for Instagram Feed: $e';
      }
      if (res.statusCode != 200) {
        throw 'Could not download the image for Instagram Feed '
            '(HTTP ${res.statusCode}).';
      }

      final decoded = img.decodeImage(res.bodyBytes);
      if (decoded == null) {
        throw 'Could not read the image for Instagram Feed.';
      }

      final ratio = decoded.width / decoded.height;
      debugPrint(
        'SocialService: target=instagram/feed original=${decoded.width}x'
        '${decoded.height} ratio=${ratio.toStringAsFixed(3)}',
      );

      if (ratio >= _kIgFeedMinRatio && ratio <= _kIgFeedMaxRatio) {
        debugPrint(
          'SocialService: target=instagram/feed normalisation=not-required',
        );
        result.add(url);
        continue;
      }

      // Center-crop to whichever in-range boundary is closest to the
      // source, trimming only the excess dimension so as much of the
      // original frame survives as possible.
      final img.Image cropped;
      if (ratio < _kIgFeedMinRatio) {
        // Too tall (e.g. 864x1920): keep the full width, crop height down to
        // a 4:5 portrait — trims the top and bottom only.
        final targetHeight = (decoded.width / _kIgFeedMinRatio).round();
        final y = ((decoded.height - targetHeight) / 2).round();
        cropped = img.copyCrop(
          decoded,
          x: 0,
          y: y,
          width: decoded.width,
          height: targetHeight,
        );
      } else {
        // Too wide (beyond 1.91:1): keep the full height, crop width down —
        // trims the left and right only.
        final targetWidth = (decoded.height * _kIgFeedMaxRatio).round();
        final x = ((decoded.width - targetWidth) / 2).round();
        cropped = img.copyCrop(
          decoded,
          x: x,
          y: 0,
          width: targetWidth,
          height: decoded.height,
        );
      }
      debugPrint(
        'SocialService: target=instagram/feed normalisation=required '
        'derived=${cropped.width}x${cropped.height}',
      );

      final jpg = Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
      final path =
          '$userId/ig-feed-${DateTime.now().millisecondsSinceEpoch}.jpg';
      try {
        await _supabase.storage.from('property-media').uploadBinary(
              path,
              jpg,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
      } catch (e) {
        throw 'Could not upload the Instagram Feed image: $e';
      }
      result.add(
        PublicMediaUrl.resolve(
          _supabase.storage.from('property-media').getPublicUrl(path),
        ),
      );
    }
    return result;
  }

  /// AI-generated caption/hashtags/CTA for one piece of content —
  /// `meta-caption-generate`. Degrades to an empty result on any failure,
  /// same as `captionGeneratorService.generateCaption` — never blocks the
  /// publish dialog on a caption-generation hiccup.
  Future<Map<String, dynamic>> generateCaption({
    required String contentType,
    required String contentId,
    required String platform,
    String? tone,
  }) async {
    try {
      return await _invoke(
        'meta-caption-generate',
        body: {
          'content_type': contentType,
          'content_id': contentId,
          'platform': platform,
          if (tone != null) 'tone': tone,
        },
      );
    } catch (e) {
      debugPrint('SocialService.generateCaption failed: $e');
      return const {'caption': '', 'hashtags': [], 'cta': null};
    }
  }
}
