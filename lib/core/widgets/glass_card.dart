import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Frosted-glass card used across the app.
///
/// Structure (outside → in): soft orange-tinted shadow → rounded clip →
/// [BackdropFilter] blur of whatever is behind → translucent white gradient
/// fill + thin white rim → optional top reflection → content.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  /// Fill opacity of the white glass (0–1). Around 0.6 reads as real frosted
  /// glass; higher values read closer to a solid card.
  final double opacity;

  /// Backdrop blur strength. 0 skips the [BackdropFilter] entirely.
  final double blurSigma;

  /// Border colour. Defaults to the thin white glass rim.
  final Color? borderColor;

  /// Adds a thin, fading white sheen across the top edge — light catching
  /// the glass.
  final bool highlight;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.padding = const EdgeInsets.all(16),
    this.width,
    this.height,
    this.onTap,
    this.opacity = 0.62,
    this.blurSigma = 16,
    this.borderColor,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final top = (opacity + 0.12).clamp(0.0, 1.0);
    final bottom = (opacity - 0.1).clamp(0.0, 1.0);

    Widget panel = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: top),
            Colors.white.withValues(alpha: bottom),
          ],
        ),
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.glassBorder),
      ),
      foregroundDecoration: !highlight
          ? null
          : BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.3],
              ),
            ),
      child: child,
    );

    if (blurSigma > 0) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: panel,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: AppColors.glassShadow,
        ),
        child: ClipRRect(borderRadius: radius, child: panel),
      ),
    );
  }
}
