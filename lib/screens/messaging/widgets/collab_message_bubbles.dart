// screens/messaging/widgets/collab_message_bubbles.dart
//
// Dedicated rendering for the six collaboration-marketplace message types —
// `collab_system`, `collab_payment`, `collab_agreement`, `location`,
// `sample_onetime`, `deliverable`. Ports `CollabMessageBubbles.tsx` (the
// exported `SampleBubble`/`DeliverableBubble`) plus the inline
// `collab_system`/`collab_payment`/`collab_agreement`/`location` cases from
// ChatModal.tsx/Chat.tsx's own bubble switch — on the portal those four live
// inline rather than in the exported component, but the rendering is ported
// 1:1 either way.
//
// DELIBERATELY NOT A [ChatBubble] variant: no long-press action sheet, so
// none of edit/forward/delete-for-everyone/react ever reaches a collab
// message — Phase 1's safety rule. `ChatBubble` never wraps this in its own
// `GestureDetector(onLongPress: ...)` — see the early-return branch added
// there.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/chat_message.dart';
import '../../../models/collaboration.dart';
import 'relative_time.dart';

/// Renders the right sub-widget for [message], centered in the thread — none
/// of these six types are attributed to "mine"/"theirs" the way a normal
/// bubble is; they're shared system/marketplace state.
class CollabMessageBubble extends StatelessWidget {
  final ChatMessage message;

  /// Resolved from `message.collabAssetId` against the thread's already
  /// loaded [CollaborationThreadController.assets] — null while that hasn't
  /// loaded yet, or for the four asset-less types.
  final CollabAsset? asset;

  final bool isClient;

  /// Sample: returns a signed ~60s one-time-view URL, or null + an error
  /// message. Never called except by the user's own tap.
  final Future<(String?, String?)> Function()? onViewSample;

  /// Deliverable: returns a signed ~300s URL, or null + an error message.
  final Future<(String?, String?)> Function()? onDownloadDeliverable;

  /// Agreement: returns the current signed agreement PDF URL.
  final Future<(String?, String?)> Function()? onDownloadAgreement;

  const CollabMessageBubble({
    super.key,
    required this.message,
    required this.isClient,
    this.asset,
    this.onViewSample,
    this.onDownloadDeliverable,
    this.onDownloadAgreement,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isCollabSystem || message.isCollabPayment) {
      return _SystemEventCard(message: message);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _buildContent(context),
          const SizedBox(height: 3),
          Text(
            formatClockTime(message.createdAt),
            style: AppTextStyles.caption.copyWith(
              fontSize: 10,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isCollabSystem || message.isCollabPayment) {
      return Text(
        message.content,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: AppColors.textSecondary,
        ),
      );
    }
    if (message.isCollabAgreement) {
      return _AgreementCard(message: message, onDownload: onDownloadAgreement);
    }
    if (message.isLocation) {
      return _LocationCard(message: message);
    }
    if (message.isCollabSample) {
      return _SampleBubble(
        asset: asset,
        isClient: isClient,
        onView: onViewSample,
      );
    }
    if (message.isCollabDeliverable) {
      return _DeliverableBubble(
        asset: asset,
        isClient: isClient,
        onDownload: onDownloadDeliverable,
      );
    }
    return Text(message.displayContent, style: AppTextStyles.body);
  }
}

/// `collab_system` / `collab_payment` event — a full-width card with an
/// orange status icon, timestamp underneath.
class _SystemEventCard extends StatelessWidget {
  final ChatMessage message;
  const _SystemEventCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFEDD5)),
              boxShadow: AppColors.surfaceCardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: Icon(
                    message.isCollabPayment
                        ? Icons.currency_rupee_rounded
                        : Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message.content,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              formatClockTime(message.createdAt),
              style: AppTextStyles.caption.copyWith(
                fontSize: 10,
                color: AppColors.textHint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollabCard extends StatelessWidget {
  final Widget child;
  const _CollabCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
          boxShadow: AppColors.surfaceCardShadow,
        ),
        child: child,
      ),
    );
  }
}

class _AgreementCard extends StatefulWidget {
  final ChatMessage message;
  final Future<(String?, String?)> Function()? onDownload;
  const _AgreementCard({required this.message, this.onDownload});

  @override
  State<_AgreementCard> createState() => _AgreementCardState();
}

class _AgreementCardState extends State<_AgreementCard> {
  bool _busy = false;

  Future<void> _download() async {
    final action = widget.onDownload;
    if (action == null || _busy) return;
    setState(() => _busy = true);
    final (url, error) = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CollabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Collaboration agreement',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.message.content,
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _download,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download PDF'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final ChatMessage message;
  const _LocationCard({required this.message});

  Future<void> _open() async {
    final url = message.locationMapsUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return _CollabCard(
      child: InkWell(
        onTap: _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                message.locationLabel.isEmpty
                    ? 'View location'
                    : message.locationLabel,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// View-once sample video — `SampleBubble` in `CollabMessageBubbles.tsx`.
class _SampleBubble extends StatefulWidget {
  final CollabAsset? asset;
  final bool isClient;
  final Future<(String?, String?)> Function()? onView;
  const _SampleBubble({this.asset, required this.isClient, this.onView});

  @override
  State<_SampleBubble> createState() => _SampleBubbleState();
}

enum _ViewState { idle, loading, error }

class _SampleBubbleState extends State<_SampleBubble> {
  _ViewState _state = _ViewState.idle;

  Future<void> _tapToView() async {
    final action = widget.onView;
    final asset = widget.asset;
    if (action == null || asset == null || _state == _ViewState.loading) return;

    // `CollabMessageBubbles.tsx`'s confirm-before-view dialog — previously
    // missing here, so a tap called `collab-sample-view` (which burns the
    // one-time view server-side) immediately with no warning at all.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('View once'),
        content: const Text(
          "This is a view-once video — once you watch it, it's gone for "
          "good and can't be viewed again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('View now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _state = _ViewState.loading);
    final (url, error) = await action();
    if (!mounted) return;
    if (url == null) {
      setState(() => _state = _ViewState.error);
      if (error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _state = _ViewState.idle);
      });
      return;
    }
    setState(() => _state = _ViewState.idle);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.95),
        pageBuilder: (_, __, ___) => _OneTimeVideoOverlay(url: url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final viewed = asset == null ? false : asset.isConsumed;

    if (!widget.isClient) {
      return _CollabCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              viewed ? Icons.visibility_outlined : Icons.videocam_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              viewed ? 'Viewed by client' : 'Sent — awaiting view',
              style: AppTextStyles.caption.copyWith(fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    if (viewed) {
      return _CollabCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sample viewed — ask for a new one to see it again',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _tapToView,
      child: _CollabCard(
        child: Container(
          height: 96,
          width: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF2E2E4E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Center(
                child: _state == _ViewState.loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _state == _ViewState.error
                                ? Icons.error_outline
                                : Icons.visibility_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _state == _ViewState.error
                                ? 'Try again'
                                : 'Tap to view once',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen, once-only player. Closing (X, tap outside, or playback end)
/// leaves no local replay path — a second view requires a fresh
/// `collab-sample-view` call, which the server will refuse (410).
class _OneTimeVideoOverlay extends StatefulWidget {
  final String url;
  const _OneTimeVideoOverlay({required this.url});

  @override
  State<_OneTimeVideoOverlay> createState() => _OneTimeVideoOverlayState();
}

class _OneTimeVideoOverlayState extends State<_OneTimeVideoOverlay> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
    } catch (e) {
      debugPrint('CollabMessageBubble: sample playback failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Center(
            child: _failed
                ? const Text(
                    "Couldn't play this sample.",
                    style: TextStyle(color: Colors.white),
                  )
                : controller == null
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: GestureDetector(
                      onTap: () => setState(
                        () => controller.value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                      ),
                      child: VideoPlayer(controller),
                    ),
                  ),
          ),
          Positioned(
            top: 32,
            right: 16,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Final deliverable — `DeliverableBubble` in `CollabMessageBubbles.tsx`.
class _DeliverableBubble extends StatefulWidget {
  final CollabAsset? asset;
  final bool isClient;
  final Future<(String?, String?)> Function()? onDownload;
  const _DeliverableBubble({
    this.asset,
    required this.isClient,
    this.onDownload,
  });

  @override
  State<_DeliverableBubble> createState() => _DeliverableBubbleState();
}

class _DeliverableBubbleState extends State<_DeliverableBubble> {
  bool _downloading = false;

  /// `"{days}d {hours}h left"` once days > 0, else `"{hours}h left"` — a
  /// literal port of `CollabMessageBubbles.tsx`'s `timeRemaining`.
  String? _timeRemaining(DateTime? deadline) {
    if (deadline == null) return null;
    final ms = deadline.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 'expired';
    final days = ms ~/ 86400000;
    final hours = (ms % 86400000) ~/ 3600000;
    return days > 0 ? '${days}d ${hours}h left' : '${hours}h left';
  }

  Future<void> _download() async {
    final action = widget.onDownload;
    if (action == null || _downloading) return;
    setState(() => _downloading = true);
    final (url, error) = await action();
    if (!mounted) return;
    setState(() => _downloading = false);
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final remaining = _timeRemaining(asset?.downloadDeadline);
    final expired = asset == null
        ? false
        : (asset.isExpiredOrPurged || remaining == 'expired');

    if (expired) {
      return _CollabCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 18, color: AppColors.textHint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This file has been permanently removed (7-day window passed).',
                style: AppTextStyles.caption.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (!widget.isClient) {
      final downloaded = (asset?.downloadCount ?? 0) > 0;
      return _CollabCard(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_creation_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${downloaded ? 'Delivered — downloaded by client' : 'Delivered — awaiting download'}'
                '${remaining != null ? ' ($remaining)' : ''}',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return _CollabCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.movie_creation_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Final deliverable',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (remaining != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule, size: 13, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(
                  remaining,
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download'),
            ),
          ),
        ],
      ),
    );
  }
}
