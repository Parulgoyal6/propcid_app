// widgets/shared/app_mini_charts.dart
//
// The two chart shapes and the progress row the portal's dashboards use and this
// app did not have.
//
// PRESENTATION ONLY
// -----------------
// Every widget here takes numbers it is given and draws them. Nothing fetches,
// computes a metric, or knows what a project is. The callers pass values that were
// already loaded by existing providers and services.
//
// WHY NOT A CHART PACKAGE
// -----------------------
// The portal uses recharts. Adding a Flutter charting dependency would need
// approval and would bring a desktop-shaped API (axes, legends, tooltips) for three
// small mobile visuals. `DashboardLineChart` already establishes the pattern in this
// app — a `CustomPainter` sized for a card — and these follow it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// One slice of [DashboardDonutChart].
class DonutSlice {
  const DonutSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

/// The portal's "Inventory Overview" pie, as a donut.
///
/// A donut rather than a filled pie: the centre carries the total, which on a phone
/// is the number a builder actually wants and which the portal has to put in a
/// tooltip. Same data, fewer taps.
///
/// Legend sits beside the ring on a wide card and beneath it on a narrow one, so the
/// labels never get squeezed into two characters.
class DashboardDonutChart extends StatelessWidget {
  const DashboardDonutChart({
    super.key,
    required this.slices,
    this.size = 132,
    this.centerLabel,
    this.emptyMessage = 'No data yet',
  });

  final List<DonutSlice> slices;
  final double size;

  /// Drawn in the middle. Usually the total.
  final String? centerLabel;

  final String emptyMessage;

  double get _total => slices.fold<double>(0, (sum, s) => sum + s.value);

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty || _total <= 0) {
      return SizedBox(
        height: size,
        child: Center(child: Text(emptyMessage, style: AppTextStyles.caption)),
      );
    }

    final ring = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(slices: slices, total: _total),
        child: centerLabel == null
            ? null
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      centerLabel!,
                      style: AppTextStyles.heading2.copyWith(fontSize: 19),
                    ),
                    Text(
                      'total',
                      style: AppTextStyles.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
      ),
    );

    final legend = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: slice.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${slice.label} · ${slice.value.round()}',
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 250 dp is where ring + legend stop fitting side by side at 320 dp minus
        // the card's padding.
        final sideBySide = constraints.maxWidth >= 250;
        if (sideBySide) {
          return Row(
            children: [
              ring,
              const SizedBox(width: 16),
              Expanded(child: legend),
            ],
          );
        }
        return Column(
          children: [
            ring,
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: legend),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.total});

  final List<DonutSlice> slices;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.18;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    // Starts at 12 o'clock and runs clockwise, which is how the portal's pie reads.
    var start = -math.pi / 2;
    // A 2 dp gap between slices, but only when there is more than one — a single
    // slice would otherwise render with a visible nick in it.
    final gap = slices.length > 1 ? 0.03 : 0.0;

    for (final slice in slices) {
      if (slice.value <= 0) continue;
      final sweep = (slice.value / total) * 2 * math.pi;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.01),
        false,
        Paint()
          ..color = slice.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total || old.slices.length != slices.length;
}

/// One bar of [DashboardBarChart].
class BarDatum {
  const BarDatum({required this.label, required this.value});

  final String label;
  final double value;
}

/// The portal's "Site Visits" bar chart.
///
/// Horizontal bars, not vertical. Vertical bars on a 320 dp screen give each column
/// ~40 dp and force the x-axis labels to rotate or truncate; horizontal gives the
/// label a full line and the value room to sit at the end of its bar.
class DashboardBarChart extends StatelessWidget {
  const DashboardBarChart({
    super.key,
    required this.bars,
    this.barColor = AppColors.primary,
    this.emptyMessage = 'No data yet',
  });

  final List<BarDatum> bars;
  final Color barColor;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(child: Text(emptyMessage, style: AppTextStyles.caption)),
      );
    }

    // Scaled against the largest bar, not against a fixed ceiling, so a quiet week
    // still shows shape rather than four slivers.
    final max = bars.fold<double>(0, (m, b) => math.max(m, b.value));

    return Column(
      children: [
        for (final bar in bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 54,
                  child: Text(
                    bar.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      // A zero-max would divide by zero; an all-zero series draws
                      // as empty tracks, which is the honest picture.
                      value: max <= 0 ? 0 : bar.value / max,
                      minHeight: 8,
                      backgroundColor: barColor.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${bar.value.round()}',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One row of the portal's "Performance Overview" card.
///
/// Label, percentage, animated track, and a caption spelling out the fraction the
/// percentage came from — the portal shows all four (`:1080-1145`), and the caption
/// is what stops "67%" being a number with no denominator.
class DashboardProgressRow extends StatelessWidget {
  const DashboardProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.tint = AppColors.primary,
    this.trailing,
  });

  final String label;

  /// 0.0 – 1.0. Clamped, so a bad ratio cannot overflow the track.
  final double value;

  final String caption;
  final Color tint;

  /// Overrides the percentage on the right — the rating row shows "4.6/5.0".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing ?? '${(clamped * 100).round()}%',
                style: AppTextStyles.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: clamped),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => LinearProgressIndicator(
                value: animated,
                minHeight: 7,
                backgroundColor: tint.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(caption, style: AppTextStyles.caption.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
