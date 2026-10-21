// screens/home/widgets/trending_cities_section.dart
//
// Home's "Trending Cities" rail — the Flutter counterpart to the portal's
// `TrendingCitiesBanner.tsx`.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW
// ------------------------------------------
// Same reasoning as `NewsSection`: `SizedBox.shrink()` while loading, on
// failure, and when the admin table genuinely has no active rows. No
// hardcoded sample cities are substituted — unlike the portal's own
// placeholder fallback, this app must never show invented data in place of
// admin-controlled content.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/property_model.dart';
import '../../../models/trending_city.dart';
import '../../../providers/filter_provider.dart';
import '../../../services/trending_cities_service.dart';
import '../../../widgets/section_header.dart';

const double _kCityRailHeight = 190;
const double _kCityCardWidth = 152;

class TrendingCitiesSection extends StatefulWidget {
  const TrendingCitiesSection({super.key, this.service});

  @visibleForTesting
  final TrendingCitiesService? service;

  @override
  State<TrendingCitiesSection> createState() => _TrendingCitiesSectionState();
}

class _TrendingCitiesSectionState extends State<TrendingCitiesSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying trending cities every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<TrendingCity>> _future =
      (widget.service ?? TrendingCitiesService()).listActive();

  void _openCity(BuildContext context, TrendingCity city) {
    context.read<FilterProvider>().setCities([city.cityName]);
    Navigator.pushNamed(context, AppConstants.searchResultsScreen);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<TrendingCity>>(
      future: _future,
      builder: (context, snapshot) {
        final cities = snapshot.data;
        if (cities == null || cities.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Top Trending Cities'),
              SizedBox(
                height: _kCityRailHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingL,
                  ),
                  itemCount: cities.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(
                      right: AppConstants.spacingM,
                    ),
                    child: ScaleTap(
                      onTap: () => _openCity(context, cities[i]),
                      child: _TrendingCityCard(city: cities[i]),
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

class _TrendingCityCard extends StatelessWidget {
  const _TrendingCityCard({required this.city});

  final TrendingCity city;

  @override
  Widget build(BuildContext context) {
    final growth = city.growthPercentage;

    return Container(
      width: _kCityCardWidth,
      height: _kCityRailHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (city.featuredImageUrl != null)
            Builder(
              builder: (context) {
                // Bounds decoding to the card's actual rendered pixels
                // rather than the source's native resolution.
                final dpr = MediaQuery.of(context).devicePixelRatio;
                return CachedNetworkImage(
                  imageUrl: city.featuredImageUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: (_kCityCardWidth * dpr).round(),
                  memCacheHeight: (_kCityRailHeight * dpr).round(),
                  placeholder: (_, _) =>
                      Container(color: AppColors.primaryLight),
                  errorWidget: (_, _, _) =>
                      Container(color: AppColors.primaryLight),
                );
              },
            )
          else
            Container(color: AppColors.primaryLight),

          // Bottom-weighted scrim so the label stays legible over any photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xB3000000)],
                stops: [0.4, 1.0],
              ),
            ),
          ),

          if (growth != null && growth > 0)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(AppConstants.pillRadius),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.trending_up_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '+${growth.toStringAsFixed(0)}%',
                      style: AppTextStyles.chip.copyWith(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  city.cityName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading3.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
                if (city.totalProperties != null && city.totalProperties! > 0)
                  Text(
                    '${city.totalProperties} properties',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10.5,
                    ),
                  )
                else if (city.avgPropertyPrice != null)
                  Text(
                    'Avg ${PropertyModel.formatIndianPrice(city.avgPropertyPrice)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
