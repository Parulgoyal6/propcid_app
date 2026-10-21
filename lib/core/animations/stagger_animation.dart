import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class StaggerItem extends StatelessWidget {
  final int index;
  final Widget child;
  final AnimationController controller;

  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final delay = index * AppConstants.staggerListItemDelayMs;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: controller,
          curve: Interval(
            delay / 1000,
            (delay + 300) / 1000,
            curve: Curves.easeOut,
          ),
        );

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
