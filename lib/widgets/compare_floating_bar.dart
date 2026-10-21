import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_navigator.dart';
import '../core/constants/app_constants.dart';
import '../core/navigation/current_route_notifier.dart';
import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/compare_provider.dart';

/// Global "Compare (n/4)" pill — mounted once in `app.dart`'s `MaterialApp`
/// builder (alongside `FloatingAiOrb`) so every property card's compare
/// toggle is reachable without each screen wiring its own bar. Hides itself
/// below [CompareProvider.minCompare] selections and while the Compare
/// screen itself is already on top.
///
/// The portal has an equivalent (`FloatingCompareBar.tsx`) that is fully
/// built but never mounted anywhere — a dead component. This widget exists
/// to provide the same affordance while actually being wired in, not to
/// reproduce that bug.
class CompareFloatingBar extends StatelessWidget {
  const CompareFloatingBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: CurrentRouteNotifier.instance.routeName,
      builder: (context, routeName, _) {
        if (routeName == AppConstants.comparePropertiesScreen) {
          return const SizedBox.shrink();
        }
        return Consumer2<CompareProvider, AuthProvider>(
          builder: (context, compare, auth, _) {
            // Portal FloatingCompareBar.tsx: needs a signed-in user and at
            // least two selections.
            if (!auth.isLoggedIn ||
                compare.count < CompareProvider.minCompare) {
              return const SizedBox.shrink();
            }
            return _CompareBar(compare: compare);
          },
        );
      },
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({required this.compare});

  final CompareProvider compare;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      // Sits clear of the app's bottom nav bar (64 dp) wherever one is
      // present; on a screen without one this just floats a bit higher
      // above the edge, which reads fine either way. The nav bar is itself
      // a floating pill with a 16 dp gap below it now (bottom_nav_bar.dart's
      // `_kFloatingMargin`), so that same 16 dp is added here to keep this
      // bar clear of its top edge instead of sinking into it.
      bottom: AppConstants.bottomNavHeight + bottomInset + 12 + 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            boxShadow: AppColors.primaryGlow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.compare_arrows_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Compare (${compare.count}/${CompareProvider.maxCompare})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                // This widget is mounted in `app.dart`'s `MaterialApp.builder`
                // — a sibling of the Navigator, not a descendant of it — so
                // `Navigator.of(context)`/`Navigator.pushNamed(context, ...)`
                // has no Navigator ancestor to find and throws. `appNavigatorKey`
                // exists in this codebase specifically for this case (see its
                // doc comment in `app_navigator.dart`); `FloatingAiOrb`, the
                // other widget living at this same level, uses the identical
                // pattern for its own navigation.
                onPressed: () => appNavigatorKey.currentState?.pushNamed(
                  AppConstants.comparePropertiesScreen,
                  arguments: const {'propertyIds': <String>[]},
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
                child: const Text(
                  'View Comparison',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Semantics(
                label: 'Clear comparison',
                button: true,
                child: GestureDetector(
                  onTap: compare.clear,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 18,
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
