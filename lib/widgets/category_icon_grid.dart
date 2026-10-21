import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/navigation/banner_destination_resolver.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/glass_card.dart';
import '../core/widgets/scale_tap.dart';
import '../models/banner_destination.dart';
import '../providers/filter_provider.dart';
import '../services/property_service.dart';
import 'section_header.dart';

class CategoryItem {
  final String label;

  /// Category-specific illustration, copied verbatim from the portal's own
  /// `src/assets/categoriesicons/*.webp` (`PropertyCategories.tsx`'s
  /// `categoryIconConfig`) into `assets/categoriesicons/` — same art, same
  /// files, not a Flutter-only redraw.
  final String imageAsset;

  /// Accent used for the live-count badge's border/text — sampled to match
  /// each image's own dominant colour so the badge reads as part of the
  /// same illustration rather than an unrelated flat tint.
  final Color accentColor;

  /// Where tapping this shortcut goes. A `collection` is just a pre-applied
  /// set of filter fields, which is exactly what a category shortcut is.
  /// Null for the four role/project tiles below, which use [routeName]
  /// instead — a plain named-route push, no filter state involved.
  final BannerDestination? destination;

  /// Named route for the four role/project tiles (Verified Brokers,
  /// Builders, Influencers, Premium Projects) — their "browse all" screen,
  /// mirroring the portal's `/brokers` / `/builders` / `/influencers` /
  /// `/latest-projects` (`PropertyCategories.tsx`'s `handleCardClick`).
  /// Null for the five property tiles above, which use [destination]
  /// instead.
  final String? routeName;

  /// Key into [_CategoryIconGridState._counts]'s result map, for the live
  /// count badge.
  final String countKey;

  const CategoryItem({
    required this.label,
    required this.imageAsset,
    required this.accentColor,
    required this.countKey,
    this.destination,
    this.routeName,
  }) : assert(
         (destination == null) != (routeName == null),
         'exactly one of destination/routeName must be set',
       );
}

/// Home's "Popular Categories" — mirrors the portal's `PropertyCategories.tsx`
/// in full: all nine tiles (Land, Residential, Commercial, Rent, For Sale,
/// Verified Brokers, Builders, Influencers, Premium Projects), each with a
/// live count badge.
///
/// WHAT EACH TILE FILTERS BY
/// --------------------------
/// Taken from the portal's own `PropertyCategories.handleCardClick`
/// (`PropertyCategories.tsx:42-66`): **Rent and For Sale set a listing type,
/// never a category**, while Land / Residential / Commercial set a category
/// and leave the listing type open.
///
/// Values are the wire values `FilterProvider` validates against
/// (`validCategories` / `validListingTypes`) — a display label passed to
/// `setCategory` is silently coerced to null, which would quietly return
/// unfiltered results.
///
/// The remaining four tiles (Verified Brokers, Builders, Influencers,
/// Premium Projects) navigate to this app's own "browse all of this
/// role/type" screens (`RoleDirectoryScreen`, `LatestProjectsScreen`),
/// mirroring the portal's dedicated `/brokers`, `/builders`, `/influencers`,
/// `/latest-projects` pages.
class CategoryIconGrid extends StatefulWidget {
  const CategoryIconGrid({super.key, this.service, this.onPhoto = false});

  /// Renders for a dark/photo background: clear glass tiles, white title and
  /// labels. Defaults to the regular light-background look.
  final bool onPhoto;

  @visibleForTesting
  final PropertyService? service;

  static const String _assetBase = 'assets/categoriesicons';

  static const List<CategoryItem> categories = [
    CategoryItem(
      label: 'Land',
      imageAsset: '$_assetBase/land.webp',
      accentColor: Color(0xFF22C55E),
      destination: BannerDestination.collection(category: 'land'),
      countKey: 'land',
    ),
    CategoryItem(
      label: 'Residential',
      imageAsset: '$_assetBase/residential.webp',
      accentColor: Color(0xFF2563EB),
      destination: BannerDestination.collection(category: 'residential'),
      countKey: 'residential',
    ),
    CategoryItem(
      label: 'Commercial',
      imageAsset: '$_assetBase/commercial.webp',
      accentColor: Color(0xFF475569),
      destination: BannerDestination.collection(category: 'commercial'),
      countKey: 'commercial',
    ),
    CategoryItem(
      label: 'Rent',
      imageAsset: '$_assetBase/rent.webp',
      accentColor: Color(0xFF14B8A6),
      destination: BannerDestination.collection(listingType: 'rent'),
      countKey: 'rent',
    ),
    CategoryItem(
      label: 'For Sale',
      imageAsset: '$_assetBase/sale.webp',
      accentColor: Color(0xFF92722A),
      destination: BannerDestination.collection(listingType: 'sell'),
      countKey: 'sell',
    ),
    CategoryItem(
      label: 'Verified Brokers',
      imageAsset: '$_assetBase/brokerverified.webp',
      accentColor: Color(0xFF1E3A8A),
      routeName: AppConstants.brokersDirectoryScreen,
      countKey: 'brokers',
    ),
    CategoryItem(
      label: 'Builders',
      imageAsset: '$_assetBase/builder.webp',
      accentColor: Color(0xFFD97706),
      routeName: AppConstants.buildersDirectoryScreen,
      countKey: 'builders',
    ),
    CategoryItem(
      label: 'Influencers',
      imageAsset: '$_assetBase/influencer.webp',
      accentColor: Color(0xFFDB2777),
      routeName: AppConstants.influencersDirectoryScreen,
      countKey: 'influencers',
    ),
    CategoryItem(
      label: 'Premium Projects',
      imageAsset: '$_assetBase/premiumproject.webp',
      accentColor: Color(0xFFB8860B),
      routeName: AppConstants.latestProjectsScreen,
      countKey: 'projects',
    ),
  ];

  @override
  State<CategoryIconGrid> createState() => _CategoryIconGridState();
}

class _CategoryIconGridState extends State<CategoryIconGrid>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_counts` (and the Future it's already resolved to) across
  // Home's own scroll — without this, `CategoryIconGrid` is disposed and a
  // fresh instance rebuilt (with a brand-new, re-fetching `_counts` Future)
  // any time it scrolls far enough off/on screen, since it sits inside a
  // `SliverList`.
  @override
  bool get wantKeepAlive => true;

  /// Height of the illustration zone inside each card.
  static const double _kTileImageHeight = 92.0;

  /// Gap between adjacent cards, and the horizontal page padding either
  /// side of the rail — shared by the width computation below and the
  /// `ListView`'s own padding/gap so the maths and the actual layout never
  /// drift apart.
  static const double _kTileGap = 14.0;
  static const double _kRailPadding = 16.0;

  /// How many cards the row is sized to fill edge-to-edge.
  static const int _kTilesPerRow = 4;

  /// Sliver of the next card deliberately left peeking in from the right —
  /// an intentional "there's more" affordance (this app has nine real
  /// categories; none are ever hidden to force a tidy row) rather than an
  /// ambiguous mid-cut card or an invisible-until-you-try-scrolling row.
  static const double _kNextCardPeek = 14.0;

  /// Sizes the first [_kTilesPerRow] cards to fill (almost) exactly one
  /// viewport width, so the row reads as intentionally full on any screen
  /// size, while every one of the app's nine tiles stays reachable by
  /// scrolling — never deletes any of them just to make the row look tidy.
  double _tileWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final usableWidth = screenWidth - _kRailPadding * 2 - _kNextCardPeek;
    final width =
        (usableWidth - _kTileGap * (_kTilesPerRow - 1)) / _kTilesPerRow;
    // Clamped so a very narrow or very wide phone still gets a sane card
    // rather than something illegibly small or a stretched illustration.
    return width.clamp(92.0, 132.0);
  }

  late final Future<Map<String, int>> _counts = _loadCounts();

  /// Merges [PropertyService.getCategoryCounts] (land/residential/
  /// commercial/rent/sell) with counts for the four role/project tiles,
  /// queried here directly rather than adding to that service — mirrors the
  /// portal's own `countProfiles`/`countProjects` queries
  /// (`PropertyCategories.tsx`) against the same `profiles`/
  /// `builder_projects` tables every other role rail on this app already
  /// reads (`PeopleSearchService.listPopularAgents`,
  /// `ProjectService.listLatestActive`).
  Future<Map<String, int>> _loadCounts() async {
    final propertyCounts = await (widget.service ?? PropertyService())
        .getCategoryCounts();

    Future<int> countProfiles(String userType) async {
      try {
        final response = await Supabase.instance.client
            .from('profiles')
            .select('user_id')
            .eq('user_type', userType)
            .eq('approval_status', 'approved')
            .not('is_blocked', 'is', true)
            .limit(1)
            .count(CountOption.exact);
        return response.count;
      } catch (_) {
        return 0;
      }
    }

    Future<int> countProjects() async {
      try {
        final response = await Supabase.instance.client
            .from('builder_projects')
            .select('id')
            .eq('status', 'active')
            .eq('approval_status', 'approved')
            .limit(1)
            .count(CountOption.exact);
        return response.count;
      } catch (_) {
        return 0;
      }
    }

    final extra = await Future.wait([
      countProfiles('broker'),
      countProfiles('builder'),
      countProfiles('influencer'),
      countProjects(),
    ]);

    return {
      ...propertyCounts,
      'brokers': extra[0],
      'builders': extra[1],
      'influencers': extra[2],
      'projects': extra[3],
    };
  }

  /// A shortcut is a fresh entry point, so it starts from a clean filter set.
  ///
  /// `BannerDestinationResolver` only *sets* the fields its destination
  /// carries; without the reset, tapping Commercial and then Residential
  /// would leave `category: commercial` behind. The portal gets this for
  /// free — each shortcut navigates to a fresh `/search?...` URL — so the
  /// reset is what matches its behaviour.
  void _open(BuildContext context, CategoryItem category) {
    final routeName = category.routeName;
    if (routeName != null) {
      Navigator.pushNamed(context, routeName);
      return;
    }
    context.read<FilterProvider>().resetFilters();
    BannerDestinationResolver.navigate(context, category.destination!);
  }

  /// One category card — extracted from `build()` so the eagerly-built
  /// `ListView(children: [...])` above can construct all nine via a plain
  /// collection-`for`, rather than needing a `.builder`'s lazy `itemBuilder`
  /// callback shape.
  Widget _buildCategoryCard(
    BuildContext context,
    CategoryItem category,
    int? count,
    double tileWidth,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: _kTileGap),
      child: ScaleTap(
        onTap: () => _open(context, category),
        scaleDown: 0.97,
        child: GlassCard(
          width: tileWidth,
          borderRadius: 20,
          padding: EdgeInsets.zero,
          // Frosted glass tile. On light backgrounds 0.62 keeps each
          // illustration's baked-in white canvas from showing a seam; on the
          // Home photo the tile is clear glass and the artwork reads as an
          // inset card.
          opacity: widget.onPhoto ? 0.22 : 0.62,
          blurSigma: 10,
          borderColor: widget.onPhoto
              ? Colors.white.withOpacity(0.55)
              : AppColors.glassBorder,
          highlight: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                    child: Image.asset(
                      category.imageAsset,
                      height: _kTileImageHeight,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (count != null && count > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(
                            AppConstants.pillRadius,
                          ),
                          border: Border.all(
                            color: category.accentColor,
                            width: 1,
                          ),
                          boxShadow: AppColors.surfaceCardShadow,
                        ),
                        child: Text(
                          count > 999 ? '999+' : '$count',
                          style: AppTextStyles.chip.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: category.accentColor,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
                child: Text(
                  category.label,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: widget.onPhoto ? Colors.white : AppColors.textPrimary,
                  ),
                  // Was `maxLines: 2` — a label that happened to wrap (e.g.
                  // "Commercial" on a narrow tile) made that one card taller
                  // than its single-line siblings, which is exactly the
                  // "cards aren't visually consistent" symptom. Capped to one
                  // line so every tile's height is identical regardless of
                  // label length.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const categories = CategoryIconGrid.categories;
    final tileWidth = _tileWidth(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Popular Categories',
          titleColor: widget.onPhoto ? Colors.white : null,
        ),
        FutureBuilder<Map<String, int>>(
          future: _counts,
          builder: (context, snapshot) {
            final counts = snapshot.data ?? const <String, int>{};

            return SizedBox(
              // Illustration zone + label footer, inside a proper card.
              height: _kTileImageHeight + 62,
              child: Stack(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    // A `Row` inside a plain `SingleChildScrollView`, not a
                    // `ListView` — even `ListView(children: [...])` (not
                    // just `.builder`) still virtualises via a sliver
                    // underneath, so it only mounts the cards currently
                    // within the viewport/cache area, not every card that
                    // exists. A `Row` has no such concept: with only nine
                    // small cards total, there is no meaningful cost to
                    // every one of them genuinely existing in the tree from
                    // the first frame — which is also what a real swipe (or
                    // a test's `ensureVisible`) needs to reach any of them.
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kRailPadding,
                    ),
                    child: Row(
                      children: [
                        for (final category in categories)
                          _buildCategoryCard(
                            context,
                            category,
                            counts[category.countKey],
                            tileWidth,
                          ),
                      ],
                    ),
                  ),
                  // A subtle fade at the trailing edge hints that the rail
                  // continues past the visible cards, without hiding the
                  // deliberate next-card peek computed by [_tileWidth] or
                  // removing any of the nine real categories.
                  if (!widget.onPhoto)
                    const Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 32,
                    child: IgnorePointer(child: _CategoryRailFadeEdge()),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Right-edge fade mask for [CategoryIconGrid]'s horizontal rail — matches
/// the page's own [AppColors.background] so it reads as the page fading the
/// content out rather than a hard-edged overlay.
class _CategoryRailFadeEdge extends StatelessWidget {
  const _CategoryRailFadeEdge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.background.withOpacity(0),
            AppColors.background.withOpacity(0.9),
          ],
        ),
      ),
    );
  }
}
