import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Tokens for the Post Property wizard.
///
/// Split of responsibility, per the project brief:
///
///  * **The React portal supplies structure** — sizes, spacing, radii, field
///    heights, hierarchy. Those numbers are transcribed from its source and the
///    `.property-wizard-container` CSS overrides in `PropertyWizard.tsx`.
///  * **The Flutter app supplies branding** — every colour here resolves to
///    [AppColors] and every text style is built on [AppTextStyles] (Poppins).
///    The portal's orange palette, its Roboto/Space Mono type and its orange
///    gradients are deliberately NOT used.
///
/// So a size like `inputHeight = 34` comes from the portal; the colour drawn at
/// that size comes from the app.
class PortalTheme {
  PortalTheme._();

  // ── Palette ────────────────────────────────────────────────────────────
  // All app tokens. The names are kept from the portal mapping so the step
  // files read the same, but nothing here is portal branding.

  /// Primary accent — selected borders, active step, progress, focus.
  static const Color accent = AppColors.primary;

  /// The portal used a second, brighter orange for titles and badges. The app
  /// has one primary, so both map to it.
  static const Color accentBright = AppColors.primary;

  /// Gradient partner for [accent] — the same end stop as
  /// [AppColors.primaryGradient] (kept as a literal here since a `const`
  /// can't read `.colors.last` off that gradient at compile time).
  static const Color accentGradientEnd = Color(0xFFFDBA74);

  /// Tinted surface behind a selected card / step header.
  static const Color accentSurface = AppColors.primaryLight;

  /// Soft accent border.
  static Color get accentBorderSoft =>
      AppColors.primary.withValues(alpha: 0.25);

  static const Color cardSurface = AppColors.cardBackground;

  /// Idle field border. Neutral, derived from the app's hint colour.
  static Color get cardBorder => AppColors.textHint.withValues(alpha: 0.35);

  /// Unchecked radio ring.
  static Color get radioIdle => AppColors.textHint;

  static const Color headingText = AppColors.textPrimary;
  static const Color subheadingText = AppColors.textSecondary;
  static const Color sectionLabel = AppColors.textSecondary;
  static const Color titleText = AppColors.textPrimary;
  static const Color bodyMuted = AppColors.textSecondary;
  static const Color fieldLabel = AppColors.textPrimary;

  // Neutral scale, all sourced from the app's text/background tokens.
  static const Color slate500 = AppColors.textSecondary;
  static const Color slate700 = AppColors.textPrimary;
  static Color get slate200 => AppColors.textHint.withValues(alpha: 0.30);
  static const Color slate100 = AppColors.background;
  static const Color slate400 = AppColors.textHint;
  static const Color slate600 = AppColors.textSecondary;
  static const Color slate900 = AppColors.textPrimary;

  /// Error ring on an invalid field.
  static const Color fieldError = AppColors.error;

  // ValidationSummary.
  static Color get errorSurface => AppColors.error.withValues(alpha: 0.08);
  static Color get errorBorder => AppColors.error.withValues(alpha: 0.30);
  static const Color errorIcon = AppColors.error;
  static const Color errorText = AppColors.error;

  /// Completed step / Publish action.
  static const Color success = AppColors.success;
  static const Color successDark = Color(0xFF16A34A);

  /// Step-header surface and border, formerly Tailwind orange-50/100.
  static const Color headerSurface = AppColors.primaryLight;
  static Color get headerBorder => AppColors.primary.withValues(alpha: 0.18);

  // Field-icon accents. The portal gives each field a differently-coloured
  // label icon so a long form stays scannable — that hierarchy is worth
  // keeping, but the specific hues come from the app's palette, not Tailwind.
  static const Color iconPrimary = AppColors.primary;
  static const Color iconIndigo = AppColors.amenityIndigo;
  static const Color iconBlue = AppColors.amenityBlue;
  static const Color iconGreen = AppColors.amenityGreen;
  static const Color iconTeal = AppColors.statusLoanAvailableText;
  static const Color iconRed = AppColors.amenityRed;
  static const Color iconMuted = AppColors.textSecondary;

  // ── Shadows ────────────────────────────────────────────────────────────
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static List<BoxShadow> get cardShadowActive => [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.15),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  // ── Radii & spacing (from the portal) ──────────────────────────────────
  static const double cardRadius = 16;
  static const double imageRadius = 12;

  /// Wizard-wide spacing after the portal's CSS overrides: space-y-6 -> 10,
  /// space-y-4 -> 8, space-y-2 -> 4; grid gap-4 -> 8, gap-2 -> 4.
  static const double gapSm = 4;
  static const double gapMd = 8;
  static const double gapLg = 10;

  /// `[class*="card-content"] { padding: 10px 12px }`
  static const EdgeInsets cardContentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  /// `[class*="card-header"] { padding: 8px 12px }`
  static const EdgeInsets cardHeaderPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  /// Form fields are 34px tall in the portal.
  static const double inputHeight = 34;

  // ── Type ───────────────────────────────────────────────────────────────
  // Poppins throughout, via AppTextStyles. Sizes and weights follow the
  // portal's hierarchy; family and colour follow the app.

  /// Step heading — portal `h2 { 20px / 700 }`.
  static TextStyle get stepHeading => AppTextStyles.heading1.copyWith(
    fontSize: 20,
    letterSpacing: -0.4,
    height: 1.25,
  );

  /// Step subheading — portal `p { 13px }`.
  static TextStyle get stepSubheading => AppTextStyles.body.copyWith(
    fontSize: 13,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  /// Uppercase group label — portal `12px / 800 / 0.08em`.
  static TextStyle get groupLabel => AppTextStyles.caption.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.96,
  );

  /// Selection-card title — portal `18px / 500`.
  static TextStyle cardTitle(bool active) => AppTextStyles.heading3.copyWith(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: active ? AppColors.primary : AppColors.textPrimary,
    letterSpacing: -0.18,
    height: 1.2,
  );

  /// Selection-card description — portal `10px`.
  static TextStyle get cardDescription =>
      AppTextStyles.caption.copyWith(fontSize: 10, height: 1.35);

  /// Form field label — portal `13px / 500`.
  static TextStyle get inputLabel =>
      AppTextStyles.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500);

  /// Form input text — portal `14px`.
  static TextStyle get inputText => AppTextStyles.body;

  /// Footer step counter — portal `12px / 500`.
  static TextStyle get footerCounter =>
      AppTextStyles.caption.copyWith(fontSize: 12, fontWeight: FontWeight.w500);

  /// Footer buttons.
  static TextStyle get navButton => AppTextStyles.button;

  /// StepHeader title — portal `15px / 700`.
  static TextStyle get stepHeaderTitle => AppTextStyles.heading3.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  /// StepHeader subtitle — portal `12px`.
  static TextStyle get stepHeaderSubtitle => AppTextStyles.caption;

  /// StepHeader badge — portal `10px uppercase / 500`.
  static TextStyle pill(Color color) => AppTextStyles.chip.copyWith(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: color,
  );

  /// SectionDivider title — portal `13px / 700`.
  static TextStyle get sectionDividerTitle => AppTextStyles.heading3.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w700,
  );

  /// The bare `<h4 className="text-lg font-semibold tracking-tight">` heading
  /// PropertyDimensionsStep opens each block with ("Land Specfication",
  /// "Building Level Details", "Area Details", "PG Structure & Capacity", …).
  static TextStyle get blockHeading =>
      AppTextStyles.heading2.copyWith(fontSize: 18, letterSpacing: -0.45);

  /// The `<p className="text-sm text-muted-foreground">` under a block heading.
  static TextStyle get blockSubtitle =>
      AppTextStyles.body.copyWith(color: AppColors.textSecondary);

  /// SelectGroup label — portal `12px / 700 uppercase`.
  static TextStyle get selectGroupLabel => AppTextStyles.caption.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// Small grey note under a control — portal `11px`.
  static TextStyle get helperText =>
      AppTextStyles.caption.copyWith(fontSize: 11);

  /// ValidationSummary heading — portal `13px / 600`.
  static TextStyle get errorTitle => AppTextStyles.body.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.error,
  );

  /// ValidationSummary item — portal `12px`, dotted underline.
  static TextStyle get errorItem => AppTextStyles.caption.copyWith(
    fontSize: 12,
    color: AppColors.error,
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
  );

  /// Stepper node title — portal `15px / 800`.
  static TextStyle stepperTitle(Color color) => AppTextStyles.heading3.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: color,
    height: 1.15,
  );

  /// Stepper node sub-label — portal `12px / 500`.
  static TextStyle get stepperCounter => AppTextStyles.caption.copyWith(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textHint,
  );

  /// "Progress" card heading — portal `16px / 800`.
  static TextStyle get progressHeading => AppTextStyles.heading3.copyWith(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: AppColors.primary,
  );

  /// Percentage inside the ring — portal `11px / 900`.
  static TextStyle get progressPercent => AppTextStyles.caption.copyWith(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
  );
}

/// The wizard's selection indicator: a filled primary check when selected, an
/// outlined ring when not. 18x18 in both states.
class PortalCheckBadge extends StatelessWidget {
  const PortalCheckBadge({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: PortalTheme.radioIdle, width: 1.5),
        ),
      );
    }
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: PortalTheme.accent,
      ),
      child: const Icon(Icons.check, size: 11, color: Colors.white),
    );
  }
}

/// Small uppercase group label ("PROPERTY TYPE", "LISTING TYPE").
class PortalGroupLabel extends StatelessWidget {
  const PortalGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text.toUpperCase(), style: PortalTheme.groupLabel),
  );
}

/// The step's own heading block, as each portal step renders it.
class PortalStepHeading extends StatelessWidget {
  const PortalStepHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PortalTheme.stepHeading),
        const SizedBox(height: 4),
        Text(subtitle, style: PortalTheme.stepSubheading),
      ],
    ),
  );
}
