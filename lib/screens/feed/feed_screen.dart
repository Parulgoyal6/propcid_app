// screens/feed/feed_screen.dart
//
// The "Feed" destination reached from the Workspace Drawer / More sheet —
// previously a stub that pushed Home (see WorkspaceDestinations.feed). Mirrors
// the portal's CombinedFeed.tsx: a single bounded fetch across properties,
// builder_projects and influencer_videos, with a client-side Brokers/
// Builders/Influencers filter row. Built entirely from this app's existing
// theme tokens (AppColors/AppTextStyles/AppConstants) — no new visual system.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/feed_item.dart';
import '../../models/reel_model.dart';
import '../../core/constants/project_options.dart' show projectTypeLabel;
import '../../providers/auth_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/projects_provider.dart';
import '../../providers/property_provider.dart';
import '../../providers/reels_provider.dart';
import '../../widgets/post_comments_sheet.dart';
import '../project/widgets/share_project_sheet.dart';
import '../property_detail/property_media_viewer_screen.dart'
    show PropertyMediaViewerScreen, isVideoMediaUrl;
import '../property_detail/widgets/share_property_sheet.dart';
import '../reels/widgets/reel_action_button.dart';
import '../reels/widgets/share_reel_sheet.dart';
import '../search/widgets/property_card_facts.dart' show propertyPostedAgo;

/// `post_comments.post_type` for a Feed property card's comment thread —
/// mirrors the portal's `CombinedFeed.tsx` `CommentsPanel postType="property"`.
const String _kPropertyCommentPostType = 'property';

/// Same table, same post_type value the Reels screen already uses for this
/// exact `influencer_videos` row (`_kReelCommentPostType` in
/// `reels_screen.dart`) — a Feed video card opens the same comment thread,
/// not a new one.
const String _kVideoCommentPostType = 'video';

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FeedProvider()..load(context.read<AuthProvider>().userId),
      child: const _FeedView(),
    );
  }
}

class _FeedView extends StatelessWidget {
  const _FeedView();

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<FeedProvider>();
    // Existing session role (`profiles.user_type`) — the portal's own gate.
    final showExclusive = FeedRoleFilter.isExclusiveViewer(
      context.watch<AuthProvider>().userType,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Feed', style: AppTextStyles.heading2),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<FeedProvider>().load(
          context.read<AuthProvider>().userId,
        ),
        child: Column(
          children: [
            _FilterRow(
              selected: feed.filter,
              showExclusive: showExclusive,
              onSelected: (f) => context.read<FeedProvider>().setFilter(f),
            ),
            Expanded(
              child: feed.filter == FeedRoleFilter.exclusive && showExclusive
                  ? _ExclusiveOffersBody(feed: feed)
                  : _FeedBody(feed: feed),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final FeedRoleFilter selected;
  final bool showExclusive;
  final ValueChanged<FeedRoleFilter> onSelected;

  const _FilterRow({
    required this.selected,
    required this.showExclusive,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final roles = [
      for (final role in FeedRoleFilter.values)
        if (role != FeedRoleFilter.exclusive || showExclusive) role,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: AppConstants.spacingS,
      ),
      child: Row(
        children: [
          for (final role in roles) ...[
            if (role != roles.first)
              const SizedBox(width: AppConstants.spacingS),
            _FilterChip(
              role: role,
              isSelected: role == selected,
              onTap: () => onSelected(role),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final FeedRoleFilter role;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: role.label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.hairline,
            ),
          ),
          child: Text(
            role.label,
            style: AppTextStyles.chip.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? AppColors.cardBackground
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedBody extends StatelessWidget {
  final FeedProvider feed;

  const _FeedBody({required this.feed});

  @override
  Widget build(BuildContext context) {
    if (feed.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (feed.error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              feed.error!,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    final items = feed.visibleItems;
    if (items.isEmpty) {
      // Matches the portal's own copy for an empty feed.
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              'No content available',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingL,
        0,
        AppConstants.spacingL,
        AppConstants.spacingL,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => FeedItemCard(item: items[index]),
    );
  }
}

/// The broker/admin-only Exclusive tab — `builder_project_offers` via
/// `combined-feed-list` (portal parity), with the portal's own empty copy.
class _ExclusiveOffersBody extends StatelessWidget {
  final FeedProvider feed;

  const _ExclusiveOffersBody({required this.feed});

  Widget _message(String title, String body) => ListView(
    children: [
      const SizedBox(height: 80),
      Center(child: Text(title, style: AppTextStyles.heading3)),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          body,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (feed.offersLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (feed.offersError != null) {
      return _message(feed.offersError!, 'Pull down to try again.');
    }
    final offers = feed.offers;
    if (offers.isEmpty) {
      return _message(
        'No Exclusive Offers',
        'There are no exclusive project offers available at the moment. '
            'Check back soon!',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingL,
        0,
        AppConstants.spacingL,
        AppConstants.spacingL,
      ),
      itemCount: offers.length,
      itemBuilder: (context, index) => _FeedOfferCard(offer: offers[index]),
    );
  }
}

/// One exclusive offer — the portal `ProjectOfferCard`'s content (builder,
/// "Exclusive Broker Offer" badge, offer title, project + location, price
/// range, description) in this feed's existing card style. Tapping opens the
/// offer's project, like the other project cards.
class _FeedOfferCard extends StatelessWidget {
  final FeedOffer offer;

  const _FeedOfferCard({required this.offer});

  /// Same cover-photo selection as [FeedItemCard._coverUrl] — skip a
  /// leading video in `offer_media_urls`, which `CachedNetworkImage` can't
  /// decode and would otherwise render as the broken-image icon.
  String? _coverUrl(FeedOffer offer) {
    if (offer.mediaUrls.isEmpty) return offer.imageUrl;
    final photos = offer.mediaUrls.where((u) => !isVideoMediaUrl(u));
    return photos.isNotEmpty ? photos.first : offer.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final projectId = offer.projectId;
    final hasAvatar = offer.builderAvatarUrl?.isNotEmpty ?? false;
    final coverUrl = _coverUrl(offer);
    final projectLine = [
      if (offer.projectTitle.isNotEmpty) offer.projectTitle,
      if (offer.projectLocation.isNotEmpty) offer.projectLocation,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: projectId == null || projectId.isEmpty
            ? null
            : () => Navigator.pushNamed(
                context,
                AppConstants.projectDetailScreen,
                arguments: {'projectId': projectId},
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: hasAvatar
                        ? CachedNetworkImageProvider(offer.builderAvatarUrl!)
                        : null,
                    child: hasAvatar
                        ? null
                        : const Icon(
                            Icons.business,
                            size: 18,
                            color: AppColors.primary,
                          ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.builderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          [
                            'Builder',
                            propertyPostedAgo(offer.createdAt),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: AppTextStyles.caption.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(
                        AppConstants.chipRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Exclusive Broker Offer',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (coverUrl != null)
              GestureDetector(
                onTap: offer.mediaUrls.isEmpty
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PropertyMediaViewerScreen(media: offer.mediaUrls),
                        ),
                      ),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        Container(color: AppColors.background),
                    errorWidget: (_, _, _) =>
                        Container(color: AppColors.background),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    offer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading3.copyWith(fontSize: 14.5),
                  ),
                  if (projectLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            projectLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (offer.priceLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      offer.priceLabel!,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                  if (offer.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      offer.description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Feed's content card. Public so other screens (Property Detail's
/// Related Properties) can show the identical card.
class FeedItemCard extends StatelessWidget {
  final FeedItem item;

  const FeedItemCard({required this.item});

  void _open(BuildContext context) {
    switch (item.type) {
      case FeedItemType.property:
        Navigator.pushNamed(
          context,
          AppConstants.propertyDetailScreen,
          arguments: {'propertyId': item.id},
        );
        break;
      case FeedItemType.project:
        Navigator.pushNamed(
          context,
          AppConstants.projectDetailScreen,
          arguments: {'projectId': item.id},
        );
        break;
      case FeedItemType.video:
        // Portal CombinedFeed: a video card navigates into the reels player
        // (reelPath). Open the Reels screen on this reel — same call the
        // chat's reel preview uses — instead of playing it inline here.
        Navigator.pushNamed(
          context,
          AppConstants.reelsScreen,
          arguments: {'reelId': item.id},
        );
        break;
    }
  }

  /// Opens the full-screen gallery viewer on the card's photo tap. Falls
  /// back to [_open] when there's nothing to swipe through — a video item
  /// (whose single reel already has its own player, not a gallery) or a
  /// property/project with no `media_urls` at all.
  void _openMedia(BuildContext context) {
    if (item.mediaUrls.isEmpty) {
      _open(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyMediaViewerScreen(media: item.mediaUrls),
      ),
    );
  }

  /// The card's cover photo — the first *photo* in `media_urls`, skipping
  /// over a leading video (which `CachedNetworkImage` can't decode, so it
  /// silently rendered as the broken-image icon before this check existed).
  /// Falls back to [FeedItem.imageUrl] for item types (video) that don't
  /// populate [FeedItem.mediaUrls].
  String? get _coverUrl {
    if (item.mediaUrls.isEmpty) return item.imageUrl;
    final photos = item.mediaUrls.where((u) => !isVideoMediaUrl(u));
    return photos.isNotEmpty ? photos.first : item.imageUrl;
  }

  /// Opens the poster's own public profile — distinct from [_open], which
  /// opens the content itself. Uses `item.posterUserId` (the same id the
  /// feed already resolved the poster's profile fields from), never the
  /// signed-in viewer's id.
  void _openProfile(BuildContext context) {
    final userId = item.posterUserId;
    if (userId == null || userId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
  }

  String get _roleLabel {
    final type = item.posterUserType;
    if (type == null || type.isEmpty) return '';
    return type[0].toUpperCase() + type.substring(1);
  }

  /// "2 days ago" etc. — same relative-age formatting the Search results
  /// property card already uses ([propertyPostedAgo]), reused here rather
  /// than duplicated so both never drift.
  String get _postedAgo => propertyPostedAgo(item.createdAt);

  String get _metaLine => [
    if (_roleLabel.isNotEmpty) _roleLabel,
    if (_postedAgo.isNotEmpty) _postedAgo,
  ].join(' · ');

  String get _typeBadge => switch (item.type) {
    FeedItemType.property => 'Property',
    FeedItemType.project => 'Project',
    FeedItemType.video => 'Video',
  };

  /// The price shown over the photo: a property's price (with "/month" for
  /// rent) or a project's range. Videos have none.
  String get _photoPrice => switch (item.type) {
    FeedItemType.property =>
      item.propertyType == 'rent' ? '${item.subtitle} /month' : item.subtitle,
    FeedItemType.project => item.subtitle,
    FeedItemType.video => '',
  };

  IconData get _typeIcon => switch (item.type) {
    FeedItemType.property => Icons.home_work_rounded,
    FeedItemType.project => Icons.apartment_rounded,
    FeedItemType.video => Icons.play_circle_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final String? coverUrl = _coverUrl;
    final bool hasImage = coverUrl != null && coverUrl.isNotEmpty;
    final String photoPrice = _photoPrice;
    // The price rides on the photo when there is one; otherwise it stays in
    // the tags row, so it is never lost.
    final bool priceOnPhoto = hasImage && photoPrice.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM + 2),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── poster row ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _openProfile(context),
                      borderRadius: BorderRadius.circular(
                        AppConstants.cardRadius,
                      ),
                      child: Row(
                        children: [
                          // Brand-gradient ring around the avatar.
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.ctaGradient,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: CircleAvatar(
                                radius: 17,
                                backgroundColor: AppColors.primaryLight,
                                backgroundImage:
                                    (item.posterAvatarUrl?.isNotEmpty ?? false)
                                    ? CachedNetworkImageProvider(
                                        item.posterAvatarUrl!,
                                      )
                                    : null,
                                child:
                                    (item.posterAvatarUrl?.isNotEmpty ?? false)
                                    ? null
                                    : const Icon(
                                        Icons.person,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.posterName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_metaLine.isNotEmpty)
                                  Text(
                                    _metaLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.16),
                          AppColors.primary.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        AppConstants.chipRadius,
                      ),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_typeIcon, size: 12, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          _typeBadge,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── photo: inset, rounded, with a bottom scrim, the price on a
            // glass pill, and the photo-count badge ──────────────────────
            if (hasImage)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: GestureDetector(
                      onTap: () => _openMedia(context),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: AppColors.background),
                            errorWidget: (_, _, _) =>
                                Container(color: AppColors.background),
                          ),
                          // Bottom scrim so the pills stay readable on any photo.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 90,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.55),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (item.type == FeedItemType.video)
                            Center(
                              child: Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.35),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if (item.photoCount > 0)
                            Positioned(
                              left: AppConstants.spacingS,
                              bottom: AppConstants.spacingS,
                              child: _PhotoCountBadge(count: item.photoCount),
                            ),
                          if (priceOnPhoto)
                            Positioned(
                              right: AppConstants.spacingS,
                              bottom: AppConstants.spacingS,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: AppColors.ctaGradient,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66F97316),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  photoPrice,
                                  maxLines: 1,
                                  style: AppTextStyles.price.copyWith(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // ── title, tags, location ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading3.copyWith(fontSize: 15.5),
                  ),
                  const SizedBox(height: 8),
                  switch (item.type) {
                    FeedItemType.property => _FeedPropertyTagsRow(
                      item: item,
                      showPrice: !priceOnPhoto,
                    ),
                    FeedItemType.project => _FeedProjectTagsRow(
                      item: item,
                      showPrice: !priceOnPhoto,
                    ),
                    FeedItemType.video => Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  },
                  if (item.location.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: 11,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // ── action strip: Like / Save / Comment / Share, in a tinted
            // rounded bar. Same per-type actions as before. ──────────────
            Container(
              margin: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: switch (item.type) {
                FeedItemType.property => _PropertyFeedActions(item: item),
                FeedItemType.project => _ProjectFeedActions(item: item),
                FeedItemType.video => _VideoFeedActions(item: item),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The image's photo-count badge — same look as the Search results property
/// card's (`PropertyCardSearchRow._buildPhotoCountBadge`), reproduced here
/// rather than imported since that one is private to its own file.
class _PhotoCountBadge extends StatelessWidget {
  const _PhotoCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.camera_alt_rounded, size: 11, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Category + listing-type chips beside the price — a property feed item's
/// version of the Search results property card's tags/price row
/// (`PropertyCardSearchRow._buildTagsAndPriceRow`), same categories, same
/// labels, same "/month" rent suffix.
class _FeedPropertyTagsRow extends StatelessWidget {
  const _FeedPropertyTagsRow({required this.item, this.showPrice = true});

  final FeedItem item;

  /// False when the price is already shown on the card's photo.
  final bool showPrice;

  String _priceWithSuffix() =>
      item.propertyType == 'rent' ? '${item.subtitle} /month' : item.subtitle;

  (IconData, String)? _categoryChip() {
    switch (item.category) {
      case 'residential':
        return (Icons.home_rounded, 'Residential');
      case 'commercial':
        return (Icons.store_mall_directory_rounded, 'Commercial');
      case 'land':
        return (Icons.landscape_rounded, 'Land');
      case 'pg_coliving':
        return (Icons.groups_rounded, 'PG/Co-living');
      case 'others':
        return (Icons.category_rounded, 'Others');
      default:
        return null;
    }
  }

  String? _listingLabel() {
    switch (item.propertyType) {
      case 'sell':
        return 'For Sale';
      case 'rent':
        return 'For Rent';
      case 'lease':
        return 'For Lease';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _categoryChip();
    final listingLabel = _listingLabel();

    return Row(
      children: [
        Flexible(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (category != null)
                _chip(icon: category.$1, label: category.$2),
              if (listingLabel != null)
                _chip(
                  icon: Icons.sell_rounded,
                  label: listingLabel,
                  isListingType: true,
                ),
            ],
          ),
        ),
        if (showPrice) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _priceWithSuffix(),
              style: AppTextStyles.price.copyWith(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    bool isListingType = false,
  }) {
    final Color bg = isListingType
        ? const Color(0xFFFCE4EC)
        : AppColors.primaryLight;
    final Color fg = isListingType
        ? const Color(0xFFD6336C)
        : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        border: isListingType
            ? null
            : Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.5, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTextStyles.chip.copyWith(
              fontSize: 10,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A project's equivalent of [_FeedPropertyTagsRow] — a project-type chip
/// (`builder_projects.project_type`, the same value `ProjectModel.typeLabel`
/// already formats via the shared [projectTypeLabel]) plus its price range
/// (`price_range_min`/`price_range_max`, already parsed into [FeedItem.
/// subtitle] by `FeedItem.fromProject`). Either half is omitted, not shown
/// blank/zero, when that data is genuinely absent for a given project.
class _FeedProjectTagsRow extends StatelessWidget {
  const _FeedProjectTagsRow({required this.item, this.showPrice = true});

  final FeedItem item;

  /// False when the price range is already shown on the card's photo.
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final typeLabel = projectTypeLabel(item.projectType);
    final hasType = typeLabel.isNotEmpty;
    final hasPrice = showPrice && item.subtitle.isNotEmpty;

    if (!hasType && !hasPrice) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasType)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppConstants.chipRadius),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.apartment_rounded,
                    size: 10.5,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.chip.copyWith(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (hasType && hasPrice) const SizedBox(width: 6),
        if (hasPrice)
          Expanded(
            child: Text(
              item.subtitle,
              style: AppTextStyles.price.copyWith(fontSize: 15),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Property card action row — Like / Save / Comment / Share, matching the
// portal's CombinedFeed.tsx PropertyCard exactly (same order, same targets):
//   Like    -> user_likes, via the existing PropertyProvider.toggleLike/isLiked
//   Save    -> saved_properties, via PropertyProvider.toggleShortlist/isShortlisted
//   Comment -> post_comments (post_type='property'), via the existing CommentService
//   Share   -> the app's own property share link (profile_link.dart)
// Every backend call here already existed and is already used elsewhere in the
// app (Home rails use the same toggleLike/toggleShortlist; Reels uses the same
// CommentService); this only wires the same existing calls into the Feed card.
// ─────────────────────────────────────────────────────────────────────────────
class _PropertyFeedActions extends StatelessWidget {
  const _PropertyFeedActions({required this.item});

  final FeedItem item;

  void _signInRequired(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in required')));
  }

  Future<void> _like(BuildContext context, PropertyProvider properties) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await properties.toggleLike(item.id);
  }

  Future<void> _save(BuildContext context, PropertyProvider properties) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await properties.toggleShortlist(item.id);
  }

  Future<void> _share(BuildContext context) async {
    try {
      // The same share sheet as Property Detail/Search — native share,
      // "Send to a user" (signed in), socials, copy link (portal
      // ShareToSocial parity) — instead of the bare system share.
      showSharePropertySheet(
        context,
        propertyId: item.id,
        title: item.title,
        location: item.location,
        priceDisplay: item.subtitle,
        currentUserId: context.read<AuthProvider>().userId,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share sheet')),
        );
      }
    }
  }

  void _openComments(BuildContext context) {
    showPostCommentsSheet(
      context,
      postId: item.id,
      postType: _kPropertyCommentPostType,
    );
  }

  static String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final properties = context.watch<PropertyProvider>();
    final liked = properties.isLiked(item.id);
    final saved = properties.isShortlisted(item.id);

    return Row(
      children: [
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.error,
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          isActive: liked,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.likes),
          onTap: () => _like(context, properties),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.primary,
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          isActive: saved,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Save',
          onTap: () => _save(context, properties),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.mode_comment_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.comments),
          onTap: () => _openComments(context),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.share_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Share',
          onTap: () => _share(context),
        ),
        const Spacer(),
        const Icon(
          Icons.visibility_outlined,
          size: 15,
          color: AppColors.textHint,
        ),
        const SizedBox(width: 4),
        Text('${item.views}', style: AppTextStyles.caption),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project card action row — Like / Save / Comment / Share, the same full
// treatment as [_PropertyFeedActions]:
//   Like    -> user_likes.project_id, via the existing ProjectsProvider.toggleLike/isLiked
//              (already used by project_detail_screen.dart)
//   Save    -> saved_projects, via ProjectsProvider.toggleSave/isSaved
//              (already used by project_detail_screen.dart)
//   Comment -> post_comments (post_type='project'), via the existing CommentService.
//              `post_comments.post_type` is a free-form column already storing
//              'property' and 'video' side by side (see _kVideoCommentPostType);
//              this adds 'project' as a third value on the same table/service,
//              not a new backend feature.
//   Share   -> the app's own project share link (profile_link.dart)
// ─────────────────────────────────────────────────────────────────────────────
const String _kProjectCommentPostType = 'project';

class _ProjectFeedActions extends StatelessWidget {
  const _ProjectFeedActions({required this.item});

  final FeedItem item;

  void _signInRequired(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in required')));
  }

  Future<void> _like(BuildContext context, ProjectsProvider projects) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await projects.toggleLike(item.id);
  }

  Future<void> _save(BuildContext context, ProjectsProvider projects) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await projects.toggleSave(item.id);
  }

  Future<void> _share(BuildContext context) async {
    try {
      // The same share sheet as Project Detail, incl. "Send to a user".
      showShareProjectSheet(
        context,
        projectId: item.id,
        title: item.title,
        location: item.location,
        currentUserId: context.read<AuthProvider>().userId,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share sheet')),
        );
      }
    }
  }

  void _openComments(BuildContext context) {
    showPostCommentsSheet(
      context,
      postId: item.id,
      postType: _kProjectCommentPostType,
    );
  }

  static String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectsProvider>();
    final liked = projects.isLiked(item.id);
    final saved = projects.isSaved(item.id);

    return Row(
      children: [
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.error,
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          isActive: liked,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.likes),
          onTap: () => _like(context, projects),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.primary,
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          isActive: saved,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Save',
          onTap: () => _save(context, projects),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.mode_comment_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.comments),
          onTap: () => _openComments(context),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.share_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Share',
          onTap: () => _share(context),
        ),
        const Spacer(),
        const Icon(
          Icons.visibility_outlined,
          size: 15,
          color: AppColors.textHint,
        ),
        const SizedBox(width: 4),
        Text('${item.views}', style: AppTextStyles.caption),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video card action row — Like / Save / Comment / Share, the full treatment,
// all four wired to the exact same tables/services the Reels screen already
// uses for this same `influencer_videos` row:
//   Like    -> user_likes.reel_id, via ReelsProvider.toggleLike/isLiked
//   Save    -> saved_reels, via ReelsProvider.toggleSave/isSaved
//   Comment -> post_comments (post_type='video'), via the existing CommentService
//   Share   -> this reel's own `/property-reels/:id` page, same link
//              ReelModel.shareUrl builds for the Reels screen.
// ─────────────────────────────────────────────────────────────────────────────
class _VideoFeedActions extends StatelessWidget {
  const _VideoFeedActions({required this.item});

  final FeedItem item;

  void _signInRequired(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in required')));
  }

  Future<void> _like(BuildContext context, ReelsProvider reels) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await reels.toggleLike(item.id);
  }

  Future<void> _save(BuildContext context, ReelsProvider reels) async {
    if (context.read<AuthProvider>().userId == null) {
      _signInRequired(context);
      return;
    }
    await reels.toggleSave(item.id);
  }

  Future<void> _share(BuildContext context) async {
    try {
      // The same share sheet as the Reels screen, incl. "Send to a user".
      // Uses the already-loaded reel when there is one (full share text),
      // else a minimal reel carrying this card's own id/title/video.
      final loaded = context
          .read<ReelsProvider>()
          .reels
          .where((r) => r.id == item.id)
          .firstOrNull;
      showShareReelSheet(
        context,
        reel:
            loaded ??
            ReelModel(
              id: item.id,
              title: item.title,
              description: '',
              videoUrl: item.videoUrl ?? '',
            ),
        currentUserId: context.read<AuthProvider>().userId,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share sheet')),
        );
      }
    }
  }

  void _openComments(BuildContext context) {
    showPostCommentsSheet(
      context,
      postId: item.id,
      postType: _kVideoCommentPostType,
    );
  }

  static String _count(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final reels = context.watch<ReelsProvider>();
    final liked = reels.isLiked(item.id);
    final saved = reels.isSaved(item.id);

    return Row(
      children: [
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.error,
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          isActive: liked,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.likes),
          onTap: () => _like(context, reels),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          activeColor: AppColors.primary,
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          isActive: saved,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Save',
          onTap: () => _save(context, reels),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.mode_comment_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: _count(item.comments),
          onTap: () => _openComments(context),
        ),
        const SizedBox(width: AppConstants.spacingM),
        ReelActionButton(
          axis: Axis.horizontal,
          showIconBackground: false,
          baseColor: AppColors.textHint,
          icon: Icons.share_outlined,
          iconSize: 16,
          iconBoxSize: 16,
          label: 'Share',
          onTap: () => _share(context),
        ),
        const Spacer(),
        const Icon(
          Icons.visibility_outlined,
          size: 15,
          color: AppColors.textHint,
        ),
        const SizedBox(width: 4),
        Text('${item.views}', style: AppTextStyles.caption),
      ],
    );
  }
}
