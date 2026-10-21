import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/reel_model.dart';
import '../../../providers/reels_provider.dart';
import '../../../widgets/section_header.dart';
import '../../reels/widgets/reel_controller_manager.dart';

/// Read-only preview row of the reels already being fetched app-wide by
/// `ReelsProvider` (it self-loads on construction, per `main.dart`) — no new
/// fetch logic here. Tapping any card, or "See all", opens the existing
/// `ReelsScreen` (same route the Home dropdown menu already uses).
///
/// Purely manual `ListView` scrolling — no auto-scroll. A previous pass had
/// this rail nudge itself every 40ms via `Timer.periodic` + `jumpTo` for a
/// premium "alive" feel; that timer ran continuously (even while the rail
/// merely sat further down the Home feed, since a `wantKeepAlive` widget is
/// never actually removed from the tree while Home is mounted) and was one of
/// the biggest contributors to scroll jank on lower-powered devices. Removed
/// outright rather than throttled, per the Home scroll-performance pass.
///
/// WHY THE CARDS ARE VIDEO, NOT IMAGES
/// -----------------------------------
/// `influencer_videos.thumbnail_url` is optional at upload and is NULL for every
/// row today, and these reels carry no `property_id` either — so there is no
/// image anywhere in the data to show. The portal has the same rows and looks
/// fine because its card is a `<video preload="metadata">` whose `poster` is
/// simply absent: the browser paints the decoded first frame, and
/// `TrendingVideosSection.tsx:169-197` then plays whichever cards are in view,
/// muted. This is the same thing — a still first frame until the card enters the
/// window, then silent playback.
///
/// [ReelModel.previewImageUrl] is still honoured and still wins when it resolves
/// to something. That is exactly `poster`'s role: a still shown until the video
/// has a frame of its own to give.
class PropertyReelsSection extends StatefulWidget {
  const PropertyReelsSection({super.key});

  /// Card width plus its trailing gap. Declared rather than inferred so the
  /// visible-card maths below is exact, and handed to the `ListView` as a fixed
  /// extent so it can scroll without measuring children.
  static const double cardWidth = 130;
  static const double cardGap = 12;
  static const double itemExtent = cardWidth + cardGap;
  static const double listPadding = 16;

  /// Which card sits under the middle of the viewport.
  ///
  /// Pure and static so the arithmetic is testable without a live scroll view —
  /// it decides which videos hold decoders, so an off-by-one here is a card
  /// playing off screen while a visible one stays a still.
  static int centreIndexFor({
    required double offset,
    required double viewportWidth,
    required int itemCount,
  }) {
    if (itemCount <= 0) return 0;
    final centre = offset + viewportWidth / 2 - listPadding;
    return (centre / itemExtent).floor().clamp(0, itemCount - 1);
  }

  @override
  State<PropertyReelsSection> createState() => _PropertyReelsSectionState();
}

class _PropertyReelsSectionState extends State<PropertyReelsSection>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  /// How long the rail must hold still before its playback window is rebuilt.
  ///
  /// Swapping the window allocates and frees hardware decoders, so doing it
  /// mid-fling would be both wasted and janky. Manual drags settle in well
  /// under this, so in the steady state this fires once per genuine stop.
  static const _windowSettleDelay = Duration(milliseconds: 250);

  final ScrollController _scrollController = ScrollController();

  /// Shared with the full-screen feed — same sliding window, same decoder
  /// ordering, same disposal rules — in its muted rail mode. `windowRadius:
  /// 0`, not 1: a Home preview rail never needs a neighbour pre-decoding —
  /// exactly one video (the centred card) ever holds a decoder here, unlike
  /// the full-screen feed's own instance (untouched, still radius 1).
  final ReelControllerManager _videos = ReelControllerManager(
    windowRadius: 0,
    previewMode: true,
  );

  Timer? _windowTimer;
  int _centreIndex = 0;
  int _reelCount = 0;

  /// The enclosing Home feed's scroll position, so the rail can tell when it
  /// has been scrolled off screen. This widget is `wantKeepAlive`, so without
  /// this the video would keep decoding while the user reads the rest of the
  /// page. Visibility is only ever recomputed when the outer feed's
  /// `isScrollingNotifier` flips — never per scroll pixel/frame, which the
  /// previous `ScrollPosition.addListener` + `findRenderObject`/
  /// `localToGlobal` combination did do, on every single scroll update.
  ScrollPosition? _outerPosition;
  bool _onScreen = true;

  /// Another route — the full-screen `ReelsScreen`, usually — is covering Home.
  ///
  /// Home is not unmounted by a push, and this widget is `wantKeepAlive`, so
  /// without this the rail would sit behind `ReelsScreen` still holding three
  /// native video surfaces while that screen tries to allocate three of its own.
  /// Android's buffer pool is finite and this app has already exhausted it once
  /// (`bottom_nav_bar.dart:58-68`), so the rail hands its surfaces back rather
  /// than merely pausing them.
  Animation<double>? _coverAnimation;
  bool _covered = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onRailScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final outer = Scrollable.maybeOf(context)?.position;
    if (outer != _outerPosition) {
      _outerPosition?.isScrollingNotifier.removeListener(
        _onOuterScrollingChanged,
      );
      _outerPosition = outer;
      _outerPosition?.isScrollingNotifier.addListener(_onOuterScrollingChanged);
    }

    // `secondaryAnimation` is this route's "something is covering me" signal —
    // it drives from 0 to 1 as another route pushes over Home. Cheaper than a
    // RouteObserver, which would need registering on the app's navigator.
    final cover = ModalRoute.of(context)?.secondaryAnimation;
    if (cover != _coverAnimation) {
      _coverAnimation?.removeListener(_onCoverChanged);
      _coverAnimation = cover;
      _coverAnimation?.addListener(_onCoverChanged);
    }
  }

  void _onCoverChanged() {
    final covered = (_coverAnimation?.value ?? 0) > 0;
    if (covered == _covered) return;
    _covered = covered;
    if (covered) {
      // Give the surfaces up before the incoming screen asks for its own.
      _windowTimer?.cancel();
      unawaited(_videos.releaseAll());
    } else {
      _syncWindow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _outerPosition?.isScrollingNotifier.removeListener(
      _onOuterScrollingChanged,
    );
    _coverAnimation?.removeListener(_onCoverChanged);
    _windowTimer?.cancel();
    _scrollController.dispose();
    // Frees every decoder this rail allocated. Not awaited — `dispose` cannot be
    // async, and the manager tolerates teardown mid-initialisation.
    unawaited(_videos.disposeAll());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounded: stop decoding but keep the decoders, so returning is instant.
    if (state == AppLifecycleState.resumed) {
      if (_onScreen && !_covered) _videos.resumeWindow();
    } else {
      _videos.pauseAll();
    }
  }

  // ── Playback window ───────────────────────────────────────────────────────

  void _onRailScroll() {
    if (!_scrollController.hasClients) return;
    final next = PropertyReelsSection.centreIndexFor(
      offset: _scrollController.offset,
      viewportWidth: _scrollController.position.viewportDimension,
      itemCount: _reelCount,
    );
    if (next == _centreIndex) return;
    _centreIndex = next;
    _windowTimer?.cancel();
    _windowTimer = Timer(_windowSettleDelay, _syncWindow);
  }

  void _syncWindow() {
    if (!mounted || !_onScreen || _covered || _reelCount == 0) return;
    _videos.onActiveIndexChanged(_centreIndex.clamp(0, _reelCount - 1));
  }

  /// True while any part of the rail is within the screen's vertical bounds.
  /// Only ever called from [_onOuterScrollingChanged], once the outer Home
  /// feed has actually stopped scrolling — never per scroll pixel/frame.
  bool _isOnScreen() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.of(context).size.height;
    return top < screenHeight && top + box.size.height > 0;
  }

  /// Fires only when the outer Home feed's `isScrollingNotifier` flips —
  /// i.e. exactly twice per scroll gesture (start, then settle), not once per
  /// pixel/frame the way the previous `ScrollPosition.addListener` did.
  void _onOuterScrollingChanged() {
    final isScrolling = _outerPosition?.isScrollingNotifier.value ?? false;
    if (isScrolling) {
      // Scrolling just started: give up the decoder immediately rather than
      // waiting to learn where the rail ends up.
      _videos.pauseAll();
      return;
    }

    // Scrolling just settled — the one point visibility is (re)computed.
    final visible = _isOnScreen();
    _onScreen = visible;
    if (visible && !_covered) {
      _videos.resumeWindow();
      _syncWindow();
    } else {
      _videos.pauseAll();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<ReelsProvider>(
      builder: (context, reelsProvider, _) {
        final reels = reelsProvider.reels;
        if (reels.isEmpty) return const SizedBox.shrink();

        // Hand the list over whenever it changes, then open the first window
        // after the frame — `onActiveIndexChanged` notifies, and notifying
        // during a build is not allowed.
        if (reels.length != _reelCount) {
          _reelCount = reels.length;
          _videos.setReels(reels);
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindow());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'PropClips',
              actionLabel: 'See all ›',
              onActionTap: () =>
                  Navigator.pushNamed(context, AppConstants.reelsScreen),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              // Rebuilds the visible cards the moment a controller reports
              // itself ready, which is what swaps a poster for a first frame.
              // No `Listener`/pointer wrapper here any more — that existed
              // only to pause/resume the auto-scroll timer, which is gone;
              // manual dragging is just this `ListView`'s own gestures.
              child: AnimatedBuilder(
                animation: _videos,
                builder: (context, _) => ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: PropertyReelsSection.listPadding,
                  ),
                  // Fixed extent: the list scrolls without measuring
                  // children, and it makes the centre-card maths exact.
                  itemExtent: PropertyReelsSection.itemExtent,
                  itemCount: reels.length,
                  itemBuilder: (context, index) => _card(reels[index], index),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(ReelModel reel, int index) {
    return Padding(
      padding: const EdgeInsets.only(right: PropertyReelsSection.cardGap),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(
          context,
          AppConstants.reelsScreen,
          arguments: {'reelId': reel.id},
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: PropertyReelsSection.cardWidth,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _cover(reel, index),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                      stops: const [0.5, 1],
                    ),
                  ),
                ),
                const Center(child: _PlayButton()),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      if (reel.hasLocation) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 10,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                reel.location!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Poster underneath, video on top once it has a frame — `<video poster>`.
  Widget _cover(ReelModel reel, int index) {
    final controller = _videos.controllerAt(index);
    final ready =
        controller != null &&
        controller.value.isInitialized &&
        !controller.value.hasError;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Guarded, because an empty URL never resolves and never reaches
        // `errorWidget` — it just sits on the placeholder forever.
        if (reel.previewImageUrl.isNotEmpty)
          Builder(
            builder: (context) {
              // Bounds decoding to the card's actual rendered pixels
              // (130×200 logical, per `PropertyReelsSection.cardWidth` and
              // the outer `SizedBox(height: 200)`) rather than whatever
              // resolution the source happens to be — same physical size on
              // screen either way, far less decode work per poster.
              final dpr = MediaQuery.of(context).devicePixelRatio;
              return CachedNetworkImage(
                imageUrl: reel.previewImageUrl,
                fit: BoxFit.cover,
                memCacheWidth: (PropertyReelsSection.cardWidth * dpr).round(),
                memCacheHeight: (200 * dpr).round(),
                placeholder: (context, url) =>
                    Container(color: AppColors.primaryLight),
                errorWidget: (context, url, error) =>
                    const _ReelCoverFallback(),
              );
            },
          )
        else
          const _ReelCoverFallback(),
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
      ],
    );
  }
}

/// Cover for a reel with no usable image and no decoded frame yet. Unchanged
/// visually: this is exactly what the card's `errorWidget` already drew, lifted
/// out so the empty, failed and pre-frame cases share it instead of stating it
/// three times.
class _ReelCoverFallback extends StatelessWidget {
  const _ReelCoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight,
      child: const Icon(Icons.movie_outlined, color: AppColors.primary),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.22),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 24,
      ),
    );
  }
}
