// screens/search/widgets/people_result_card.dart
//
// One person in the People Search list, and its loading placeholder.
//
// WHAT IS SHOWN, AND WHERE EACH FIELD COMES FROM
// ----------------------------------------------
//   avatar          `avatar_url`, initials fallback   SearchModal.tsx:477-488
//   name            `display_name`                    BrokersList.tsx:156
//   role pill       `user_type`                       Search.tsx:2770-2775
//   company         `company_name || agency_name`     BrokersList.tsx:159-162
//   username        `username`                        (not on any portal card — G7)
//   city            `city || work_city`               BrokersList.tsx:168
//   experience      `years_experience || years_of_experience`  BrokersList.tsx:127
//   rating          `user_ratings` average            ExploreCity.tsx:226-235
//   verified badge  `verification_status || rera_number || license_number`
//
// Every one of those is a value the portal already reads. Nothing is derived from
// a column the portal does not use, and nothing new is computed.
//
// THE VERIFIED BADGE IS DATA-DRIVEN HERE, AND IS NOT IN THE PORTAL
// ---------------------------------------------------------------
// `BrokersList.tsx:135-137`, `BuildersList.tsx:127-129` and
// `InfluencersList.tsx` all render `<ShieldCheck/>` unconditionally, so every
// listed broker, builder and influencer appears verified whatever their
// `verification_status` says. That is reported as a portal defect (D2) rather
// than reproduced: this card gates the badge on `UserProfile.isVerified`, the
// same condition the Public Profile screen uses.
//
// No new design tokens. Colours, type and spacing are existing AppColors /
// AppTextStyles / AppConstants values, and the role pill reuses `roleColor` /
// `roleBadge` so a person's role reads identically here and on their profile.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/number_format.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/people_search_result.dart';
import '../../profile/public_profile_role.dart';

/// Avatar diameter. 56 is the size `Search.tsx:2758` uses for its people cards.
const double kPeopleAvatarSize = 56;

class PeopleResultCard extends StatelessWidget {
  final PersonResult result;

  /// Opens the person's public profile. Supplied by the screen so this widget
  /// stays presentational and testable without a Navigator.
  final VoidCallback onTap;

  const PeopleResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final profile = result.profile;

    // `display_name` is the heading, NOT `displayTitle`. `displayTitle` prefers
    // the company name — right for a profile header, wrong for a people search
    // result, where the portal's cards lead with the person and put the company
    // underneath (BrokersList.tsx:156-162, SearchModal.tsx:492-500).
    final name =
        _firstNonEmpty([profile.displayName, profile.companyName]) ??
        'PropCid Member';
    final company = _firstNonEmpty([profile.companyName, profile.agencyName]);
    // Suppressed when it is the heading already, which happens for a profile
    // that has a company name and no display name.
    final subtitle = company == name ? null : company;

    final username = _firstNonEmpty([profile.username]);
    final city = _firstNonEmpty([profile.effectiveCity]);
    final experience = profile.effectiveExperience;
    final rating = result.rating;
    final rera = _firstNonEmpty([profile.effectiveRera]);

    final metaChips = <Widget>[
      if (city != null) _MetaBit(icon: Icons.location_on_outlined, label: city),
      if (experience != null && experience > 0)
        _MetaBit(
          icon: Icons.work_outline_rounded,
          label: '$experience yr${experience == 1 ? '' : 's'} exp',
        ),
      if (rating != null && rating.hasRatings)
        _MetaBit(
          icon: Icons.star_rounded,
          iconColor: AppColors.warning,
          label: '${formatRating(rating.average)} (${rating.count})',
        ),
    ];

    return ScaleTap(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: _semanticLabel(
          name: name,
          role: roleLabel(profile.userType),
          company: subtitle,
          city: city,
          experience: experience,
          rating: rating?.hasRatings == true ? rating : null,
          verified: profile.isVerified,
        ),
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              boxShadow: AppColors.surfaceCardShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PeopleAvatar(
                  avatarUrl: profile.avatarUrl,
                  initials: profile.initials,
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.heading3.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (profile.isVerified) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.verified_rounded,
                              size: 15,
                              color: AppColors.verifiedBadge,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _RolePill(userType: profile.userType),
                          if (subtitle != null) ...[
                            const SizedBox(width: AppConstants.spacingS),
                            Flexible(
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (username != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                      if (metaChips.isNotEmpty) ...[
                        const SizedBox(height: AppConstants.spacingS),
                        // Scrollable rather than wrapping: three bits of meta at
                        // a 1.3x text scale exceed the width of a 320 dp phone,
                        // and a second line would make the cards uneven.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          child: Row(
                            children: [
                              for (var i = 0; i < metaChips.length; i++) ...[
                                if (i > 0)
                                  const SizedBox(width: AppConstants.spacingM),
                                metaChips[i],
                              ],
                            ],
                          ),
                        ),
                      ],
                      if (rera != null) ...[
                        const SizedBox(height: 6),
                        _ReraTag(rera: rera),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One sentence for a screen reader, instead of the eight fragments the visual
  /// layout is made of.
  static String _semanticLabel({
    required String name,
    required String role,
    String? company,
    String? city,
    int? experience,
    dynamic rating,
    required bool verified,
  }) {
    final parts = <String>[name, role];
    if (verified) parts.add('verified');
    if (company != null) parts.add('at $company');
    if (city != null) parts.add(city);
    if (experience != null && experience > 0) {
      parts.add('$experience years experience');
    }
    if (rating != null) {
      parts.add(
        'rated ${formatRating(rating.average)} from ${rating.count} '
        '${rating.count == 1 ? 'review' : 'reviews'}',
      );
    }
    return parts.join(', ');
  }
}

/// First non-blank string, or null.
///
/// The same `''`-is-falsy rule `UserProfile._firstText` applies: the portal is
/// JavaScript, where an empty string loses to the next candidate, and Dart's `??`
/// would keep it.
String? _firstNonEmpty(List<String?> candidates) {
  for (final value in candidates) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// A person's avatar, with initials behind it.
///
/// Public so the Search entry screen's People preview rows draw the same circle
/// at a smaller size instead of keeping a second copy of the fallback rule.
class PeopleAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double size;

  const PeopleAvatar({
    super.key,
    required this.avatarUrl,
    required this.initials,
    this.size = kPeopleAvatarSize,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials,
        style: AppTextStyles.heading3.copyWith(
          // Scales with the circle so the 34 dp dropdown variant is not filled
          // edge to edge by two capitals.
          fontSize: size * 0.30,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    final url = avatarUrl;

    return Container(
      width: size,
      height: size,
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
                width: size,
                height: size,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  final String? userType;

  const _RolePill({required this.userType});

  @override
  Widget build(BuildContext context) {
    final color = roleColor(userType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        roleBadge(userType),
        style: AppTextStyles.chip.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

class _MetaBit extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _MetaBit({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: iconColor ?? AppColors.textHint),
        const SizedBox(width: 3),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// RERA / licence number, shown when the profile carries one.
///
/// The portal prints a RERA number on a *project* card
/// (`SearchModal.tsx:438-445`) but never on a people card, even though the
/// verified shield it always draws is partly derived from the same column. This
/// shows the number the badge is actually claiming.
class _ReraTag extends StatelessWidget {
  final String rera;

  const _ReraTag({required this.rera});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RERA',
            style: AppTextStyles.chip.copyWith(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              rera,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The loading placeholder.
///
/// Same 56 dp circle, same three text bars and the same card box as the real
/// card, so nothing shifts when the page lands. The portal's directories show
/// eight of these (`BrokersList.tsx:111-122`); the shimmer recipe is the app's
/// existing `grey[300]`/`grey[100]` one.
class PeopleResultSkeleton extends StatelessWidget {
  const PeopleResultSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: kPeopleAvatarSize,
              height: kPeopleAvatarSize,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _SkeletonBar(width: 150, height: 14),
                  SizedBox(height: AppConstants.spacingS),
                  _SkeletonBar(width: 100, height: 11),
                  SizedBox(height: 6),
                  _SkeletonBar(width: 130, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;

  const _SkeletonBar({required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
