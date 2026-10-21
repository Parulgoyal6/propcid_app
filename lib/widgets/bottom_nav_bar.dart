import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/scale_tap.dart';
import '../providers/navigation_provider.dart';
import '../screens/reels/reels_screen.dart';
import '../screens/reels/widgets/reel_controller_manager.dart';

class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int)? onTap;

  const BottomNavBar({super.key, required this.currentIndex, this.onTap});

  // How far the "+" button rises above the pill's top edge. The widget
  // reserves this much extra height above the pill and lays the button out
  // in it (not merely painting it there via a transform), so its whole face
  // is inside this widget's bounds and fully tappable.
  static const double _kButtonLift = 12.0;

  // The elevated "+" button, and the gap reserved for it in the Row.
  static const double _kButtonSize = 58.0;
  static const double _kCenterSlotWidth = 74.0;

  // Maximum width of the nav content before it stops growing. Prevents items
  // from becoming absurdly wide on tablets and large-screen foldables.
  static const double _kMaxContentWidth = 600.0;

  // Gap between the floating pill and the screen's edges (sides and bottom),
  // so the bar reads as a rounded island rather than a wall-to-wall bar.
  static const double _kFloatingMargin = 16.0;

  // Index of the Profile destination within this bar. Home 0, Search 1,
  // Reels 2, Profile 3 — the centre "+" occupies an unindexed slot.
  static const int _kProfileIndex = 3;

  /// Back to the Profile page from a Profile-tab screen that sits on top of it
  /// (or, if Profile isn't in the stack, opens it). Reuses the existing Profile
  /// route when there is one - same approach as the Reels tab - so tapping the
  /// tab never stacks a second Profile page.
  void _returnToProfile(BuildContext context) {
    final navigator = Navigator.of(context);
    var found = false;
    navigator.popUntil((route) {
      if (route.settings.name == AppConstants.profileScreen) {
        found = true;
        return true;
      }
      return route.isFirst;
    });
    if (!found) navigator.pushNamed(AppConstants.profileScreen);
  }

  void _defaultNavigation(BuildContext context, int index) {
    // Tapping Profile while already on Profile resets to the Profile root
    // rather than doing nothing, matching the prototype's `backToProfile`.
    //
    // The check reads the *route name* rather than `currentIndex` on purpose:
    // some screens pass a currentIndex that doesn't match the route they are
    // on, and keying off the route keeps this branch from firing on them.
    // Routes without forwarded RouteSettings report a null name, so they
    // simply fall through to the existing behaviour below.
    if (index == _kProfileIndex &&
        ModalRoute.of(context)?.settings.name == AppConstants.profileScreen) {
      // `route.isFirst` is a safety stop: if the Profile route were ever
      // reached without its settings, popUntil would otherwise unwind the
      // entire stack.
      Navigator.of(context).popUntil(
        (route) =>
            route.settings.name == AppConstants.profileScreen || route.isFirst,
      );
      return;
    }

    if (currentIndex == index) {
      // A screen that belongs to the Profile tab (the role dashboards,
      // Notifications, Visits) but is not the Profile page itself: tapping
      // Profile must bring the user back to the Profile page, not do nothing.
      if (index == _kProfileIndex) _returnToProfile(context);
      return;
    }

    Provider.of<NavigationProvider>(context, listen: false).setIndex(index);

    if (index == 2) {
      // Reuse an existing ReelsScreen if one is already in the stack rather
      // than always pushing a new instance. Each ReelsScreen owns a
      // ReelControllerManager holding up to 3 live VideoPlayerControllers
      // (native video surfaces); pushing a fresh one every tap without ever
      // popping the old ones left prior instances buried (not disposed) in
      // the stack, accumulating undisposed native surfaces until the
      // Android surface buffer pool was exhausted (BLASTBufferQueue
      // "acquireNextBufferLocked: Can't acquire next buffer") and the
      // screen stopped rendering entirely.
      final navigator = Navigator.of(context);
      bool foundExisting = false;
      navigator.popUntil((route) {
        if (route.settings.name == AppConstants.reelsScreen) {
          foundExisting = true;
          return true;
        }
        return route.isFirst;
      });
      if (!foundExisting) {
        navigator.push(
          MaterialPageRoute(
            settings: const RouteSettings(name: AppConstants.reelsScreen),
            builder: (context) => const ReelsScreen(),
          ),
        );
      }
      return;
    }

    String routeName;
    switch (index) {
      case 0:
        routeName = AppConstants.homeScreen;
        break;
      case 1:
        routeName = AppConstants.searchScreen;
        break;
      case 3:
        routeName = AppConstants.profileScreen;
        break;
      default:
        routeName = AppConstants.homeScreen;
    }

    if (index == 0) {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      final isRoot = ModalRoute.of(context)?.isFirst ?? true;
      if (isRoot) {
        Navigator.pushNamed(context, routeName);
      } else {
        Navigator.pushReplacementNamed(context, routeName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final viewPadding = mediaQuery.viewPadding;

    // Scaffold does NOT inset a custom bottomNavigationBar above the system
    // bottom area, so reserve it here: the real nav-bar height on 3-button
    // navigation, or the gesture strip on gesture navigation.
    final double bottomSafePadding = viewPadding.bottom > 0
        ? viewPadding.bottom
        : mediaQuery.systemGestureInsets.bottom.clamp(0.0, 40.0);

    final pillRadius = BorderRadius.circular(AppConstants.pillRadius);

    return Container(
      // Lift headroom for the "+" + visible pill + floating margin below it
      // + gesture-safe padding. AppConstants.bottomNavHeight is the pill's
      // own visual height only.
      height:
          _kButtonLift +
          AppConstants.bottomNavHeight +
          _kFloatingMargin +
          bottomSafePadding,
      color: Colors.transparent,
      padding: EdgeInsets.only(bottom: bottomSafePadding),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _kFloatingMargin,
          0,
          _kFloatingMargin,
          _kFloatingMargin,
        ),
        child: Center(
          child: ConstrainedBox(
            // Keeps items compact and centred on tablets / foldables.
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: SizedBox(
              height: _kButtonLift + AppConstants.bottomNavHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: AppConstants.bottomNavHeight,
                    // Floating frosted-glass pill. The shadow sits outside
                    // the clip so it is not cut off.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: pillRadius,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2EF97316),
                            blurRadius: 30,
                            offset: Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Color(0x141A1A2E),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: pillRadius,
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: AppColors.glassGradient,
                              borderRadius: pillRadius,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            // Top reflection: light catching the glass.
                            foregroundDecoration: BoxDecoration(
                              borderRadius: pillRadius,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.white.withOpacity(0.3),
                                  Colors.white.withOpacity(0.0),
                                ],
                                stops: const [0.0, 0.45],
                              ),
                            ),
                            child: Row(
                              // Each item gets exactly 1/4 of the width left
                              // after the centre button slot.
                              children: [
                                Expanded(
                                  child: _buildNavItem(
                                    context: context,
                                    icon: Icons.home_outlined,
                                    activeIcon: Icons.home_rounded,
                                    label: 'Home',
                                    index: 0,
                                  ),
                                ),
                                Expanded(
                                  child: _buildNavItem(
                                    context: context,
                                    icon: Icons.search_outlined,
                                    activeIcon: Icons.search_rounded,
                                    label: 'Search',
                                    index: 1,
                                  ),
                                ),
                                const SizedBox(width: _kCenterSlotWidth),
                                Expanded(
                                  child: _buildNavItem(
                                    context: context,
                                    icon: Icons.movie_outlined,
                                    activeIcon: Icons.movie_rounded,
                                    label: 'PropClips',
                                    index: 2,
                                  ),
                                ),
                                Expanded(
                                  child: _buildNavItem(
                                    context: context,
                                    icon: Icons.person_outline_rounded,
                                    activeIcon: Icons.person_rounded,
                                    label: 'Profile',
                                    index: 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Elevated "+", laid out above the pill's top edge.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildPostPropertyButton(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostPropertyButton(BuildContext context) {
    return ScaleTap(
      scaleDown: 0.88,
      // Orange halo swells while pressed.
      glowCircle: true,
      onTap: () async {
        // If Reels is live underneath (this button is reachable from its
        // own bottom nav), pushing a route on top does not dispose it, so
        // its active video/audio would otherwise keep playing behind the
        // form — see ReelControllerManager.active's doc comment.
        final reelsManager = ReelControllerManager.active;
        reelsManager?.pauseAll();
        await Navigator.pushNamed(context, AppConstants.postPropertyScreen);
        reelsManager?.resumeWindow();
      },
      // Explicit semantics so screen readers announce the action correctly
      // even though this button is not a standard nav item.
      child: Semantics(
        label: 'Post a property',
        button: true,
        child: SizedBox(
          width: _kButtonSize,
          height: _kButtonSize,
          child: Stack(
            children: [
              // Frosted glass ring...
              ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.9)),
                    ),
                  ),
                ),
              ),
              // ...around a glowing orange core (outside the clip, so its
              // glow is not cut off).
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.ctaGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppColors.ctaShadow,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 28,
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

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = currentIndex == index;

    // Press-scale + haptic tick on every tab (via ScaleTap).
    return ScaleTap(
      scaleDown: 0.9,
      onTap: () {
        if (onTap != null) {
          onTap!(index);
        } else {
          _defaultNavigation(context, index);
        }
      },
      // opaque so the full Expanded area is tappable, not just the icon+label.
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        label: label,
        selected: isActive,
        button: true,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            // Soft orange glass capsule slides in behind the active icon.
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: isActive ? 46 : 36,
              height: 28,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withOpacity(0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? AppColors.primary.withOpacity(0.2)
                      : Colors.transparent,
                ),
                // Soft orange glow under the active capsule; animates in/out
                // with the capsule itself.
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? AppColors.primary.withOpacity(0.22)
                        : Colors.transparent,
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: AnimatedScale(
                scale: isActive ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(
                  isActive ? activeIcon : icon,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
