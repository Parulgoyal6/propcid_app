import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../models/reel_model.dart';

/// Manages [VideoPlayerController] lifecycle for the reels feed.
///
/// Why a dedicated manager instead of one controller per page widget?
///   • TikTok/Instagram-style feeds must PRELOAD the neighbouring videos so a
///     swipe starts playing instantly instead of showing a spinner.
///   • Controllers are expensive (native decoders, buffers). We therefore keep
///     a small sliding window of controllers alive (previous, current, next)
///     and dispose everything outside it — bounding memory use regardless of
///     feed length.
///   • Centralising lifecycle here removes the per-page init/dispose races that
///     caused the old screen's flicker and "wrong video playing" glitches.
///
/// [ReelControllerManager] is a [ChangeNotifier]: it notifies whenever a
/// controller's readiness changes (becomes initialized, fails, or times out).
/// The screen listens to this via `AnimatedBuilder` so the UI rebuilds at the
/// exact moment a controller is ready — this is what makes the first reel
/// actually appear instead of being frozen on its pre-init placeholder.
class ReelControllerManager extends ChangeNotifier {
  ReelControllerManager({
    this.windowRadius = 1,
    this.initTimeout = const Duration(seconds: 20),
    this.previewMode = false,
    this.viewType = VideoViewType.textureView,
  });

  /// How the decoder's output reaches the screen.
  ///
  /// `textureView` (the plugin's default) has ExoPlayer render into a
  /// `SurfaceProducer`, which Flutter samples as an external texture and
  /// composites — `TextureVideoPlayer.java:82`. That extra sampling step is
  /// where a decoder that reports a non-standard stride or colour format shows
  /// up as green diagonal tearing, and it is device-specific because the stride
  /// comes from the vendor's driver.
  ///
  /// `platformView` calls `exoPlayer.setVideoSurfaceView(surfaceView)`
  /// (`PlatformVideoView.java:49`), handing frames straight to SurfaceFlinger.
  /// No Flutter texture, no sampling, no stride to get wrong.
  ///
  /// The trade is composition: a `SurfaceView` is a separate window layer, so it
  /// does not clip or transform with Flutter the way a texture does. Fine for a
  /// full-bleed player; not for a rounded, cover-cropped card in a scroller.
  final VideoViewType viewType;

  /// How many neighbours on each side of the active index to keep initialised.
  final int windowRadius;

  /// Rail mode: every controller in the window plays, silently.
  ///
  /// The full-screen feed has exactly one reel in front of the user, so it plays
  /// the active index with audio and holds its neighbours paused at frame zero,
  /// ready for the next swipe. A horizontal rail shows three cards at once and
  /// none of them is "the" one — the portal plays every card that is on screen
  /// and mutes them all (`TrendingVideosSection.tsx:169-197`, `muted` at `:317`).
  ///
  /// Only the playback policy changes. The window, the decoder-ordering fix and
  /// the disposal rules below are shared, which is the point: a rail that
  /// allocated decoders on its own terms would compete with this one for them.
  ///
  /// Defaults to false, so the feed behaves exactly as it did.
  final bool previewMode;

  /// How long to wait for `initialize()` before treating a reel as failed.
  /// Without this, a slow/flaky mobile network can leave the UI spinning
  /// forever with no way to recover.
  final Duration initTimeout;

  /// The manager backing whichever [ReelsScreen] is currently live in the
  /// navigator stack, or null when none is mounted. Widgets outside Reels
  /// that push a route on top of it (e.g. the bottom nav's "+" button) read
  /// this to pause/resume playback across that navigation — the same way
  /// `ReelsScreen._openUploaderProfile` already does internally with its own
  /// direct reference. Without it, the active reel's video/audio keeps
  /// running behind whatever got pushed on top, since pushing a route does
  /// not dispose the screen underneath. Set/cleared by `_ReelsScreenState`'s
  /// `initState`/`dispose`.
  static ReelControllerManager? active;

  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, Future<void>> _initializationFutures = {};
  final Set<int> _failedIndices = {};

  List<ReelModel> _reels = const [];
  int _activeIndex = 0;
  int _activationGeneration = 0;
  bool _disposed = false;

  /// Global sound preference — persists across swipes rather than resetting
  /// per reel, so muting once keeps every subsequent reel muted until the
  /// user turns it back on. Applied only to the active controller; preloaded
  /// neighbours stay muted regardless, same as before.
  bool _muted = false;
  bool get isMuted => _muted;

  VideoPlayerController? controllerAt(int index) => _controllers[index];

  bool hasFailed(int index) => _failedIndices.contains(index);

  void setReels(List<ReelModel> reels) {
    _reels = reels;
  }

  /// Called on page change / first build. Ensures the sliding window around
  /// [index] is initialised, plays the active video (looping, full volume),
  /// mutes + pauses the rest, and disposes controllers that fell outside the
  /// window.
  Future<void> onActiveIndexChanged(int index) async {
    if (_disposed || _reels.isEmpty || index < 0 || index >= _reels.length) {
      return;
    }

    final generation = ++_activationGeneration;
    _activeIndex = index;

    final int lower = (index - windowRadius).clamp(0, _reels.length - 1);
    final int upper = (index + windowRadius).clamp(0, _reels.length - 1);

    final toRemove = _controllers.keys
        .where((i) => i < lower || i > upper)
        .toList();

    for (final i in toRemove) {
      await _disposeAt(i);

      if (!_isCurrentActivation(generation, index)) {
        return;
      }
    }

    await _ensureInitialized(index);

    if (!_isCurrentActivation(generation, index)) {
      return;
    }

    _applyPlaybackState(_activeIndex);

    for (int i = lower; i <= upper; i++) {
      if (!_isCurrentActivation(generation, index)) {
        return;
      }

      if (i == index) continue;
      // Neighbour initialization intentionally runs in the background.
      // ignore: unawaited_futures
      _ensureInitialized(i);
    }
  }

  bool _isCurrentActivation(int generation, int index) {
    return !_disposed &&
        generation == _activationGeneration &&
        index == _activeIndex;
  }

  void _applyPlaybackState(int activeIndex) {
    for (final entry in _controllers.entries) {
      final c = entry.value;
      if (!c.value.isInitialized) continue;
      if (previewMode) {
        // Every card in the window is on screen, so every card plays — silently.
        c
          ..setVolume(0.0)
          ..setLooping(true)
          ..play();
        continue;
      }
      if (entry.key == activeIndex) {
        // The active reel plays with full audio unless the user has muted —
        // this is the fix for Issue 2: previously this branch called
        // setVolume(0.0) unconditionally, muting every reel with no code
        // path ever restoring volume.
        c
          ..setVolume(_muted ? 0.0 : 1.0)
          ..setLooping(true)
          ..play();
      } else {
        // Preloaded neighbours stay muted and paused so only the active
        // reel is ever heard.
        c
          ..setVolume(0.0)
          ..pause()
          ..seekTo(Duration.zero);
      }
    }
  }

  Future<void> _ensureInitialized(int index) {
    if (_disposed || index < 0 || index >= _reels.length) {
      return Future<void>.value();
    }

    final controller = _controllers[index];

    if (controller != null && controller.value.isInitialized) {
      return Future<void>.value();
    }

    final existingFuture = _initializationFutures[index];

    if (existingFuture != null) {
      return existingFuture;
    }

    late final Future<void> initializationFuture;

    initializationFuture = _initializeController(index).whenComplete(() {
      if (identical(_initializationFutures[index], initializationFuture)) {
        _initializationFutures.remove(index);
      }
    });

    _initializationFutures[index] = initializationFuture;
    return initializationFuture;
  }

  Future<void> _initializeController(int index) async {
    if (_controllers.containsKey(index)) return;
    if (index < 0 || index >= _reels.length) return;

    final url = _reels[index].videoUrl;
    if (url.isEmpty) {
      _failedIndices.add(index);
      _safeNotify();
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      viewType: viewType,
    );
    _controllers[index] = controller;
    _failedIndices.remove(index);

    try {
      if (kDebugMode) {
        final filename = Uri.parse(url).pathSegments.lastOrNull ?? url;
        debugPrint('[ReelDebug] init start    [$index]: $filename');
      }
      await controller.initialize().timeout(initTimeout);

      // The controller may have been evicted from the window (user swiped
      // past it) while we were awaiting initialize(). Calling further
      // methods on a disposed controller throws, so bail out here rather
      // than touching it.
      if (_controllers[index] != controller) return;

      if (kDebugMode) {
        final v = controller.value;
        debugPrint(
          '[ReelDebug] init complete [$index]: '
          '${v.size.width.toStringAsFixed(0)}×${v.size.height.toStringAsFixed(0)} '
          'dur=${v.duration.inMilliseconds}ms',
        );
        // One-shot listener: fires on first decoded frame or on playback error.
        late VoidCallback onFirstFrame;
        onFirstFrame = () {
          if (controller.value.hasError) {
            debugPrint(
              '[ReelDebug] playback error [$index]: '
              '${controller.value.errorDescription}',
            );
            controller.removeListener(onFirstFrame);
          } else if (controller.value.position > Duration.zero) {
            debugPrint('[ReelDebug] first frame    [$index]');
            controller.removeListener(onFirstFrame);
          }
        };
        controller.addListener(onFirstFrame);
      }

      await controller.setLooping(true);
      await controller.setVolume(
        previewMode ? 0.0 : (index == _activeIndex && !_muted ? 1.0 : 0.0),
      );

      if (_controllers[index] != controller) return;
      if (previewMode || index == _activeIndex) {
        // Deliberately NOT awaited: play() only needs to be *issued*, not
        // settled, before we notify the UI that this controller is ready.
        // Awaiting it here previously left `finally`'s _safeNotify() (the
        // only thing that tells ReelVideoView to rebuild and show the
        // video) stuck behind however long play() took to resolve — on a
        // slow network that could be indefinitely, producing a permanent
        // black screen despite the controller being fully initialized.
        controller.play();
      }
    } catch (e) {
      debugPrint('Reel controller init failed [$index]: $e');
      if (kDebugMode) debugPrint('[ReelDebug] init FAILED    [$index]: $e');
      // Only mark as failed if this controller is still the tracked one for
      // this index (i.e. wasn't already disposed/replaced during the await).
      if (_controllers[index] == controller) {
        _controllers.remove(index);
        _failedIndices.add(index);

        try {
          await controller.dispose();
        } catch (_) {
          // Controller may already be partially disposed after a timeout.
        }
      }
    } finally {
      // Notify regardless of outcome: either the controller is now ready and
      // the UI should show the video, or it failed/timed out and the UI
      // should show the error fallback instead of spinning forever.
      _safeNotify();
    }
  }

  Future<void> _disposeAt(int index) async {
    _initializationFutures.remove(index);

    final controller = _controllers.remove(index);
    _failedIndices.remove(index);

    if (controller == null) return;

    try {
      await controller.pause();
    } catch (_) {
      // Controller may already be paused or partially disposed.
    }

    try {
      await controller.dispose();
    } catch (_) {
      // Cleanup must not prevent the latest Reel from initializing.
    }
  }

  void pauseActive() {
    _controllers[_activeIndex]?.pause();
  }

  /// Flips the global sound preference and immediately applies it to the
  /// active controller (neighbours stay muted either way).
  void toggleMute() {
    _muted = !_muted;
    final active = _controllers[_activeIndex];
    if (active != null && active.value.isInitialized) {
      active.setVolume(_muted ? 0.0 : 1.0);
    }
    _safeNotify();
  }

  void playActive() {
    _controllers[_activeIndex]?.play();
  }

  /// Stops every live controller without disposing any of them.
  ///
  /// For leaving the viewport or backgrounding the app: decoders stay allocated
  /// so coming back is instant, but nothing decodes or pulls bytes meanwhile.
  /// [resumeWindow] puts playback back exactly as the mode dictates.
  void pauseAll() {
    for (final c in _controllers.values) {
      if (c.value.isInitialized && c.value.isPlaying) c.pause();
    }
  }

  void resumeWindow() => _applyPlaybackState(_activeIndex);

  /// Frees every native video surface, leaving the manager reusable.
  ///
  /// Distinct from [disposeAll], which retires the manager for good. This is for
  /// giving the device's surface budget back to another screen: Android's buffer
  /// pool is finite and this app has already exhausted it once by leaving
  /// surfaces alive on buried routes (see `bottom_nav_bar.dart:58-68`).
  /// [onActiveIndexChanged] rebuilds the window afterwards.
  ///
  /// Deliberately heavier than [pauseAll]: pausing keeps the surface, which is
  /// right for a moment's scroll and wrong when another player needs it.
  Future<void> releaseAll() async {
    ++_activationGeneration;
    _initializationFutures.clear();

    for (final index in _controllers.keys.toList()) {
      await _disposeAt(index);
    }

    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> disposeAll() async {
    if (_disposed) return;

    _disposed = true;
    ++_activationGeneration;
    _initializationFutures.clear();

    final controllers = _controllers.values.toList();

    _controllers.clear();
    _failedIndices.clear();

    for (final controller in controllers) {
      try {
        await controller.pause();
      } catch (_) {
        // Controller may already be paused or tearing down.
      }

      try {
        await controller.dispose();
      } catch (_) {
        // Continue disposing the remaining controllers.
      }
    }

    super.dispose();
  }
}
