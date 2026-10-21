import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Cover banner with the menu / notification actions and the overhanging
/// avatar (blueprint §4.1).
///
/// Renders `profiles.background_image_url` when set (same field
/// `EditProfileProvider.pickAndUploadCover` writes), falling back to the
/// static branded gradient otherwise — mirroring how
/// `PublicProfileCoverHeader` already displays another user's cover photo.
class ProfileCoverHeader extends StatelessWidget {
  final String? avatarUrl;
  final String initial;

  /// `profiles.background_image_url`. Null/empty falls back to the gradient.
  final String? coverImageUrl;

  /// Drives the avatar's check badge. Ported from the existing screen's
  /// `auth.userRole != null` condition — "verified" is not redefined here.
  final bool isVerified;

  final VoidCallback onMenuTap;
  final VoidCallback onNotificationsTap;

  /// Shows the unread dot on the bell.
  final bool hasNotifications;

  const ProfileCoverHeader({
    super.key,
    required this.avatarUrl,
    required this.initial,
    required this.isVerified,
    required this.onMenuTap,
    required this.onNotificationsTap,
    this.coverImageUrl,
    this.hasNotifications = true,
  });

  /// Prototype: 172 dp cover, 88 dp avatar hanging 42 dp below it.
  static const double _kCoverHeight = 172;
  static const double _kAvatarSize = 88;
  static const double _kAvatarOverhang = 42;

  /// Total height the header occupies, including the overhang.
  static const double totalHeight = _kCoverHeight + _kAvatarOverhang + 4;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return SizedBox(
      height: totalHeight + topInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Cover ────────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            child: SizedBox(
              height: _kCoverHeight + topInset,
              width: double.infinity,
              child: (coverImageUrl == null || coverImageUrl!.isEmpty)
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.heroGradient,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: coverImageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                        ),
                      ),
                      errorWidget: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: AppColors.heroGradient,
                        ),
                      ),
                    ),
            ),
          ),
          // Soft shade at the top (keeps the glass buttons legible over any
          // cover photo) and a warm glow along the bottom edge.
          IgnorePointer(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
              child: SizedBox(
                height: _kCoverHeight + topInset,
                width: double.infinity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x40000000),
                        Color(0x00000000),
                        Color(0x00000000),
                        Color(0x33C2410C),
                      ],
                      stops: [0.0, 0.4, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
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
                _GlassIconButton(
                  icon: Icons.menu,
                  semanticLabel: 'Open menu',
                  onTap: onMenuTap,
                ),
                _GlassIconButton(
                  icon: Icons.notifications_outlined,
                  semanticLabel: 'Notifications',
                  onTap: onNotificationsTap,
                  showDot: hasNotifications,
                ),
              ],
            ),
          ),

          // ── Avatar ───────────────────────────────────────────────────────
          Positioned(
            left: 20,
            top: topInset + _kCoverHeight - (_kAvatarSize - _kAvatarOverhang),
            child: _Avatar(
              size: _kAvatarSize,
              avatarUrl: avatarUrl,
              initial: initial,
              isVerified: isVerified,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool showDot;

  const _GlassIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              // Frosted glass bubble over the cover photo.
              ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.24),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Icon(icon, size: 19, color: Colors.white),
                  ),
                ),
              ),
              if (showDot)
                Positioned(
                  top: 8,
                  right: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 1.5,
                      ),
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

class _Avatar extends StatelessWidget {
  final double size;
  final String? avatarUrl;
  final String initial;
  final bool isVerified;

  const _Avatar({
    required this.size,
    required this.avatarUrl,
    required this.initial,
    required this.isVerified,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initial,
        style: AppTextStyles.heading1.copyWith(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 4,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4DF97316),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: avatarUrl == null
                  ? fallback
                  : CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      width: size,
                      height: size,
                      errorWidget: (_, _, _) => fallback,
                    ),
            ),
          ),
          if (isVerified)
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
