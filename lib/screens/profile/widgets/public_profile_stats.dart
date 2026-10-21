// screens/profile/widgets/public_profile_stats.dart
//
// The headline stat card and the Meta follower grid.
//
// `StatTripletCard` reproduces `ProfileStatsRow`'s geometry exactly — one white
// card, equal columns divided by 1 dp `hairlineStrong` rules, 16 dp bold values
// over 11.5 dp muted labels, a 34 x 16 shimmer box while loading and an em dash on
// failure. That widget is not modified and not reused: it is hard-wired to
// `ProfileStats`' three fixed labels (Followers / Reviews / Profile Views), and
// this screen shows a different, variable set. The shared behaviour that mattered
// — compact number formatting — lives in `core/utils/number_format.dart`.
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/number_format.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/user_profile.dart';
import '../../../widgets/shared/stat_kpi_card.dart';

/// One column of [StatTripletCard].
@immutable
class ProfileStatTile {
  final String label;

  /// Pre-formatted so the caller decides between a compact count and a rating.
  final String value;

  final VoidCallback? onTap;

  const ProfileStatTile({required this.label, required this.value, this.onTap});
}

/// Two or three stats in one divided card.
///
/// Two when the profile is an individual: the portal hides Connections for that
/// role (UserProfile.tsx:1131), and an empty third column would read as a
/// missing number rather than an absent concept.
class StatTripletCard extends StatelessWidget {
  final List<ProfileStatTile> tiles;
  final bool isLoading;
  final bool hasFailed;

  const StatTripletCard({
    super.key,
    required this.tiles,
    required this.isLoading,
    this.hasFailed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const _StatDivider(),
              Expanded(
                child: _StatTile(
                  tile: tiles[i],
                  isLoading: isLoading,
                  hasFailed: hasFailed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) => const VerticalDivider(
    width: 1,
    thickness: 1,
    color: AppColors.hairlineStrong,
    indent: 2,
    endIndent: 2,
  );
}

class _StatTile extends StatelessWidget {
  final ProfileStatTile tile;
  final bool isLoading;
  final bool hasFailed;

  const _StatTile({
    required this.tile,
    required this.isLoading,
    required this.hasFailed,
  });

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 34,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          )
        else
          // A dash on failure, never a zero: a zero is a claim, a dash is an
          // absence. `ProfileStatsRow` sets this rule.
          Text(
            hasFailed ? '—' : tile.value,
            style: AppTextStyles.heading3.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        const SizedBox(height: 2),
        Text(
          tile.label,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
        ),
      ],
    );

    final labelled = Semantics(
      label: isLoading
          ? '${tile.label} loading'
          : '${hasFailed ? 'unavailable' : tile.value} ${tile.label}',
      button: tile.onTap != null,
      child: ExcludeSemantics(child: body),
    );

    if (tile.onTap == null || isLoading) return labelled;
    return ScaleTap(onTap: tile.onTap, child: labelled);
  }
}

/// Meta-verified follower counts.
///
/// Reuses `MetricCard` / `MetricCardGrid` from the shared library verbatim, so
/// these tiles are pixel-identical to the dashboard's.
///
/// Visible to every viewer: all five columns are GRANTed to `anon` by
/// 20270312000000_social_follower_counts.sql ("so logged-out visitors see them
/// too"), so there is no auth gate here.
class SocialReachCard extends StatelessWidget {
  final UserProfile profile;

  const SocialReachCard({super.key, required this.profile});

  /// True when at least one count is present. The whole section is omitted
  /// otherwise rather than rendering an empty grid.
  static bool hasData(UserProfile profile) =>
      profile.igFollowersCount != null ||
      profile.igFollowsCount != null ||
      profile.fbFollowersCount != null;

  @override
  Widget build(BuildContext context) {
    final cards = <MetricCard>[
      if (profile.igFollowersCount != null)
        MetricCard(
          icon: Icons.camera_alt_outlined,
          value: formatCompactCount(profile.igFollowersCount!),
          label: 'Instagram followers',
        ),
      if (profile.igFollowsCount != null)
        MetricCard(
          icon: Icons.person_add_alt_outlined,
          value: formatCompactCount(profile.igFollowsCount!),
          label: 'Instagram following',
        ),
      if (profile.fbFollowersCount != null)
        MetricCard(
          icon: Icons.thumb_up_outlined,
          value: formatCompactCount(profile.fbFollowersCount!),
          label: 'Facebook followers',
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();

    final syncedAt = profile.socialFollowersSyncedAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MetricCardGrid(cards: cards),
        if (syncedAt != null) ...[
          const SizedBox(height: AppConstants.spacingS),
          Text(
            'Synced ${_relativeTime(syncedAt)}',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Short relative time — "2 hours ago", "3 days ago".
///
/// Hand-rolled rather than pulled from `date-fns`' Dart equivalent because the
/// app declares no such package and adding one is out of scope. Only the coarse
/// buckets a sync timestamp needs.
String _relativeTime(DateTime timestamp) {
  final delta = DateTime.now().difference(timestamp);

  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) {
    final m = delta.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (delta.inHours < 24) {
    final h = delta.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  if (delta.inDays < 30) {
    final d = delta.inDays;
    return '$d ${d == 1 ? 'day' : 'days'} ago';
  }
  final months = (delta.inDays / 30).floor();
  if (months < 12) return '$months ${months == 1 ? 'month' : 'months'} ago';
  final years = (delta.inDays / 365).floor();
  return '$years ${years == 1 ? 'year' : 'years'} ago';
}

/// Exposed for reuse by the reviews list, which needs the same wording.
String profileRelativeTime(DateTime timestamp) => _relativeTime(timestamp);
