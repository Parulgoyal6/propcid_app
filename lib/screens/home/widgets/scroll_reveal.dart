import 'package:flutter/material.dart';

/// Fades + slides [child] up into place the first time it scrolls into the
/// viewport, then stops listening — a one-shot reveal (not a continuous
/// parallax), so it adds no per-frame cost once a section has appeared.
/// Used sparingly on a few "moment" sections rather than every section, so
/// scrolling the Home feed doesn't pay for a dozen independent listeners.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  ScrollPosition? _position;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (newPosition != _position) {
      _position?.removeListener(_check);
      _position = newPosition;
      _position?.addListener(_check);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    _controller.dispose();
    super.dispose();
  }

  void _check() {
    if (_revealed || !mounted) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    if (top < screenHeight * 0.92) {
      _revealed = true;
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
