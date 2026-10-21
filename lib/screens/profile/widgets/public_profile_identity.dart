// screens/profile/widgets/public_profile_identity.dart
//
// The identity zone: overhanging avatar, name + role pill, role subtitle,
// @handle, inline rating, meta strip, and the trust chips beneath.
//
// Role colour and label come from the existing `profile_role.dart` via
// `public_profile_role.dart`, so the role pill here and on the own-profile screen
// cannot diverge.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/profile_review.dart';
import '../../../models/user_profile.dart';
import '../../../services/profile_connection_service.dart';
import '../public_profile_role.dart';
import 'public_profile_cover_header.dart';
import 'public_profile_sticky_bar.dart' show ConnectActionButton;

/// Large avatar that straddles the cover's bottom edge.
///
/// Reproduces `ProfileCoverHeader`'s treatment exactly — 88 dp, `primaryLight`
/// fill, 4 dp ring in the page background, a 24 dp verified disc bottom-right —
/// but takes its verified condition from [UserProfile.isVerified] (the portal's
/// rule) rather than the own-profile screen's `userRole != null`.
class PublicProfileAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final bool isVerified;

  /// Tag for the flight from whichever surface was tapped. Null disables the
  /// Hero, which is what a screen with no matching source should pass.
  final String? heroTag;

  const PublicProfileAvatar({
    super.key,
    required this.avatarUrl,
    required this.initials,
    required this.isVerified,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = avatarUrl != null && avatarUrl!.isNotEmpty;

    Widget avatar = Container(
      width: kPublicAvatarSize,
      height: kPublicAvatarSize,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        shape: BoxShape.circle,
        // Accent ring instead of a plain white one — the reference cover-card
        // design uses a coloured ring around the avatar.
        border: Border.all(color: AppColors.primary, width: 3),
      ),
      child: ClipOval(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                width: kPublicAvatarSize,
                height: kPublicAvatarSize,
                errorWidget: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );

    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }

    return Semantics(
      image: true,
      label: hasImage ? 'Profile photo' : 'No profile photo',
      child: SizedBox(
        width: kPublicAvatarSize,
        height: kPublicAvatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            hasImage
                ? ScaleTap(onTap: () => _openFullScreen(context), child: avatar)
                : avatar,
            if (isVerified)
              Positioned(
                right: 2,
                bottom: 2,
                child: Semantics(
                  label: 'Verified',
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.background,
                        width: 2.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Center(
    child: Text(
      initials,
      style: AppTextStyles.heading1.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: AppColors.primary,
      ),
    ),
  );

  /// Full-screen viewer. `photo_view` is already a dependency and is used the
  /// same way by the gallery, so no new package is needed for this.
  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _FullScreenAvatar(imageUrl: avatarUrl!),
      ),
    );
  }
}

class _FullScreenAvatar extends StatelessWidget {
  final String imageUrl;

  const _FullScreenAvatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tap anywhere outside to dismiss — the gesture people try first.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: PhotoView(
                imageProvider: CachedNetworkImageProvider(imageUrl),
                backgroundDecoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name + role pill + subtitle + handle, with an optional Follow/Share action
/// pair alongside it.
///
/// The Follow/Share controls are entirely optional (default: hidden) and,
/// when shown, are wired to the exact same connect/share handlers and
/// [ProfileConnectionStatus] the bottom `ProfileStickyActionBar` already
/// uses — this reuses `ConnectActionButton` as-is rather than introducing any
/// new connection logic, so having the control appear here as well changes
/// nothing about how connecting or sharing actually works.
class PublicIdentityBlock extends StatelessWidget {
  final UserProfile profile;

  /// Viewing your own profile — Follow/Share are never shown here, matching
  /// `ProfileStickyActionBar.isSelf`.
  final bool isSelf;
  final bool viewerSignedIn;
  final ProfileConnectionStatus connectionStatus;
  final bool statusLoading;

  /// Null hides the Follow control entirely (mirrors the bottom bar's rule
  /// for an unresolved/unavailable connect action).
  final VoidCallback? onConnect;

  /// Null hides the Share icon.
  final VoidCallback? onShare;

  const PublicIdentityBlock({
    super.key,
    required this.profile,
    this.isSelf = true,
    this.viewerSignedIn = false,
    this.connectionStatus = ProfileConnectionStatus.none,
    this.statusLoading = false,
    this.onConnect,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final title = profile.displayTitle ?? 'PropCid user';
    final tint = roleColor(profile.userType);
    final handle = profile.username;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrap, not Row: a long company name must push the pill onto the next
        // line rather than clipping it. Same choice `ProfileIdentityBlock` makes.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppConstants.spacingS,
          runSpacing: 6,
          children: [
            Text(
              title,
              style: AppTextStyles.heading2.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                // Poppins' default line box is looser than the design's; pinning
                // this is what keeps a two-line name from over-spacing. Same fix
                // `MetricCard` documents.
                height: 1.15,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              ),
              child: Text(
                roleBadge(profile.userType),
                style: AppTextStyles.chip.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          roleSubtitle(profile.userType),
          style: AppTextStyles.caption.copyWith(fontSize: 12.5),
        ),
        // Omitted entirely when there is no username — never a fabricated
        // placeholder. `ProfileIdentityBlock` sets the same rule.
        if (handle != null) ...[
          const SizedBox(height: 3),
          Text(
            handle.startsWith('@') ? handle : '@$handle',
            style: AppTextStyles.caption.copyWith(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );

    if (isSelf || !viewerSignedIn) return identity;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: identity),
        const SizedBox(width: AppConstants.spacingS),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConnectActionButton(
                status: connectionStatus,
                isLoading: statusLoading,
                onTap: onConnect,
              ),
              if (onShare != null) ...[
                const SizedBox(width: 8),
                _ShareIconButton(onTap: onShare!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Plain outlined circular share button — the identity block's compact
/// companion to [ConnectActionButton], for the same [onShare] the bottom
/// sticky bar's share action already uses.
class _ShareIconButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShareIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Share this profile',
      button: true,
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardBackground,
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Icon(
              Icons.ios_share_rounded,
              size: 18,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// `4.6 ★★★★☆ (23 reviews)`, or a muted line when nobody has rated yet.
class RatingInlineRow extends StatelessWidget {
  final RatingSummary rating;
  final bool isLoading;
  final VoidCallback? onTap;

  const RatingInlineRow({
    super.key,
    required this.rating,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Text(
        'Loading rating…',
        style: AppTextStyles.caption.copyWith(fontSize: 12.5),
      );
    }

    if (!rating.hasRatings) {
      return Text(
        'No reviews yet',
        style: AppTextStyles.caption.copyWith(fontSize: 12.5),
      );
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rating.average.toStringAsFixed(1),
          maxLines: 1,
          style: AppTextStyles.heading3.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(width: 6),
        StarRow(value: rating.average, size: 14),
        const SizedBox(width: 6),
        // Flexible, for the same reason as `_MetaCell`: the value and the five
        // stars are fixed, so the review count is the only part that can give.
        // Unbounded it overflowed by 20 px at 320 dp, and a four-digit count
        // ("(1,204 reviews)") or a raised text scale makes that worse. Found by
        // test/public_profile_device_validation_test.dart.
        Flexible(
          child: Text(
            '(${rating.count} ${rating.count == 1 ? 'review' : 'reviews'})',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );

    // One label for the whole row. Five separate star icons would be announced
    // individually, which is noise.
    final labelled = Semantics(
      label:
          'Rated ${rating.average.toStringAsFixed(1)} out of 5 '
          'from ${rating.count} reviews',
      button: onTap != null,
      child: ExcludeSemantics(child: row),
    );

    return onTap == null ? labelled : ScaleTap(onTap: onTap, child: labelled);
  }
}

/// Five stars filled to [value].
///
/// `AppColors.warning` for a filled star and `hairlineStrong` for an empty one —
/// the palette has no amber token, and inventing one would breach the no-new-
/// tokens rule.
class StarRow extends StatelessWidget {
  final double value;
  final double size;

  const StarRow({super.key, required this.value, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final filled = value.round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            Icons.star_rounded,
            size: size,
            color: star <= filled
                ? AppColors.warning
                : AppColors.hairlineStrong,
          ),
      ],
    );
  }
}

/// City · experience · specialisation, separated by hairline rules.
///
/// Stacks vertically once the text scale passes 1.3, where three cells and two
/// rules can no longer share a line without clipping.
class IdentityMetaStrip extends StatelessWidget {
  final UserProfile profile;

  const IdentityMetaStrip({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];

    final city = profile.effectiveCity;
    if (city != null) {
      cells.add(_MetaCell(icon: Icons.place_outlined, label: city));
    }

    if (profile.hasExperienceField) {
      final years = profile.effectiveExperience ?? 0;
      cells.add(
        _MetaCell(
          icon: Icons.work_outline_rounded,
          label: '$years ${years == 1 ? 'yr' : 'yrs'} experience',
        ),
      );
    }

    if (profile.specialization.isNotEmpty) {
      cells.add(
        _MetaCell(
          icon: Icons.apartment_rounded,
          label: profile.specialization.take(2).join(', '),
        ),
      );
    }

    if (cells.isEmpty) return const SizedBox.shrink();

    // `>=`, not `>`: at exactly 1.3x this evaluates to 15.6, so the strict form
    // failed to stack at the one scale the spec promises to support — the same
    // off-by-a-hair as `_DetailRowView`. Found by
    // test/public_profile_device_validation_test.dart.
    final stacked = MediaQuery.textScalerOf(context).scale(12) >= 15.5;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            cells[i],
          ],
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 6,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: AppColors.hairline,
            ),
          cells[i],
        ],
      ],
    );
  }
}

class _MetaCell extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaCell({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 5),
        // Flexible + ellipsis, not a bare Text.
        //
        // `Wrap` hands each child its own maxWidth (the strip's full width), so
        // an unconstrained Text here overflows rather than wrapping: two long
        // specialisations ("Luxury Residential Redevelopment, Commercial
        // Leasing") measured 133 px past the available 358 at 390 dp. Found by
        // test/public_profile_device_validation_test.dart.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// One horizontally scrolling row of data-backed trust chips.
///
/// Every chip resolves from a real column. The portal's four static tiles
/// ("Quick Response / Always Available", "Best Deals / Market Expertise",
/// "Client Focused / Satisfaction First") have no data behind them and are
/// deliberately not reproduced.
class TrustChipStrip extends StatelessWidget {
  final UserProfile profile;

  const TrustChipStrip({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (profile.verificationStatus?.toLowerCase() == 'verified') {
      chips.add(
        const _TrustChip(
          icon: Icons.verified_rounded,
          label: 'Verified',
          foreground: AppColors.verifiedBadge,
          background: Color(0x1F10B981),
        ),
      );
    }

    final rera = profile.effectiveRera;
    if (rera != null) {
      chips.add(
        _TrustChip(
          icon: Icons.shield_outlined,
          label: 'RERA $rera',
          foreground: AppColors.primary,
          background: AppColors.primaryLight,
        ),
      );
    }

    final created = profile.createdAt;
    if (created != null) {
      chips.add(
        _TrustChip(
          icon: Icons.calendar_today_outlined,
          label: 'Member since ${created.year}',
          foreground: AppColors.textSecondary,
          background: AppColors.surfaceMuted,
        ),
      );
    }

    final company = profile.companyName;
    if (company != null && !profile.isIndividual) {
      chips.add(
        _TrustChip(
          icon: Icons.business_outlined,
          label: company,
          foreground: AppColors.primary,
          background: AppColors.primaryLight,
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: AppConstants.spacingS),
            chips[i],
          ],
        ],
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _TrustChip({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.chip.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
