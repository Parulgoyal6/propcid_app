// screens/home/widgets/property_verification_section.dart
//
// Home's Property Verification promo — a three-card carousel plus a CTA card,
// all of which open the verification form.
//
// The three cards, their copy and their icons are the portal's
// `features/property/PropertyVerificationBanner.tsx:44-86` set: Market Rate
// Analysis / Legal Verification / Growth Insights, with the descriptions
// unchanged. The dot indicator is that banner's too, translated to a `Row` of
// animated pills driven by the `PageController`.
//
// Colour: the portal's orange is not carried over. Each card gets its own tint —
// primary orange, `AppColors.success` green, `AppColors.warning` amber — so the
// three read as distinct without inventing a palette.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../widgets/property_verification_sheet.dart';

/// Carousel height, sized for the tallest card (badge + title + two-line body).
const double _kCarouselHeight = 132;

class _VerificationCard {
  const _VerificationCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.tint,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color tint;
}

class PropertyVerificationSection extends StatefulWidget {
  const PropertyVerificationSection({super.key});

  @override
  State<PropertyVerificationSection> createState() =>
      _PropertyVerificationSectionState();
}

class _PropertyVerificationSectionState
    extends State<PropertyVerificationSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_controller`/`_page` across Home's own scroll — without
  // this, scrolling this section far enough off/on screen disposes and
  // rebuilds it from scratch, snapping the carousel back to its first page.
  @override
  bool get wantKeepAlive => true;

  final PageController _controller = PageController(viewportFraction: 0.86);
  int _page = 0;

  /// `PropertyVerificationBanner.tsx:44-86`, copy verbatim.
  static const List<_VerificationCard> _cards = [
    _VerificationCard(
      title: 'Market Rate Analysis',
      description: 'Check out the market rate with local experts',
      icon: Icons.bar_chart_rounded,
      tint: AppColors.primary,
    ),
    _VerificationCard(
      title: 'Legal Verification',
      description: 'Verify legal aspect of property before buying',
      icon: Icons.verified_user_rounded,
      tint: AppColors.success,
    ),
    _VerificationCard(
      title: 'Growth Insights',
      description: 'Advice on future growth of the property',
      icon: Icons.trending_up_rounded,
      tint: AppColors.warning,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// Driven off the controller rather than `onPageChanged` so the dots track a
  /// drag continuously instead of snapping only when a page settles.
  void _onScroll() {
    final page = _controller.page?.round() ?? 0;
    if (page != _page && mounted) setState(() => _page = page);
  }

  void _open() => showPropertyVerificationSheet(context);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // One extra page for the CTA card at the end of the carousel.
    final int pageCount = _cards.length + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingL,
            0,
            AppConstants.spacingL,
            AppConstants.spacingM,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Property Verification',
                      style: AppTextStyles.heading3.copyWith(fontSize: 16),
                    ),
                    Text(
                      'Expert verification services',
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _kCarouselHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: pageCount,
            padEnds: false,
            itemBuilder: (context, index) {
              final bool isCta = index == _cards.length;
              return Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? AppConstants.spacingL : 0,
                  right: AppConstants.spacingM,
                ),
                child: ScaleTap(
                  onTap: _open,
                  child: isCta
                      ? const _CtaCard()
                      : _InfoCard(card: _cards[index]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pageCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : AppColors.hairline,
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.card});

  final _VerificationCard card;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: card.tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(card.icon, size: 19, color: card.tint),
          ),
          const Spacer(),
          Text(
            card.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            card.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// The last page — the explicit call to action.
class _CtaCard extends StatelessWidget {
  const _CtaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            'Verify with Experts',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                'Get Started',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 13,
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
