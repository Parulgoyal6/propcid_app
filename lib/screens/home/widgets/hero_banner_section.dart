import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/navigation/banner_destination_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/banner_destination.dart';

class _BannerData {
  const _BannerData({
    required this.imageUrl,
    required this.eyebrow,
    required this.headline,
    required this.accentWord,
    required this.subtext,
    required this.destination,
  });

  final String imageUrl;
  final String eyebrow;
  final String headline;
  final String accentWord;
  final String subtext;
  final BannerDestination destination;
}

/// The Home hero carousel — full-bleed photo cards, "FEATURED" pill, page
/// counter, a large headline with one accent word, and a white CTA pill, per
/// the reference design. One card per `BannerDestinationType` so every
/// resolver branch (including the graceful "coming soon" ones) is exercised
/// at least once. Every tap — card or CTA — hands a `BannerDestination` to
/// `BannerDestinationResolver`; nothing here calls `Navigator` directly.
class HeroBannerSection extends StatefulWidget {
  const HeroBannerSection({super.key});

  @override
  State<HeroBannerSection> createState() => _HeroBannerSectionState();
}

class _HeroBannerSectionState extends State<HeroBannerSection>
    with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int _bannerCount = 5;

  /// A one-shot `Timer`, rescheduled after every advance — properly
  /// cancellable (`_autoAdvanceTimer?.cancel()` takes effect immediately),
  /// unlike the previous `Future.doWhile` + `Future.delayed` loop, which had
  /// no handle to cancel at all: it could only stop *after* its next 5s
  /// delay elapsed and re-checked `mounted`, so it kept firing (and
  /// animating the PageView) for up to 5s after the Hero had already
  /// scrolled off screen or Home had started scrolling.
  Timer? _autoAdvanceTimer;

  /// The enclosing Home feed's scroll position, mirroring
  /// `PropertyReelsSection`'s own pattern: pause automatic advancement while
  /// Home is scrolling, and only ever recompute whether the Hero is still on
  /// screen once scrolling actually stops — never on every scroll pixel.
  ScrollPosition? _outerPosition;
  bool _onScreen = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scheduleAutoAdvance();
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
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _outerPosition?.isScrollingNotifier.removeListener(
      _onOuterScrollingChanged,
    );
    _pageController.dispose();
    super.dispose();
  }

  /// Fires only when the outer Home feed's `isScrollingNotifier` flips —
  /// twice per scroll gesture (start, then settle), not once per pixel.
  void _onOuterScrollingChanged() {
    final isScrolling = _outerPosition?.isScrollingNotifier.value ?? false;
    if (isScrolling) {
      _autoAdvanceTimer?.cancel();
      return;
    }

    // Scrolling just settled — the one point visibility is (re)computed.
    final visible = _isOnScreen();
    _onScreen = visible;
    if (visible) {
      _scheduleAutoAdvance();
    } else {
      _autoAdvanceTimer?.cancel();
    }
  }

  /// True while any part of the Hero is within the screen's vertical bounds.
  /// Only ever called from [_onOuterScrollingChanged], once scrolling has
  /// actually stopped — never per scroll pixel/frame.
  bool _isOnScreen() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.of(context).size.height;
    return top < screenHeight && top + box.size.height > 0;
  }

  void _scheduleAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    if (!_onScreen) return;
    _autoAdvanceTimer = Timer(const Duration(seconds: 5), _advance);
  }

  void _advance() {
    if (!mounted || !_onScreen) return;
    if (_bannerCount > 1 && _pageController.hasClients) {
      final next = (_currentPage + 1) % _bannerCount;
      _pageController
          .animateToPage(
            next,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          )
          .then((_) {
            if (mounted) _scheduleAutoAdvance();
          });
    } else {
      _scheduleAutoAdvance();
    }
  }

  List<_BannerData> _buildBanners(BuildContext context) {
    return [
      // Static promo slide — deliberately not tied to any single listing
      // (no `PropertyProvider`/`PropertyModel` dependency): a rotating
      // "featured" property here previously surfaced that listing's own
      // photo as the banner image, which read as an ad for one specific
      // property rather than the app itself. Image/subtext/destination are
      // all fixed, same as the other four slides.
      const _BannerData(
        imageUrl:
            'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800&q=80',
        eyebrow: 'Featured Listing',
        headline: 'Discover Your',
        accentWord: 'Dream Home.',
        subtext: 'Premium properties, trusted by thousands',
        destination: BannerDestination.collection(),
      ),
      const _BannerData(
        imageUrl:
            'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800&q=80',
        eyebrow: 'Luxury Collection',
        headline: 'Live in',
        accentWord: 'Style.',
        subtext: 'Handpicked premium residences, 50+ cities',
        destination: BannerDestination.collection(budgetMin: 20000000),
      ),
      const _BannerData(
        imageUrl:
            'https://images.unsplash.com/photo-1778159396492-b9a89e6d99f2?w=1600&q=85',
        eyebrow: 'New Launches',
        headline: 'Your Dream',
        accentWord: 'Home.',
        subtext: 'Exclusive pre-launch deals available now',
        destination: BannerDestination.project(hashtag: 'newlaunch'),
      ),
      const _BannerData(
        imageUrl:
            'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=800&q=80',
        eyebrow: 'Builder Spotlight',
        headline: 'Trusted',
        accentWord: 'Builders.',
        subtext: 'Verified developers, verified projects',
        destination: BannerDestination.builder(),
      ),
      const _BannerData(
        imageUrl:
            'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=800&q=80',
        eyebrow: 'PropCID Magazine',
        headline: 'City Living',
        accentWord: 'Guides.',
        subtext: 'Neighborhood guides & smart buying tips',
        // Placeholder destination — points at the reserved documentation
        // domain until a real magazine/blog URL exists.
        destination: BannerDestination.externalUrl(
          'https://example.com/propcid-magazine',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final banners = _buildBanners(context);
    _bannerCount = banners.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // 240 dp card + 16 dp below it so the card's soft floating shadow
          // isn't clipped by the PageView viewport.
          height: 256,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: banners.length,
            itemBuilder: (context, i) => _BannerCard(
              data: banners[i],
              pageController: _pageController,
              index: i,
              total: banners.length,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(banners.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 22 : 6,
                height: 6,
                decoration: BoxDecoration(
                  gradient: active ? AppColors.ctaGradient : null,
                  color: active ? null : AppColors.primary.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
        // Gradient bleed: the brand tint fades out under the dot row instead
        // of ending on a hard edge, so the next section doesn't read as a
        // separate box dropped underneath.
        Container(
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primaryLight.withOpacity(0.5),
                AppColors.primaryLight.withOpacity(0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.data,
    required this.pageController,
    required this.index,
    required this.total,
  });

  final _BannerData data;
  final PageController pageController;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    // Above the fold on every Home load, and the one image on this screen
    // that had no cache-size bound at all — every other rail sizes its
    // `CachedNetworkImage` to its actual rendered dp size (see
    // trending_cities_section.dart), which this now matches.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (MediaQuery.of(context).size.width * dpr).round();
    const cacheHeight = 240;

    // Carousel depth: a banner that is swiping out shrinks slightly while
    // the incoming one grows to full size — driven straight off the
    // PageController, so it tracks the finger with no extra controller.
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        double page = index.toDouble();
        if (pageController.hasClients &&
            pageController.position.haveDimensions) {
          page = pageController.page ?? index.toDouble();
        }
        final delta = (page - index).abs().clamp(0.0, 1.0);
        return Transform.scale(scale: 1 - delta * 0.06, child: child);
      },
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ScaleTap(
        scaleDown: 0.98,
        onTap: () =>
            BannerDestinationResolver.navigate(context, data.destination),
        child: DecoratedBox(
          // Floating depth: a warm orange glow + a soft contact shadow, and a
          // thin white glass rim painted over the photo's edge.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40F97316),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
              BoxShadow(
                color: Color(0x1A1A1A2E),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          position: DecorationPosition.background,
          child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.55)),
          ),
          child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Subtle parallax: the photo drifts opposite the swipe as the
              // page settles, driven directly by the PageController (no
              // extra AnimationController needed).
              AnimatedBuilder(
                animation: pageController,
                builder: (context, child) {
                  double page = index.toDouble();
                  if (pageController.hasClients &&
                      pageController.position.haveDimensions) {
                    page = pageController.page ?? index.toDouble();
                  }
                  final delta = (page - index).clamp(-1.0, 1.0);
                  return OverflowBox(
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(-delta * 24, 0),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width - 32 + 48,
                        child: child,
                      ),
                    ),
                  );
                },
                child: CachedNetworkImage(
                  imageUrl: data.imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheWidth,
                  memCacheHeight: (cacheHeight * dpr).round(),
                  placeholder: (context, url) =>
                      Container(color: AppColors.primaryLight),
                  errorWidget: (context, url, error) =>
                      Container(color: AppColors.primary.withOpacity(0.25)),
                ),
              ),
              // Bottom scrim for text legibility.
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Light top shade for the chips, a clear middle so the
                    // photo stays vivid, deep cinematic fade under the text.
                    colors: [
                      Colors.black.withOpacity(0.2),
                      Colors.transparent,
                      Colors.black.withOpacity(0.28),
                      Colors.black.withOpacity(0.8),
                    ],
                    stops: const [0.0, 0.28, 0.62, 1.0],
                  ),
                ),
              ),
              // FEATURED pill — frosted glass, matching the rest of Home's
              // glass system, while staying opaque enough to read clearly
              // over any part of the photo.
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.ctaGradient,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.4)),
                    boxShadow: AppColors.ctaShadow,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Page counter — dark frosted glass, same treatment, tuned
              // dark so it still reads over light parts of the photo.
              Positioned(
                top: 14,
                right: 14,
                child: _GlassChip(
                  tint: Colors.black,
                  tintOpacity: 0.4,
                  borderOpacity: 0.22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    '${index + 1} / $total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Text + CTA.
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.eyebrow.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                        children: [
                          TextSpan(text: '${data.headline} '),
                          TextSpan(
                            text: data.accentWord,
                            style: const TextStyle(color: Color(0xFFFFC98A)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.subtext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Frosted white-glass CTA over the photo.
                    _GlassChip(
                      tintOpacity: 0.3,
                      borderOpacity: 0.7,
                      radius: 24,
                      padding: const EdgeInsets.fromLTRB(16, 5, 5, 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Explore Properties',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              gradient: AppColors.ctaGradient,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
          ),
        ),
      ),
      ),
    );
  }
}

/// A small frosted-glass chip — used for the banner's FEATURED tag, page
/// counter, and "Explore Properties" CTA, so every overlay on the hero photo
/// reads as part of the same glass system as the rest of Home, without ever
/// blurring the photo itself (only what's behind each small chip is
/// blurred — the photo stays 100% sharp everywhere else).
class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.child,
    required this.padding,
    this.tint = Colors.white,
    this.tintOpacity = 0.78,
    this.borderOpacity = 0.55,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;
  final double tintOpacity;
  final double borderOpacity;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withOpacity(tintOpacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(borderOpacity)),
          ),
          child: child,
        ),
      ),
    );
  }
}
