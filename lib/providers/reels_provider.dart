import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reel_model.dart';
import '../services/reels_service.dart';
import '../services/reel_likes_service.dart';
import '../services/saved_reels_service.dart';

class ReelsProvider with ChangeNotifier {
  bool _hasCompletedOnboarding = false;

  String? _selectedCity;
  String? _selectedBudget;
  String? _selectedPropertyType;

  final ReelsService _reelsService = ReelsService();
  final ReelLikesService _reelLikesService = ReelLikesService();
  final SavedReelsService _savedReelsService = SavedReelsService();

  List<ReelModel> _reels = [];
  bool _isLoading = false;
  bool _hasError = false;

  // Per-reel interaction state keyed by reel id. Kept in the provider (rather
  // than in the screen's setState) so swiping pages never rebuilds the video
  // layer and so state survives page recycling in the PageView.
  final Set<String> _likedIds = {};
  final Set<String> _savedIds = {};

  List<ReelModel> get reels => _reels;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  String? get selectedCity => _selectedCity;
  String? get selectedBudget => _selectedBudget;
  String? get selectedPropertyType => _selectedPropertyType;

  bool isLiked(String id) => _likedIds.contains(id);
  bool isSaved(String id) => _savedIds.contains(id);

  /// Displayed like count = base likes + 1 when the user has liked locally.
  int likeCount(ReelModel reel) =>
      reel.likes + (_likedIds.contains(reel.id) ? 1 : 0);

  /// Live comment counts, keyed by reel id — overrides the `comments`
  /// value [ReelModel] was loaded with, which is otherwise frozen until the
  /// next [loadReels]. Fed by the counter subscription below and by
  /// [recordPostedComment]; cleared on reload (fresh rows are authoritative).
  final Map<String, int> _commentCounts = {};

  int commentCount(ReelModel reel) =>
      _commentCounts[reel.id] ?? reel.commentCount;

  /// Called by the comments sheet right after the caller's own comment was
  /// saved, so the open reel's count moves at once instead of waiting on
  /// the counter event. [countBefore] is [commentCount] read when the post
  /// started: the result is `countBefore + 1`, and a count the counter
  /// event already raised to that (or beyond) is left alone — so the
  /// event and this call never double-count, whichever lands first.
  void recordPostedComment(String reelId, {required int countBefore}) {
    final index = reels.indexWhere((r) => r.id == reelId);
    if (index < 0) return;
    final current = commentCount(reels[index]);
    final next = countBefore + 1;
    if (next <= current) return;
    _commentCounts[reelId] = next;
    notifyListeners();
  }

  // ── Live comment counter (portal ReelView.tsx parity) ────────────────────
  //
  // The portal keeps visible reels' counters live with `postgres_changes`
  // UPDATE on both source tables (`properties`, `influencer_videos`) and
  // merges `comments` into the matching reel — adding a comment bumps that
  // row's counter server-side, which arrives here as an UPDATE. Only the
  // comment count is merged (likes/views keep their existing handling).
  RealtimeChannel? _counterChannel;

  void _subscribeCommentCounters() {
    if (_counterChannel != null) return;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    _counterChannel = Supabase.instance.client.channel('reel-counters-$suffix')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'properties',
        callback: (payload) => applyCommentCounterRow(payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'influencer_videos',
        callback: (payload) => applyCommentCounterRow(payload.newRecord),
      )
      ..subscribe();
  }

  /// Merges one counter UPDATE row (from the subscription above).
  @visibleForTesting
  void applyCommentCounterRow(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    final comments = (row['comments'] as num?)?.toInt();
    if (id == null || comments == null) return;
    final index = reels.indexWhere((r) => r.id == id);
    if (index < 0) return;
    if (commentCount(reels[index]) == comments) return;
    _commentCounts[id] = comments;
    notifyListeners();
  }

  @override
  void dispose() {
    final channel = _counterChannel;
    _counterChannel = null;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  ReelsProvider() {
    _loadPreferences();
    loadReels();
    _loadLikedIds();
    _loadSavedIds();
  }

  /// Loads the current user's liked-reel ids from the persisted `user_likes`
  /// table. Silently does nothing when signed out or on failure — a reel's
  /// like state just falls back to session-only in that case rather than
  /// crashing the feed.
  Future<void> _loadLikedIds() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final ids = await _reelLikesService.fetchLikedReelIds(userId);
      _likedIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (e) {
      debugPrint('[ReelsProvider] _loadLikedIds failed: $e');
    }
  }

  /// Loads the current user's saved-reel ids from the persisted
  /// `saved_reels` table, mirroring [_loadLikedIds]. Silently does nothing
  /// when signed out or on failure.
  Future<void> _loadSavedIds() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final ids = await _savedReelsService.fetchSavedReelIds(userId);
      _savedIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (e) {
      debugPrint('[ReelsProvider] _loadSavedIds failed: $e');
    }
  }

  Future<void> loadReels() async {
    try {
      _isLoading = true;
      _hasError = false;
      notifyListeners();

      final data = await _reelsService.getReels();
      _reels = data.map((e) => ReelModel.fromSupabase(e)).toList();
      _commentCounts.clear();
      // Once there are reels to keep live; guarded, so reloads never add
      // a second channel.
      _subscribeCommentCounters();

      debugPrint('Loaded reels: ${_reels.length}');

      // TEMPORARY cover-image trace. Debug builds only; remove once the blank
      // rail is explained. Prints the raw column exactly as Postgrest returned
      // it, so a NULL thumbnail is distinguishable from a populated URL that
      // fails to load — the two render identically.
      if (kDebugMode) {
        for (var i = 0; i < data.length && i < 5; i++) {
          final row = data[i];
          final property = row['_property'] as Map<String, dynamic>?;
          debugPrint(
            '[reel-cover] #$i "${row['title']}"\n'
            '    thumbnail_url = ${row['thumbnail_url'] == null ? 'NULL' : '"${row['thumbnail_url']}"'}\n'
            '    property_id   = ${row['property_id'] ?? 'NULL'}'
            '  joined=${property != null}'
            '  media_urls=${property?['media_urls'] ?? '-'}\n'
            '    → previewImageUrl = "${_reels[i].previewImageUrl}"',
          );
        }
      }
    } catch (e) {
      _hasError = true;
      debugPrint('Reels error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Optimistically toggles, then persists to `user_likes` when signed in;
  /// rolls back on failure. Guests still get the local optimistic toggle
  /// (no persistence) so browsing without an account isn't blocked.
  Future<void> toggleLike(String id) async {
    final wasLiked = _likedIds.contains(id);
    wasLiked ? _likedIds.remove(id) : _likedIds.add(id);
    notifyListeners();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (wasLiked) {
        await _reelLikesService.unlike(userId, id);
      } else {
        await _reelLikesService.like(userId, id);
      }
    } catch (e) {
      debugPrint('[ReelsProvider] toggleLike persistence failed: $e');
      wasLiked ? _likedIds.add(id) : _likedIds.remove(id);
      notifyListeners();
    }
  }

  /// Optimistically toggles, then persists to `saved_reels` when signed in;
  /// rolls back on failure — same pattern as [toggleLike]. Guests still get
  /// the local optimistic toggle (no persistence) so browsing without an
  /// account isn't blocked.
  Future<void> toggleSave(String id) async {
    final wasSaved = _savedIds.contains(id);
    wasSaved ? _savedIds.remove(id) : _savedIds.add(id);
    notifyListeners();

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      if (wasSaved) {
        await _savedReelsService.unsave(userId, id);
      } else {
        await _savedReelsService.save(userId, id);
      }
    } catch (e) {
      debugPrint('[ReelsProvider] toggleSave persistence failed: $e');
      wasSaved ? _savedIds.add(id) : _savedIds.remove(id);
      notifyListeners();
    }
  }

  /// Cached reels the user has saved — same "filter what's already cached"
  /// approach as `PropertyProvider.getShortlistedProperties`, backing the
  /// "Saved" tab's Reels filter in My Activity.
  ///
  /// A listing-video reel's own id is a `properties.id` (see
  /// `ReelModel.isPropertyVideo`'s doc) and its save is recorded via
  /// `saved_properties`, not this provider's own `_savedIds` (`saved_reels`)
  /// — so [shortlistedPropertyIds] (the caller's already-loaded
  /// `PropertyProvider` state) decides for those, exactly as the reel player
  /// itself does (`reels_screen.dart`'s `_buildVideoActionRail`). Every other
  /// (influencer) reel keeps checking [_savedIds], unchanged. Defaults to
  /// empty so a caller that doesn't pass it keeps the pre-existing
  /// behaviour: no property-video reel is ever considered saved here.
  List<ReelModel> getSavedReels({
    Set<String> shortlistedPropertyIds = const {},
  }) => selectBySavedState(
    reels: _reels,
    savedReelIds: _savedIds,
    shortlistedPropertyIds: shortlistedPropertyIds,
  );

  /// Cached reels the user has liked — same approach as [getSavedReels],
  /// backing the "Liked" tab's Reels filter in My Activity. See
  /// [getSavedReels]'s doc for why [likedPropertyIds] decides a
  /// listing-video reel's state instead of this provider's own `_likedIds`.
  List<ReelModel> getLikedReels({Set<String> likedPropertyIds = const {}}) =>
      selectByLikedState(
        reels: _reels,
        likedReelIds: _likedIds,
        likedPropertyIds: likedPropertyIds,
      );

  /// Pure filter behind [getLikedReels] — split out so the property-video
  /// vs. influencer-reel branch (the fix for My Activity never showing a
  /// liked listing-video reel) is testable without a live Supabase session.
  @visibleForTesting
  static List<ReelModel> selectByLikedState({
    required List<ReelModel> reels,
    required Set<String> likedReelIds,
    required Set<String> likedPropertyIds,
  }) {
    return reels
        .where(
          (r) => r.isPropertyVideo
              ? likedPropertyIds.contains(r.id)
              : likedReelIds.contains(r.id),
        )
        .toList();
  }

  /// Pure filter behind [getSavedReels] — see [selectByLikedState]'s doc.
  @visibleForTesting
  static List<ReelModel> selectBySavedState({
    required List<ReelModel> reels,
    required Set<String> savedReelIds,
    required Set<String> shortlistedPropertyIds,
  }) {
    return reels
        .where(
          (r) => r.isPropertyVideo
              ? shortlistedPropertyIds.contains(r.id)
              : savedReelIds.contains(r.id),
        )
        .toList();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _hasCompletedOnboarding =
        prefs.getBool('hasCompletedReelsOnboarding') ?? false;

    _selectedCity = prefs.getString('reelsCity');
    _selectedBudget = prefs.getString('reelsBudget');
    _selectedPropertyType = prefs.getString('reelsPropertyType');

    notifyListeners();
  }

  Future<void> completeOnboarding({
    required String city,
    required String budget,
    required String propertyType,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('hasCompletedReelsOnboarding', true);
    await prefs.setString('reelsCity', city);
    await prefs.setString('reelsBudget', budget);
    await prefs.setString('reelsPropertyType', propertyType);

    _hasCompletedOnboarding = true;
    _selectedCity = city;
    _selectedBudget = budget;
    _selectedPropertyType = propertyType;

    notifyListeners();
  }
}
