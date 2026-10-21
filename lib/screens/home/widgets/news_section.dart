// screens/home/widgets/news_section.dart
//
// Home's "Latest News" rail plus its detail sheet.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW
// ------------------------------------------
// The portal's `NewsSection.tsx` returns null when the query comes back empty, so
// the page has no gap where the section would be. This does the same —
// `SizedBox.shrink()` for an empty list, a failed fetch, *and* the first frame
// before the fetch resolves. That last one matters on a feed: a header and a
// shimmer row that then vanish would shift everything below them. Nothing about
// this section is visible until there is real content for it.
//
// The fetch runs once per mount and is held in a field, not called from `build` —
// a `Future` created inside `build` re-fires on every rebuild, and this widget
// rebuilds whenever a sibling section's animation ticks.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/news_item_model.dart';
import '../../../services/news_service.dart';
import '../../../widgets/area_converter_sheet.dart' show SheetDragHandle;
import '../../../widgets/section_header.dart';

/// Rail height and card width. 16:9 thumbnail at 232 dp wide is 130 dp tall,
/// leaving room for a two-line title, an optional two-line summary and a source.
const double _kNewsRailHeight = 268;
const double _kNewsCardWidth = 232;
const double _kNewsThumbHeight = 124;

/// Trailing gap, owned by this section rather than by `home_screen.dart`'s
/// `sections` list.
///
/// Every other section's spacing is a separate entry in that list, which is fine
/// because every other section always renders something. This one can render
/// nothing, and a spacer sitting beside it in the list would survive that — the
/// feed would keep a 24 dp hole where the section used to be, on top of the 24 dp
/// already following Featured Properties. Holding the gap inside the widget makes
/// it collapse together with the content.
const double _kNewsBottomGap = 24;

const double _kSheetRadius = 24;

class NewsSection extends StatefulWidget {
  const NewsSection({super.key, this.service});

  /// Injected by tests. Production always builds a real service.
  @visibleForTesting
  final NewsService? service;

  @override
  State<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<NewsSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying `news` every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<NewsItemModel>> _future =
      (widget.service ?? NewsService()).listActive();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<NewsItemModel>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data;
        // Not loaded, failed, or genuinely empty — all three render nothing, so
        // the feed never grows and then loses a section.
        if (items == null || items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: _kNewsBottomGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Latest News'),
              SizedBox(
                height: _kNewsRailHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingL,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(
                      right: AppConstants.spacingM,
                    ),
                    child: ScaleTap(
                      onTap: () => showNewsDetailSheet(context, items[i]),
                      child: _NewsCard(item: items[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItemModel item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kNewsCardWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppConstants.cardRadius),
            ),
            child: NewsThumbnail(
              item: item,
              height: _kNewsThumbHeight,
              width: _kNewsCardWidth,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (item.summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (item.source != null)
                    Row(
                      children: [
                        const Icon(
                          Icons.newspaper_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.source!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
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

/// The still for a news item, with a play badge when it carries a video.
///
/// A video item may have no `image_url` at all, so the placeholder has to work as
/// a final fallback rather than only as a loading state.
class NewsThumbnail extends StatelessWidget {
  const NewsThumbnail({
    super.key,
    required this.item,
    required this.height,
    this.width,
  });

  final NewsItemModel item;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl;

    // Bounds decoding to this thumbnail's actual rendered pixels rather
    // than the source's native resolution — both the rail card (fixed
    // width) and the detail sheet (height only) benefit.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final Widget base = url == null
        ? _placeholder()
        : CachedNetworkImage(
            imageUrl: url,
            height: height,
            width: width,
            fit: BoxFit.cover,
            memCacheWidth: width == null ? null : (width! * dpr).round(),
            memCacheHeight: (height * dpr).round(),
            placeholder: (_, _) => _placeholder(),
            errorWidget: (_, _, _) => _placeholder(),
          );

    if (!item.hasVideo) return base;

    return Stack(
      alignment: Alignment.center,
      children: [
        base,
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
    height: height,
    width: width,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: const Icon(
      Icons.newspaper_rounded,
      size: 26,
      color: AppColors.primary,
    ),
  );
}

/// Opens the full story.
Future<void> showNewsDetailSheet(BuildContext context, NewsItemModel item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (_) => _NewsDetailSheet(item: item),
  );
}

class _NewsDetailSheet extends StatefulWidget {
  const _NewsDetailSheet({required this.item});

  final NewsItemModel item;

  @override
  State<_NewsDetailSheet> createState() => _NewsDetailSheetState();
}

class _NewsDetailSheetState extends State<_NewsDetailSheet> {
  VideoPlayerController? _video;

  /// Sound state for the speaker toggle. Starts unmuted: the portal plays a
  /// news video with audio (NewsDetail.tsx `<video controls>`, and the home
  /// card unmutes on hover) — it was only this sheet that forced volume 0.
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.hasVideo) _initVideo();
  }

  /// Looping + autoplay, with audio. Failure is swallowed to a null
  /// controller, which falls back to the still — a dead video URL must not
  /// take the sheet down.
  Future<void> _initVideo() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.item.videoUrl!),
    );
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _video = controller);
    } catch (_) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _toggleMute() async {
    final controller = _video;
    if (controller == null) return;
    setState(() => _muted = !_muted);
    await controller.setVolume(_muted ? 0 : 1);
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(widget.item.linkUrl!);
    if (uri == null) return;
    final bool opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open that link.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final media = MediaQuery.of(context);
    final controller = _video;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: AppConstants.spacingM),
              child: SheetDragHandle(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingXL,
                  0,
                  AppConstants.spacingXL,
                  AppConstants.spacingL,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.cardRadius,
                      ),
                      child:
                          controller != null && controller.value.isInitialized
                          ? AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  VideoPlayer(controller),
                                  // Speaker toggle — mute / unmute the video.
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    child: Semantics(
                                      label: _muted
                                          ? 'Unmute video'
                                          : 'Mute video',
                                      button: true,
                                      child: GestureDetector(
                                        onTap: _toggleMute,
                                        behavior: HitTestBehavior.opaque,
                                        child: Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _muted
                                                ? Icons.volume_off_rounded
                                                : Icons.volume_up_rounded,
                                            size: 19,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : NewsThumbnail(item: item, height: 190),
                    ),
                    const SizedBox(height: AppConstants.spacingL),
                    Text(
                      item.title,
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: 17,
                        height: 1.3,
                      ),
                    ),
                    if (item.source != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.newspaper_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              item.source!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (item.summary != null) ...[
                      const SizedBox(height: AppConstants.spacingM),
                      Text(
                        item.summary!,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          height: 1.55,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (item.hasLink) ...[
                      const SizedBox(height: AppConstants.spacingXL),
                      GestureDetector(
                        onTap: _openLink,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(
                              AppConstants.buttonRadius,
                            ),
                            boxShadow: AppColors.primaryGlow,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Read Full Story',
                                style: AppTextStyles.button.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.open_in_new_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
