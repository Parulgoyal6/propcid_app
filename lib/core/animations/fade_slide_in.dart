import 'package:flutter/material.dart';

/// One-shot entrance: fades the child in while it rises a few pixels into
/// place, the first time it is built. Used for screen sections and list
/// items so content "arrives" instead of popping in.
///
/// Cheap by construction: a single short controller per item, animating only
/// opacity and a translation (both compositor-friendly, no relayout), which
/// finishes and then sits idle. Items built later — e.g. scrolled into view in
/// a lazy list — play their entrance once, at that point.
///
/// [index] staggers siblings by [staggerMs] each, capped at [maxStaggerSteps]
/// so a long list never makes later items wait noticeably.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.staggerMs = 45,
    this.maxStaggerSteps = 6,
    this.duration = const Duration(milliseconds: 380),
    this.offsetY = 14,
    this.animate = true,
  });

  final Widget child;
  final int index;
  final int staggerMs;
  final int maxStaggerSteps;
  final Duration duration;

  /// How far below its final position the child starts, in logical pixels.
  final double offsetY;

  /// When false the child starts fully shown (no entrance). Read once, when
  /// the item is first built, so the tree shape never changes either way.
  final bool animate;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _controller.value = 1;
      return;
    }
    final steps = widget.index.clamp(0, widget.maxStaggerSteps);
    final delay = Duration(milliseconds: steps * widget.staggerMs);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the system "reduce motion" setting.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offsetY),
            child: child,
          ),
        );
      },
    );
  }
}
