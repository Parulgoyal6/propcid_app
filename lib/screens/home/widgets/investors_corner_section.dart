// screens/home/widgets/investors_corner_section.dart
//
// Home's "Investor's Corner" rail — the Flutter counterpart to the portal's
// `InvestorsCornerSection.tsx`. Cards are intentionally not tappable: the
// portal's own cards carry no `onClick` either (only its "View All" header
// action does, and that opens a dedicated `/investors-corner` list page
// this app has no equivalent screen for).
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW — same convention as every
// other admin/backend-driven Home rail.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/investor_opportunity.dart';
import '../../../models/property_model.dart';
import '../../../services/investors_corner_service.dart';
import '../../../widgets/section_header.dart';

const double _kInvestorCardWidth = 250;
// 16:9 image inside the card padding, like the portal's `aspect-[16/9]`.
const double _kInvestorImageHeight = 126;
const double _kCardPadding = 12;

class InvestorsCornerSection extends StatefulWidget {
  const InvestorsCornerSection({super.key, this.service});

  @visibleForTesting
  final InvestorsCornerService? service;

  @override
  State<InvestorsCornerSection> createState() => _InvestorsCornerSectionState();
}

class _InvestorsCornerSectionState extends State<InvestorsCornerSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying investor opportunities every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<InvestorOpportunity>> _future =
      (widget.service ?? InvestorsCornerService()).listActive();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<InvestorOpportunity>>(
      future: _future,
      builder: (context, snapshot) {
        final items = snapshot.data;
        if (items == null || items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: "Investor's Corner"),
              SizedBox(
                // Fixed parts (padding, image, gaps) + text rows that grow
                // with the user's text-size setting, so the card never
                // overflows at large accessibility text sizes.
                height: 190 + 125 * (MediaQuery.textScalerOf(context).scale(14) / 14),
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
                    child: _InvestorCard(item: items[i]),
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

/// One opportunity card, field-for-field the portal's
/// `InvestorsCornerSection.tsx` slide: "% ROI" badge top-right, 16:9 image,
/// title, 2-line description, investment amount, time period, and the
/// "% Yield" / "% Growth" chips.
class _InvestorCard extends StatelessWidget {
  const _InvestorCard({required this.item});

  final InvestorOpportunity item;

  /// `15.0` -> "15", `6.5` -> "6.5" — the portal prints the raw number.
  static String _num(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  Widget build(BuildContext context) {
    // Bounds decoding to the card's actual rendered pixels rather than the
    // source's native resolution.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    const imageWidth = _kInvestorCardWidth - _kCardPadding * 2;

    final yieldPct = item.rentalYieldPercentage;
    final growthPct = item.appreciationPercentage;

    return Container(
      width: _kInvestorCardWidth,
      padding: const EdgeInsets.all(_kCardPadding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.featuredImageUrl.isEmpty
                    ? _placeholder()
                    : CachedNetworkImage(
                        imageUrl: item.featuredImageUrl,
                        height: _kInvestorImageHeight,
                        width: imageWidth,
                        fit: BoxFit.cover,
                        memCacheWidth: (imageWidth * dpr).round(),
                        memCacheHeight: (_kInvestorImageHeight * dpr).round(),
                        placeholder: (_, _) => _placeholder(),
                        errorWidget: (_, _, _) => _placeholder(),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (item.investmentAmount != null)
                _InfoRow(
                  icon: Icons.attach_money_rounded,
                  text: PropertyModel.formatIndianPrice(item.investmentAmount),
                ),
              if (item.timePeriodMonths != null) ...[
                const SizedBox(height: 6),
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  text: '${item.timePeriodMonths} months',
                ),
              ],
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (yieldPct != null && yieldPct != 0)
                    _StatChip(
                      label: '${_num(yieldPct)}% Yield',
                      background: const Color(0xFFDBEAFE),
                      foreground: const Color(0xFF1E40AF),
                    ),
                  if (growthPct != null && growthPct != 0)
                    _StatChip(
                      label: '${_num(growthPct)}% Growth',
                      background: const Color(0xFFF3E8FF),
                      foreground: const Color(0xFF6B21A8),
                    ),
                ],
              ),
            ],
          ),
          if (item.expectedRoiPercentage != null)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF25400), Color(0xFFFF7C0A)],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                  boxShadow: AppColors.surfaceCardShadow,
                ),
                child: Text(
                  '${_num(item.expectedRoiPercentage!)}% ROI',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    height: _kInvestorImageHeight,
    width: _kInvestorCardWidth - _kCardPadding * 2,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: const Icon(
      Icons.insights_rounded,
      size: 26,
      color: AppColors.primary,
    ),
  );
}

/// Icon + bold value line (investment amount / time period).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textPrimary.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small tinted "% Yield" / "% Growth" chip.
class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
