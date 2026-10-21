import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../widgets/overlay_toast.dart';
import '../../core/constants/influencer_video_options.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/reel_comment.dart';
import '../../models/reel_model.dart';
import '../../providers/property_provider.dart';
import '../../providers/reels_provider.dart';
import '../../services/comment_service.dart';
import '../../widgets/bottom_nav_bar.dart';
import 'widgets/reel_action_button.dart';
import 'widgets/reel_controller_manager.dart';
import 'widgets/reel_info_panel.dart';
import 'widgets/reel_property_card.dart';
import 'widgets/reel_visit_booking_sheet.dart';
import 'widgets/share_reel_sheet.dart';
import 'package:video_player/video_player.dart'
    show VideoPlayerController, VideoViewType;

import 'widgets/reel_video_view.dart';

/// `post_comments.post_type` for a reel — mirrors the website's
/// ReelView.tsx (`postType={reel.type === 'influencer_video' ? 'video' :
/// 'property'}`): `'video'` for `influencer_videos` reels, `'property'` for
/// a listing's own video ([ReelModel.isPropertyVideo]).
String _reelCommentPostType(ReelModel reel) =>
    reel.isPropertyVideo ? 'property' : 'video';

/// Premium vertical reels feed — matches the compact reference layout:
/// video occupies ~80% of the screen, with a slim floating white card
/// (title, price, status, actions, CTAs) beneath it.
///
/// Everything under the hood is untouched from the previous implementation:
///   • A single [ReelControllerManager] still owns the sliding window of
///     video controllers (previous / current / next) for instant swipes and
///     bounded memory.
///   • The video layer still never rebuilds on interaction — like/save
///     still live in [ReelsProvider] and only small overlay/card
///     widgets rebuild via [Consumer].
///   • Pagination, autoplay, and swipe gestures are unchanged — only the
///     presentation around the video changed.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.initialReelId});

  /// When set, the feed opens scrolled to this reel instead of the top —
  /// used when opening a reel from My Activity's saved-reels list, mirroring
  /// the portal's `handleReelClick` (which navigates into the same reel
  /// player pre-selecting that reel; there is no standalone reel-detail
  /// route on the portal either).
  final String? initialReelId;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final PageController _pageController = PageController();

  /// Rendered through a native `SurfaceView` rather than a Flutter texture.
  ///
  /// The texture path samples the decoder's output buffer into a Flutter
  /// texture, and a driver that reports a non-standard stride or colour format
  /// makes that sampling produce green diagonal tearing — which is why the
  /// artifact follows the device, not the file. `platformView` hands frames
  /// straight to SurfaceFlinger, so there is no stride for Flutter to get wrong.
  ///
  /// Only the full-screen player. A `SurfaceView` is its own window layer and
  /// does not clip or transform with Flutter, which is fine for a full-bleed
  /// video and wrong for the Home rail's rounded, cover-cropped cards — those
  /// stay on the texture path.
  final ReelControllerManager _manager = ReelControllerManager(
    windowRadius: 1,
    viewType: VideoViewType.textureView,
  );

  int _currentIndex = 0;
  bool _isPaused = false;
  bool _initializedFeed = false;

  /// True while the viewer is in the distraction-free "view full screen"
  /// mode: every overlay (back arrow, mute toggle, right-hand action rail,
  /// bottom details card) and the bottom nav bar are hidden so only the
  /// video itself and the exit button remain. Playback and swiping between
  /// reels are untouched — this only toggles what is drawn on top.
  bool _isFullScreen = false;

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
  }

  @override
  void initState() {
    super.initState();
    // Lets navigation started from OUTSIDE Reels (the bottom nav's "+"
    // button) pause/resume this screen's playback across a pushed route —
    // see ReelControllerManager.active's doc comment.
    ReelControllerManager.active = _manager;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Note: we deliberately do NOT trigger provider.loadReels() here.
    // ReelsProvider is an app-global singleton (see main.dart) that already
    // starts loading in its own constructor. Triggering a second, overlapping
    // fetch here raced with that one — the two loadReels() calls interleaved
    // their isLoading/notifyListeners() cycles unpredictably, which was one
    // of the causes of inconsistent first-open behaviour. If reels ever fail
    // to load, the empty-state screen already exposes an explicit Retry
    // button wired to provider.loadReels().
  }

  @override
  void dispose() {
    if (identical(ReelControllerManager.active, _manager)) {
      ReelControllerManager.active = null;
    }
    _pageController.dispose();
    _manager.disposeAll();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Called once reels are available: primes the controller window, and —
  /// when [ReelsScreen.initialReelId] is set — starts on that reel instead
  /// of the top of the feed.
  void _maybeInitFeed(List<ReelModel> reels) {
    if (_initializedFeed || reels.isEmpty) return;
    _initializedFeed = true;

    final requestedId = widget.initialReelId;
    final matchedIndex = requestedId == null
        ? -1
        : reels.indexWhere((r) => r.id == requestedId);
    final startIndex = matchedIndex == -1 ? 0 : matchedIndex;

    _currentIndex = startIndex;
    _manager.setReels(reels);
    _manager.onActiveIndexChanged(startIndex);

    if (startIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(startIndex);
        }
      });
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isPaused = false;
    });
    // Deferred a frame: onActiveIndexChanged disposes/initializes native
    // video surfaces (real platform-channel round trips), and starting that
    // work in the same call stack as the page-change notification meant it
    // began competing with the PageView's own settle animation for the UI
    // thread at the exact moment of the swipe. Starting it only once that
    // frame has been drawn keeps the fling/settle smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _currentIndex) return;

      // Ignore callbacks queued for a Reel that is no longer active.
      // ignore: unawaited_futures
      _manager.onActiveIndexChanged(index);
    });
  }

  void _togglePlayPause() {
    setState(() => _isPaused = !_isPaused);
    _isPaused ? _manager.pauseActive() : _manager.playActive();
  }

  void _shareReel(ReelModel reel) {
    showShareReelSheet(
      context,
      reel: reel,
      currentUserId: Supabase.instance.client.auth.currentUser?.id,
    );
  }

  void _onViewDetails(ReelModel reel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PropertyDetailsSheet(
        reel: reel,
        onBookVisit: () => _onBookVisit(reel),
      ),
    );
  }

  /// "Book a Site Visit" for a reel linked to a property (for a listing's own
  /// video the reel id IS the property id) - the in-place booking form, same
  /// booking service as the property page.
  void _onBookVisit(ReelModel reel) {
    final propertyId = reel.propertyId;
    if (propertyId == null || propertyId.isEmpty) return;
    showReelVisitBookingSheet(
      context,
      propertyId: propertyId,
      title: reel.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // While in full screen, the system/gesture back action exits full
      // screen instead of leaving Reels — mirrors how a video player's own
      // full-screen mode behaves, and gives full screen a way out besides
      // the on-screen exit button.
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _isFullScreen = false);
      },
      child: Scaffold(
        // Must stay black, not white: the video (or its own black placeholder)
        // always paints over this, but during video_player's native decoder
        // startup (MediaCodec/AudioTrack init) nothing has painted yet, so
        // this base color is what's actually on screen. White here was the
        // regression that turned that brief, previously-invisible gap into a
        // visible blank white screen.
        backgroundColor: Colors.black,
        bottomNavigationBar: _isFullScreen
            ? null
            : const BottomNavBar(currentIndex: 2),
        body: Consumer<ReelsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading && provider.reels.isEmpty) {
              return const _ReelsLoadingState();
            }
            if (provider.reels.isEmpty) {
              return _ReelsEmptyState(
                hasError: provider.hasError,
                onRetry: provider.loadReels,
              );
            }

            _maybeInitFeed(provider.reels);

            // Full-bleed video with every panel (creator row, title,
            // description, specs, price/CTA, comment bar, action rail)
            // floating directly on top of it — matching the reference's
            // TikTok/Reels-style layout, rather than the video handing off to
            // a separate solid card underneath.
            return _buildVideoArea(provider);
          },
        ),
      ),
    );
  }

  // ── Video area (top ~80%) ────────────────────────────────────────────────
  Widget _buildVideoArea(ReelsProvider provider) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // PageView is stable — it does not rebuild when any controller
          // notifies. Each item wraps its own AnimatedBuilder so only that
          // item's ReelVideoView rebuilds when the manager fires (e.g. a
          // controller becomes initialized or fails). Previously the outer
          // AnimatedBuilder rebuilt the entire PageView on every notification,
          // triggering the scroll engine, gesture recognizer, and all visible
          // itemBuilder calls unnecessarily.
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: provider.reels.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              // RepaintBoundary isolates each reel's own compositing layer
              // (the video surface, especially the platform-view/SurfaceView
              // path above) from the page-transition transform and from
              // sibling rebuilds — without it every page's paint is at the
              // mercy of the same layer as its neighbours during a swipe,
              // which is a well-known source of jank for platform views
              // inside a scrollable.
              return RepaintBoundary(
                child: _ReelPageSurface(
                  key: ValueKey(provider.reels[index].id),
                  manager: _manager,
                  index: index,
                  reel: provider.reels[index],
                  isActive: index == _currentIndex,
                  isPaused: index == _currentIndex && _isPaused,
                  onTogglePlayPause: _togglePlayPause,
                ),
              );
            },
          ),
          // Bottom scrim so the creator row / title / description / specs /
          // price bar / comment bar stay legible over any video frame,
          // without boxing each one in its own translucent panel.
          //
          // In full screen every one of these overlays — scrim, back arrow,
          // details card, action rail — is hidden so only the video and the
          // exit-full-screen button remain on top of it.
          if (!_isFullScreen) const _BottomScrim(),
          if (!_isFullScreen) _buildTopBar(),
          if (!_isFullScreen) _buildBottomContent(provider),
          if (!_isFullScreen) _buildActionRailOverlay(provider),
          _buildTopRightControls(),
        ],
      ),
    );
  }

  // ── Right rail ───────────────────────────────────────────────────────────
  // Like / comment / share (+ the overflow "more" menu) as dark round buttons
  // with their count underneath, floating on the right edge a little above
  // the middle of the screen. Save now lives on the details card. Same
  // provider wiring as before - only the look and the position changed.
  Widget _buildActionRailOverlay(ReelsProvider provider) {
    return Positioned.fill(
      child: Align(
        alignment: const Alignment(1, -0.38),
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _buildVideoActionRail(provider),
        ),
      ),
    );
  }

  Widget _buildVideoActionRail(ReelsProvider provider) {
    final reel = provider.reels[_currentIndex];
    // A listing-video reel is liked/saved as its property (user_likes
    // .property_id, saved_properties) via PropertyProvider, as the portal
    // does, so the state matches the property page. Influencer reels are
    // unchanged.
    final isProperty = reel.isPropertyVideo;
    // Only looked up for listing videos, so influencer reels never depend
    // on PropertyProvider being in scope.
    final PropertyProvider? properties = isProperty
        ? context.watch<PropertyProvider>()
        : null;
    final liked = isProperty
        ? properties!.isLiked(reel.id)
        : provider.isLiked(reel.id);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Views: the reel's own view count, shown above like / comment / share.
        // Display only - tapping does nothing.
        ReelActionButton(
          showIconBackground: true,
          showLabelShadow: true,
          iconSize: 20,
          iconBoxSize: 42,
          icon: Icons.visibility_outlined,
          label: _formatActionCount(reel.views),
          onTap: () {},
        ),
        const SizedBox(height: 14),
        ReelActionButton(
          showIconBackground: true,
          showLabelShadow: true,
          iconSize: 20,
          iconBoxSize: 42,
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          // `reel.likes` for a listing-video reel is the property's own
          // `properties.likes` - already the true, current total, which
          // already includes the current viewer's own like.
          label: _formatActionCount(
            isProperty ? reel.likes : provider.likeCount(reel),
          ),
          isActive: liked,
          activeColor: AppColors.error,
          onTap: () => isProperty
              ? properties!.toggleLike(reel.id)
              : provider.toggleLike(reel.id),
        ),
        const SizedBox(height: 14),
        ReelActionButton(
          showIconBackground: true,
          showLabelShadow: true,
          iconSize: 20,
          iconBoxSize: 42,
          icon: Icons.mode_comment_outlined,
          // Live count: the loaded `comments` counter, kept current by
          // ReelsProvider's counter subscription and by the comments sheet.
          label: _formatActionCount(provider.commentCount(reel)),
          onTap: () => _showComments(reel),
        ),
        const SizedBox(height: 14),
        ReelActionButton(
          showIconBackground: true,
          showLabelShadow: true,
          iconSize: 20,
          iconBoxSize: 42,
          icon: Icons.ios_share_rounded,
          label: '',
          onTap: () => _shareReel(reel),
        ),
        const SizedBox(height: 8),
        _buildMoreButton(reel),
      ],
    );
  }

  /// The save/bookmark button on the details card (was in the right rail).
  Widget _buildSaveButton(ReelsProvider provider, ReelModel reel) {
    final isProperty = reel.isPropertyVideo;
    final PropertyProvider? properties = isProperty
        ? context.watch<PropertyProvider>()
        : null;
    final saved = isProperty
        ? properties!.isShortlisted(reel.id)
        : provider.isSaved(reel.id);
    return Semantics(
      button: true,
      label: saved ? 'Remove from saved' : 'Save',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => isProperty
            ? properties!.toggleShortlist(reel.id)
            : provider.toggleSave(reel.id),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: saved ? AppColors.primary : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// "•••" — copy link / report, mirroring what a reel's overflow menu
  /// commonly offers. Both actions are self-contained UI affordances (the
  /// clipboard and a snackbar), not new backend behaviour.
  Widget _buildMoreButton(ReelModel reel) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: AppColors.textPrimary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link_rounded, color: Colors.white),
                title: const Text(
                  'Copy link',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: reel.shareUrl));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: Colors.white),
                title: const Text(
                  'Report',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thanks — we\'ll take a look'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      child: const Icon(
        Icons.more_horiz_rounded,
        color: Colors.white,
        size: 28,
        shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
      ),
    );
  }

  /// Top-right sound toggle — mirrors the website's mute/unmute button
  /// (ReelView.tsx, `top-4 right-4`, Volume2/VolumeX) — plus the
  /// view-full-screen / exit-full-screen toggle, placed to its left.
  ///
  /// The mute button only shows outside full screen (it's one of the icons
  /// full screen hides); the full-screen toggle itself always shows, since
  /// it's the only way back out once every other control is hidden.
  /// Scoped to its own AnimatedBuilder so toggling sound repaints only that
  /// icon, not the rest of the video overlay.
  Widget _buildTopRightControls() {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: _isFullScreen ? 'Exit full screen' : 'View full screen',
                child: _circleIcon(
                  _isFullScreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onTap: _toggleFullScreen,
                ),
              ),
              if (!_isFullScreen) ...[
                const SizedBox(width: 10),
                AnimatedBuilder(
                  animation: _manager,
                  builder: (context, _) {
                    return _circleIcon(
                      _manager.isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onTap: _manager.toggleMute,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatActionCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _circleIcon(
              Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  /// Opens the reel uploader's own public profile — `reel.builderUserId`
  /// (`influencer_videos.user_id`), never the signed-in viewer's id.
  ///
  /// This pushes a new route on top of Reels rather than replacing it, so
  /// `ReelsScreen`'s State (and its `_manager`) stays alive underneath —
  /// `dispose()` never runs, and without an explicit pause the active
  /// video's audio kept playing behind the profile screen. `pauseAll()` /
  /// `resumeWindow()` already existed on [ReelControllerManager] for exactly
  /// this "leaving the viewport" case; this was the one navigation path that
  /// never called them.
  Future<void> _openUploaderProfile(String userId) async {
    _manager.pauseAll();
    await Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
    if (mounted) _manager.resumeWindow();
  }

  /// Opens the reel's listing page. Same pause / resume dance as
  /// [_openUploaderProfile]: this pushes on top of Reels, so without pausing
  /// the video would keep playing behind the listing.
  Future<void> _openListing(String propertyId) async {
    _manager.pauseAll();
    await Navigator.pushNamed(
      context,
      AppConstants.propertyDetailScreen,
      arguments: {'propertyId': propertyId},
    );
    if (mounted) _manager.resumeWindow();
  }

  /// The reel's title. For a reel tied to a property listing (a listing's own
  /// video, or a reel linked to a property) it is a tappable link - underlined,
  /// with a small "open" icon - that lands on that listing's page.
  Widget _buildReelTitle(ReelModel reel) {
    final title = (reel.title.isNotEmpty ? reel.title : 'Featured Property')
        .toUpperCase();
    final style = AppTextStyles.heading3.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w800,
      fontSize: 15.5,
      height: 1.25,
    );
    final propertyId = reel.propertyId;

    final text = Text(
      title,
      style: style,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    if (propertyId == null || propertyId.isEmpty) return text;

    // A reel tied to a listing: the title still opens that listing's page.
    return Semantics(
      link: true,
      label: 'Open listing: ${reel.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openListing(propertyId),
        child: text,
      ),
    );
  }

  // The card's tags read the same whether a reel's values came from a manual
  // listing video ('sale', 'pg/Co-living') or a linked property ('sell',
  // 'pg_coliving') - both vocabularies are mapped here.
  static String _categoryTag(String value) =>
      switch (value.trim().toLowerCase()) {
        'residential' => 'Residential',
        'commercial' => 'Commercial',
        'land' => 'Plot/Land',
        'pg_coliving' || 'pg/co-living' => 'PG/Co-living',
        'others' || 'other' => 'Others',
        _ => value,
      };

  static IconData _categoryIcon(String value) =>
      switch (value.trim().toLowerCase()) {
        'residential' => Icons.home_rounded,
        'commercial' => Icons.store_mall_directory_rounded,
        'land' => Icons.landscape_rounded,
        'pg_coliving' || 'pg/co-living' => Icons.groups_rounded,
        _ => Icons.apartment_rounded,
      };

  static String _listingTag(String value) =>
      switch (value.trim().toLowerCase()) {
        'sell' || 'sale' => 'Sell',
        'rent' => 'Rent',
        'lease' => 'Lease',
        _ => value,
      };

  // ── Details card ─────────────────────────────────────────────────────────
  // Everything about the listing sits in one dark rounded card at the bottom
  // of the video: poster row with the save button, category / listing chips,
  // price, title, location, then the quick facts with a "more" link. (The
  // right-hand like / comment / share rail is `_buildActionRailOverlay`.)
  Widget _buildBottomContent(ReelsProvider provider) {
    final reel = provider.reels[_currentIndex];

    final chips = <Widget>[
      if (reel.category != null && reel.category!.trim().isNotEmpty)
        _ReelTagChip(
          icon: _categoryIcon(reel.category!),
          label: _categoryTag(reel.category!),
          color: const Color(0xFFEA580C),
        ),
      if (reel.listingType != null && reel.listingType!.trim().isNotEmpty)
        _ReelTagChip(
          icon: Icons.sell_outlined,
          label: _listingTag(reel.listingType!),
          color: const Color(0xFF059669),
        ),
    ];

    final facts = <String>[
      if (reel.bedrooms != null) '${reel.bedrooms} BHK',
      if (reel.areaLabel != null) '${reel.areaLabel} Square Feet',
      if (reel.bathrooms != null) '${reel.bathrooms} Bath',
    ];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ReelInfoPanel(
                          reel: reel,
                          onTapProfile: reel.builderUserId == null
                              ? null
                              : () => _openUploaderProfile(reel.builderUserId!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildSaveButton(provider, reel),
                  ],
                ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: chips),
                ],
                if (reel.hasPrice) ...[
                  const SizedBox(height: 10),
                  Text(
                    reel.price!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1.1,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _buildReelTitle(reel),
                if (reel.hasLocation) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        color: Colors.white.withValues(alpha: 0.85),
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          reel.location!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        facts.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // "more" opens the same details sheet the old
                    // "View Details" button did.
                    Semantics(
                      button: true,
                      label: 'View details',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onViewDetails(reel),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Text(
                            'more',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Comments ──────────────────────────────────────────────────────────────
  void _showComments(ReelModel reel) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _CommentsSheet(reel: reel, onOpenProfile: _openUploaderProfile),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// One PageView slot's video surface — rebuilds only for its own state
// ─────────────────────────────────────────────────────────────────────────────

/// Renders one page's [ReelVideoView], listening to [manager] but rebuilding
/// only when THIS index's own (controller, ready, failed) state actually
/// changes — not on every notification the manager fires.
///
/// [ReelControllerManager] is one [ChangeNotifier] shared by the whole
/// sliding window: muting, a neighbour finishing its preload-init, or a
/// far-out-of-window controller being disposed all call `notifyListeners()`.
/// The previous code wrapped every built page in an `AnimatedBuilder` keyed
/// to that same notifier, so any one of those unrelated events rebuilt every
/// visible/preloading page at once — right as the swipe's settle animation
/// was running. Comparing before calling `setState` bounds each page's
/// rebuilds to changes that are actually its own.
class _ReelPageSurface extends StatefulWidget {
  const _ReelPageSurface({
    super.key,
    required this.manager,
    required this.index,
    required this.reel,
    required this.isActive,
    required this.isPaused,
    required this.onTogglePlayPause,
  });

  final ReelControllerManager manager;
  final int index;
  final ReelModel reel;
  final bool isActive;
  final bool isPaused;
  final VoidCallback onTogglePlayPause;

  @override
  State<_ReelPageSurface> createState() => _ReelPageSurfaceState();
}

class _ReelPageSurfaceState extends State<_ReelPageSurface> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _hasFailed = false;

  @override
  void initState() {
    super.initState();
    _sync();
    widget.manager.addListener(_onManagerChanged);
  }

  @override
  void didUpdateWidget(_ReelPageSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.removeListener(_onManagerChanged);
      widget.manager.addListener(_onManagerChanged);
    }
    if (oldWidget.manager != widget.manager ||
        oldWidget.index != widget.index) {
      _sync();
    }
  }

  @override
  void dispose() {
    widget.manager.removeListener(_onManagerChanged);
    super.dispose();
  }

  void _sync() {
    _controller = widget.manager.controllerAt(widget.index);
    _ready = _controller?.value.isInitialized ?? false;
    _hasFailed = widget.manager.hasFailed(widget.index);
  }

  void _onManagerChanged() {
    final controller = widget.manager.controllerAt(widget.index);
    final ready = controller?.value.isInitialized ?? false;
    final hasFailed = widget.manager.hasFailed(widget.index);
    if (controller == _controller &&
        ready == _ready &&
        hasFailed == _hasFailed) {
      return;
    }
    setState(() {
      _controller = controller;
      _ready = ready;
      _hasFailed = hasFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ReelVideoView(
      reel: widget.reel,

      // Keep neighbouring controllers initialized, but don't attach additional
      // native SurfaceViews while PageView is scrolling.
      controller: widget.isActive ? _controller : null,
      hasFailed: widget.isActive && _hasFailed,
      showLoadingIndicator: widget.isActive,
      isPaused: widget.isPaused,
      onTogglePlayPause: widget.onTogglePlayPause,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small overlay pieces used by `_buildBottomContent` above
// ─────────────────────────────────────────────────────────────────────────────

/// Bottom-anchored gradient so the caption/specs/price/comment overlay
/// stays legible over any video frame, however light. Purely decorative —
/// `IgnorePointer` so it never intercepts the play/pause tap-to-toggle.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: SizedBox(
          height: 340,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A coloured "Residential" / "Sell" tag on the details card.
class _ReelTagChip extends StatelessWidget {
  const _ReelTagChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.chip.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Property details sheet — slides up while the reel keeps playing
// ─────────────────────────────────────────────────────────────────────────────
class _PropertyDetailsSheet extends StatelessWidget {
  const _PropertyDetailsSheet({required this.reel, required this.onBookVisit});

  final ReelModel reel;
  final VoidCallback onBookVisit;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.65, 0.92],
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── handle + close ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textHint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.cardBackground,
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                ],
              ),
            ),
            // ── scrollable body ─────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  ReelPropertyCard(reel: reel, compact: false),
                  if (reel.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      'Description',
                      style: AppTextStyles.heading3.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reel.description.trim(),
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary.withValues(alpha: 0.75),
                        height: 1.5,
                      ),
                    ),
                  ],
                  // A reel linked to a property offers "Book a Site Visit" (the
                  // owner may be a builder, broker, influencer or an individual,
                  // so a builder-specific "Contact Builder" was wrong for most).
                  // One with no property to visit has no CTA here at all.
                  if (reel.propertyId?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(
                            AppConstants.buttonRadius,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              AppConstants.buttonRadius,
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              onBookVisit();
                            },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_available_rounded,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Book a Site Visit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading state
// ─────────────────────────────────────────────────────────────────────────────
class _ReelsLoadingState extends StatelessWidget {
  const _ReelsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / error state
// ─────────────────────────────────────────────────────────────────────────────
class _ReelsEmptyState extends StatelessWidget {
  const _ReelsEmptyState({required this.hasError, required this.onRetry});

  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasError
                          ? Icons.wifi_off_rounded
                          : Icons.video_library_outlined,
                      size: 72,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      hasError
                          ? 'Something went wrong'
                          : 'No reels available yet',
                      style: AppTextStyles.heading3.copyWith(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasError
                          ? 'Check your connection and try again.'
                          : 'Property reels will appear here soon.',
                      style: AppTextStyles.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                      ),
                      label: Text(
                        'Retry',
                        style: AppTextStyles.button.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comments sheet — real data via `post_comments` (post_type = 'video'),
// mirroring the website's CommentsPanel usage in ReelView.tsx.
// ─────────────────────────────────────────────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.reel, required this.onOpenProfile});

  final ReelModel reel;

  /// Reuses `_ReelsScreenState._openUploaderProfile` — same pause/resume
  /// handling around the navigation so a commenter's video doesn't keep
  /// playing behind their profile page, matching the uploader-profile path.
  final Future<void> Function(String userId) onOpenProfile;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final CommentService _service = CommentService();
  final TextEditingController _input = TextEditingController();

  List<ReelComment>? _comments;
  bool _loadFailed = false;
  bool _submitting = false;
  RealtimeChannel? _realtime;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeNewComments();
  }

  @override
  void dispose() {
    final channel = _realtime;
    _realtime = null;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    _input.dispose();
    super.dispose();
  }

  /// Live list — the portal CommentsPanel's subscription: INSERT on
  /// `post_comments` filtered by `post_id` (one filter allowed), `post_type`
  /// matched client-side. One channel per open sheet, removed in [dispose].
  /// The reel's count is kept live separately by ReelsProvider.
  void _subscribeNewComments() {
    final postType = _reelCommentPostType(widget.reel);
    final client = Supabase.instance.client;
    _realtime = client
        .channel(
          'reel-comments-${widget.reel.id}-'
          '${DateTime.now().microsecondsSinceEpoch}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: widget.reel.id,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            if (row['post_type']?.toString() != postType) return;
            final id = row['id']?.toString();
            // Already listed — e.g. our own comment, added by _submit.
            if (id == null || _isListed(id)) return;
            Map<String, dynamic>? profile;
            final uid = row['user_id']?.toString();
            if (uid != null && uid.isNotEmpty) {
              try {
                profile = await client
                    .from('profiles')
                    .select('user_id,display_name,avatar_url')
                    .eq('user_id', uid)
                    .maybeSingle();
              } catch (e) {
                debugPrint('[Reels] live comment profile failed: $e');
              }
            }
            // Re-checked after the await: _submit may have added it meanwhile.
            if (!mounted || _isListed(id)) return;
            setState(() {
              _comments = [
                ReelComment.fromSupabase(row, profile: profile),
                ...?_comments,
              ];
            });
          },
        )
        .subscribe();
  }

  bool _isListed(String id) => _comments?.any((c) => c.id == id) ?? false;

  Future<void> _load() async {
    try {
      final comments = await _service.fetchComments(
        widget.reel.id,
        _reelCommentPostType(widget.reel),
      );
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('[Reels] fetchComments failed: $e');
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  Future<void> _submit() async {
    final content = _input.text.trim();
    if (content.isEmpty || _submitting) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to comment')));
      return;
    }

    // Read before the request so a counter event arriving mid-request can't
    // be counted a second time (see ReelsProvider.recordPostedComment).
    final reels = context.read<ReelsProvider>();
    final countBefore = reels.commentCount(widget.reel);

    setState(() => _submitting = true);
    try {
      final comment = await _service.submitComment(
        postId: widget.reel.id,
        postType: _reelCommentPostType(widget.reel),
        userId: userId,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        // De-duplicated by id: the realtime INSERT may have landed first.
        _comments = [comment, ...?_comments?.where((c) => c.id != comment.id)];
        _input.clear();
      });
      // Moves the open reel's 💬 count now (2 → 3) instead of waiting for
      // the counter event; idempotent with that event (see the provider).
      reels.recordPostedComment(widget.reel.id, countBefore: countBefore);
    } catch (e) {
      debugPrint('[Reels] submitComment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Couldn't post comment")));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // Optimistic remove + rollback on failure — mirrors the portal's
  // CommentsPanel `deleteComment`.
  Future<void> _delete(ReelComment comment) async {
    // Ask first - a deleted comment cannot be brought back.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete comment?'),
        content: const Text(
          'This comment will be removed permanently. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final previous = _comments;
    setState(() {
      _comments = previous?.where((c) => c.id != comment.id).toList();
    });
    try {
      await _service.deleteComment(comment.id);
      if (mounted) showOverlayToast(context, 'Comment deleted successfully');
    } catch (e) {
      debugPrint('[Reels] deleteComment failed: $e');
      if (!mounted) return;
      setState(() => _comments = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool commentsEnabled = widget.reel.commentsEnabled;

    return Padding(
      // Rides above the keyboard so the input stays visible.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: AppTextStyles.heading3.copyWith(color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            Expanded(child: _buildBody()),
            if (commentsEnabled) _buildInputBar() else _buildDisabledNotice(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load comments',
              style: AppTextStyles.body.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final comments = _comments;
    if (comments == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2),
      );
    }

    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mode_comment_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            Text(
              'No comments yet',
              style: AppTextStyles.body.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: comments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => _buildCommentRow(comments[index]),
    );
  }

  Widget _buildCommentRow(ReelComment comment) {
    final name = (comment.authorName?.isNotEmpty ?? false)
        ? comment.authorName!
        : 'User';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => widget.onOpenProfile(comment.userId),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.white24,
            backgroundImage: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? NetworkImage(comment.authorAvatarUrl!)
                : null,
            child: (comment.authorAvatarUrl?.isNotEmpty ?? false)
                ? null
                : Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => widget.onOpenProfile(comment.userId),
                child: Text(
                  name,
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                comment.content,
                style: AppTextStyles.body.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        // Only the commenter sees the delete option — same rule as the
        // portal (and re-enforced by the `property-comments` function).
        if (comment.userId == Supabase.instance.client.auth.currentUser?.id)
          IconButton(
            onPressed: () => _delete(comment),
            tooltip: 'Delete comment',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a comment...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white70,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisabledNotice() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Comments are turned off for this creator',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
