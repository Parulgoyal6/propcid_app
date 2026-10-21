// screens/profile/widgets/public_profile_content_sections.dart
//
// The Listings and Reviews sections.
//
// Listings reuse `PropertyCardCompact` verbatim. Note that card paints a 0.5 dp
// bottom border and NO shadow, so consecutive cards read as a list rather than
// floating panels — which is correct here and is how `MyContentSection` already
// presents the user's own listings. They are deliberately not wrapped in
// `DashboardCard`.
//
// Reviews are capped at three inline. The full list is a separate screen, not a
// nested scrollable: a `ListView` inside a `CustomScrollView` would need
// `shrinkWrap`, which builds every child eagerly.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/builder_project_model.dart';
import '../../../models/profile_review.dart';
import '../../../models/property_model.dart';
import '../../../widgets/property_card_compact.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/shared/app_action_button.dart';
import '../../../widgets/shared/app_surface_card.dart';
import '../public_profile_role.dart';
import 'public_profile_identity.dart';
import 'public_profile_stats.dart';

/// How many listings and reviews render inline before "View all".
const int kInlineListingLimit = 4;
const int kInlineReviewLimit = 3;

// ─────────────────────────────────────────────────────────────────────────────
// Listings / Projects
// ─────────────────────────────────────────────────────────────────────────────

class ProfileListingsSection extends StatelessWidget {
  final String? userType;
  final String displayName;
  final List<PropertyModel> properties;
  final List<BuilderProjectModel> projects;
  final bool isLoading;
  final bool hasFailed;
  final VoidCallback onRetry;
  final void Function(PropertyModel property) onPropertyTap;
  final void Function(BuilderProjectModel project) onProjectTap;

  /// Null until the dedicated list screen exists — the footer button is hidden
  /// rather than shown as a dead end.
  final VoidCallback? onViewAll;

  const ProfileListingsSection({
    super.key,
    required this.userType,
    required this.displayName,
    required this.properties,
    required this.projects,
    required this.isLoading,
    required this.hasFailed,
    required this.onRetry,
    required this.onPropertyTap,
    required this.onProjectTap,
    this.onViewAll,
  });

  bool get _showsProjects => userType?.toLowerCase() == 'builder';
  int get _count => _showsProjects ? projects.length : properties.length;

  @override
  Widget build(BuildContext context) {
    final title = contentLabel(userType, plural: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `SectionHeader` supplies its own 16 x 12 padding, so this section is
        // placed with NO outer horizontal padding and pads its body instead.
        // Wrapping the header too would double it to 32.
        SectionHeader(
          title: title,
          actionLabel:
              !isLoading &&
                  !hasFailed &&
                  _count > kInlineListingLimit &&
                  onViewAll != null
              ? 'View all'
              : null,
          onActionTap: onViewAll,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
          ),
          child: _buildBody(context, title),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, String title) {
    if (isLoading) return const _ListingShimmer();

    if (hasFailed) {
      return EmptyStateView(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load $title",
        message: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: onRetry,
        iconCircleSize: 56,
        titleFontSize: 14.5,
      );
    }

    if (_count == 0) {
      return EmptyStateView(
        icon: _showsProjects ? Icons.domain_rounded : Icons.apartment_rounded,
        title: _showsProjects ? 'No projects yet' : 'No listings yet',
        message: _showsProjects
            ? "$displayName hasn't published any projects."
            : "$displayName hasn't posted any properties.",
        iconCircleSize: 56,
        titleFontSize: 14.5,
      );
    }

    final children = <Widget>[];

    if (_showsProjects) {
      for (final project in projects.take(kInlineListingLimit)) {
        children.add(
          _ProjectRow(project: project, onTap: () => onProjectTap(project)),
        );
      }
    } else {
      for (final property in properties.take(kInlineListingLimit)) {
        children.add(
          PropertyCardCompact(
            property: property,
            onTap: () => onPropertyTap(property),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingM),
          children[i],
        ],
        if (_count > kInlineListingLimit && onViewAll != null) ...[
          const SizedBox(height: AppConstants.spacingL),
          AppActionButton(
            label: 'View all $_count ${title.toLowerCase()}',
            trailingIcon: Icons.chevron_right_rounded,
            variant: AppActionButtonVariant.surface,
            height: 44,
            onTap: onViewAll,
          ),
        ],
      ],
    );
  }
}

/// A builder project row.
///
/// `PropertyCardCompact` takes a `PropertyModel` and cannot render a
/// `BuilderProjectModel`, so this mirrors its proportions — 130 x 95 thumbnail,
/// 12 dp radius — rather than converting between models.
class _ProjectRow extends StatelessWidget {
  final BuilderProjectModel project;
  final VoidCallback onTap;

  const _ProjectRow({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${project.title}, ${project.location}',
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              boxShadow: AppColors.surfaceCardShadow,
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppConstants.imageThumbnailRadius,
                  ),
                  child: SizedBox(
                    width: AppConstants.propertyCompactImageWidth,
                    height: AppConstants.propertyCompactImageHeight,
                    child: project.image.isEmpty
                        ? const ColoredBox(
                            color: AppColors.primaryLight,
                            child: Icon(
                              Icons.domain_rounded,
                              color: AppColors.primary,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: project.image,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const ColoredBox(
                              color: AppColors.primaryLight,
                              child: Icon(
                                Icons.domain_rounded,
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
                        project.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              project.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (project.availableUnits > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${project.availableUnits} units available',
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11.5,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

class _ListingShimmer extends StatelessWidget {
  const _ListingShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingM),
          // 95 dp matches `MyContentSection._ContentShimmer` and the real card's
          // thumbnail height, so nothing shifts when rows land.
          const _ShimmerBox(height: 95),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reviews
// ─────────────────────────────────────────────────────────────────────────────

/// The Reviews section. Owns which star bar (if any) is selected; the actual
/// rendering lives in [_ProfileReviewsBody].
class ProfileReviewsSection extends StatefulWidget {
  final RatingBreakdown ratings;
  final bool isBuilder;
  final String displayName;
  final bool isLoading;
  final bool hasFailed;
  final VoidCallback onRetry;

  /// Null until the reviews screen exists.
  final VoidCallback? onViewAll;

  /// Null when the viewer cannot rate - signed out, or viewing themselves.
  final VoidCallback? onWriteReview;

  /// Opens a review author's public profile. Null leaves the cards inert.
  final void Function(ProfileReview review)? onReviewerTap;

  /// "Write a review" or "Update your review".
  final String writeReviewLabel;

  const ProfileReviewsSection({
    super.key,
    required this.ratings,
    required this.isBuilder,
    required this.displayName,
    required this.isLoading,
    required this.hasFailed,
    required this.onRetry,
    this.onViewAll,
    this.onWriteReview,
    this.onReviewerTap,
    this.writeReviewLabel = 'Write a review',
  });

  @override
  State<ProfileReviewsSection> createState() => _ProfileReviewsSectionState();
}

class _ProfileReviewsSectionState extends State<ProfileReviewsSection> {
  int? _star;

  @override
  Widget build(BuildContext context) {
    return _ProfileReviewsBody(
      ratings: widget.ratings,
      isBuilder: widget.isBuilder,
      displayName: widget.displayName,
      isLoading: widget.isLoading,
      hasFailed: widget.hasFailed,
      onRetry: widget.onRetry,
      onViewAll: widget.onViewAll,
      onWriteReview: widget.onWriteReview,
      onReviewerTap: widget.onReviewerTap,
      writeReviewLabel: widget.writeReviewLabel,
      selectedStar: _star,
      // Tapping the selected bar again clears the filter.
      onStarTap: (star) => setState(() => _star = _star == star ? null : star),
    );
  }
}

class _ProfileReviewsBody extends StatelessWidget {
  final RatingBreakdown ratings;
  final bool isBuilder;
  final String displayName;
  final bool isLoading;
  final bool hasFailed;
  final VoidCallback onRetry;

  /// Null until the reviews screen exists.
  final VoidCallback? onViewAll;

  /// Null when the viewer cannot rate — signed out, or viewing themselves.
  /// Wiring the sheet is Phase 5.
  final VoidCallback? onWriteReview;

  /// Opens a review author's public profile. Null leaves the cards inert.
  final void Function(ProfileReview review)? onReviewerTap;

  /// "Write a review" or "Update your review", depending on whether the viewer
  /// has already rated (UserProfile.tsx:1876).
  final String writeReviewLabel;

  /// The star bar the user tapped (1-5), or null for "all reviews".
  final int? selectedStar;
  final ValueChanged<int> onStarTap;

  const _ProfileReviewsBody({
    required this.selectedStar,
    required this.onStarTap,
    required this.ratings,
    required this.isBuilder,
    required this.displayName,
    required this.isLoading,
    required this.hasFailed,
    required this.onRetry,
    this.onViewAll,
    this.onWriteReview,
    this.onReviewerTap,
    this.writeReviewLabel = 'Write a review',
  });

  /// The reviews to list: everything up to the inline limit, or - when a star
  /// bar is selected - every loaded written review with that rating.
  Iterable<ProfileReview> get _visibleReviews => selectedStar == null
      ? ratings.reviews.take(kInlineReviewLimit)
      : ratings.reviews.where((r) => r.rating == selectedStar);

  @override
  Widget build(BuildContext context) {
    final summary = ratings.displayFor(isBuilder: isBuilder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // As above: the header pads itself; the body is padded below.
        SectionHeader(
          title: 'Reviews',
          actionLabel:
              !isLoading &&
                  !hasFailed &&
                  ratings.reviews.length > kInlineReviewLimit &&
                  onViewAll != null
              ? 'See all'
              : null,
          onActionTap: onViewAll,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
          ),
          child: _buildReviewsBody(summary),
        ),
      ],
    );
  }

  Widget _buildReviewsBody(RatingSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLoading)
          const _ShimmerBox(height: 150)
        else if (hasFailed)
          EmptyStateView(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load reviews",
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: onRetry,
            iconCircleSize: 56,
            titleFontSize: 14.5,
          )
        else if (!summary.hasRatings)
          EmptyStateView(
            icon: Icons.star_outline_rounded,
            title: 'No reviews yet',
            message: 'Be the first to review $displayName.',
            actionLabel: onWriteReview == null ? null : writeReviewLabel,
            onAction: onWriteReview,
            iconCircleSize: 56,
            titleFontSize: 14.5,
          )
        else ...[
          RatingSummaryCard(
            ratings: ratings,
            isBuilder: isBuilder,
            selectedStar: selectedStar,
            onStarTap: onStarTap,
          ),
          if (selectedStar != null) ...[
            const SizedBox(height: AppConstants.spacingM),
            ReviewStarFilterStrip(
              star: selectedStar!,
              ratingCount: ratings.distribution[selectedStar!] ?? 0,
              writtenCount: _visibleReviews.length,
              onClear: () => onStarTap(selectedStar!),
            ),
          ],
          for (final review in _visibleReviews) ...[
            const SizedBox(height: AppConstants.spacingM),
            ReviewCard(
              review: review,
              // Inert when the author could not be resolved: "Anonymous" has no
              // profile to open, and a tap that does nothing is worse than none.
              onTap: onReviewerTap == null || review.raterId.isEmpty
                  ? null
                  : () => onReviewerTap!(review),
            ),
          ],
          if (onWriteReview != null) ...[
            const SizedBox(height: AppConstants.spacingL),
            AppActionButton(
              label: writeReviewLabel,
              icon: Icons.star_outline_rounded,
              variant: AppActionButtonVariant.outline,
              height: 44,
              onTap: onWriteReview,
            ),
          ],
        ],
      ],
    );
  }
}

/// Big average on the left, animated 5-bar distribution on the right.
class RatingSummaryCard extends StatelessWidget {
  final RatingBreakdown ratings;
  final bool isBuilder;

  /// Which bar is selected (1-5), or null when none is. Only meaningful with
  /// [onStarTap]; without it the bars stay display-only, as before.
  final int? selectedStar;

  /// Called with the tapped star. Null leaves the bars inert.
  final ValueChanged<int>? onStarTap;

  const RatingSummaryCard({
    super.key,
    required this.ratings,
    required this.isBuilder,
    this.selectedStar,
    this.onStarTap,
  });

  @override
  Widget build(BuildContext context) {
    final summary = ratings.displayFor(isBuilder: isBuilder);

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label:
                          '${summary.average.toStringAsFixed(1)} out of 5, '
                          '${summary.count} reviews',
                      child: ExcludeSemantics(
                        // FittedBox(scaleDown), following the same precedent
                        // `MetricCard` documents: a 32 dp numeral in a fixed
                        // 96 dp column is not safe as the text scale rises —
                        // real Poppins reaches ~93 dp of the 96 at 1.3x, and the
                        // test environment's fallback font (one em per glyph)
                        // blows straight past it. Scaling down cannot overflow at
                        // any font or scale. Found by
                        // test/public_profile_device_validation_test.dart.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                summary.average.toStringAsFixed(1),
                                maxLines: 1,
                                style: AppTextStyles.heading1.copyWith(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: AppColors.primary,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '/5',
                                  maxLines: 1,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    StarRow(value: summary.average, size: 13),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.count} ${summary.count == 1 ? 'review' : 'reviews'}',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppConstants.spacingL),
              Expanded(
                child: Column(
                  children: [
                    for (var star = 5; star >= 1; star--) ...[
                      // Row spacing now comes from each bar's own vertical
                      // padding (a bigger tap target at the same 6 dp gap).
                      RatingDistributionBar(
                        star: star,
                        count: ratings.distribution[star] ?? 0,
                        peak: ratings.distributionPeak,
                        selected: selectedStar == star,
                        dimmed: selectedStar != null && selectedStar != star,
                        onTap: onStarTap == null
                            ? null
                            : () => onStarTap!(star),
                        // 60 ms per row, top bar first.
                        delayMs:
                            (5 - star) * AppConstants.staggerListItemDelayMs,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Builders carry a second score from brokers only — portal parity.
          if (isBuilder && ratings.hasBrokerTrustScore) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: AppColors.hairline),
            const SizedBox(height: 14),
            const DashboardSectionLabel('Broker trust score'),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  ratings.broker.average.toStringAsFixed(1),
                  style: AppTextStyles.heading2.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: AppColors.statusNewLaunch,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: Text(
                    '${ratings.broker.count} professional '
                    '${ratings.broker.count == 1 ? 'recommendation' : 'recommendations'}',
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One histogram row, filling from zero on first paint. Tappable when
/// [onTap] is given: it selects this star rating so the reviews list can be
/// narrowed to it.
class RatingDistributionBar extends StatelessWidget {
  final int star;
  final int count;
  final int peak;
  final int delayMs;

  /// This bar is the active filter.
  final bool selected;

  /// Another bar is the active filter - this one is faded back.
  final bool dimmed;

  final VoidCallback? onTap;

  const RatingDistributionBar({
    super.key,
    required this.star,
    required this.count,
    required this.peak,
    this.delayMs = 0,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = peak == 0 ? 0.0 : count / peak;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final fill = dimmed
        ? AppColors.primary.withValues(alpha: 0.3)
        : AppColors.primary;

    final row = Row(
      children: [
        SizedBox(
          width: 8,
          child: Text(
            '$star',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
              color: selected ? AppColors.primary : null,
            ),
          ),
        ),
        const SizedBox(width: 3),
        const Icon(Icons.star_rounded, size: 10, color: AppColors.warning),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ColoredBox(color: AppColors.hairline),
                  ),
                  if (reduceMotion)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      heightFactor: 1,
                      child: ColoredBox(color: fill),
                    )
                  else
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: fraction),
                      duration: Duration(milliseconds: 600 + delayMs),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        heightFactor: 1,
                        child: ColoredBox(color: fill),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 22,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w400,
              color: selected ? AppColors.primary : AppColors.textHint,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label:
          '$star ${star == 1 ? 'star' : 'stars'}, $count '
          '${count == 1 ? 'review' : 'reviews'}'
          '${onTap != null ? ', tap to filter' : ''}',
      child: ExcludeSemantics(
        // 3 dp above and below the 6 dp bar gives a ~12 dp tall row to touch
        // while keeping the same 6 dp visual gap between rows.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: row,
          ),
        ),
      ),
    );
  }
}

/// The strip shown under the rating card while a star bar is selected:
/// what is being shown, and a way back to all reviews.
class ReviewStarFilterStrip extends StatelessWidget {
  final int star;

  /// How many ratings gave this star (the bar's own number).
  final int ratingCount;

  /// How many of them carry a written review that can be listed.
  final int writtenCount;
  final VoidCallback onClear;

  const ReviewStarFilterStrip({
    super.key,
    required this.star,
    required this.ratingCount,
    required this.writtenCount,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final ratings = '$ratingCount ${ratingCount == 1 ? 'rating' : 'ratings'}';
    final label = writtenCount == 0
        ? '$ratings with $star ${star == 1 ? 'star' : 'stars'} - no written reviews'
        : '$ratings with $star ${star == 1 ? 'star' : 'stars'}';
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// One review.
///
/// Stage 2B: the card opens its author's public profile when [onTap] is supplied.
/// The card was inert before, so this adds a gesture rather than re-pointing one,
/// and it lives entirely in a file created for this feature — no pre-existing
/// screen is involved.
class ReviewCard extends StatelessWidget {
  final ProfileReview review;

  /// Null leaves the card inert, exactly as it was.
  final VoidCallback? onTap;

  const ReviewCard({super.key, required this.review, this.onTap});

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (onTap == null) return body;

    return Semantics(
      button: true,
      label: "Open ${review.raterName}'s profile",
      child: ExcludeSemantics(
        child: ScaleTap(onTap: onTap, child: body),
      ),
    );
  }

  Widget _buildBody() {
    final createdAt = review.createdAt;

    return DashboardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RaterAvatar(review: review),
              const SizedBox(width: AppConstants.spacingS),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      review.raterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    StarRow(value: review.rating.toDouble(), size: 12),
                  ],
                ),
              ),
              if (createdAt != null)
                Text(
                  profileRelativeTime(createdAt),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
          if (review.hasText) ...[
            const SizedBox(height: 10),
            Text(
              review.review!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RaterAvatar extends StatelessWidget {
  final ProfileReview review;

  const _RaterAvatar({required this.review});

  static const double _size = 36;

  @override
  Widget build(BuildContext context) {
    final url = review.raterAvatarUrl;
    final fallback = Center(
      child: Text(
        review.raterInitial,
        style: AppTextStyles.caption.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return Container(
      width: _size,
      height: _size,
      decoration: const BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                width: _size,
                height: _size,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Shared shimmer block, using the app's only shimmer recipe.
class _ShimmerBox extends StatelessWidget {
  final double height;

  const _ShimmerBox({required this.height});

  @override
  Widget build(BuildContext context) => ProfileShimmerBox(height: height);
}

/// Public so the skeleton can use the identical box.
class ProfileShimmerBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const ProfileShimmerBox({
    super.key,
    required this.height,
    this.width,
    this.radius = AppConstants.cardRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
