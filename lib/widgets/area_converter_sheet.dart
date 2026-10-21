// widgets/area_converter_sheet.dart
//
// Area unit converter, opened from the Home screen's Smart Tools section.
//
// THE CONVERSION TABLE IS PORTED, NOT DERIVED
// -------------------------------------------
// Every factor below is copied byte-for-byte from `features/tools/
// UnitConverter.tsx:9-14`. They are deliberately NOT recomputed from exact
// definitions (1 sq yd is exactly 9 sq ft, 1 acre is exactly 4840 sq yd, …)
// because the portal's table is itself rounded in places — `sq_ft → sq_yards` is
// `0.111111`, not `1/9` — and a "more correct" number here would make the app and
// the website disagree on the same conversion. Matching the reference wins.
//
// The sheet chrome (24 dp top corners, a 36 × 4 hairline drag handle) is the same
// composition `screens/search/widgets/filter_sheet.dart` established, so this
// reads as the same family as the filter sheet rather than a new kind of surface.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

// ── Sheet chrome, matching filter_sheet.dart ─────────────────────────────────
const double _kSheetRadius = 24;
const double _kHandleWidth = 36;
const double _kHandleHeight = 4;

/// Input corner radius. 14 is what `AppTheme.inputDecorationTheme` uses for every
/// other field in the app, so these match rather than introducing a second value.
const double _kFieldRadius = 14;

/// `UnitConverter.tsx:9-14`, verbatim.
const Map<String, Map<String, double>> kAreaConversions = {
  'sq_ft': {
    'sq_ft': 1,
    'sq_mtr': 0.092903,
    'sq_yards': 0.111111,
    'acres': 0.000022957,
    'hectares': 0.0000092903,
  },
  'sq_mtr': {
    'sq_ft': 10.7639,
    'sq_mtr': 1,
    'sq_yards': 1.19599,
    'acres': 0.000247105,
    'hectares': 0.0001,
  },
  'sq_yards': {
    'sq_ft': 9,
    'sq_mtr': 0.836127,
    'sq_yards': 1,
    'acres': 0.000206612,
    'hectares': 0.000083613,
  },
  'acres': {
    'sq_ft': 43560,
    'sq_mtr': 4046.86,
    'sq_yards': 4840,
    'acres': 1,
    'hectares': 0.404686,
  },
  'hectares': {
    'sq_ft': 107639,
    'sq_mtr': 10000,
    'sq_yards': 11959.9,
    'acres': 2.47105,
    'hectares': 1,
  },
};

/// `UnitConverter.tsx:17-22`, verbatim.
const Map<String, String> kAreaUnitLabels = {
  'sq_ft': 'Square Feet',
  'sq_mtr': 'Square Meters',
  'sq_yards': 'Square Yards',
  'acres': 'Acres',
  'hectares': 'Hectares',
};

/// Opens the converter.
Future<void> showAreaConverterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (_) => const _AreaConverterSheet(),
  );
}

class _AreaConverterSheet extends StatefulWidget {
  const _AreaConverterSheet();

  @override
  State<_AreaConverterSheet> createState() => _AreaConverterSheetState();
}

class _AreaConverterSheetState extends State<_AreaConverterSheet> {
  final TextEditingController _fromController = TextEditingController();

  // Same defaults as the portal: sq ft → sq m (UnitConverter.tsx:28-29).
  String _fromUnit = 'sq_ft';
  String _toUnit = 'sq_mtr';

  @override
  void dispose() {
    _fromController.dispose();
    super.dispose();
  }

  /// The parsed input, or null when the box is empty or not a number.
  ///
  /// `UnitConverter.tsx:31-33` gates on `fromValue && !isNaN(parseFloat(...))`
  /// and renders an empty result otherwise — no zero, no error.
  double? get _fromValue {
    final text = _fromController.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  double get _factor => kAreaConversions[_fromUnit]![_toUnit]!;

  /// 4 decimal places, matching the portal's `.toFixed(4)`.
  String get _result {
    final value = _fromValue;
    if (value == null) return '';
    return (value * _factor).toStringAsFixed(4);
  }

  void _swapUnits() {
    HapticFeedback.selectionClick();
    setState(() {
      final previousFrom = _fromUnit;
      _fromUnit = _toUnit;
      _toUnit = previousFrom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard instead of letting it cover the
        // result field.
        padding: EdgeInsets.only(bottom: viewInsets),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingXL,
              AppConstants.spacingM,
              AppConstants.spacingXL,
              AppConstants.spacingXL,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetDragHandle(),
                const SheetToolHeader(
                  icon: Icons.grid_view_rounded,
                  title: 'Area Converter',
                  subtitle: 'Convert between area units instantly',
                ),
                const SizedBox(height: AppConstants.spacingXL),

                _label('From'),
                const SizedBox(height: AppConstants.spacingS),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _fromController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: sheetFieldDecoration(hint: 'Enter value'),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      flex: 6,
                      child: _unitDropdown(
                        value: _fromUnit,
                        onChanged: (v) => setState(() => _fromUnit = v),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppConstants.spacingM),
                Center(
                  child: Semantics(
                    button: true,
                    label: 'Swap units',
                    child: GestureDetector(
                      onTap: _swapUnits,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppColors.primaryGlow,
                        ),
                        child: const Icon(
                          Icons.swap_vert_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingM),

                _label('To'),
                const SizedBox(height: AppConstants.spacingS),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Container(
                        height: 52,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(_kFieldRadius),
                        ),
                        child: Text(
                          _result.isEmpty ? '—' : _result,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _result.isEmpty
                                ? AppColors.textHint
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      flex: 6,
                      child: _unitDropdown(
                        value: _toUnit,
                        onChanged: (v) => setState(() => _toUnit = v),
                      ),
                    ),
                  ],
                ),

                // Shown only once a value is entered — the portal's own
                // conditional (UnitConverter.tsx renders the formula line under
                // the same `fromValue` guard as the result).
                if (_fromValue != null) ...[
                  const SizedBox(height: AppConstants.spacingL),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppConstants.spacingM),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(_kFieldRadius),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Text(
                      '${_trimZeros(_fromValue!)} ${kAreaUnitLabels[_fromUnit]} '
                      '× ${_trimZeros(_factor)} = $_result '
                      '${kAreaUnitLabels[_toUnit]}',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTextStyles.body.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    ),
  );

  Widget _unitDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(_kFieldRadius),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.textSecondary,
      ),
      style: AppTextStyles.body.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: sheetFieldDecoration(),
      items: [
        for (final entry in kAreaUnitLabels.entries)
          DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  /// `1.0` reads as `1`, `0.092903` stays intact — so the formula line does not
  /// print "1.0 Square Feet".
  static String _trimZeros(double value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sheet chrome
//
// Declared here and reused by the other two tool/form sheets rather than
// re-implemented three times, so all three have an identical handle, header and
// field treatment. They are in this file because it is the first of the three
// alphabetically and every one of them already imports it for the converter —
// no fourth file just to hold twenty lines.
// ─────────────────────────────────────────────────────────────────────────────

/// The grab handle every bottom sheet in the app opens with.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: _kHandleWidth,
      height: _kHandleHeight,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.hairline,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
    ),
  );
}

/// Gradient icon badge + title + subtitle, the composition `QuickActionsSection`
/// uses for its cards, scaled up for a sheet header.
class SheetToolHeader extends StatelessWidget {
  const SheetToolHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(13),
            boxShadow: AppColors.primaryGlow,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.heading3.copyWith(fontSize: 17)),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: 'Close',
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The field treatment every sheet form uses.
///
/// `AppTheme.inputDecorationTheme` fills white with **no** enabled border and a
/// 2 dp primary focused border. On a white sheet a white fill with no border is
/// invisible, so the fill and the enabled border are overridden here. The radius
/// stays at the theme's 14 so these fields match the rest of the app.
InputDecoration sheetFieldDecoration({
  String? hint,
  String? label,
  Widget? suffixIcon,
  bool enabled = true,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(_kFieldRadius),
    borderSide: BorderSide(color: color, width: width),
  );

  return InputDecoration(
    hintText: hint,
    labelText: label,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: enabled ? AppColors.surfaceMuted : AppColors.hairlineStrong,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    hintStyle: AppTextStyles.body.copyWith(
      fontSize: 13,
      color: AppColors.textHint,
    ),
    labelStyle: AppTextStyles.body.copyWith(
      fontSize: 13,
      color: AppColors.textSecondary,
    ),
    floatingLabelStyle: AppTextStyles.body.copyWith(
      fontSize: 13,
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    ),
    // All six slots are set explicitly. Leaving any of them to the theme brings
    // back its own border and the field stops matching its siblings.
    border: border(AppColors.hairline, 1),
    enabledBorder: border(AppColors.hairline, 1),
    focusedBorder: border(AppColors.primary, 1.6),
    disabledBorder: border(AppColors.hairline, 1),
    errorBorder: border(AppColors.error, 1),
    focusedErrorBorder: border(AppColors.error, 1.6),
    errorStyle: AppTextStyles.caption.copyWith(
      fontSize: 11,
      color: AppColors.error,
    ),
  );
}
