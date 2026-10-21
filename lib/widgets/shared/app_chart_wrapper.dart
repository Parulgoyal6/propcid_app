import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_analytics.dart';

/// The design's line chart: a smooth primary stroke over a vertical gradient
/// area fill, with optional weekday labels beneath.
///
/// Hand-painted rather than pulled from a charting package — no new dependency.
/// Geometry follows the prototype's inline SVG:
///
///  * Performance Over Time — 120 dp tall, 8 dp vertical padding, weekday
///    labels at 10 dp `#9CA3AF`, gradient `#5B50E8` 0.25 → 0.
///  * Follower Growth — 100 dp tall, no labels, gradient `#7C72F0` 0.25 → 0.
///
/// The stroke is 2.5 dp with round caps and joins, matching the SVG.
class DashboardLineChart extends StatelessWidget {
  final List<ChartPoint> points;

  /// 120 for the performance chart, 100 for follower growth.
  final double height;

  /// Weekday labels under the axis. The prototype shows them on the
  /// performance chart only.
  final bool showDayLabels;

  /// Top stop of the area gradient. Primary for performance, the lighter
  /// `#7C72F0` for follower growth.
  final Color areaColor;

  /// Shown when there is nothing to plot — React renders an equivalent
  /// "No performance data available" placeholder.
  final String emptyMessage;

  const DashboardLineChart({
    super.key,
    required this.points,
    this.height = 120,
    this.showDayLabels = false,
    this.areaColor = AppColors.primary,
    this.emptyMessage = 'No data yet',
  });

  /// A flat all-zero series carries no information, so it is treated as empty
  /// rather than drawn as a line along the baseline.
  bool get _hasData => points.length >= 2 && points.any((p) => p.value > 0);

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyMessage,
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _LineChartPainter(
              points: points,
              areaColor: areaColor,
              verticalPadding: 8,
            ),
          ),
        ),
        if (showDayLabels) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final point in points)
                Text(
                  _weekday(point.date),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.textHint,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _weekday(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(date.weekday - 1) % 7];
  }
}

class _LineChartPainter extends CustomPainter {
  final List<ChartPoint> points;
  final Color areaColor;
  final double verticalPadding;

  const _LineChartPainter({
    required this.points,
    required this.areaColor,
    required this.verticalPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final values = points.map((p) => p.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    // Guard against a zero range: a flat series would divide by zero.
    final range = (max - min) == 0 ? 1.0 : (max - min);

    final usableHeight = size.height - verticalPadding * 2;
    final step = size.width / (points.length - 1);

    final coords = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final normalised = (values[i] - min) / range;
      coords.add(
        Offset(
          i * step,
          verticalPadding + usableHeight - (normalised * usableHeight),
        ),
      );
    }

    final linePath = _smoothPath(coords);

    // Area fill: the stroke path closed down to the baseline.
    final areaPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            areaColor.withValues(alpha: 0.25),
            areaColor.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Catmull-Rom style smoothing via cubic segments, giving the eased curve the
  /// design shows rather than hard polyline corners.
  Path _smoothPath(List<Offset> coords) {
    final path = Path()..moveTo(coords.first.dx, coords.first.dy);

    for (var i = 0; i < coords.length - 1; i++) {
      final current = coords[i];
      final next = coords[i + 1];
      final previous = i == 0 ? current : coords[i - 1];
      final afterNext = i + 2 < coords.length ? coords[i + 2] : next;

      // Tension 1/6 keeps the curve close to the data without overshooting.
      final control1 = Offset(
        current.dx + (next.dx - previous.dx) / 6,
        current.dy + (next.dy - previous.dy) / 6,
      );
      final control2 = Offset(
        next.dx - (afterNext.dx - current.dx) / 6,
        next.dy - (afterNext.dy - current.dy) / 6,
      );

      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        next.dx,
        next.dy,
      );
    }

    return path;
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.areaColor != areaColor ||
      oldDelegate.verticalPadding != verticalPadding;
}
