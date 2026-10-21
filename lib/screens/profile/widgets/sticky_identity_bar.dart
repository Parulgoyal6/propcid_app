// screens/profile/widgets/sticky_identity_bar.dart
//
// The small pinned "avatar + name" bar that stays fixed at the top once a
// profile screen has scrolled its cover photo away — used by both
// `profile_screen.dart` (personal) and `public_profile_screen.dart` (any
// other user), so the two screens share one definition rather than two
// near-duplicate implementations.
//
// OVERLAY, NOT AN IN-FLOW PINNED SLIVER
// --------------------------------------
// An earlier version of this file put the bar in a pinned `SliverPersistentHeader`
// sitting directly after the cover in each screen's `CustomScrollView`. A pinned
// sliver still renders at its normal position in the list before any scrolling
// happens — so the compact bar was visible immediately below the cover, at the
// same time as the real overhanging avatar and name text a little further down.
// That showed the profile picture (and name) twice at once.
//
// `StickyIdentityOverlay` fixes that by not being part of the scrolling list at
// all: it is a `Positioned` overlay drawn on top of the ordinary
// `SingleChildScrollView`, hidden until the real identity block (tracked via
// [identityKey]) has scrolled up behind where this bar sits, and hidden again
// once it scrolls back into view — so the real content and this bar are never
// on-screen together.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Height of the pinned bar.
const double kStickyIdentityBarHeight = 60;

/// Shows [StickyIdentityBar] pinned at the top of the screen, but only once
/// [identityKey]'s widget (the real, in-flow avatar/name block) has scrolled
/// up past where this bar sits — so the two are never visible together.
///
/// Place as a direct child of a `Stack` whose other child is the screen's
/// scroll view, with [scrollController] the same controller driving that
/// scroll view.
class StickyIdentityOverlay extends StatefulWidget {
  final ScrollController scrollController;
  final GlobalKey identityKey;
  final String? avatarUrl;
  final String initials;
  final String name;

  const StickyIdentityOverlay({
    super.key,
    required this.scrollController,
    required this.identityKey,
    required this.avatarUrl,
    required this.initials,
    required this.name,
  });

  @override
  State<StickyIdentityOverlay> createState() => _StickyIdentityOverlayState();
}

class _StickyIdentityOverlayState extends State<StickyIdentityOverlay> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant StickyIdentityOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final renderObject = widget.identityKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;

    final topInset = MediaQuery.of(context).padding.top;
    // Only once the real block's own top edge has scrolled up behind where
    // this bar would sit is there no risk of the two overlapping/doubling.
    final shouldShow =
        renderObject.localToGlobal(Offset.zero).dy <
        topInset + kStickyIdentityBarHeight;

    if (shouldShow != _visible) setState(() => _visible = shouldShow);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topInset,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _visible ? 1 : 0,
          child: StickyIdentityBar(
            avatarUrl: widget.avatarUrl,
            initials: widget.initials,
            name: widget.name,
            docked: true,
          ),
        ),
      ),
    );
  }
}

/// The bar's actual content — a small avatar circle and the display name,
/// on a plain surface that only shows its shadow once [docked] (i.e. once
/// content is genuinely scrolling underneath it).
class StickyIdentityBar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final String name;
  final bool docked;

  const StickyIdentityBar({
    super.key,
    required this.avatarUrl,
    required this.initials,
    required this.name,
    this.docked = false,
  });

  static const double _avatarSize = 38;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials.isEmpty ? 'U' : initials,
        style: AppTextStyles.caption.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: kStickyIdentityBarHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        boxShadow: docked
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: const BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: avatarUrl == null || avatarUrl!.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      width: _avatarSize,
                      height: _avatarSize,
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isNotEmpty ? name : 'Profile',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.heading3.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
