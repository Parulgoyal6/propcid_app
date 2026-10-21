// screens/property_detail/property_media_viewer_screen.dart
//
// Full-screen viewer for a listing's photos AND videos together. `media_urls`
// holds both (the portal files a "Property Video" into the same array), and
// the old flow split them apart: tapping a photo opened a photo-only viewer
// (videos removed from it) and tapping a video opened a separate single-video
// player, so there was no way to swipe on to the next item once you had
// opened one. This swipes through the whole list in order, whatever each
// item is.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:video_player/video_player.dart';

final RegExp _videoExtension = RegExp(
  r'\.(mp4|webm|ogg|mov|avi|m4v|mkv|3gp)$',
  caseSensitive: false,
);

/// Same extension test the property page uses to tell a video from a photo
/// (the query string is ignored).
bool isVideoMediaUrl(String url) =>
    _videoExtension.hasMatch(url.split('?').first);

class PropertyMediaViewerScreen extends StatefulWidget {
  /// Every `media_urls` entry, in order - photos and videos.
  final List<String> media;
  final int initialIndex;

  /// When set, each photo page gets a Hero tag `'<prefix>_<index>'` matching
  /// the property page's carousel, so tapping a photo still flies into place.
  final String? heroTagPrefix;

  const PropertyMediaViewerScreen({
    super.key,
    required this.media,
    this.initialIndex = 0,
    this.heroTagPrefix,
  });

  @override
  State<PropertyMediaViewerScreen> createState() =>
      _PropertyMediaViewerScreenState();
}

class _PropertyMediaViewerScreenState extends State<PropertyMediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.media.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: widget.media.length,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            builder: (context, index) {
              final url = widget.media[index];
              if (isVideoMediaUrl(url)) {
                // Gestures off so a horizontal drag on the video is a page
                // swipe, not a pan of the "image".
                return PhotoViewGalleryPageOptions.customChild(
                  disableGestures: true,
                  child: _ViewerVideoPage(
                    key: ValueKey('video_$index'),
                    url: url,
                    isActive: index == _currentIndex,
                  ),
                );
              }
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(url),
                heroAttributes: widget.heroTagPrefix != null
                    ? PhotoViewHeroAttributes(
                        tag: '${widget.heroTagPrefix}_$index',
                      )
                    : null,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1}/${widget.media.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One video page. Plays while it is the current page and pauses as soon as
/// the user swipes away; tap to pause / resume.
class _ViewerVideoPage extends StatefulWidget {
  final String url;
  final bool isActive;

  const _ViewerVideoPage({super.key, required this.url, required this.isActive});

  @override
  State<_ViewerVideoPage> createState() => _ViewerVideoPageState();
}

class _ViewerVideoPageState extends State<_ViewerVideoPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          _controller.setLooping(true);
          setState(() => _ready = true);
          if (widget.isActive) _controller.play();
        })
        .catchError((Object e) {
          debugPrint('[PropertyMediaViewer] Video failed to load: $e');
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void didUpdateWidget(covariant _ViewerVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_ready) return;
    if (widget.isActive && !oldWidget.isActive) {
      _controller.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_ready) return;
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text(
          "Couldn't play this video",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final playing = _controller.value.isPlaying;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (!playing)
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
