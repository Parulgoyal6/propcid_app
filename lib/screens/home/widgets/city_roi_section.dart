// screens/home/widgets/city_roi_section.dart
//
// Home's "City ROI Index" rail — the Flutter counterpart to the portal's
// `CityROIIndexBanner.tsx`. Tapping a row filters Search Results to that
// city, the same mechanism `TrendingCitiesSection` and
// `BannerDestinationResolver` already use — the portal's own tap target for
// this rail (`navigate('/explore_${cityName}')`) is the same city-explore
// destination Trending Cities opens.
//
// Mirrors the portal's own double-slice: the service returns up to 10
// active rows ordered by `roi_percentage` descending, and this widget takes
// the top 5 of those for display.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW — same convention as every
// other admin/backend-driven Home rail.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/city_roi.dart';
import '../../../providers/filter_provider.dart';
import '../../../services/city_roi_service.dart';
import '../../../widgets/section_header.dart';

class CityRoiSection extends StatefulWidget {
  const CityRoiSection({super.key, this.service});

  @visibleForTesting
  final CityRoiService? service;

  @override
  State<CityRoiSection> createState() => _CityRoiSectionState();
}

class _CityRoiSectionState extends State<CityRoiSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying city ROI data every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<CityRoi>> _future =
      (widget.service ?? CityRoiService()).listActive();

  void _openCity(BuildContext context, CityRoi city) {
    context.read<FilterProvider>().setCities([city.cityName]);
    Navigator.pushNamed(context, AppConstants.searchResultsScreen);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<CityRoi>>(
      future: _future,
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null || all.isEmpty) return const SizedBox.shrink();
        final cities = all.take(5).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'City ROI Index'),
              ...cities.map(
                (city) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingL,
                    0,
                    AppConstants.spacingL,
                    AppConstants.spacingM,
                  ),
                  child: ScaleTap(
                    onTap: () => _openCity(context, city),
                    child: _CityRoiRow(city: city),
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

class _CityRoiRow extends StatelessWidget {
  const _CityRoiRow({required this.city});

  final CityRoi city;

  @override
  Widget build(BuildContext context) {
    // Bounds decoding to the thumbnail's actual rendered pixels (52×52
    // logical) rather than the source's native resolution.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final thumbCachePx = (52 * dpr).round();
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              AppConstants.imageThumbnailRadius,
            ),
            child: city.featuredImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: city.featuredImageUrl!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    memCacheWidth: thumbCachePx,
                    memCacheHeight: thumbCachePx,
                    placeholder: (_, _) => _thumbPlaceholder(),
                    errorWidget: (_, _, _) => _thumbPlaceholder(),
                  )
                : _thumbPlaceholder(),
          ),
          const SizedBox(width: AppConstants.spacingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city.cityName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (city.state != null)
                  Text(
                    city.state!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${city.roiPercentage.toStringAsFixed(1)}%',
                style: AppTextStyles.body.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
              Text('ROI', style: AppTextStyles.caption.copyWith(fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder() => Container(
    width: 52,
    height: 52,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: const Icon(
      Icons.location_city_rounded,
      size: 22,
      color: AppColors.primary,
    ),
  );
}
