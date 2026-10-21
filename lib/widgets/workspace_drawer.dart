import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/launch_features.dart';
import '../core/constants/app_constants.dart';
import '../core/navigation/workspace_destinations.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/scale_tap.dart';
import '../providers/auth_provider.dart';

/// Left slide-in navigation panel opened from the Profile header, giving
/// access to the full destination set (blueprint §16.2).
///
/// Built on Flutter's native [Drawer] rather than a bespoke overlay, per §7's
/// stated preference: it matches the prototype's 280 dp width and scrim while
/// providing swipe-to-dismiss, back-button handling, focus traversal and
/// screen-reader semantics for free. The native settle duration (246 ms) is
/// close enough to the prototype's 280 ms not to read as different.
///
/// Every row delegates to [WorkspaceDestinations] so this and the More bottom
/// sheet can never diverge.
class WorkspaceDrawer extends StatelessWidget {
  const WorkspaceDrawer({super.key});

  /// Prototype: 280 dp panel.
  static const double _kWidth = 280;

  /// Prototype scrim: `rgba(26,26,46,0.45)`. Applied by the host Scaffold via
  /// `drawerScrimColor`.
  ///
  /// Kept light so the screen stays visible behind the frosted panel.
  static const Color scrimColor = Color(0x331A1A2E);

  /// Closes the drawer, then runs a navigation action.
  ///
  /// The [NavigatorState] is captured before dismissal because the drawer's
  /// own context is deactivated once it closes.
  void _navigate(BuildContext context, void Function(NavigatorState) action) {
    final navigator = Navigator.of(context);
    navigator.pop();
    action(navigator);
  }

  /// Closes the drawer, then shows a sheet/dialog. Uses the navigator's own
  /// context, which outlives the drawer and still sits below the providers.
  void _overlay(BuildContext context, void Function(BuildContext) action) {
    final navigator = Navigator.of(context);
    navigator.pop();
    action(navigator.context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Additive, never a replacement — `ProfileDashboardShell.tsx:693-708`'s
    // nav link only ever appears alongside an existing role's own dashboard.
    // Excluding `userType == 'team_member'` avoids a redundant second entry
    // to the same screen "Manage Dashboard" already resolves to for that
    // population (`ManageDashboardDispatcher`'s `team_member` case).
    final showTeamWorkspace =
        auth.hasTeamMembership && auth.userType != 'team_member';

    return Drawer(
      width: _kWidth,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      // Frosted glass panel: strong blur of the screen behind it, a
      // translucent white fill with a faint warm tint, and a bright rim.
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xB8FFFFFF), Color(0xA6FFF4EA)],
            ),
            border: Border(
              right: BorderSide(color: Color(0xE6FFFFFF), width: 1.2),
            ),
          ),
          child: SafeArea(
        child: Column(
          children: [
            const _DrawerHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                children: [
                  _row(
                    context,
                    Icons.home_outlined,
                    'Home',
                    onNavigate: WorkspaceDestinations.home,
                    isActive: true,
                  ),
                  _row(
                    context,
                    Icons.grid_view_rounded,
                    'Manage Dashboard',
                    onNavigate: WorkspaceDestinations.manageDashboard,
                  ),
                  if (showTeamWorkspace)
                    _row(
                      context,
                      Icons.groups_outlined,
                      'Team Workspace',
                      onNavigate: WorkspaceDestinations.teamWorkspace,
                    ),
                  _row(
                    context,
                    Icons.dynamic_feed_outlined,
                    'Feed',
                    onNavigate: WorkspaceDestinations.feed,
                  ),
                  _row(
                    context,
                    Icons.movie_outlined,
                    'PropClips',
                    onNavigate: WorkspaceDestinations.reels,
                  ),
                  _row(
                    context,
                    Icons.chat_bubble_outline,
                    'Messages',
                    onNavigate: WorkspaceDestinations.messages,
                  ),
                  _row(
                    context,
                    Icons.people_outline,
                    'Network',
                    onNavigate: WorkspaceDestinations.network,
                  ),
                  if (LaunchFeatures.subscriptions) ...[
                    _row(
                      context,
                      Icons.trending_up_rounded,
                      'Upgrade',
                      onNavigate: WorkspaceDestinations.upgrade,
                    ),
                    _row(
                      context,
                      Icons.credit_card_outlined,
                      'Subscription & Billing',
                      onNavigate: WorkspaceDestinations.subscriptionBilling,
                    ),
                  ],
                  if (LaunchFeatures.metaPublishing)
                    _row(
                      context,
                      Icons.share_outlined,
                      'Social',
                      onNavigate: WorkspaceDestinations.social,
                    ),
                  _row(
                    context,
                    Icons.settings_outlined,
                    'Settings',
                    onOverlay: WorkspaceDestinations.settings,
                  ),
                  // Logout set apart from the navigation rows.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    child: Divider(
                      height: 1,
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  _row(
                    context,
                    Icons.logout_rounded,
                    'Logout',
                    isDestructive: true,
                    onOverlay: WorkspaceDestinations.logout,
                  ),
                ],
              ),
            ),
            const _DrawerFooter(),
          ],
        ),
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String label, {
    void Function(NavigatorState)? onNavigate,
    void Function(BuildContext)? onOverlay,
    bool isDestructive = false,
    bool isActive = false,
  }) {
    return _DrawerRow(
      icon: icon,
      label: label,
      isDestructive: isDestructive,
      isActive: isActive,
      onTap: () {
        if (onNavigate != null) {
          _navigate(context, onNavigate);
        } else if (onOverlay != null) {
          _overlay(context, onOverlay);
        }
      },
    );
  }
}

/// One menu row — icon, label and a trailing chevron, with an optional
/// highlighted/active treatment (the reference design's tinted "Home" row).
/// Kept local to this drawer rather than added to the shared
/// [ManageListTile] (also used by the Profile screen's Manage list and the
/// More bottom sheet), so neither of those surfaces is affected.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final Color foreground = isDestructive
        ? AppColors.error
        : (isActive ? Colors.white : AppColors.textPrimary);

    final Color iconColor = isDestructive
        ? AppColors.error
        : (isActive ? Colors.white : AppColors.primary);

    // Small glass badge behind each icon.
    final Color iconBoxColor = isDestructive
        ? AppColors.error.withValues(alpha: 0.1)
        : (isActive
              ? Colors.white.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.6));

    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: ScaleTap(
        onTap: onTap,
        scaleDown: 0.97,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
          decoration: BoxDecoration(
            // Orange only for the active row.
            gradient: isActive ? AppColors.ctaGradient : null,
            color: isActive
                ? null
                : (isDestructive
                      ? AppColors.error.withValues(alpha: 0.06)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive ? AppColors.ctaShadow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBoxColor,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: isActive ? 0.35 : 0.9,
                    ),
                  ),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
              if (!isDestructive)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.9)
                      : AppColors.textHint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar + name + verified badge + email + bio + Edit Profile + close
/// button, above a hairline divider.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  /// Same verified condition `UserProfile.isVerified` uses
  /// (`verification_status === 'verified' || license_number || rera_number`),
  /// applied to the raw `profiles` row `AuthProvider` already exposes via
  /// `profileRow` — no provider/model change, just reading fields that were
  /// already being fetched.
  bool _isVerified(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    return profile['verification_status']?.toString().toLowerCase() ==
            'verified' ||
        profile['license_number'] != null ||
        profile['rera_number'] != null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final initial = auth.userName.isNotEmpty
        ? auth.userName[0].toUpperCase()
        : 'U';
    final profile = auth.profileRow;
    final isVerified = _isVerified(profile);

    // Glass profile card at the top of the frosted panel.
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xC7FFFFFF), Color(0x8CFFE8D6)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: AppColors.glassShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                avatarUrl: auth.avatarUrl,
                initial: initial,
                isVerified: isVerified,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            auth.userName.isNotEmpty ? auth.userName : 'Guest',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body.copyWith(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 14,
                            color: AppColors.verifiedBadge,
                          ),
                        ],
                      ],
                    ),
                    if (auth.userEmail.isNotEmpty)
                      Text(
                        auth.userEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Close menu',
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _EditProfileButton(),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final bool isVerified;

  const _Avatar({
    required this.avatarUrl,
    required this.initial,
    this.isVerified = false,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initial,
        style: AppTextStyles.heading3.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4DF97316),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: avatarUrl == null
                ? fallback
                : ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: avatarUrl!,
                      fit: BoxFit.cover,
                      width: 45,
                      height: 45,
                      errorWidget: (_, _, _) => fallback,
                    ),
                  ),
          ),
          if (isVerified)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: AppColors.verifiedBadge,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The header's "Edit Profile" pill — same destination the Profile screen's
/// own Edit Profile action already uses (`profile_screen.dart`'s
/// `AppConstants.editProfileScreen` push), just reachable from the drawer too.
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Edit Profile',
      button: true,
      child: ScaleTap(
        onTap: () {
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.pushNamed(AppConstants.editProfileScreen);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: AppColors.ctaGradient,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            boxShadow: AppColors.ctaShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.edit_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                'Edit Profile',
                style: AppTextStyles.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      // Hardcoded to match the prototype. Reading the real build number needs
      // package_info_plus, which is not an approved dependency — documented
      // for a later milestone.
      child: Text(
        'Version 1.0.0',
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}
