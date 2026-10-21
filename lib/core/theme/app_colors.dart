import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // PropCid brand accent — warm orange, matching the web portal's identity.
  // Replaces the previous indigo/purple palette; token names are kept
  // unchanged (only the underlying values moved) so every screen that
  // already references AppColors.primary/etc. picks up the new brand
  // automatically with no per-file changes required.
  static const Color primary = Color(0xFFF97316);
  static const Color primaryLight = Color(0xFFFFF1E6);
  static const Color accentPurple = Color(0xFFF97316);
  static const Color priceColor = Color(0xFFF97316);

  // Warm white / light cream canvas under the glass.
  static const Color background = Color(0xFFFBF6F0);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // ── Premium frosted-glass tokens ─────────────────────────────────────────
  // Shared by every glass surface (cards, header, search, nav, drawer) so the
  // glass reads identically everywhere. Fills are deliberately translucent —
  // the warm orange ambient light behind them should show through.

  /// ~60% white — standard frosted glass.
  static const Color glassFill = Color(0x99FFFFFF);

  /// ~72% white — glass that carries dense text (lists, drawer, sheets).
  static const Color glassFillStrong = Color(0xB8FFFFFF);

  /// Thin translucent white rim that catches the light on the glass edge.
  static const Color glassBorder = Color(0x9EFFFFFF);

  /// Top-left → bottom-right fill gradient: brighter where light hits the
  /// glass, a touch clearer at the far corner (real glass is never flat).
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xB3FFFFFF), Color(0x80FFFFFF)],
  );

  /// Stronger variant of [glassGradient] for text-dense panels.
  static const LinearGradient glassGradientStrong = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xD1FFFFFF), Color(0xA6FFFFFF)],
  );

  /// Soft diffuse shadow: a warm orange ambient glow plus a faint contact
  /// shadow — makes glass panels float.
  static const List<BoxShadow> glassShadow = [
    BoxShadow(color: Color(0x1FF97316), blurRadius: 30, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x0D1A1A2E), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// Deeper orange gradient for primary CTAs and active states.
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [Color(0xFFFF8A3D), Color(0xFFF26B0F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Elevated orange glow under primary CTAs / the nav "+".
  static const List<BoxShadow> ctaShadow = [
    BoxShadow(color: Color(0x66F97316), blurRadius: 20, offset: Offset(0, 8)),
  ];
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);

  // ── Tokens added in Phase 5 for the shared component library ──────────────
  // Purely additive; the design system table lists these and nothing in the
  // app had a name for them yet (they were being written as inline hex).

  /// Hairline borders, list separators, and the toggle's OFF track.
  static const Color hairline = Color(0xFFEDEDF2);

  /// The design system's second hairline value, used for drawer/header rules.
  static const Color hairlineStrong = Color(0xFFF0F0F4);

  /// Pressed/hover state for primary links and buttons.
  static const Color primaryPressed = Color(0xFFC2410C);

  /// Inset surface a shade below the card — the billing rows and the read-only
  /// billing-detail fields sit on this. Added in Phase 7.
  static const Color surfaceMuted = Color(0xFFF9F9FB);

  /// Border for the destructive outline button ("Cancel Subscription").
  static const Color errorBorder = Color(0xFFFCA5A5);

  static const Color verifiedBadge = Color(0xFF10B981);
  static const Color verifiedBadgeText = Color(0xFFFFFFFF);

  // Status Chip Colors
  static const Color statusAvailable = Color(0xFF22C55E);
  static const Color statusBooked = Color(0xFFF97316);
  static const Color statusSold = Color(0xFFEF4444);
  static const Color statusPending = Color(0xFFEAB308);
  static const Color statusNewLaunch = Color(0xFF3B82F6);

  // Additional Status Colors
  static const Color success = Color(0xFF22C55E);
  // Amber, not the brand orange — `warning` and `primary` need to read as
  // two different things wherever a screen shows both (e.g. a "pending"
  // badge next to a primary CTA).
  static const Color warning = Color(0xFFEAB308);
  static const Color error = Color(0xFFEF4444);
  static const Color statusTopBuilderText = Color(0xFFF97316);
  static const Color statusGatedCommunityBg = Color(0xFFFFF1E6);
  static const Color statusGatedCommunityText = Color(0xFFF97316);
  static const Color statusPremiumBg = Color(0xFFF97316);
  static const Color statusPremiumText = Color(0xFFFFFFFF);
  static const Color statusLoanAvailableText = Color(0xFF1ABC9C);

  // Gradient helpers
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFFDBA74)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFC2410C), Color(0xFFF97316), Color(0xFFFDBA74)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Prototype surface elevation ───────────────────────────────────────────
  // The redesign renders solid white cards on the #F4F4F8 canvas with a much
  // softer, neutral shadow than `cardShadow`'s orange-tinted glow below.
  // Kept as separate tokens (rather than changing `cardShadow`) so existing
  // screens that already use `cardShadow`/`GlassCard` are visually untouched.

  /// `0 2px 10px rgba(26,26,46,0.05)` — standard card/tile surface.
  static const List<BoxShadow> surfaceCardShadow = [
    BoxShadow(color: Color(0x0D1A1A2E), blurRadius: 10, offset: Offset(0, 2)),
  ];

  /// `0 2px 6px rgba(26,26,46,0.1)` — the raised, selected pill inside a
  /// segmented tab track.
  static const List<BoxShadow> raisedPillShadow = [
    BoxShadow(color: Color(0x1A1A1A2E), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// `0 4px 12px rgba(249,115,22,0.28)` — solid primary CTA.
  static const List<BoxShadow> primaryActionShadow = [
    BoxShadow(color: Color(0x47F97316), blurRadius: 12, offset: Offset(0, 4)),
  ];

  // Premium card shadow
  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0xFFF97316).withOpacity(0.10),
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  // Glow effect for interactive elements
  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: Color(0xFFF97316).withOpacity(0.35),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];

  // Category icon backgrounds
  static const Color categoryBuyBg = Color(0xFFFFF4D6);
  static const Color categoryRentBg = Color(0xFFE6F1FB);
  static const Color categoryPlotBg = Color(0xFFEAF3DE);
  static const Color categoryCommercialBg = Color(0xFFFFF3E0);
  static const Color categoryPgBg = Color(0xFFFCE4EC);

  // Amenity icon backgrounds
  // Despite the name, this is now a warm gold — the old indigo/purple hue
  // this token held is gone. Kept as `amenityIndigo` (not renamed) so every
  // existing call site (amenity chips, payment-method accents, lead-status
  // colours, etc.) keeps working unchanged.
  static const Color amenityIndigo = Color(0xFFCA8A04);
  static const Color amenityBlue = Color(0xFF3B82F6);
  static const Color amenityOrange = Color(0xFFF97316);
  static const Color amenityGreen = Color(0xFF22C55E);
  static const Color amenityRed = Color(0xFFEF4444);

  static Color getStatusChipBg(String label) {
    switch (label) {
      case 'Ready to Move':
        return statusAvailable;
      // `statusNewLaunch` has existed since the palette was written but was
      // never wired into this switch, so a "New Launch" tag fell through to the
      // default. Added for the search result cards; no existing case changed.
      case 'New Launch':
        return statusNewLaunch;
      case 'Under Construction':
        return statusPending;
      case 'Top Builder':
        return statusTopBuilderText;
      case 'Gated Community':
        return statusGatedCommunityBg;
      case 'Premium':
        return statusPremiumBg;
      case 'Loan Available':
        return primaryLight;
      default:
        return primaryLight;
    }
  }

  static Color getStatusChipText(String label) {
    switch (label) {
      case 'Ready to Move':
        return Colors.white;
      // White on the solid `statusNewLaunch` fill, matching how the other solid
      // chip ('Ready to Move') is treated. Introduces no new colour value.
      case 'New Launch':
        return Colors.white;
      case 'Under Construction':
        return textPrimary;
      case 'Top Builder':
        return statusTopBuilderText;
      case 'Gated Community':
        return statusGatedCommunityText;
      case 'Premium':
        return statusPremiumText;
      case 'Loan Available':
        return statusLoanAvailableText;
      default:
        return textPrimary;
    }
  }
}
