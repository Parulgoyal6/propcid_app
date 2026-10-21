import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AnimatedHeart extends StatefulWidget {
  final bool isFilled;
  final VoidCallback onTap;
  final double size;

  const AnimatedHeart({
    super.key,
    required this.isFilled,
    required this.onTap,
    this.size = 24,
  });

  @override
  State<AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<AnimatedHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: AppConstants.heartAnimationDurationMs,
      ),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void didUpdateWidget(AnimatedHeart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFilled != oldWidget.isFilled && widget.isFilled) {
      _controller.forward().then((_) {
        _controller.reverse();
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
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value == 0.0 ? 1.0 : _scaleAnimation.value,
            child: Icon(
              widget.isFilled ? Icons.favorite : Icons.favorite_border,
              color: widget.isFilled ? Colors.red : Colors.grey,
              size: widget.size,
            ),
          );
        },
      ),
    );
  }
}
