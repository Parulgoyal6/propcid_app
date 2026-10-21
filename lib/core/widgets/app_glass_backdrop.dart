import 'dart:ui';

import 'package:flutter/material.dart';

/// The app-wide ambient background every screen floats over.
///
/// Painted once, behind every route (see `PropertyApp.builder` in
/// `app.dart`), rather than duplicated per screen. A soft, premium, light
/// "frosted" atmosphere: very light blue, warm off-white/cream and a subtle
/// mint/teal, melted together by large, heavily blurred colour blobs, with a
/// faint PropCID-orange glow in two corners. No patterns, shapes, images or
/// textures — only smooth colour — so it never competes with the UI on top.
///
/// Responsive: every blob's size, position and blur radius is a fraction of
/// the screen, so the composition looks the same on small and large phones.
///
/// Deliberately not a `BackdropFilter`: that filter samples and re-blurs
/// whatever is currently rendered *behind* it, every single frame anything
/// behind it moves — which caused real scroll jank when tried on the Home
/// header earlier, and would be far worse repeated behind every scrolling
/// screen in the app. Each [_Blob] instead blurs only its own simple,
/// unmoving shape via [ImageFiltered] — a fixed cost paid once at first
/// paint, independent of whatever scrolls on top of it in later,
/// separately-composited layers.
///
/// Individual screens show this by leaving their `Scaffold.backgroundColor`
/// transparent (the theme default) — this widget does not touch any screen's
/// content, cards, or layout, only what shows through the gaps between them.
class AppGlassBackdrop extends StatelessWidget {
  const AppGlassBackdrop({super.key});

  // Palette — kept light so text and cards stay fully readable on top.
  static const Color _cream = Color(0xFFFFF9F1);
  static const Color _lightBlue = Color(0xFFE6F0FA);
  static const Color _mintBase = Color(0xFFEEF8F4);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    // Blob sizes follow the shorter side, so a tall phone doesn't get
    // oversized blobs and a short one doesn't get tiny ones.
    final s = size.shortestSide;

    // RepaintBoundary: the backdrop never changes, so its blurred blobs are
    // rasterised once and reused.
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base wash: light blue (top-left) → cream (middle) → soft mint
            // (bottom). Everything else is layered on top of this.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_lightBlue, _cream, _cream, _mintBase],
                  stops: [0.0, 0.4, 0.62, 1.0],
                ),
              ),
            ),

            // ── Large, heavily blurred colour blobs ──────────────────────
            // Light blue, top-left.
            Positioned(
              top: -s * 0.35,
              left: -s * 0.35,
              child: _Blob(diameter: s * 1.1, color: const Color(0xCCCFE2F6)),
            ),
            // Faint orange glow, top-right (PropCID brand warmth).
            Positioned(
              top: -s * 0.3,
              right: -s * 0.4,
              child: _Blob(diameter: s * 0.9, color: const Color(0x38F97316)),
            ),
            // Warm cream light pool across the upper middle.
            Positioned(
              top: h * 0.18,
              left: w * 0.1,
              child: _Blob(diameter: s * 0.95, color: const Color(0xB3FFF6EA)),
            ),
            // Mint/teal, left side lower half.
            Positioned(
              top: h * 0.48,
              left: -s * 0.45,
              child: _Blob(diameter: s * 1.0, color: const Color(0x8CBFE7DE)),
            ),
            // Soft light blue, right side middle.
            Positioned(
              top: h * 0.36,
              right: -s * 0.5,
              child: _Blob(diameter: s * 0.95, color: const Color(0x80D6E8F8)),
            ),
            // Faint orange glow, bottom-right.
            Positioned(
              bottom: -s * 0.35,
              right: -s * 0.3,
              child: _Blob(diameter: s * 0.95, color: const Color(0x33FB923C)),
            ),
            // Subtle teal, bottom-left.
            Positioned(
              bottom: -s * 0.4,
              left: -s * 0.2,
              child: _Blob(diameter: s * 0.9, color: const Color(0x66A9DDD3)),
            ),

            // ── Frosted veil ─────────────────────────────────────────────
            // A thin white frost over everything softens the colours into a
            // light, clean "glass" atmosphere and keeps contrast high.
            const ColoredBox(color: Color(0x33FFFFFF)),
            // A gentle top-left sheen, the way light catches frosted glass.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x40FFFFFF),
                    Color(0x00FFFFFF),
                    Color(0x00FFFFFF),
                    Color(0x1AFFFFFF),
                  ],
                  stops: [0.0, 0.35, 0.75, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One soft, heavily blurred colour blob. Self-blurring (not a
/// `BackdropFilter`) — see the class doc above for why that distinction
/// matters for scroll performance. The blur scales with the blob, so edges
/// stay invisible at every screen size.
class _Blob extends StatelessWidget {
  const _Blob({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final sigma = diameter * 0.2;
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
