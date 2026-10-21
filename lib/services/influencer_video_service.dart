// services/influencer_video_service.dart
//
// Read and write access to `influencer_videos` for the influencer content flow.
//
// WHY A COMPANION SERVICE RATHER THAN NEW METHODS ON InfluencerCampaignService
// ---------------------------------------------------------------------------
// `InfluencerCampaignService.getVideos` returns `InfluencerCampaignModel`, which
// carries 8 of the table's 16 columns and cannot round-trip a row (no
// `video_type`, which is NOT NULL and CHECK-constrained). Appending writes there
// would mean either widening that model — changing what the dashboard's existing
// "Recent Videos" strip receives — or having one service speak two models. It also
// swallows every error and returns `[]`, which is defensible for a decorative strip
// and wrong for an editor, where "no videos" and "the fetch failed" must not look
// alike.
//
// So: new file, new model, and `InfluencerCampaignService` /
// `InfluencerCampaignModel` / `InfluencerRecentCampaignsWidget` are untouched.
//
// DELETE IS SOFT, WHICH IS A CHOICE BETWEEN TWO PORTAL BEHAVIOURS
// --------------------------------------------------------------
// The portal deletes videos two different ways:
//
//   SellerWall.tsx:302                  softDeleteContent('influencer_videos', id)
//   InfluencerContentManager.tsx:76-80  .from('influencer_videos').delete()
//
// The second was never migrated. `src/lib/softDelete.ts` explains why the first
// exists: a hard delete runs the table's ON DELETE CASCADE immediately, and gives
// no undo. The `soft_delete_content` RPC it calls is live — it is in
// `supabase/migrations/`, not the unapplied `migration2/` set — is SECURITY
// INVOKER, so the existing RLS UPDATE policy still decides who may touch the row,
// and is granted to `authenticated`
// (20270318040000_soft_delete_content.sql:73-116). A RESTRICTIVE SELECT policy
// hides soft-deleted rows from every client read, and `purge_soft_deleted()`
// hard-deletes them after 30 days, which is when the cascades finally run.
//
// This service follows SellerWall. Copying the un-migrated path would mean
// deliberately choosing the version the portal's own comments describe as the bug.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/influencer_video_options.dart';
import '../models/influencer_video_model.dart';

/// Raised when a write is refused before it is attempted.
class InfluencerVideoException implements Exception {
  const InfluencerVideoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The form's contents, ready to become an `influencer-video-save` request.
///
/// Mirrors `InfluencerVideoModal`'s `formData` plus the two resolved media
/// URLs, and — for a `property_listing` video — the property fields the
/// edge function validates and writes via its own `buildPropertyFields`.
class InfluencerVideoDraft {
  const InfluencerVideoDraft({
    required this.title,
    required this.videoType,
    required this.videoUrl,
    this.description = '',
    this.thumbnailUrl,
    this.hashtagsText = '',
    this.propertyLocation,
    this.propertyPrice,
    this.propertyListingType,
    this.propertyCategory,
    this.propertyBedrooms,
    this.propertyBathrooms,
    this.propertyArea,
  });

  final String title;
  final String description;
  final String videoType;
  final String videoUrl;
  final String? thumbnailUrl;

  /// Raw comma-separated text, exactly as the form field holds it —
  /// `influencer-video-save` does its own split/trim/lowercase/dedupe/cap
  /// (`normaliseHashtags`), so this is sent as-is rather than pre-parsed.
  final String hashtagsText;

  /// Only meaningful when [videoType] is `property_listing`; sent regardless
  /// so a switch away from that type still reaches the server, which forces
  /// every property_* column to null for any other type
  /// (`buildPropertyFields`) — clearing stale data is the *server's* job,
  /// not something this draft needs to special-case.
  final String? propertyLocation;
  final String? propertyPrice;
  final String? propertyListingType;
  final String? propertyCategory;
  final int? propertyBedrooms;
  final int? propertyBathrooms;
  final String? propertyArea;

  /// The `influencer-video-save` request body, minus `mode`/`videoId` (added
  /// by the caller) — see that function's `RequestBody` interface.
  Map<String, dynamic> toRequestBody() => <String, dynamic>{
    'title': title,
    'description': description,
    'videoUrl': videoUrl,
    'thumbnailUrl': thumbnailUrl,
    'videoType': videoType,
    'hashtags': hashtagsText,
    if (videoType == 'property_listing') ...{
      'propertyLocation': propertyLocation,
      'propertyPrice': propertyPrice,
      'propertyListingType': propertyListingType,
      'propertyCategory': propertyCategory,
      'propertyBedrooms': propertyBedrooms,
      'propertyBathrooms': propertyBathrooms,
      'propertyArea': propertyArea,
    },
  };
}

class InfluencerVideoService {
  InfluencerVideoService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'influencer_videos';

  /// This influencer's videos, newest first.
  ///
  /// The portal's fetch, filter for filter: `.eq('user_id', user.id)
  /// .order('created_at', { ascending: false })`
  /// (InfluencerContentManager.tsx:55-59). No `deleted_at` predicate is needed —
  /// the RESTRICTIVE policy from 20270318040000 already hides those rows from every
  /// client read.
  ///
  /// Errors propagate, unlike `InfluencerCampaignService.getVideos`: the content
  /// library has to tell "you have no videos" apart from "the fetch failed".
  Future<List<InfluencerVideoModel>> listMine(String userId) async {
    final rows = await _supabase
        .from(table)
        .select(InfluencerVideoModel.columns)
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(
      rows,
    ).map(InfluencerVideoModel.fromSupabase).toList();
  }

  /// One video by id, or null when it is not visible to the caller.
  Future<InfluencerVideoModel?> fetchById(String videoId) async {
    final row = await _supabase
        .from(table)
        .select(InfluencerVideoModel.columns)
        .eq('id', videoId)
        .maybeSingle();

    if (row == null) return null;
    return InfluencerVideoModel.fromSupabase(row);
  }

  /// Creates a video via the `influencer-video-save` edge function and
  /// returns its id.
  ///
  /// Routed through the function rather than a direct table insert so
  /// `user_id` is set server-side from the caller's JWT (never client-
  /// trusted) and so every validation rule the function enforces — title/
  /// description length caps, the `video_type` CHECK, hashtag
  /// normalisation, and every property_* rule below — actually runs, not
  /// just the client-side subset [_validate] repeats for a fast local error.
  Future<String> create(InfluencerVideoDraft draft) async {
    _validate(draft);

    final data = await _invoke({'mode': 'create', ...draft.toRequestBody()});
    final id = data['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const InfluencerVideoException('Could not save this video.');
    }
    return id;
  }

  /// Updates an existing video via `influencer-video-save`, which re-queues
  /// a non-admin's edit for review (`resubmit_for_approval`) atomically with
  /// the edit itself — see that function's own header comment for why this
  /// replaced the portal's old two-step, non-atomic path.
  Future<void> update(String videoId, InfluencerVideoDraft draft) async {
    _validate(draft);

    await _invoke({
      'mode': 'edit',
      'videoId': videoId,
      ...draft.toRequestBody(),
    });
  }

  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — same unwrap every other edge-function caller in this app uses
  /// (`DashboardAnalyticsService`/`MetaOAuthService`/`EdgeFunctionsService`).
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.functions.invoke(
        'influencer-video-save',
        body: body,
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw InfluencerVideoException(data['error'].toString());
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on InfluencerVideoException {
      rethrow;
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw InfluencerVideoException(
        message?.toString() ?? 'Could not save this video. Please try again.',
      );
    } catch (e) {
      throw const InfluencerVideoException(
        'A network error occurred. Please try again.',
      );
    }
  }

  /// Retires a video via `soft_delete_content`.
  ///
  /// Returns true when a row was retired, false when it was already soft-deleted or
  /// RLS matched nothing — the same contract as the portal's `softDeleteContent`,
  /// which distinguishes the two so an RLS denial cannot read as success.
  Future<bool> softDelete(String videoId) async {
    final result = await _supabase.rpc(
      'soft_delete_content',
      params: <String, dynamic>{'p_table': table, 'p_id': videoId},
    );
    return result == true;
  }

  /// Undoes a soft delete. Unused by the current UI; present because
  /// `restore_content` is granted to `authenticated` and a delete this service can
  /// perform should be one it can also reverse.
  @visibleForTesting
  Future<bool> restore(String videoId) async {
    final result = await _supabase.rpc(
      'restore_content',
      params: <String, dynamic>{'p_table': table, 'p_id': videoId},
    );
    return result == true;
  }

  /// Refuses a payload the edge function would 400 on anyway.
  ///
  /// Mirrors `influencer-video-save`'s `validateCommon` field-for-field and
  /// message-for-message (same order, same wording) — a fast local error
  /// instead of a round trip for something the client already knows is
  /// wrong. The function re-validates all of this server-side regardless;
  /// this is a courtesy, not the source of truth.
  void _validate(InfluencerVideoDraft draft) {
    if (draft.title.trim().isEmpty) {
      throw const InfluencerVideoException('Title is required.');
    }
    if (draft.title.trim().length > kVideoTitleMaxLength) {
      throw const InfluencerVideoException(
        'Title must be $kVideoTitleMaxLength characters or fewer.',
      );
    }
    if (!isValidInfluencerVideoType(draft.videoType)) {
      throw const InfluencerVideoException('Invalid content type.');
    }
    if (draft.videoUrl.trim().isEmpty) {
      throw const InfluencerVideoException('A video is required.');
    }
    if (draft.description.length > kVideoDescriptionMaxLength) {
      throw const InfluencerVideoException(
        'Description must be $kVideoDescriptionMaxLength characters or fewer.',
      );
    }

    if (draft.videoType != 'property_listing') return;

    final location = draft.propertyLocation?.trim() ?? '';
    if (location.isEmpty) {
      throw const InfluencerVideoException('Property location is required.');
    }
    if (location.length > kPropertyLocationMaxLength) {
      throw const InfluencerVideoException(
        'Property location must be $kPropertyLocationMaxLength characters '
        'or fewer.',
      );
    }

    final price = draft.propertyPrice?.trim() ?? '';
    if (price.isEmpty) {
      throw const InfluencerVideoException('Property price is required.');
    }
    if (price.length > kPropertyPriceMaxLength ||
        !kPropertyPricePattern.hasMatch(price)) {
      throw const InfluencerVideoException(
        'Property price must be a whole number of rupees.',
      );
    }

    if (!kPropertyListingTypes.contains(draft.propertyListingType)) {
      throw const InfluencerVideoException(
        'Listing type must be sale, rent, or lease.',
      );
    }
    if (!kPropertyListingCategories.contains(draft.propertyCategory)) {
      throw const InfluencerVideoException(
        'Property type must be Residential, Commercial, PG/Co-living, '
        'Land, or Others.',
      );
    }

    final area = draft.propertyArea?.trim() ?? '';
    if (area.isNotEmpty &&
        (area.length > kPropertyAreaMaxLength ||
            !kPropertyAreaPattern.hasMatch(area))) {
      throw const InfluencerVideoException(
        'Property area must be a valid number (sq.ft).',
      );
    }

    for (final (label, value) in [
      ('Bedrooms', draft.propertyBedrooms),
      ('Bathrooms', draft.propertyBathrooms),
    ]) {
      if (value == null) continue;
      if (value < 0 || value > kPropertyBedBathMax) {
        throw InfluencerVideoException(
          '$label must be a whole number between 0 and $kPropertyBedBathMax.',
        );
      }
    }
  }
}
