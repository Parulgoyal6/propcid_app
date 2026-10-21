import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/chat_message.dart';
import '../../../services/chat_media_service.dart';
import '../../../services/messaging_exceptions.dart';

/// Renders an image or voice-note message via a short-lived signed URL — the
/// `chat-media` bucket is private with no SELECT policy at all, so every read
/// goes through the `get-chat-media-url` Edge Function
/// ([ChatMediaService.getSignedUrl]), never a public/cached path.
///
/// Mirrors the portal's `ChatMediaImage.tsx` state machine: `pending` shows a
/// placeholder with a manual retry after ~2 minutes (there's also a 10-minute
/// server-side sweep cron, so retry is a convenience, not the only path to
/// resolution); `rejected` shows a removed-content notice; `approved` renders
/// the real media.
class ChatMediaView extends StatefulWidget {
  final ChatMessage message;
  final String surface; // 'dm' | 'channel'
  final bool isMine;

  const ChatMediaView({
    super.key,
    required this.message,
    required this.surface,
    required this.isMine,
  });

  @override
  State<ChatMediaView> createState() => _ChatMediaViewState();
}

class _ChatMediaViewState extends State<ChatMediaView> {
  final _service = ChatMediaService();
  String? _signedUrl;
  bool _loadingUrl = false;
  bool _retrying = false;
  Timer? _retryEligibleTimer;
  bool _retryEligible = false;

  String? get _path =>
      widget.message.mediaUrls.isEmpty ? null : widget.message.mediaUrls.first;

  @override
  void initState() {
    super.initState();
    if (widget.message.mediaStatus == MediaStatus.approved) {
      _loadUrl();
    }
    if (widget.message.mediaStatus == MediaStatus.pending) {
      _retryEligibleTimer = Timer(const Duration(minutes: 2), () {
        if (mounted) setState(() => _retryEligible = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaStatus != MediaStatus.approved &&
        widget.message.mediaStatus == MediaStatus.approved) {
      _loadUrl();
    }
  }

  @override
  void dispose() {
    _retryEligibleTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    final path = _path;
    if (path == null || _loadingUrl) return;
    setState(() => _loadingUrl = true);
    try {
      final url = await _service.getSignedUrl(
        path: path,
        surface: widget.surface,
      );
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      // Left null — the placeholder below covers this case too.
    } finally {
      if (mounted) setState(() => _loadingUrl = false);
    }
  }

  Future<void> _retryModeration() async {
    final path = _path;
    if (path == null) return;
    setState(() => _retrying = true);
    await _service.requestModeration(
      storagePath: path,
      messageId: widget.message.id,
      surface: widget.surface,
    );
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.message.mediaStatus) {
      case MediaStatus.rejected:
        return _placeholder(
          icon: Icons.block,
          label: 'This content was removed',
        );
      case MediaStatus.pending:
        return _pendingView();
      case MediaStatus.approved:
      case MediaStatus.text:
        if (widget.message.isAudio) return _audioPlayer();
        if (widget.message.isVideo) return _videoView();
        return _imageView();
    }
  }

  Widget _pendingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _placeholder(icon: Icons.hourglass_top, label: 'Checking image…'),
        if (_retryEligible) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: _retrying ? null : _retryModeration,
            child: Text(
              _retrying ? 'Retrying…' : 'Retry',
              style: AppTextStyles.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: widget.isMine ? Colors.white : AppColors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _imageView() {
    if (_signedUrl == null) {
      return _placeholder(
        icon: _loadingUrl ? Icons.hourglass_top : Icons.image_outlined,
        label: _loadingUrl ? 'Loading…' : 'Image unavailable',
      );
    }
    return GestureDetector(
      onTap: _openViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CachedNetworkImage(
          imageUrl: _signedUrl!,
          // Signed URLs expire; cache the pixels, not the (soon-invalid) URL.
          cacheKey: _path,
          width: 200,
          fit: BoxFit.cover,
          placeholder: (_, _) => const SizedBox(
            width: 200,
            height: 150,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          errorWidget: (_, _, _) => _placeholder(
            icon: Icons.broken_image_outlined,
            label: "Couldn't load image",
          ),
        ),
      ),
    );
  }

  void _openViewer() {
    final path = _path;
    if (path == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChatImageViewer(
          service: _service,
          path: path,
          surface: widget.surface,
        ),
      ),
    );
  }

  /// A dark play-button tile — there's no stored thumbnail for a chat video
  /// (unlike the reel feed, which has its own `thumbnail_url` column), so
  /// this doesn't try to show a frame preview; tapping opens the real player.
  Widget _videoView() {
    if (_signedUrl == null) {
      return _placeholder(
        icon: _loadingUrl ? Icons.hourglass_top : Icons.videocam_outlined,
        label: _loadingUrl ? 'Loading…' : 'Video unavailable',
      );
    }
    return GestureDetector(
      onTap: _openVideoViewer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 200,
          height: 150,
          color: Colors.black87,
          child: const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  void _openVideoViewer() {
    final url = _signedUrl;
    if (url == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => _ChatVideoViewer(url: url)));
  }

  Widget _audioPlayer() {
    return _VoiceMessagePlayer(
      resolveUrl: () =>
          _service.getSignedUrl(path: _path ?? '', surface: widget.surface),
      isMine: widget.isMine,
    );
  }

  Widget _placeholder({required IconData icon, required String label}) {
    // A clean white card with a tinted icon medallion (matching the
    // reference design) rather than a flat translucent tint — reads clearly
    // on both mine/theirs bubble colours instead of needing two colour
    // variants of the same box.
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceMessagePlayer extends StatefulWidget {
  final Future<String> Function() resolveUrl;
  final bool isMine;

  const _VoiceMessagePlayer({required this.resolveUrl, required this.isMine});

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final url = await widget.resolveUrl();
      await _player.play(UrlSource(url));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't play this voice message.")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMine ? Colors.white : AppColors.primary;
    return SizedBox(
      width: 160,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _loading ? null : _toggle,
            child: _loading
                ? SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    _playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 28,
                    color: color,
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            'Voice message',
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              color: widget.isMine ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen image viewer opened by tapping a chat image — pinch to zoom,
/// with a visible Download (save to gallery) button and a Share button.
/// Download used to exist only as a long-press menu item, which nothing on
/// screen hinted at.
class _ChatImageViewer extends StatefulWidget {
  final ChatMediaService service;
  final String path;
  final String surface;

  const _ChatImageViewer({
    required this.service,
    required this.path,
    required this.surface,
  });

  @override
  State<_ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<_ChatImageViewer> {
  late final Future<String> _url = widget.service.getSignedUrl(
    path: widget.path,
    surface: widget.surface,
  );
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    try {
      await action();
      if (successMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is ChatMediaValidationError
                ? e.message
                : "Couldn't complete that. Please try again.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded),
              onPressed: () => _run(
                () => widget.service.saveImageToGallery(
                  path: widget.path,
                  surface: widget.surface,
                ),
                successMessage: 'Image saved to gallery',
              ),
            ),
            IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => _run(
                () => widget.service.shareImage(
                  path: widget.path,
                  surface: widget.surface,
                ),
              ),
            ),
          ],
        ],
      ),
      body: FutureBuilder<String>(
        future: _url,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                "Couldn't load image",
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: CachedNetworkImage(
                imageUrl: snapshot.data!,
                cacheKey: widget.path,
                fit: BoxFit.contain,
                placeholder: (_, _) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen video player opened by tapping a chat video — streams the
/// same short-lived signed URL [_imageView] uses for stills, just handed to
/// `video_player` instead of `CachedNetworkImage`. No download/share actions
/// yet (unlike [_ChatImageViewer]) — those go through [ChatMediaService],
/// which only has image-saving helpers today.
class _ChatVideoViewer extends StatefulWidget {
  final String url;

  const _ChatVideoViewer({required this.url});

  @override
  State<_ChatVideoViewer> createState() => _ChatVideoViewerState();
}

class _ChatVideoViewerState extends State<_ChatVideoViewer> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((Object e) {
          debugPrint('ChatMediaView: video playback failed: $e');
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_failed) {
      return const Text(
        "Couldn't load video",
        style: TextStyle(color: Colors.white70),
      );
    }
    if (!_controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: GestureDetector(
        onTap: _togglePlayPause,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            if (!_controller.value.isPlaying)
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 64,
              ),
          ],
        ),
      ),
    );
  }
}
