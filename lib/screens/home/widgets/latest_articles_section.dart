// screens/home/widgets/latest_articles_section.dart
//
// Home's "Latest Articles" rail plus its detail sheet — the Flutter
// counterpart to the portal's inline `cms_posts` query
// (`PublicHomePage.tsx`/`AuthenticatedHomePage.tsx`, queryKey
// `'home-articles'`) rendered via `BlogCard`, which on the web navigates to
// `/blog/articles/:slug` (`BlogDetail`).
//
// This app has no article-reader screen or HTML-rendering package yet, so
// the article opens in a bottom sheet (the same pattern `NewsSection` already
// uses for its own admin-curated rail) rather than a full page — a smaller,
// self-contained addition than introducing a new route and a new dependency
// for a single read-only view.
//
// HIDES ITSELF WHEN THERE IS NOTHING TO SHOW
// ------------------------------------------
// Same convention as `NewsSection` / `TrendingCitiesSection`: nothing renders
// while loading, on failure, or when there are genuinely no published
// articles.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/profile_link.dart' show kProfileOrigin;
import '../../../core/widgets/scale_tap.dart';
import '../../../models/article_model.dart';
import '../../../services/article_service.dart';
import '../../../widgets/area_converter_sheet.dart' show SheetDragHandle;
import '../../../widgets/section_header.dart';

const double _kArticleRailFixedHeight = 200;
const double _kArticleRailTextHeight = 120;
const double _kArticleCardWidth = 250;
// 16:9 cover, like the portal's `aspect-video`.
const double _kArticleThumbHeight = 140;
const double _kSheetRadius = 24;

class LatestArticlesSection extends StatefulWidget {
  const LatestArticlesSection({super.key, this.service});

  @visibleForTesting
  final ArticleService? service;

  @override
  State<LatestArticlesSection> createState() => _LatestArticlesSectionState();
}

class _LatestArticlesSectionState extends State<LatestArticlesSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves `_future` across Home's own scroll — without this, scrolling
  // this rail far enough off/on screen disposes and rebuilds it from
  // scratch, re-querying published articles every time.
  @override
  bool get wantKeepAlive => true;

  late final Future<List<ArticleModel>> _future =
      (widget.service ?? ArticleService()).listPublished();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<ArticleModel>>(
      future: _future,
      builder: (context, snapshot) {
        final articles = snapshot.data;
        if (articles == null || articles.isEmpty)
          return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Latest Articles'),
              SizedBox(
                // Fixed parts (cover, padding, avatar) + text rows that grow
                // with the user's text-size setting, so nothing clips.
                height:
                    _kArticleRailFixedHeight +
                    _kArticleRailTextHeight *
                        (MediaQuery.textScalerOf(context).scale(14) / 14),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingL,
                  ),
                  itemCount: articles.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(
                      right: AppConstants.spacingM,
                    ),
                    child: ScaleTap(
                      onTap: () => showArticleDetailSheet(context, articles[i]),
                      child: _ArticleCard(article: articles[i]),
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

/// One article card, laid out like the portal's `BlogCard.tsx`: 16:9 cover
/// with the orange category tag, title (2 lines), brief (2 lines), writer
/// avatar + name, then read time, publish date and a share button.
class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article});

  final ArticleModel article;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Sep 17, 2026" — the portal's `format(date, 'MMM dd, yyyy')`.
  static String _formatDate(DateTime d) =>
      '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

  /// Same link the portal's share button builds for an article.
  Future<void> _share(BuildContext context) async {
    final slug = article.slug.isNotEmpty ? article.slug : article.id;
    try {
      await Share.share(
        '$kProfileOrigin/blog/articles/$slug',
        subject: article.title,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share sheet')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Portal falls back to "PropCID Staff" when a post has no author name.
    final authorName = article.authorName ?? 'PropCID Staff';
    final avatarUrl = article.authorImageUrl;

    return Container(
      width: _kArticleCardWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover + category tag.
          Stack(
            children: [
              _ArticleThumbnail(
                imageUrl: article.imageUrl,
                height: _kArticleThumbHeight,
                width: _kArticleCardWidth,
              ),
              if (article.category != null)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7C0A),
                      borderRadius: BorderRadius.circular(
                        AppConstants.pillRadius,
                      ),
                      boxShadow: AppColors.surfaceCardShadow,
                    ),
                    child: Text(
                      article.category!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.chip.copyWith(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (article.brief.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      article.brief,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Writer.
                  Row(
                    children: [
                      _AuthorAvatar(name: authorName, imageUrl: avatarUrl),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Read time · date · share.
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${article.readTime} min read',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      if (article.publishedAt != null) ...[
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _formatDate(article.publishedAt!.toLocal()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Semantics(
                        label: 'Share article',
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _share(context),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.share_outlined,
                              size: 16,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ),
                    ],
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

/// Writer avatar: their photo when it is a full URL, else the portal's
/// orange-gradient circle with their initial.
class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  static const double _size = 24;

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF25400), Color(0xFFFF7C0A)],
        ),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: AppTextStyles.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );

    final url = imageUrl;
    if (url == null || !url.startsWith('http')) return initial;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        placeholder: (_, _) => initial,
        errorWidget: (_, _, _) => initial,
      ),
    );
  }
}

class _ArticleThumbnail extends StatelessWidget {
  const _ArticleThumbnail({
    required this.imageUrl,
    required this.height,
    this.width,
  });

  final String? imageUrl;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) return _placeholder();
    // Bounds decoding to this thumbnail's actual rendered pixels rather
    // than the source's native resolution.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      height: height,
      width: width,
      fit: BoxFit.cover,
      memCacheWidth: width == null || width == double.infinity
          ? null
          : (width! * dpr).round(),
      memCacheHeight: (height * dpr).round(),
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    height: height,
    width: width,
    color: AppColors.primaryLight,
    alignment: Alignment.center,
    child: const Icon(
      Icons.article_rounded,
      size: 26,
      color: AppColors.primary,
    ),
  );
}

/// Strips HTML tags for a plain-text chunk — good enough for a read-only
/// sheet without pulling in an HTML-rendering package for this one screen.
/// Collapses runs of whitespace left behind by stripped block tags.
String _stripHtml(String html) {
  final withoutTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  return withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// One piece of a split article body — either a heading's own text or a
/// plain-text chunk of everything between two headings.
class _ArticleBodyBlock {
  final String text;
  final bool isHeading;
  const _ArticleBodyBlock(this.text, {this.isHeading = false});
}

/// Splits [html] around its `<h1>`–`<h6>` tags (the article editor writes
/// real headings — see `article_content_converter.dart`) so they can be
/// rendered distinctly instead of `_stripHtml` collapsing the whole article,
/// headings included, into one undifferentiated paragraph. Everything
/// between headings — paragraphs, lists, blockquotes alike — stays grouped
/// into a single plain-text chunk via [_stripHtml], exactly as before this
/// split; only the heading text itself is pulled out and styled separately,
/// so no content is dropped, just re-segmented.
List<_ArticleBodyBlock> _splitArticleBody(String html) {
  final headingTag = RegExp(
    r'<h[1-6][^>]*>(.*?)</h[1-6]>',
    caseSensitive: false,
    dotAll: true,
  );
  final blocks = <_ArticleBodyBlock>[];
  var cursor = 0;
  for (final match in headingTag.allMatches(html)) {
    final before = _stripHtml(html.substring(cursor, match.start));
    if (before.isNotEmpty) blocks.add(_ArticleBodyBlock(before));
    final heading = _stripHtml(match.group(1) ?? '');
    if (heading.isNotEmpty) {
      blocks.add(_ArticleBodyBlock(heading, isHeading: true));
    }
    cursor = match.end;
  }
  final rest = _stripHtml(html.substring(cursor));
  if (rest.isNotEmpty) blocks.add(_ArticleBodyBlock(rest));
  return blocks;
}

/// Opens [article] in the read-only bottom sheet — the app's only article
/// reader (see this file's header comment). Reused by the influencer
/// dashboard's "Most Liked Content" (Audience Insights) so an article result
/// opens the same reader as Home's own "Latest Articles" rail, rather than a
/// second one.
void showArticleDetailSheet(BuildContext context, ArticleModel article) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (_) => ArticleDetailSheet(article: article),
  );
}

class ArticleDetailSheet extends StatelessWidget {
  const ArticleDetailSheet({super.key, required this.article});

  final ArticleModel article;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bodyBlocks = _splitArticleBody(article.contentHtml);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: AppConstants.spacingM),
              child: SheetDragHandle(),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingXL,
                  0,
                  AppConstants.spacingXL,
                  AppConstants.spacingL,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.cardRadius,
                      ),
                      child: _ArticleThumbnail(
                        imageUrl: article.imageUrl,
                        height: 190,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingL),
                    if (article.category != null)
                      Text(
                        article.category!.toUpperCase(),
                        style: AppTextStyles.chip.copyWith(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      article.title,
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: 17,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Writer — same "PropCID Staff" fallback as the portal.
                    Text(
                      'By ${article.authorName ?? 'PropCID Staff'}',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${article.readTime} min read',
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                        ),
                        if (article.publishedAt != null) ...[
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.event_rounded,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${article.publishedAt!.day}/'
                            '${article.publishedAt!.month}/'
                            '${article.publishedAt!.year}',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (article.brief.isNotEmpty) ...[
                      const SizedBox(height: AppConstants.spacingM),
                      Text(
                        article.brief,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                    for (final block in bodyBlocks) ...[
                      SizedBox(
                        height: block == bodyBlocks.first
                            ? AppConstants.spacingM
                            : AppConstants.spacingS,
                      ),
                      Text(
                        block.text,
                        style: block.isHeading
                            ? AppTextStyles.body.copyWith(
                                fontSize: 15,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              )
                            : AppTextStyles.body.copyWith(
                                fontSize: 13.5,
                                height: 1.6,
                                color: AppColors.textSecondary,
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
