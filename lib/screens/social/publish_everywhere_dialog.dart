import 'package:flutter/material.dart';

import '../../config/launch_features.dart';
import '../../core/constants/app_constants.dart';
import '../../models/social_models.dart';
import '../../services/social_service.dart';

/// Shows the "Publish everywhere" dialog for one already-created piece of
/// content — a direct port of `PublishEverywhereDialog.tsx`.
///
/// There is no content picker here, on either platform: the portal always
/// launches this from an existing item's context (auto-opened right after a
/// property/project is created, or from a manual "Share" button on a
/// reel/article/video's success card), never as a standalone "pick something
/// to publish" flow. Callers pass the content that already exists.
Future<void> showPublishEverywhereDialog(
  BuildContext context, {
  required String userId,
  required String contentType,
  required String contentId,
  required List<String> mediaUrls,
  String? title,
}) async {
  if (!LaunchFeatures.metaPublishing) return;
  return showDialog<void>(
    context: context,
    builder: (_) => PublishEverywhereDialog(
      userId: userId,
      contentType: contentType,
      contentId: contentId,
      mediaUrls: mediaUrls,
      title: title,
    ),
  );
}

class PublishEverywhereDialog extends StatefulWidget {
  final String userId;
  final String contentType;
  final String contentId;
  final List<String> mediaUrls;
  final String? title;

  const PublishEverywhereDialog({
    super.key,
    required this.userId,
    required this.contentType,
    required this.contentId,
    required this.mediaUrls,
    this.title,
  });

  @override
  State<PublishEverywhereDialog> createState() =>
      _PublishEverywhereDialogState();
}

class _PublishEverywhereDialogState extends State<PublishEverywhereDialog> {
  final _service = SocialService();

  bool _loading = true;
  bool _loadFailed = false;
  bool _publishing = false;
  SocialAccount? _account;
  SocialPreferences? _prefs;

  bool _fb = false;
  bool _ig = false;
  bool _fbFeed = true;
  bool _fbStory = false;
  bool _igFeed = true;
  bool _igStory = false;

  bool _genFb = false;
  bool _genIg = false;

  final _fbCaptionController = TextEditingController();
  final _igCaptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fbCaptionController.dispose();
    _igCaptionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final account = await _service.getAccount(widget.userId);
      final prefs = await _service.getPreferences(widget.userId);
      if (!mounted) return;

      final canFb = account?.connected == true && prefs.fbEnabled;
      final canIg = account?.hasInstagram == true && prefs.igEnabled;
      setState(() {
        _account = account;
        _prefs = prefs;
        _fb = canFb;
        _ig = canIg;
        _fbFeed = true;
        _fbStory = prefs.fbStory;
        _igFeed = prefs.igFeed;
        _igStory = prefs.igStory;
        _loading = false;
      });
      if (canFb) _draft('facebook');
      if (canIg) _draft('instagram');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _draft(String platform) async {
    final isFb = platform == 'facebook';
    setState(() => isFb ? _genFb = true : _genIg = true);
    try {
      final res = await _service.generateCaption(
        contentType: widget.contentType,
        contentId: widget.contentId,
        platform: platform,
      );
      if (!mounted) return;
      final caption = '${res['caption'] ?? ''}';
      final hashtags = (res['hashtags'] as List? ?? const [])
          .map((h) => '$h')
          .toList();
      final cta = (res['cta'] as String?) ?? _prefs?.defaultCta;
      final composed = composeCaption(caption, hashtags, cta);
      if (composed.isNotEmpty) {
        (isFb ? _fbCaptionController : _igCaptionController).text = composed;
      }
    } finally {
      if (mounted) setState(() => isFb ? _genFb = false : _genIg = false);
    }
  }

  List<String> get _fbTargets =>
      _fb ? [if (_fbFeed) 'feed', if (_fbStory) 'story'] : const [];

  List<String> get _igTargets =>
      _ig ? [if (_igFeed) 'feed', if (_igStory) 'story'] : const [];

  Future<void> _publish() async {
    final fbTargets = _fbTargets;
    final igTargets = _igTargets;
    if (fbTargets.isEmpty && igTargets.isEmpty) {
      Navigator.pop(context);
      return;
    }

    // Instagram (any destination) and Stories need at least one image.
    final needsImage = igTargets.isNotEmpty || fbTargets.contains('story');
    if (needsImage && widget.mediaUrls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Instagram and Stories need at least one image. Add media, or '
            'publish to Facebook Feed only.',
          ),
        ),
      );
      return;
    }

    setState(() => _publishing = true);
    try {
      final queued = await _service.publishEverywhere(
        userId: widget.userId,
        contentType: widget.contentType,
        contentId: widget.contentId,
        facebook: fbTargets,
        instagram: igTargets,
        captions: {
          'facebook': _fbCaptionController.text,
          'instagram': _igCaptionController.text,
        },
        mediaUrls: widget.mediaUrls,
        cta: _prefs?.defaultCta,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Queued for $queued destination${queued == 1 ? '' : 's'}. '
            "You'll be notified when it's live.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notConnected =
        !_loading && !_loadFailed && _account?.connected != true;
    final nothingSelected = _fbTargets.isEmpty && _igTargets.isEmpty;

    return AlertDialog(
      scrollable: true,
      title: const Text('Publish everywhere'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title != null && widget.title!.isNotEmpty
                  ? '"${widget.title}" is live on PropCID. Choose where to '
                        'share it and pick the destinations.'
                  : 'Your content is live on PropCID. Choose where to share '
                        'it and pick the destinations.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Published to PropCID',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loadFailed)
              _LoadErrorPrompt(onRetry: _load)
            else if (notConnected)
              _ConnectPrompt(
                onConnect: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(
                    context,
                    AppConstants.socialAccountsScreen,
                  );
                },
              )
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _PlatformBlock(
                enabled: _fb,
                onToggle: (v) => setState(() => _fb = v),
                disabled: _account?.connected != true,
                icon: Icons.facebook,
                iconColor: const Color(0xFF1877F2),
                label: 'Facebook Page',
                subtitle: _account?.pageName,
                captionController: _fbCaptionController,
                generating: _genFb,
                onGenerate: () => _draft('facebook'),
                destinations: [
                  _Destination(
                    'Feed post',
                    _fbFeed,
                    (v) => setState(() => _fbFeed = v),
                  ),
                  _Destination(
                    'Story',
                    _fbStory,
                    (v) => setState(() => _fbStory = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _PlatformBlock(
                enabled: _ig,
                onToggle: (v) => setState(() => _ig = v),
                disabled: _account?.hasInstagram != true,
                icon: Icons.camera_alt_outlined,
                iconColor: const Color(0xFFE4405F),
                label: 'Instagram',
                subtitle: _account?.hasInstagram == true
                    ? '@${_account!.instagramUsername}'
                    : 'No IG linked',
                captionController: _igCaptionController,
                generating: _genIg,
                onGenerate: () => _draft('instagram'),
                destinations: [
                  _Destination(
                    'Feed post',
                    _igFeed,
                    (v) => setState(() => _igFeed = v),
                  ),
                  _Destination(
                    'Story',
                    _igStory,
                    (v) => setState(() => _igStory = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.mediaUrls.isNotEmpty
                    ? '${widget.mediaUrls.length} image'
                          '${widget.mediaUrls.length == 1 ? '' : 's'} will be '
                          'attached'
                          '${widget.mediaUrls.length > 1 ? ' as a carousel (Feed)' : ''}. '
                          'Stories use the first image.'
                    : 'No images found — Facebook Feed will post text only; '
                          'Instagram and Stories require at least one image.',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _publishing ? null : () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        ElevatedButton.icon(
          onPressed:
              (_publishing || notConnected || nothingSelected || _loadFailed)
              ? null
              : _publish,
          icon: _publishing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text('Publish everywhere'),
        ),
      ],
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  final VoidCallback onConnect;

  const _ConnectPrompt({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2EA)),
      ),
      child: Column(
        children: [
          const Text(
            'Connect Facebook & Instagram to publish there automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.open_in_new, size: 15),
            label: const Text('Connect accounts'),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Destination(this.label, this.value, this.onChanged);
}

class _LoadErrorPrompt extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadErrorPrompt({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E2EA)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.amber, size: 24),
          const SizedBox(height: 10),
          const Text(
            "Couldn't check your connection status.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _PlatformBlock extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final bool disabled;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final TextEditingController captionController;
  final bool generating;
  final VoidCallback onGenerate;
  final List<_Destination> destinations;

  const _PlatformBlock({
    required this.enabled,
    required this.onToggle,
    required this.disabled,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.captionController,
    required this.generating,
    required this.onGenerate,
    required this.destinations,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E2EA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: enabled,
                  onChanged: disabled ? null : (v) => onToggle(v ?? false),
                ),
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: (disabled || generating || !enabled)
                      ? null
                      : onGenerate,
                  icon: generating
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('AI', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if (enabled) ...[
              Padding(
                padding: const EdgeInsets.only(left: 40),
                child: Wrap(
                  spacing: 16,
                  children: [
                    for (final d in destinations)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(value: d.value, onChanged: d.onChanged),
                          Text(d.label, style: const TextStyle(fontSize: 12.5)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: captionController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write a caption or tap AI to generate one…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Captions apply to Feed posts. Stories are image-only (no '
                'caption).',
                style: TextStyle(fontSize: 10.5, color: Colors.black45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
