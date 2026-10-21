import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// The Plan Usage ring — "4/10 Unlocked".
///
/// Design: a 120 dp circle whose `conic-gradient` fills `#5B50E8` for the
/// unlocked fraction and `#F0F0F4` for the rest, with an 88 dp white disc
/// punched out of the middle. That is a 16 dp donut, drawn here as two arcs on
/// a [CustomPainter] — no chart package, matching the approach already used for
/// the dashboard line chart.
class PlanUsageDonut extends StatelessWidget {
  final int unlocked;
  final int total;

  const PlanUsageDonut({
    super.key,
    required this.unlocked,
    required this.total,
  });

  static const double _diameter = 120;
  static const double _innerDiameter = 88;

  @override
  Widget build(BuildContext context) {
    // Guard against a zero total: an empty plan list would otherwise divide by
    // zero and paint a full ring.
    final fraction = total <= 0 ? 0.0 : (unlocked / total).clamp(0.0, 1.0);

    return Semantics(
      label: '$unlocked of $total plan features unlocked',
      child: SizedBox(
        width: _diameter,
        height: _diameter,
        child: CustomPaint(
          painter: _DonutPainter(
            fraction: fraction,
            thickness: (_diameter - _innerDiameter) / 2,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$unlocked/$total',
                  style: AppTextStyles.heading2.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                Text(
                  'Unlocked',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 9.5,
                    color: AppColors.textHint,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double fraction;
  final double thickness;

  const _DonutPainter({required this.fraction, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppColors.hairlineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    final progress = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;

    canvas.drawCircle(center, radius, track);

    if (fraction <= 0) return;

    // CSS conic-gradient starts at 12 o'clock and sweeps clockwise; Canvas
    // angles start at 3 o'clock, hence the -90° offset.
    canvas.drawArc(rect, -math.pi / 2, fraction * 2 * math.pi, false, progress);
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.thickness != thickness;
}
