import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Animated mic waveform — 5 vertical bars that pulse while listening.
class VoiceWaveform extends StatelessWidget {
  final bool isActive;

  const VoiceWaveform({super.key, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(5, (i) {
        final bar = Container(
          width: 4,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );

        if (!isActive) return bar;

        // Each bar has a different delay so they ripple.
        return bar
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleY(
              begin: 0.3,
              end: 1.0,
              duration: Duration(milliseconds: 400 + i * 80),
              curve: Curves.easeInOut,
              delay: Duration(milliseconds: i * 80),
            );
      }),
    );
  }
}
