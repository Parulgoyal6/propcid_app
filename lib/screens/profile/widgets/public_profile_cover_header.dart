// screens/profile/widgets/public_profile_cover_header.dart
//
// The cover at the top of the Public Profile screen.
//
// PLAIN BOX WIDGET, NOT A SLIVER — MIRRORS `ProfileCoverHeader` EXACTLY
// ----------------------------------------------------------------------
// A previous version was a `SliverAppBar` (pinned, with a collapsing
// flexibleSpace, an avatar fade animation and a collapsed-title swap-in)
// living inside a `CustomScrollView`. That gave this screen a completely
// different scrolling architecture from the own-profile screen's
// `ProfileCoverHeader`, which is a plain box sitting inside a
// `SingleChildScrollView`/`Column` and simply scrolls away with everything
// else. Per the explicit instruction to make this screen use the exact
// same scrolling structure as `ProfileScreen` — not an approximation of
// it — this is a full rewrite to a plain `StatelessWidget`, not a patch of
// the sliver version: no `SliverAppBar`, no pinning, no collapse fraction,
// no collapsed-title handoff. `public_profile_screen.dart` now places this
// as an ordinary `Column` child inside a `SingleChildScrollView`, same as
// `ProfileScreen` does with `ProfileCoverHeader`.
//
// GEOMETRY IS BORROWED, NOT INVENTED
// ----------------------------------
// 172 dp cover, 28 dp bottom corners, 88 dp avatar overhanging by 42 dp —
// every number still comes from `ProfileCoverHeader`, so the public and
// private profiles read as the same family. That widget is NOT modified.
//
// The cover image falls back to `AppColors.heroGradient` — the same
// fallback `ProfileCoverHeader` uses.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_circle_icon_button.dart';

/// Cover height, excluding the status bar — same number `ProfileCoverHeader`
/// uses.
const double kPublicCoverHeight = 172;

/// How far the 88 dp avatar hangs below the cover's bottom edge.
const double kPublicAvatarOverhang = 42;

/// Avatar diameter. Also read by `public_profile_identity.dart` and
/// `public_profile_skeleton.dart` for their own layout — kept exported
/// under this exact name.
const double kPublicAvatarSize = 88;

/// Total height this header reserves: the cover plus the avatar's overhang,
/// mirroring `ProfileCoverHeader.totalHeight`.
const double kPublicHeaderHeight = kPublicCoverHeight + kPublicAvatarOverhang + 4;

class PublicProfileCoverHeader extends StatelessWidget {
  /// `profiles.background_image_url`. Null/empty falls back to the gradient.
  final String? coverImageUrl;

  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onMore;

  /// The large overhanging avatar, supplied by the screen.
  ///
  /// Passed in rather than constructed here so this file needs no import of
  /// `public_profile_identity.dart`, which already imports this one for the
  /// geometry constants — that would be a cycle.
  final Widget? avatarOverlay;

  const PublicProfileCoverHeader({
    super.key,
    required this.coverImageUrl,
    required this.onBack,
    required this.onShare,
    required this.onMore,
    this.avatarOverlay,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: kPublicHeaderHeight + topInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Cover ────────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: SizedBox(
              height: kPublicCoverHeight + topInset,
              width: double.infinity,
              child: _CoverBackground(coverImageUrl: coverImageUrl),
            ),
          ),

          // ── Actions ──────────────────────────────────────────────────────
          Positioned(
            top: topInset + 14,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassCircleIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  semanticLabel: 'Back',
                  onTap: onBack,
                ),
                Row(
                  children: [
                    GlassCircleIconButton(
                      icon: Icons.share_outlined,
                      semanticLabel: 'Share this profile',
                      onTap: onShare,
                    ),
                    const SizedBox(width: 10),
                    GlassCircleIconButton(
                      icon: Icons.more_vert_rounded,
                      semanticLabel: 'More options',
                      onTap: onMore,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Avatar ───────────────────────────────────────────────────────
          // Same overhang math as `ProfileCoverHeader`'s own `_Avatar`
          // positioning — straddles the cover's bottom edge, sitting inside
          // this header's own reserved height, exactly like the own-profile
          // screen's avatar.
          if (avatarOverlay != null)
            Positioned(
              left: 20,
              top:
                  topInset +
                  kPublicCoverHeight -
                  (kPublicAvatarSize - kPublicAvatarOverhang),
              child: avatarOverlay!,
            ),
        ],
      ),
    );
  }
}

/// Cover photo (or gradient) and its legibility scrim.
class _CoverBackground extends StatelessWidget {
  final String? coverImageUrl;

  const _CoverBackground({required this.coverImageUrl});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _coverFill(context),
          // Bottom-up scrim: guarantees the glass buttons stay legible over
          // any photo, however light.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x001A1A2E),
                  Color(0x001A1A2E),
                  Color(0x8C1A1A2E),
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverFill(BuildContext context) {
    final url = coverImageUrl;
    if (url == null || url.isEmpty) return const _GradientCover();

    final width = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // A full-resolution cover decoded into a 172 dp box is the largest
      // avoidable allocation on this screen.
      memCacheWidth: (width * dpr).round(),
      placeholder: (_, _) => const _GradientCover(),
      errorWidget: (_, _, _) => const _GradientCover(),
    );
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(gradient: AppColors.heroGradient),
  );
}
