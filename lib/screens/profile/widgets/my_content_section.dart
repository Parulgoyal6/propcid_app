import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../core/widgets/frosted_glass.dart';
import '../../../models/article_summary.dart';
import '../../../models/influencer_video_model.dart';
import '../../../models/property_model.dart';
import '../../../providers/property_provider.dart';
import '../../../providers/reels_provider.dart';
import '../../dashboard/widgets/my_videos_section.dart'
    show InfluencerApprovalPill;

/// "My Content" — Properties / Articles tabs over the user's own listings
/// and article submissions (blueprint §4.1, §16.4), plus a Videos tab —
/// mirroring the portal's `ProfileDashboardShell.tsx` "My Content" block,
/// which shows a fourth "Videos" tab only for influencer accounts (`:4049`).
/// Video data is `InfluencerVideoService.listMine`'s existing
/// `influencer_videos` read (already used by the Manage Dashboard's
/// `MyVideosSection`) — no new query.
///
/// No "All" tab — removed on explicit request; the first tab (Properties)
/// is the default view instead.
///
/// Owns only the selected-tab index; all data is passed in from
/// `ProfileProvider`.
class MyContentSection extends StatefulWidget {
  final List<PropertyModel> properties;
  final List<ArticleSummary> articles;
  final List<InfluencerVideoModel> videos;

  /// Shows the "Videos" tab — only true for influencer accounts, mirroring
  /// the portal's `userType === "influencer"` gate.
  final bool showVideosTab;

  final bool isLoading;
  final bool hasFailed;
  final VoidCallback onRetry;
  final void Function(PropertyModel property) onPropertyTap;
  final void Function(ArticleSummary article) onArticleTap;
  final void Function(InfluencerVideoModel video) onVideoTap;
  final VoidCallback onAddProperty;
  final void Function(PropertyModel property) onEditProperty;
  final void Function(PropertyModel property) onDeleteProperty;
  final void Function(InfluencerVideoModel video) onEditVideo;
  final void Function(InfluencerVideoModel video) onDeleteVideo;
  final void Function(ArticleSummary article) onEditArticle;
  final void Function(ArticleSummary article) onDeleteArticle;

  const MyContentSection({
    super.key,
    required this.properties,
    required this.articles,
    this.videos = const [],
    this.showVideosTab = false,
    required this.isLoading,
    required this.hasFailed,
    required this.onRetry,
    required this.onPropertyTap,
    required this.onArticleTap,
    required this.onVideoTap,
    required this.onAddProperty,
    required this.onEditProperty,
    required this.onDeleteProperty,
    required this.onEditVideo,
    required this.onDeleteVideo,
    required this.onEditArticle,
    required this.onDeleteArticle,
  });

  @override
  State<MyContentSection> createState() => _MyContentSectionState();
}

class _MyContentSectionState extends State<MyContentSection> {
  int _selected = 0;

  List<String> get _tabs => widget.showVideosTab
      ? const ['Properties', 'Videos', 'Articles']
      : const ['Properties', 'Articles'];

  IconData _tabIcon(String label) => switch (label) {
    'Videos' => Icons.videocam_rounded,
    'Articles' => Icons.article_rounded,
    _ => Icons.apartment_rounded,
  };

  int _tabCount(String label) => switch (label) {
    'Videos' => widget.videos.length,
    'Articles' => widget.articles.length,
    _ => widget.properties.length,
  };

  /// Same glass segmented pill My Activity uses for Liked / Saved: a tinted
  /// track with a white hairline, and an orange-gradient glowing pill on the
  /// selected tab.
  Widget _buildTabPill() {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.7)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == _selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: i == _selected
                        ? BoxDecoration(
                            gradient: AppColors.ctaGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4DF97316),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          )
                        : const BoxDecoration(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _tabIcon(_tabs[i]),
                          size: 16,
                          color: i == _selected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${_tabs[i]} (${_tabCount(_tabs[i])})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 13,
                              fontWeight: i == _selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == _selected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same frosted-glass container as My Activity, so the two sections read as
    // one design.
    return FrostedGlass(
      borderRadius: 24,
      strong: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabPill(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingM,
              AppConstants.spacingM,
              AppConstants.spacingM,
              0,
            ),
            // `EmptyStateView` shrink-wraps to its widest child rather than
            // filling the available width, and this Column left-aligns
            // (`crossAxisAlignment.start`) - so a short empty-state message
            // rendered visibly left-aligned instead of centered. Forcing full
            // width lets `EmptyStateView` center every empty/failed state.
            child: SizedBox(width: double.infinity, child: _buildBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isLoading) return const _ContentShimmer();

    if (widget.hasFailed) {
      return EmptyStateView(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load your content",
        message: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: widget.onRetry,
      );
    }

    final selectedLabel = _tabs[_selected];
    final showProperties = selectedLabel == 'Properties';
    final showVideos = selectedLabel == 'Videos';
    final showArticles = selectedLabel == 'Articles';

    final properties = showProperties ? widget.properties : const [];
    final videos = showVideos ? widget.videos : const <InfluencerVideoModel>[];
    final articles = showArticles ? widget.articles : const <ArticleSummary>[];

    if (properties.isEmpty && videos.isEmpty && articles.isEmpty) {
      return _buildEmpty(selectedLabel);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final property in properties) ...[
          _MyPropertyCard(
            property: property,
            onTap: () => widget.onPropertyTap(property),
            onEdit: () => widget.onEditProperty(property),
            onDelete: () => widget.onDeleteProperty(property),
          ),
          const SizedBox(height: AppConstants.spacingM),
        ],
        for (final video in videos) ...[
          _VideoRow(
            video: video,
            onTap: () => widget.onVideoTap(video),
            onEdit: () => widget.onEditVideo(video),
            onDelete: () => widget.onDeleteVideo(video),
          ),
          const SizedBox(height: AppConstants.spacingM),
        ],
        for (final article in articles) ...[
          _ArticleRow(
            article: article,
            onTap: () => widget.onArticleTap(article),
            onEdit: () => widget.onEditArticle(article),
            onDelete: () => widget.onDeleteArticle(article),
          ),
          const SizedBox(height: AppConstants.spacingM),
        ],
      ],
    );
  }

  Widget _buildEmpty(String selectedLabel) {
    switch (selectedLabel) {
      case 'Properties':
        return EmptyStateView(
          icon: Icons.apartment_rounded,
          title: 'No properties yet',
          message: 'Your listings will appear here once you post one.',
          actionLabel: 'Add Property',
          onAction: widget.onAddProperty,
          iconCircleSize: 56,
          titleFontSize: 14.5,
        );
      case 'Videos':
        return const EmptyStateView(
          icon: Icons.videocam_outlined,
          title: 'No videos yet',
          message: 'Videos you upload will appear here.',
          iconCircleSize: 56,
          titleFontSize: 14.5,
        );
      case 'Articles':
        return const EmptyStateView(
          icon: Icons.article_outlined,
          title: 'No articles yet',
          message: 'Articles you write will appear here.',
          iconCircleSize: 56,
          titleFontSize: 14.5,
        );
      default:
        return const EmptyStateView(
          icon: Icons.article_outlined,
          title: 'No content yet',
          message: 'Start creating content to see your content here',
          iconCircleSize: 56,
          titleFontSize: 14.5,
        );
    }
  }
}

/// Placeholder rows while the user's content loads — follows the
/// `PropertyCardShimmer` pattern rather than showing an empty state that would
/// wrongly read as "you have nothing" (blueprint §12).
class _ContentShimmer extends StatelessWidget {
  const _ContentShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: 95,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One property in the My Content list — a card local to this screen (not
/// the shared `PropertyCardCompact`, which Shortlist and public profiles also
/// render — changing that widget would have restyled those surfaces too).
/// Category/listing-type chips mirror the Search results property card's
/// exact styling (`PropertyCardSearchRow`) for visual consistency.
class _MyPropertyCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MyPropertyCard({
    required this.property,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  (IconData, String)? get _categoryChip => switch (property.category) {
    'residential' => (Icons.home_rounded, 'Residential'),
    'commercial' => (Icons.store_mall_directory_rounded, 'Commercial'),
    'land' => (Icons.landscape_rounded, 'Land'),
    'pg_coliving' => (Icons.groups_rounded, 'PG/Co-living'),
    'others' => (Icons.category_rounded, 'Others'),
    _ => null,
  };

  String? get _listingLabel => switch (property.propertyType) {
    'sell' => 'For Sale',
    'rent' => 'For Rent',
    'lease' => 'For Lease',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final category = _categoryChip;
    final listingLabel = _listingLabel;

    return Semantics(
      label: property.title,
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spacingM),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.imageThumbnailRadius,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: property.imageUrl,
                        width: 76,
                        height: 76,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 76,
                          height: 76,
                          color: AppColors.textHint.withValues(alpha: 0.1),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 76,
                          height: 76,
                          color: AppColors.textHint.withValues(alpha: 0.1),
                          child: const Icon(Icons.broken_image, size: 18),
                        ),
                      ),
                    ),
                    if (property.photoCount > 0)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.camera_alt,
                                size: 9,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${property.photoCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (category != null)
                            _chip(
                              icon: category.$1,
                              label: category.$2,
                              bg: AppColors.primaryLight,
                              fg: AppColors.primary,
                              bordered: true,
                            ),
                          if (category != null && listingLabel != null)
                            const SizedBox(width: 6),
                          if (listingLabel != null)
                            _chip(
                              icon: Icons.sell_rounded,
                              label: listingLabel,
                              bg: const Color(0xFFFCE4EC),
                              fg: const Color(0xFFD6336C),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        property.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              property.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        property.priceDisplay,
                        style: AppTextStyles.price.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.straighten,
                            size: 11,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            property.sqft > 0 ? '${property.sqft} sq.ft' : '—',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                      // Same data the portal's card shows: how many likes, and
                      // (on tap) who liked it.
                      if ((property.likes ?? 0) > 0) ...[
                        const SizedBox(height: 4),
                        _LikesLink(
                          propertyId: property.id,
                          count: property.likes!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 22,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 19,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          size: 19,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      _PropertyLikeButton(propertyId: property.id),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
    bool bordered = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        border: bordered ? Border.all(color: fg.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9.5, color: fg),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppTextStyles.chip.copyWith(
              fontSize: 9.5,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// "N likes" on a My Content property card. Tapping it opens the list of
/// people who liked the property - the portal's LikedByLine / LikersModal.
class _LikesLink extends StatelessWidget {
  const _LikesLink({required this.propertyId, required this.count});

  final String propertyId;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'View who liked this property',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Own tap target so it opens the list instead of the card.
        onTap: () => _showLikersSheet(context, propertyId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.favorite, size: 12, color: AppColors.error),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '$count ${count == 1 ? 'like' : 'likes'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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

void _showLikersSheet(BuildContext context, String propertyId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LikersSheet(propertyId: propertyId),
  );
}

class _Liker {
  const _Liker({required this.name, this.avatarUrl});
  final String name;
  final String? avatarUrl;
}

/// Loads the likers through the portal's `content-likers` function (the same
/// call `useLikers.fetchLikers` makes), limit 50 like the portal's modal.
class _LikersSheet extends StatefulWidget {
  const _LikersSheet({required this.propertyId});

  final String propertyId;

  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  late Future<List<_Liker>> _future = _load();

  Future<List<_Liker>> _load() async {
    final response = await Supabase.instance.client.functions.invoke(
      'content-likers',
      body: {'kind': 'property', 'targetId': widget.propertyId, 'limit': 50},
    );
    final data = response.data;
    final raw = data is Map ? data['likers'] : null;
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map)
          _Liker(
            name: (row['display_name']?.toString().trim().isNotEmpty ?? false)
                ? row['display_name'].toString().trim()
                : 'Someone',
            avatarUrl: (row['avatar_url']?.toString().isNotEmpty ?? false)
                ? row['avatar_url'].toString()
                : null,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('Likes', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<_Liker>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Couldn't load likes", style: AppTextStyles.body),
                          TextButton(
                            onPressed: () => setState(() => _future = _load()),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  final likers = snapshot.data ?? const <_Liker>[];
                  if (likers.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('No likes yet', style: AppTextStyles.body),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: likers.length,
                    itemBuilder: (context, i) {
                      final liker = likers[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primaryLight,
                              backgroundImage: liker.avatarUrl != null
                                  ? CachedNetworkImageProvider(liker.avatarUrl!)
                                  : null,
                              child: liker.avatarUrl == null
                                  ? Text(
                                      liker.name.characters.first.toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                liker.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One article in the My Content list.
class _ArticleRow extends StatelessWidget {
  final ArticleSummary article;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ArticleRow({
    required this.article,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  /// "12 Sep 2026" — no `intl` dependency in this project, so spelled out the
  /// same way `AppNotification.relativeTime`'s month fallback already does.
  String? get _dateLabel {
    final created = article.createdAt;
    if (created == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${created.day} ${months[created.month - 1]} ${created.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateLabel;

    return Semantics(
      label: '${article.title}, ${article.displayStatus}',
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spacingM),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppConstants.imageThumbnailRadius,
                  ),
                  child: SizedBox(
                    width: 76,
                    height: 76,
                    child: article.imageUrl == null
                        ? const ColoredBox(
                            color: AppColors.primaryLight,
                            child: Icon(
                              Icons.article_outlined,
                              size: 22,
                              color: AppColors.primary,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: article.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const ColoredBox(
                              color: AppColors.primaryLight,
                              child: Icon(
                                Icons.article_outlined,
                                size: 22,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        article.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (dateLabel != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 11,
                              color: AppColors.textHint,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateLabel,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      _ArticleStatusChip(status: article.displayStatus),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 22,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textSecondary,
                          size: 19,
                        ),
                      ),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          color: AppColors.textSecondary,
                          size: 19,
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
    );
  }
}

/// One video in the My Content list — same row weight as [_ArticleRow], with
/// [InfluencerApprovalPill] (already used on the Manage Dashboard's video
/// cards) standing in for the article status chip.
class _VideoRow extends StatelessWidget {
  final InfluencerVideoModel video;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _VideoRow({
    required this.video,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  /// `video_type` has no dedicated display label anywhere else in the app —
  /// spelled out here the same way the Post Video form's own copy reads.
  String? get _categoryLabel => switch (video.videoType) {
    'property_listing' => 'Property Listing',
    'property_news' => 'Property News',
    'property_education' => 'Property Education',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final categoryLabel = _categoryLabel;

    return Semantics(
      label: '${video.title}, ${video.approvalStatus}',
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppConstants.spacingM),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            boxShadow: AppColors.surfaceCardShadow,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.imageThumbnailRadius,
                      ),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: video.thumbnailUrl == null
                            ? const ColoredBox(
                                color: AppColors.primaryLight,
                                child: Icon(
                                  Icons.videocam_outlined,
                                  size: 22,
                                  color: AppColors.primary,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: video.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const ColoredBox(
                                  color: AppColors.primaryLight,
                                  child: Icon(
                                    Icons.videocam_outlined,
                                    size: 22,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    // Play-button overlay — same reason the Feed screen's
                    // video cards show one (Icons.play_circle_fill), just
                    // sized for this smaller 76 dp thumbnail.
                    Positioned.fill(
                      child: Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 26,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InfluencerApprovalPill(
                            approvalStatus: video.approvalStatus,
                          ),
                          if (categoryLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCE4EC),
                                borderRadius: BorderRadius.circular(
                                  AppConstants.chipRadius,
                                ),
                              ),
                              child: Text(
                                categoryLabel,
                                style: AppTextStyles.chip.copyWith(
                                  fontSize: 9.5,
                                  color: const Color(0xFFD6336C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.favorite,
                            size: 12,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${video.likes} likes',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 22,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.textSecondary,
                          size: 19,
                        ),
                      ),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          color: AppColors.textSecondary,
                          size: 19,
                        ),
                      ),
                      _VideoLikeButton(videoId: video.id),
                    ],
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

/// Moderation/publication state chip.
///
/// Deliberately not `StatusTag`: that widget resolves its colours through
/// `AppColors.getStatusChipBg/Text`, which only knows property statuses and
/// falls through to one neutral style for everything else — "Published" and
/// "Rejected" would look identical. Teaching it article states would mean
/// editing global colour mappings, which is outside this milestone's scope.
/// Like toggle for a My Content property card. Backed by PropertyProvider
/// (`user_likes.property_id`) — the same like the property page and search
/// cards use, so the state matches everywhere. This used to be a plain,
/// decorative heart Icon with no handler, so a tap on it fell through to the
/// card and opened the listing instead.
class _PropertyLikeButton extends StatelessWidget {
  const _PropertyLikeButton({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context) {
    return Consumer<PropertyProvider>(
      builder: (context, properties, _) => _LikeHeart(
        liked: properties.isLiked(propertyId),
        onTap: () => properties.toggleLike(propertyId),
      ),
    );
  }
}

/// Like toggle for a My Content video card. Backed by ReelsProvider
/// (`user_likes.reel_id`) — the same like Reels uses for the same
/// `influencer_videos` row. Previously decorative only, like the property one.
class _VideoLikeButton extends StatelessWidget {
  const _VideoLikeButton({required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context) {
    return Consumer<ReelsProvider>(
      builder: (context, reels, _) => _LikeHeart(
        liked: reels.isLiked(videoId),
        onTap: () => reels.toggleLike(videoId),
      ),
    );
  }
}

/// The heart itself: same size/colour as the icon it replaces, filled when
/// liked. Its own opaque tap target wins the gesture over the card's
/// ScaleTap, so tapping it likes instead of opening the card.
class _LikeHeart extends StatelessWidget {
  const _LikeHeart({required this.liked, required this.onTap});

  final bool liked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'Unlike' : 'Like',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            key: ValueKey(liked),
            size: 19,
            color: AppColors.error,
          ),
        ),
      ),
    );
  }
}

class _ArticleStatusChip extends StatelessWidget {
  final String status;

  const _ArticleStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      'Published' => (AppColors.success, Color(0x1A22C55E)),
      'Pending review' => (AppColors.warning, Color(0x1AF97316)),
      'Rejected' => (AppColors.error, Color(0x1AEF4444)),
      _ => (AppColors.textSecondary, Color(0x141A1A2E)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Text(
        status,
        style: AppTextStyles.chip.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
