// screens/profile/profile_reviews_screen.dart
//
// "My reviews" - the destination of the Reviews tile on the profile's stats
// row, mirroring the portal's profile Reviews tab (`UserRatingsDisplay` for
// the signed-in user): the rating summary (average + 5-bar distribution)
// followed by the reviews people have written.
//
// Reuses the public profile's own `RatingSummaryCard` / `ReviewCard` and the
// same `ProfileContentService.fetchRatings`, so the numbers here can never
// disagree with what visitors see on this profile.
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/profile_review.dart';
import '../../services/profile_content_service.dart';
import 'widgets/public_profile_content_sections.dart';

class ProfileReviewsScreen extends StatefulWidget {
  final String userId;
  final String displayName;
  final bool isBuilder;

  const ProfileReviewsScreen({
    super.key,
    required this.userId,
    required this.displayName,
    required this.isBuilder,
  });

  @override
  State<ProfileReviewsScreen> createState() => _ProfileReviewsScreenState();
}

class _ProfileReviewsScreenState extends State<ProfileReviewsScreen> {
  final ProfileContentService _service = ProfileContentService();

  RatingBreakdown _ratings = RatingBreakdown.zero;
  bool _loading = true;
  bool _failed = false;

  /// Selected star bar (1-5), or null for all reviews.
  int? _star;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final ratings = await _service.fetchRatings(widget.userId);
      if (!mounted) return;
      setState(() {
        _ratings = ratings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _openReviewer(ProfileReview review) {
    if (review.raterId.isEmpty || review.raterId == widget.userId) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': review.raterId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Reviews',
          style: AppTextStyles.heading3.copyWith(fontSize: 16),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(
            color: AppColors.hairline,
            child: SizedBox(height: 1),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_failed) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppConstants.spacingL),
        children: [
          const SizedBox(height: 60),
          EmptyStateView(
            icon: Icons.cloud_off_rounded,
            title: "Couldn't load reviews",
            message: 'Check your connection and try again.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        ],
      );
    }

    final summary = _ratings.displayFor(isBuilder: widget.isBuilder);
    if (!summary.hasRatings) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppConstants.spacingL),
        children: const [
          SizedBox(height: 60),
          EmptyStateView(
            icon: Icons.star_outline_rounded,
            title: 'No reviews yet',
            message: 'When people review you, their reviews will appear here.',
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(AppConstants.spacingL),
      children: [
        RatingSummaryCard(
          ratings: _ratings,
          isBuilder: widget.isBuilder,
          selectedStar: _star,
          onStarTap: (star) => setState(() => _star = _star == star ? null : star),
        ),
        if (_star != null) ...[
          const SizedBox(height: AppConstants.spacingM),
          ReviewStarFilterStrip(
            star: _star!,
            ratingCount: _ratings.distribution[_star!] ?? 0,
            writtenCount: _ratings.reviews.where((r) => r.rating == _star).length,
            onClear: () => setState(() => _star = null),
          ),
        ],
        for (final review in _star == null
            ? _ratings.reviews
            : _ratings.reviews.where((r) => r.rating == _star)) ...[
          const SizedBox(height: AppConstants.spacingM),
          ReviewCard(
            review: review,
            onTap: review.raterId.isEmpty
                ? null
                : () => _openReviewer(review),
          ),
        ],
      ],
    );
  }
}
