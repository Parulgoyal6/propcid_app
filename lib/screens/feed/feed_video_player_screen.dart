// screens/feed/feed_video_player_screen.dart
//
// Minimal full-screen player for a Feed video item. Deliberately its own,
// self-contained screen rather than reusing the Reels player: ReelsScreen's
// ReelControllerManager is tuned for a swipeable multi-video feed (up to 3
// live controllers) and is unrelated to a single tapped Feed video — reusing
// it here would risk the Android surface-buffer issue documented in
// WorkspaceDestinations.reels for a feature that doesn't need it.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';

class FeedVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const FeedVideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<FeedVideoPlayerScreen> createState() => _FeedVideoPlayerScreenState();
}

class _FeedVideoPlayerScreenState extends State<FeedVideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // The AppBar sits transparently over the video instead of reserving
      // its own opaque strip — previously `Center` + `AspectRatio` shrank
      // the video to fit under the AppBar, letterboxing it whenever its
      // aspect ratio didn't exactly match the remaining space, so it never
      // actually filled the frame.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: GestureDetector(
        onTap: _ready ? _togglePlay : null,
        child: _ready
            // Fills the entire screen behind the AppBar, cropping any excess
            // rather than letterboxing — the same cover-fill approach the
            // Reels feed and the listing-form video preview already use.
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
      ),
    );
  }
}
