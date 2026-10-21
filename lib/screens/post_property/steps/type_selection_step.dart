import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/post_property_provider.dart';
import '../portal_theme.dart';

/// Step 1 — reproduction of the portal's `TypeSelectionStep.tsx`.
///
/// PROPERTY TYPE cards are full-bleed photo "hero" cards — a real category
/// photo filling the card, a bottom scrim for legibility, a white icon
/// badge top-left, the title/description over the scrim, and a white arrow
/// button bottom-right — matching the exact card composition the design
/// reference for this step uses. LISTING TYPE stays a compact row list (the
/// reference keeps that group as rows, not photo cards), each row now
/// carrying a small colour-coded icon badge next to its text in addition
/// to the existing thumbnail, matching that reference too.
///
/// Width stays fully responsive — computed from whatever the column gives
/// it, never hardcoded — and every card was checked against
/// `post_property_shell_layout_test.dart`'s no-overflow assertions at
/// 320–1920 dp before landing.
class TypeSelectionStep extends StatelessWidget {
  const TypeSelectionStep({super.key});

  /// Verbatim category set/order from `propertyTypes`
  /// (TypeSelectionStep.tsx:123-129) — Land first, not Residential.
  /// `photoUrl` is a real category photo (not the portal's flat SVG
  /// illustration) so the card can be a full-bleed photo hero rather than
  /// an icon-on-a-pastel-square, matching the reference design for this
  /// step; `badgeIcon`/`badgeColor` drive the small icon badge overlaid on
  /// that photo.
  static const List<_TypeCard> _propertyTypes = [
    _TypeCard(
      title: 'Land / Plot',
      description: 'Plots, Agricultural land, etc.',
      category: PropertyCategory.land,
      photoUrl:
          'https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=640&q=70',
      badgeIcon: Icons.location_on_rounded,
      badgeColor: Color(0xFFE5484D),
    ),
    _TypeCard(
      title: 'Residential',
      description: 'Houses, Apartments, Villas, etc.',
      category: PropertyCategory.residential,
      photoUrl:
          'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=640&q=70',
      badgeIcon: Icons.home_rounded,
      badgeColor: Color(0xFFEE7B4F),
    ),
    _TypeCard(
      title: 'Commercial',
      description: 'Offices, Shops, Showrooms, etc.',
      category: PropertyCategory.commercial,
      photoUrl:
          'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=640&q=70',
      badgeIcon: Icons.apartment_rounded,
      badgeColor: Color(0xFF4A82E8),
    ),
    _TypeCard(
      title: 'PG / Co-living',
      description: 'PG, Hostels, Co-living spaces, etc.',
      category: PropertyCategory.pg,
      photoUrl:
          'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=640&q=70',
      badgeIcon: Icons.chair_rounded,
      badgeColor: Color(0xFF8B6FD6),
    ),
    _TypeCard(
      title: 'Others',
      description: 'Other property types, etc.',
      category: PropertyCategory.other,
      photoUrl:
          'https://images.unsplash.com/photo-1553413077-190dd305871c?w=640&q=70',
      badgeIcon: Icons.grid_view_rounded,
      badgeColor: Color(0xFFE8A93B),
    ),
  ];

  /// Verbatim from `getAvailableListingTypes()` — Rent first, then For Sale,
  /// then Lease. `imageAsset` mirrors `listingTypeSVG`'s id→file switch
  /// (TypeSelectionStep.tsx:40-45) — the portal's internal id is `sell`,
  /// matching [ListingIntent.sell] and `sell.png`. `badgeIcon`/`badgeColor`
  /// add the small icon badge the reference shows next to each row's text.
  static const List<_IntentCard> _listingTypes = [
    _IntentCard(
      title: 'Rent',
      description: 'Monthly rental properties',
      imageAsset: 'assets/formicons/rent.png',
      intent: ListingIntent.rent,
      badgeIcon: Icons.home_rounded,
      badgeColor: Color(0xFF7C6FF7),
    ),
    _IntentCard(
      title: 'For Sale',
      description: 'Properties for sale',
      imageAsset: 'assets/formicons/sell.png',
      intent: ListingIntent.sell,
      badgeIcon: Icons.home_rounded,
      badgeColor: Color(0xFF4CAF7D),
    ),
    _IntentCard(
      title: 'Lease',
      description: 'Long-term lease properties',
      imageAsset: 'assets/formicons/lease.png',
      intent: ListingIntent.lease,
      badgeIcon: Icons.description_rounded,
      badgeColor: Color(0xFF4A82E8),
    ),
  ];

  /// Matches the portal's `title={isEdit ? '...cannot be changed while
  /// editing' : undefined}` — a tooltip has no mobile touch equivalent, so
  /// this surfaces the same explanation as a snackbar on a locked tap.
  void _showLockedMessage(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what cannot be changed while editing.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    // Matches the portal's `isEdit` lock (TypeSelectionStep.tsx) — every
    // later step's field set depends on category/intent, so both are frozen
    // once a listing already exists.
    final bool isEdit = provider.isEditMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PortalStepHeading(
          title: 'What are you listing?',
          subtitle: 'Choose a property category and how you want to list it.',
        ),

        // ── Property Type ──────────────────────────────────────────────
        const PortalGroupLabel('Property Type'),
        // One full-bleed photo card per row. Width is whatever the column
        // gives it (no hardcoded dp), so this stays correct at any phone
        // size.
        for (int i = 0; i < _propertyTypes.length; i++) ...[
          if (i > 0) const SizedBox(height: PortalTheme.gapMd),
          _PropertyTypeCard(
            data: _propertyTypes[i],
            selected: provider.category == _propertyTypes[i].category,
            locked: isEdit,
            onTap: isEdit
                ? () => _showLockedMessage(context, 'Property type')
                : () => context.read<PostPropertyProvider>().setCategory(
                    _propertyTypes[i].category,
                  ),
          ),
        ],
        const SizedBox(height: 14),

        // ── Listing Type ───────────────────────────────────────────────
        const PortalGroupLabel('Listing Type'),
        // `grid-cols-1` at mobile — one per row, matching the portal.
        for (int i = 0; i < _listingTypes.length; i++) ...[
          if (i > 0) const SizedBox(height: PortalTheme.gapMd),
          _ListingTypeCard(
            data: _listingTypes[i],
            selected: provider.listingIntent == _listingTypes[i].intent,
            locked: isEdit,
            onTap: isEdit
                ? () => _showLockedMessage(context, 'Listing type')
                : () => context.read<PostPropertyProvider>().setListingIntent(
                    _listingTypes[i].intent,
                  ),
          ),
        ],
      ],
    );
  }
}

class _TypeCard {
  const _TypeCard({
    required this.title,
    required this.description,
    required this.category,
    required this.photoUrl,
    required this.badgeIcon,
    required this.badgeColor,
  });

  final String title;
  final String description;
  final PropertyCategory category;

  /// The card's full-bleed background photo.
  final String photoUrl;

  /// The small icon badge overlaid top-left on the photo, and the
  /// selected-state accent (border glow, arrow tint, check badge).
  final IconData badgeIcon;
  final Color badgeColor;
}

class _IntentCard {
  const _IntentCard({
    required this.title,
    required this.description,
    required this.imageAsset,
    required this.intent,
    required this.badgeIcon,
    required this.badgeColor,
  });

  final String title;
  final String description;
  final String imageAsset;
  final ListingIntent intent;
  final IconData badgeIcon;
  final Color badgeColor;
}

/// Card artwork for the listing-type thumbnail: the portal's own
/// illustration, full-bleed — `BoxFit.cover` filling the box exactly like
/// the portal's `objectFit: 'cover'`. `assets/formicons/*.png` are the
/// portal's own illustrations (same art family, same filenames).
class _CategoryImageArt extends StatelessWidget {
  const _CategoryImageArt({required this.imageAsset});

  final String imageAsset;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      imageAsset,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
    );
  }
}

/// Property-type card — a full-bleed real photo, a bottom scrim for
/// legibility, a white icon badge top-left, title/description sitting on
/// the scrim, and a white circular arrow button bottom-right. Matches the
/// reference design's photo-hero card composition directly, replacing the
/// previous icon-chip-on-a-pastel-row layout.
class _PropertyTypeCard extends StatelessWidget {
  const _PropertyTypeCard({
    required this.data,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final _TypeCard data;
  final bool selected;
  final VoidCallback onTap;

  /// Edit mode — matches the portal's `lockedStyle`: the selected card stays
  /// at full opacity, every other card dims to signal it can't be chosen.
  final bool locked;

  static const double _kCardHeight = 128;
  static const double _kBadgeSize = 36;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked && !selected ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          height: _kCardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? data.badgeColor : Colors.transparent,
              width: 3,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: data.badgeColor.withOpacity(0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : PortalTheme.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: data.photoUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: data.badgeColor.withOpacity(0.12)),
                  errorWidget: (context, url, error) =>
                      Container(color: data.badgeColor.withOpacity(0.12)),
                ),
                // Bottom scrim so the white title/description stay legible
                // over whatever the photo's own brightness happens to be.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.35, 1.0],
                    ),
                  ),
                ),
                // Icon badge, top-left.
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    width: _kBadgeSize,
                    height: _kBadgeSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      data.badgeIcon,
                      color: data.badgeColor,
                      size: 19,
                    ),
                  ),
                ),
                // Title + description, bottom-left, over the scrim.
                Positioned(
                  left: 14,
                  right: 58,
                  bottom: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PortalTheme.cardTitle(false).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PortalTheme.cardDescription.copyWith(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow button, bottom-right.
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    width: _kBadgeSize,
                    height: _kBadgeSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: data.badgeColor,
                      size: 18,
                    ),
                  ),
                ),
                // Selected check badge, top-right.
                if (selected)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: PortalCheckBadge(selected: true),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Listing-type row — a radio circle, a small colour-coded icon badge,
/// title/description, and a lifted illustration "sticker" chip trailing.
/// The icon badge is new versus the previous version: the reference shows
/// each row carrying its own small tinted icon next to the text, in
/// addition to the existing thumbnail — so both are shown here rather than
/// one replacing the other.
class _ListingTypeCard extends StatelessWidget {
  const _ListingTypeCard({
    required this.data,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final _IntentCard data;
  final bool selected;
  final VoidCallback onTap;

  /// Edit mode — matches the portal's `lockedStyle`: the selected card stays
  /// at full opacity, every other card dims to signal it can't be chosen.
  final bool locked;

  static const double _kCardMinHeight = 68;
  static const double _kImageBox = 48;
  static const double _kIconBadgeSize = 34;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked && !selected ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          // A floor, not an exact height — narrow phones that wrap the
          // description onto a third line still get the room they need
          // instead of being clipped.
          constraints: const BoxConstraints(minHeight: _kCardMinHeight),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? PortalTheme.accentSurface
                : PortalTheme.cardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? PortalTheme.accent : PortalTheme.cardBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: PortalTheme.accent.withOpacity(0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : PortalTheme.cardShadow,
          ),
          child: Row(
            children: [
              PortalCheckBadge(selected: selected),
              const SizedBox(width: 10),
              Container(
                width: _kIconBadgeSize,
                height: _kIconBadgeSize,
                decoration: BoxDecoration(
                  color: data.badgeColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.badgeIcon, color: data.badgeColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PortalTheme.cardTitle(selected),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PortalTheme.cardDescription.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedScale(
                scale: selected ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: _kImageBox,
                  height: _kImageBox,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: PortalTheme.accent.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : PortalTheme.cardShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Opacity(
                      opacity: selected ? 1.0 : 0.85,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _CategoryImageArt(imageAsset: data.imageAsset),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
