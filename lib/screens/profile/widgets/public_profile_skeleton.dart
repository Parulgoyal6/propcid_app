// screens/profile/widgets/public_profile_skeleton.dart
//
// The first-load placeholder.
//
// Every block matches the box its real counterpart will occupy, so nothing shifts
// when data lands. That is the whole point: a skeleton whose proportions differ
// from the final layout produces a visible jump, which reads worse than a spinner.
//
// Uses the app's only shimmer recipe — `Shimmer.fromColors` with
// `grey[300]`/`grey[100]`, as `ProfileStatsRow`, `MyContentSection` and
// `MetricCardGridShimmer` all do.
//
// Wrapped in `ExcludeSemantics` by the caller and announced as one
// "Loading profile" label, so a screen reader is not walked through a dozen
// meaningless boxes.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import 'public_profile_content_sections.dart';
import 'public_profile_cover_header.dart';

class PublicProfileSkeleton extends StatelessWidget {
  const PublicProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No cover and no avatar here: `PublicProfileCoverHeader` renders both in
        // every state, including this one — it draws the gradient fallback while
        // `coverImageUrl` is null and takes [PublicProfileAvatarSkeleton] as its
        // `avatarOverlay`. Drawing them again would stack a second cover under
        // the first. This block therefore begins exactly where the loaded
        // identity sliver does, `spacingM` below the header.
        Padding(
          padding: const EdgeInsets.only(
            left: AppConstants.spacingL,
            right: AppConstants.spacingL,
            top: AppConstants.spacingM,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              // Name / role pill line.
              ProfileShimmerBox(height: 20, width: 190, radius: 6),
              SizedBox(height: AppConstants.spacingS),
              // Role subtitle.
              ProfileShimmerBox(height: 12, width: 130, radius: 4),
              SizedBox(height: 6),
              // Handle.
              ProfileShimmerBox(height: 12, width: 100, radius: 4),
              SizedBox(height: AppConstants.spacingM),
              // Rating row.
              ProfileShimmerBox(height: 14, width: 160, radius: 4),
              SizedBox(height: AppConstants.spacingM),
              // Meta strip.
              ProfileShimmerBox(height: 12, width: 240, radius: 4),
              SizedBox(height: AppConstants.spacingXL),

              // Trust chips.
              _ChipRowSkeleton(),
              SizedBox(height: AppConstants.spacingL),

              // Stat card — 88 dp is 16 + 16 padding plus the value/label pair.
              ProfileShimmerBox(height: 88),
              SizedBox(height: AppConstants.spacingL),

              // About.
              ProfileShimmerBox(height: 110),
              SizedBox(height: AppConstants.spacingL),

              // Contact.
              ProfileShimmerBox(height: 150),
              SizedBox(height: AppConstants.spacingXXL),

              // Listings: section label + two rows at the real 95 dp height.
              ProfileShimmerBox(height: 16, width: 110, radius: 4),
              SizedBox(height: AppConstants.spacingM),
              ProfileShimmerBox(height: 95),
              SizedBox(height: AppConstants.spacingM),
              ProfileShimmerBox(height: 95),
            ],
          ),
        ),

        SizedBox(
          height:
              kProfileSkeletonBottomSpace +
              MediaQuery.paddingOf(context).bottom,
        ),
      ],
    );
  }
}

/// Clearance so the skeleton's last row is not hidden behind the sticky bar's
/// eventual position.
const double kProfileSkeletonBottomSpace = 96;

/// The avatar's placeholder, sized and ringed exactly like [PublicProfileAvatar]
/// so the real image lands without a shift.
///
/// Handed to `PublicProfileCoverHeader.avatarOverlay` during the first load
/// rather than drawn here — the header is the only place an overhanging avatar
/// can live without being painted over by the pinned bar.
class PublicProfileAvatarSkeleton extends StatelessWidget {
  const PublicProfileAvatarSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: kPublicAvatarSize,
    height: kPublicAvatarSize,
    decoration: BoxDecoration(
      color: AppColors.hairline,
      shape: BoxShape.circle,
      border: Border.all(color: AppColors.background, width: 4),
    ),
  );
}

class _ChipRowSkeleton extends StatelessWidget {
  const _ChipRowSkeleton();

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable, like the real `TrustChipStrip` it stands in for.
    //
    // The three placeholder pills total 308 dp (92 + 8 + 120 + 8 + 80), which
    // overflowed the 288 dp available at 320 dp width by exactly 20 px and painted
    // Flutter's hatching over the loading state. Giving the Row an unbounded
    // viewport removes the overflow and matches the widget being placeheld;
    // `NeverScrollableScrollPhysics` keeps a placeholder from being draggable.
    // Found by test/public_profile_device_validation_test.dart.
    return const SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: NeverScrollableScrollPhysics(),
      child: Row(
        children: [
          ProfileShimmerBox(
            height: 28,
            width: 92,
            radius: AppConstants.pillRadius,
          ),
          SizedBox(width: AppConstants.spacingS),
          ProfileShimmerBox(
            height: 28,
            width: 120,
            radius: AppConstants.pillRadius,
          ),
          SizedBox(width: AppConstants.spacingS),
          ProfileShimmerBox(
            height: 28,
            width: 80,
            radius: AppConstants.pillRadius,
          ),
        ],
      ),
    );
  }
}
