import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../widgets/app_glass_backdrop.dart';

class PremiumPageRoute<T> extends PageRouteBuilder<T> {
  /// [settings] is optional and defaults to null, preserving the behaviour of
  /// every existing caller. Pass it from `onGenerateRoute` when the route must
  /// be identifiable later — e.g. `Navigator.popUntil` matching on
  /// `route.settings.name`. Without it `settings.name` is null and no
  /// name-based navigation predicate can ever match.
  PremiumPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        pageBuilder: (ctx, _, __) => builder(ctx),
        transitionDuration: const Duration(
          milliseconds: AppConstants.pageTransitionMs,
        ),
        // Going back is a touch quicker than going forward, as on iOS/Android.
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (ctx, anim, secondary, child) {
          final enter = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          // The page underneath eases back slightly while a new page covers
          // it, giving navigation a sense of depth.
          final covered = CurvedAnimation(
            parent: secondary,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween(
              begin: Offset.zero,
              end: const Offset(-0.03, 0),
            ).animate(covered),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(enter),
              child: FadeTransition(
                opacity: enter,
                child: ScaleTransition(
                  scale: Tween(begin: 0.985, end: 1.0).animate(enter),
                  child: GlassPageSurface(child: child),
                ),
              ),
            ),
          );
        },
      );
}

/// Paints the app's glass backdrop underneath a page.
///
/// Every Scaffold is transparent so the glass backdrop shows through it.
/// Without this, a page sliding in would also show the *previous* page
/// through its transparent background for the length of the transition.
/// Carrying its own copy of the (identical) backdrop keeps each page opaque
/// while it animates, and visually seamless once it settles.
class GlassPageSurface extends StatelessWidget {
  const GlassPageSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [const AppGlassBackdrop(), child],
    );
  }
}

/// Wraps a platform page transition with [GlassPageSurface], so plain
/// `MaterialPageRoute`s get the same backdrop as [PremiumPageRoute].
/// Installed through `ThemeData.pageTransitionsTheme`.
class GlassPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlassPageTransitionsBuilder(this.base);

  final PageTransitionsBuilder base;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return base.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      GlassPageSurface(child: child),
    );
  }
}
