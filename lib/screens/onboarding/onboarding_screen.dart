import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';

/// One feature bullet — a round icon medallion plus a short label, stacked
/// three to a slide under the subtitle.
class _FeaturePoint {
  final IconData icon;
  final String label;
  const _FeaturePoint(this.icon, this.label);
}

class _OnboardingSlide {
  final String titleTop;
  final String titleAccent;
  final String subtitle;
  final String imageUrl;
  final List<_FeaturePoint> features;

  /// Slide 1's medallions are solid orange with a white icon; slides 2/3 use
  /// white medallions with an orange icon — matching the reference design.
  final bool filledMedallions;

  const _OnboardingSlide({
    required this.titleTop,
    required this.titleAccent,
    required this.subtitle,
    required this.imageUrl,
    required this.features,
    required this.filledMedallions,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int currentIndex = 0;

  final List<_OnboardingSlide> slides = const [
    _OnboardingSlide(
      titleTop: 'Find With',
      titleAccent: 'Confidence',
      subtitle:
          'Discover properties with verified details and complete transparency.',
      imageUrl:
          'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=1000&q=80',
      features: [
        _FeaturePoint(Icons.verified_user_rounded, 'Verified Listings'),
        _FeaturePoint(Icons.location_on_rounded, 'Accurate Locations'),
        _FeaturePoint(Icons.home_rounded, 'Trusted Information'),
      ],
      filledMedallions: true,
    ),
    _OnboardingSlide(
      titleTop: 'List With',
      titleAccent: 'Ease',
      subtitle: 'Showcase your property to the right people.',
      imageUrl:
          'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=1000&q=80',
      features: [
        _FeaturePoint(Icons.home_outlined, 'Easy Listing'),
        _FeaturePoint(Icons.campaign_outlined, 'Reach Serious Buyers'),
        _FeaturePoint(Icons.visibility_outlined, 'Get More Visibility'),
      ],
      filledMedallions: false,
    ),
    _OnboardingSlide(
      titleTop: 'Connect',
      titleAccent: 'Directly',
      subtitle: 'Connect with owners, buyers and sellers.',
      imageUrl:
          'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=1000&q=80',
      features: [
        _FeaturePoint(Icons.chat_bubble_outline_rounded, 'Chat Directly'),
        _FeaturePoint(Icons.calendar_month_outlined, 'Schedule Site Visits'),
        _FeaturePoint(Icons.groups_outlined, 'Property Owner Connect'),
      ],
      filledMedallions: false,
    ),
  ];

  bool get _isLastSlide => currentIndex == slides.length - 1;

  Future<void> finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;

    context.read<AuthProvider>().enableNavigation();
  }

  void _onPrimaryPressed() {
    if (_isLastSlide) {
      finishOnboarding();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
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
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (value) => setState(() => currentIndex = value),
            itemBuilder: (context, index) =>
                _OnboardingSlideVisual(slide: slides[index]),
          ),
          // Fixed chrome over the swiping photos — progress dashes + Skip at
          // the top, the glass CTA at the bottom.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _ProgressDashes(
                        count: slides.length,
                        activeIndex: currentIndex,
                      ),
                      const Spacer(),
                      _GlassPill(
                        onTap: finishOnboarding,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Skip',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: _GlassPill(
                        onTap: _onPrimaryPressed,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLastSlide ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: Colors.white,
                                )
                                .animate(
                                  onPlay: (c) => c.repeat(reverse: true),
                                )
                                .moveX(
                                  begin: 0,
                                  end: 4,
                                  duration: 700.ms,
                                  curve: Curves.easeInOut,
                                ),
                          ],
                        ),
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

/// Three short dashes top-left — the active one orange, the rest a soft
/// translucent white.
class _ProgressDashes extends StatelessWidget {
  const _ProgressDashes({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (index) {
        final bool isActive = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.only(right: 8),
          width: 26,
          height: 4,
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary
                : Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

/// Frosted, white-outlined pill used by both Skip and the Next/Get Started
/// CTA so they read clearly over any part of the photo.
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.onTap,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(100);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.white.withOpacity(0.12),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withOpacity(0.75),
                  width: 1.2,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// One slide: full-bleed photo, dark wash top and bottom, and the headline,
/// subtitle and feature list overlaid top-left.
class _OnboardingSlideVisual extends StatelessWidget {
  const _OnboardingSlideVisual({required this.slide});

  final _OnboardingSlide slide;

  static const _titleShadow = [
    Shadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _SlidePhoto(imageUrl: slide.imageUrl),
        SafeArea(
          bottom: false,
          child: Padding(
            // Clears the progress dashes / Skip row above.
            padding: const EdgeInsets.fromLTRB(24, 58, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slide.titleTop,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        color: Colors.white,
                        shadows: _titleShadow,
                      ),
                    ),
                    Text(
                      slide.titleAccent,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: AppColors.primary,
                        shadows: _titleShadow,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 330),
                      child: Text(
                        slide.subtitle,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: Colors.white,
                          shadows: _titleShadow,
                        ),
                      ),
                    ),
                  ],
                ).animate().fadeIn(duration: 450.ms).slideY(
                  begin: 0.15,
                  end: 0,
                  duration: 450.ms,
                  curve: Curves.easeOut,
                ),
                const SizedBox(height: 26),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in slide.features) ...[
                      _FeatureBullet(
                        feature: f,
                        filled: slide.filledMedallions,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ).animate(delay: 150.ms).fadeIn(duration: 450.ms).slideY(
                  begin: 0.15,
                  end: 0,
                  duration: 450.ms,
                  curve: Curves.easeOut,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.feature, required this.filled});

  final _FeaturePoint feature;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: filled ? AppColors.primary : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: filled ? Colors.white : AppColors.primary,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            feature.icon,
            size: 20,
            color: filled ? Colors.white : AppColors.primary,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            feature.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Color(0x80000000),
                  blurRadius: 8,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SlidePhoto extends StatelessWidget {
  const _SlidePhoto({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              const ColoredBox(color: Color(0xFF1E1B18)),
          errorWidget: (context, url, error) =>
              const ColoredBox(color: Color(0xFF1E1B18)),
        ),
        // Dark wash behind the headline and the CTA, clear through the
        // middle so the photo shows.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC000000),
                Color(0x8C000000),
                Color(0x14000000),
                Color(0x00000000),
                Color(0x99000000),
              ],
              stops: [0.0, 0.3, 0.55, 0.72, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
