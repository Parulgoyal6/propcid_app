import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../providers/notification_provider.dart';

/// Home's top app bar: logo/brand dropdown + calendar/notifications/avatar
/// shortcuts. Purely presentational — every tap target below navigates to
/// exactly the same route it did in the previous inline `_buildAppBar`.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  /// The real PropCid wordmark — 862×203 px, transparent background,
  /// already brand-orange. Same file the rest of the app's branding
  /// declares in `pubspec.yaml`; sized here by height only (via
  /// `AspectRatio`) so it can never stretch or distort.
  static const String _logoAssetPath = 'assets/branding/propcid_logo.png';
  static const double _logoAspectRatio = 862 / 203;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: GlassCard(
        borderRadius: 24,
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        // Frosted glass bar — the warm orange light behind it glows through.
        // Fixed (never scrolls), so the live blur costs nothing per frame.
        opacity: 0.55,
        blurSigma: 20,
        highlight: true,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => _showLogoDropdown(context),
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: 'PropCid',
                        image: true,
                        child: SizedBox(
                          height: 25,
                          child: AspectRatio(
                            aspectRatio: _logoAspectRatio,
                            child: Image.asset(
                              _logoAssetPath,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Padding(
                        // The wordmark's own glyphs sit slightly above its
                        // bounding box's vertical centre (no descenders), so
                        // the arrow is nudged down a touch to optically (not
                        // just numerically) align with it, rather than with
                        // the wordmark's full — partly empty — box.
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Find. Compare. Own.',
                    style: AppTextStyles.caption.copyWith(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                _CircleIconButton(
                  icon: Icons.calendar_today_outlined,
                  onTap: () =>
                      Navigator.pushNamed(context, AppConstants.visitsScreen),
                ),
                const SizedBox(width: 10),
                // G-3: the badge was hard-coded `true`, so it showed a dot forever
                // whether or not anything was unread. It now watches the app-level
                // provider, which the realtime channel keeps current — a notification
                // arriving while this screen is open lights the dot without a refresh.
                _CircleIconButton(
                  icon: Icons.notifications_outlined,
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppConstants.notificationsScreen,
                  ),
                  badge: context.watch<NotificationProvider>().hasUnread,
                ),
                const SizedBox(width: 10),
                // Was the profile avatar (already one tap away via the bottom
                // nav's own Profile tab), which meant reaching Messages was
                // Profile -> Dashboard -> Messages. This is the direct
                // shortcut instead — same tap-target style as the calendar/
                // notifications icons beside it.
                _CircleIconButton(
                  icon: Icons.chat_bubble_outline_rounded,
                  onTap: () =>
                      Navigator.pushNamed(context, AppConstants.messagesScreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoDropdown(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFFFF6EE)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  shrinkWrap: true,
                  children: [
                    _buildDropdownItem(
                      context,
                      Icons.home_outlined,
                      'Home',
                      () => Navigator.pop(context),
                      isActive: true,
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.search_outlined,
                      'Search',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, AppConstants.searchScreen);
                      },
                    ),
                    // "Saved" (bookmark), not "Shortlist" (heart): this opens the
                    // saved-properties list; the heart icon means Like elsewhere.
                    _buildDropdownItem(
                      context,
                      Icons.bookmark_border_rounded,
                      'Saved',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          AppConstants.shortlistScreen,
                        );
                      },
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.calculate_outlined,
                      'EMI Calculator',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          AppConstants.emiCalculatorScreen,
                        );
                      },
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.compare_arrows_rounded,
                      'Compare Properties',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          AppConstants.comparePropertiesScreen,
                          arguments: {'propertyIds': <String>[]},
                        );
                      },
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.notifications_outlined,
                      'Notifications',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          AppConstants.notificationsScreen,
                        );
                      },
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.movie_outlined,
                      'PropClips',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, AppConstants.reelsScreen);
                      },
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.person_outline,
                      'Profile',
                      () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, AppConstants.profileScreen);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                      child: Divider(
                        height: 1,
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    _buildDropdownItem(
                      context,
                      Icons.info_outline,
                      'About PropCID',
                      () {
                        Navigator.pop(context);
                        _showAboutDialog(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One menu row: a tinted icon tile, the label and a chevron. The active row
  /// (Home) is an orange gradient with a glow.
  Widget _buildDropdownItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool isActive = false,
  }) {
    final Color fg = isActive ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: ScaleTap(
        onTap: onTap,
        scaleDown: 0.97,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          decoration: BoxDecoration(
            gradient: isActive ? AppColors.ctaGradient : null,
            color: isActive ? null : AppColors.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: isActive
                ? null
                : Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
            boxShadow: isActive ? AppColors.ctaShadow : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.24)
                      : AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isActive ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                    color: fg,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
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

  Future<void> _showAboutDialog(BuildContext context) async {
    // Reads pubspec.yaml's `version: X.Y.Z+N` as it was actually built into
    // this binary — a literal string here would go stale the moment the next
    // AAB ships with a bumped version.
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary),
            SizedBox(width: 8),
            Text('About PropCID'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PropCID is a modern real-estate application designed to make property search and visits seamless and efficient.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            Text('Version: ${info.version} (${info.buildNumber})'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: onTap,
      scaleDown: 0.9,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Small glass bubble — translucent white with a bright rim.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.glassGradient,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1FF97316),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 19),
          ),
          if (badge)
            Positioned(
              top: 5,
              right: 5,
              child:
                  Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.35, 1.35),
                        duration: 900.ms,
                        curve: Curves.easeInOut,
                      ),
            ),
        ],
      ),
    );
  }
}
