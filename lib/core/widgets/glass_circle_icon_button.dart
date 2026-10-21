// core/widgets/glass_circle_icon_button.dart
//
// The frosted circular action that sits on a photo or gradient — back, share and
// overflow on the Public Profile cover.
//
// EXTRACTED, NOT MOVED
// --------------------
// `_GlassIconButton` inside screens/profile/widgets/profile_cover_header.dart is
// the same control, but it is private and that file is not being modified. This
// is a shared copy so the Public Profile cover does not need its own one-off.
// The visual spec is taken from that widget verbatim — 38 dp circle, white at
// 22% alpha, 19 dp white glyph, an 8 dp unread dot at top-right with a 1.5 dp
// white-60% ring — so the two covers cannot look different.
//
// ONE DELIBERATE IMPROVEMENT: the hit area is padded out to 44 dp while the
// painted circle stays 38 dp. 38 is below the 44 dp minimum touch target, and on
// this screen these are the only way back. The padding is transparent, so
// nothing moves visually.
import 'package:flutter/material.dart';

/// Minimum comfortable touch target. The circle stays 38 dp; the tappable area
/// is grown around it.
const double _kHitSize = 44;
const double _kCircleSize = 38;

class GlassCircleIconButton extends StatelessWidget {
  final IconData icon;

  /// Announced by screen readers. Required — an icon-only control with no label
  /// is unusable with TalkBack/VoiceOver.
  final String semanticLabel;

  final VoidCallback onTap;

  /// Small accent dot at the top-right, for unread state.
  final bool showDot;

  /// Cross-fades the glass treatment away as a collapsing app bar turns solid:
  /// 0 = glass on photo, 1 = plain dark glyph on an opaque bar.
  ///
  /// Driven by the cover header's scroll progress so the buttons stay legible
  /// once the photo has gone.
  final double solidProgress;

  /// Glyph colour once [solidProgress] reaches 1.
  final Color solidColor;

  const GlassCircleIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.showDot = false,
    this.solidProgress = 0,
    this.solidColor = const Color(0xFF1A1A2E),
  });

  @override
  Widget build(BuildContext context) {
    final t = solidProgress.clamp(0.0, 1.0);

    // The glass disc fades out; the glyph darkens. Interpolating both against
    // the same t keeps them in step.
    final fill = Color.lerp(
      Colors.white.withValues(alpha: 0.22),
      Colors.transparent,
      t,
    )!;
    final glyph = Color.lerp(Colors.white, solidColor, t)!;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _kHitSize,
          height: _kHitSize,
          child: Center(
            child: SizedBox(
              width: _kCircleSize,
              height: _kCircleSize,
              child: Stack(
                children: [
                  Container(
                    width: _kCircleSize,
                    height: _kCircleSize,
                    decoration: BoxDecoration(
                      color: fill,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 19, color: glyph),
                  ),
                  if (showDot)
                    Positioned(
                      top: 8,
                      right: 9,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
