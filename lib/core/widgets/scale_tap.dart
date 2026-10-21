import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Press feedback used across the app: the child scales down while pressed
/// and springs back on release, with a light haptic tick on tap.
///
/// Pass [glowRadius] (the child's own corner radius, or `null`) to also fade
/// in a soft PropCID-orange glow behind the child while it is pressed — used
/// by cards and primary buttons. Without it, only the scale plays, exactly as
/// before, so existing call sites keep their look.
///
/// Cheap by construction: one short controller per instance, driving only a
/// transform and (optionally) a shadow, and only while a finger is down.
class ScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Duration duration;

  /// Corner radius of the press glow. Null = no glow.
  final BorderRadius? glowRadius;

  /// Circular press glow (for round buttons). Takes precedence over
  /// [glowRadius].
  final bool glowCircle;

  /// Light haptic tick on tap. On by default; ignored when [onTap] is null.
  final bool haptic;

  /// Hit-test behaviour of the underlying [GestureDetector].
  final HitTestBehavior? behavior;

  const ScaleTap({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.96,
    this.duration = const Duration(milliseconds: 120),
    this.glowRadius,
    this.glowCircle = false,
    this.haptic = true,
    this.behavior,
  });

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _press;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      // Release a little slower than press, so the spring-back is visible.
      reverseDuration: widget.duration * 1.8,
    );
    _press = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      // Slight overshoot on release: a springy, "physical" settle.
      reverseCurve: Curves.easeOutBack.flipped,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasGlow => widget.glowCircle || widget.glowRadius != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: (_) {
        _controller.forward();
      },
      onTapUp: (_) {
        _controller.reverse();
        if (widget.onTap != null && widget.haptic) {
          HapticFeedback.selectionClick();
        }
        widget.onTap?.call();
      },
      onTapCancel: () {
        _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _press,
        child: widget.child,
        builder: (context, child) {
          final t = _press.value;
          Widget result = Transform.scale(
            scale: 1 - (1 - widget.scaleDown) * t,
            child: child,
          );
          // The glow wrapper is always present when enabled (only its shadow
          // changes), so pressing never alters the tree shape and the child
          // never loses its state mid-tap.
          if (_hasGlow) {
            result = DecoratedBox(
              decoration: BoxDecoration(
                shape: widget.glowCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: widget.glowCircle ? null : widget.glowRadius,
                boxShadow: t > 0
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: 0.28 * t.clamp(0.0, 1.0),
                          ),
                          blurRadius: 22,
                          spreadRadius: -2,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: result,
            );
          }
          return result;
        },
      ),
    );
  }
}
