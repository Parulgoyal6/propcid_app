import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/reel_model.dart';

/// Renders a single reel's video surface + gradient overlays.
///
/// It does NOT own the controller. Instead it receives one from the
/// [ReelControllerManager] sliding window. When the controller isn't ready yet
/// it shows the cached thumbnail (premium "instant" feel) with a subtle
/// spinner rather than a black frame — eliminating the old flicker.
class ReelVideoView extends StatelessWidget {
  const ReelVideoView({
    super.key,
    required this.reel,
    required this.controller,
    required this.onTogglePlayPause,
    this.isPaused = false,
    this.hasFailed = false,
    this.showLoadingIndicator = true,
  });

  final ReelModel reel;
  final VideoPlayerController? controller;
  final VoidCallback onTogglePlayPause;
  final bool isPaused;

  /// True when [ReelControllerManager] gave up on this reel (network error,
  /// bad/empty URL, or the init timeout was hit). Feeds into the existing
  /// error fallback so a broken reel shows a clear state instead of an
  /// infinite spinner.
  final bool hasFailed;
  final bool showLoadingIndicator;

  bool get _ready => controller != null && controller!.value.isInitialized;
  bool get _errored =>
      hasFailed || (controller != null && controller!.value.hasError);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTogglePlayPause,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildSurface(context),
          _buildGradientOverlays(),
          if (isPaused && _ready)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white70,
                size: 72,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSurface(BuildContext context) {
    if (_errored) return _errorFallback();

    if (!_ready) {
      // Show the thumbnail (if any) beneath a light spinner while buffering.
      // memCacheWidth bounds the decoded bitmap to the screen's actual pixel
      // width — without it, a full-resolution phone-camera photo (e.g.
      // 4000px wide) gets decoded at full size for every reel the sliding
      // window builds, which is real, avoidable jank during fast scrolling.
      final int cacheWidth =
          (MediaQuery.sizeOf(context).width *
                  MediaQuery.devicePixelRatioOf(context))
              .round();
      return Stack(
        fit: StackFit.expand,
        children: [
          if (reel.thumbnailUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: reel.thumbnailUrl,
              fit: BoxFit.cover,
              memCacheWidth: cacheWidth,
              errorWidget: (context, url, _) => Container(color: Colors.black),
            )
          else
            Container(color: Colors.black),
          if (showLoadingIndicator)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              ),
            ),
        ],
      );
    }

    // Cover-crop the video to fill the screen.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller!.value.size.width,
        height: controller!.value.size.height,
        child: VideoPlayer(controller!),
      ),
    );
  }

  Widget _errorFallback() {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.home_work_rounded,
            size: 96,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 12),
          Text(
            reel.title.isNotEmpty ? reel.title : 'Property preview',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientOverlays() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.65),
            ],
            stops: const [0.0, 0.25, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}
