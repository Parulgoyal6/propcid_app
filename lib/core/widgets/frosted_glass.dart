import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A real frosted-glass panel: blurs whatever is behind it
/// ([BackdropFilter]), tints it with translucent white, rims it with a thin
/// white border, adds a top-edge reflection, and floats it on a soft
/// orange-tinted shadow.
///
/// The orange ambient light painted by `AppGlassBackdrop` shows *through*
/// the glass — surfaces are never filled with solid white.
class FrostedGlass extends StatelessWidget {
  const FrostedGlass({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.padding = EdgeInsets.zero,
    this.width,
    this.height,
    this.blur = 18,
    this.strong = false,
    this.gradient,
    this.borderColor,
    this.shadow = AppColors.glassShadow,
    this.highlight = true,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;

  /// Backdrop blur sigma. 0 skips the [BackdropFilter] entirely (for glass
  /// that sits over a photo that must stay sharp, or very long lists).
  final double blur;

  /// Uses the more opaque fill, for text-dense surfaces.
  final bool strong;

  /// Overrides the fill gradient.
  final Gradient? gradient;

  final Color? borderColor;
  final List<BoxShadow>? shadow;

  /// Thin fading white sheen across the top — light catching the glass.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget panel = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        gradient:
            gradient ??
            (strong ? AppColors.glassGradientStrong : AppColors.glassGradient),
        borderRadius: radius,
        border: Border.all(
          color: borderColor ?? AppColors.glassBorder,
          width: 1,
        ),
      ),
      foregroundDecoration: highlight
          ? BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                stops: [0.0, 0.32],
              ),
            )
          : null,
      child: child,
    );

    if (blur > 0) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      );
    }

    // Shadow lives outside the clip so it isn't cut off.
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(borderRadius: radius, child: panel),
    );
  }
}
