// widgets/stamp_duty_calculator_sheet.dart
//
// Stamp duty + registration charge calculator, opened from Home's Smart Tools.
//
// RATES AND THE 1% CONSTANT ARE PORTED, NOT SOURCED
// -------------------------------------------------
// `kStampDutyRates` is `features/tools/StampDutyCalculator.tsx:8-19` verbatim,
// including its own comment that these are *simplified* rates. Registration is a
// flat 1% (`value * 0.01`, StampDutyCalculator.tsx:51). Neither is adjusted here:
// real state schedules have slabs, urban/rural splits and caps that the portal
// does not model, and "fixing" the app alone would make the two products quote
// different numbers for the same property.
//
// Recalculation is live on every change, matching the portal's
// `useEffect([propertyValue, state, gender])` — there is no Calculate button.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'area_converter_sheet.dart'
    show SheetDragHandle, SheetToolHeader, sheetFieldDecoration;

const double _kSheetRadius = 24;
const double _kFieldRadius = 14;

/// `StampDutyCalculator.tsx:8-19`, verbatim. Percentages, not fractions.
const Map<String, Map<String, double>> kStampDutyRates = {
  'maharashtra': {'male': 6, 'female': 5},
  'delhi': {'male': 6, 'female': 4},
  'karnataka': {'male': 5.6, 'female': 5.6},
  'tamil_nadu': {'male': 7, 'female': 7},
  'gujarat': {'male': 4.9, 'female': 4.9},
  'rajasthan': {'male': 6, 'female': 5},
  'uttar_pradesh': {'male': 7, 'female': 6},
  'telangana': {'male': 6, 'female': 6},
  'west_bengal': {'male': 7, 'female': 6},
  'punjab': {'male': 7, 'female': 6},
};

/// `StampDutyCalculator.tsx:21-32`, verbatim.
const Map<String, String> kStampDutyStateLabels = {
  'maharashtra': 'Maharashtra',
  'delhi': 'Delhi',
  'karnataka': 'Karnataka',
  'tamil_nadu': 'Tamil Nadu',
  'gujarat': 'Gujarat',
  'rajasthan': 'Rajasthan',
  'uttar_pradesh': 'Uttar Pradesh',
  'telangana': 'Telangana',
  'west_bengal': 'West Bengal',
  'punjab': 'Punjab',
};

/// Registration charge, as a fraction of the property value.
/// `StampDutyCalculator.tsx:51` — "Typically 1% for registration".
const double kRegistrationRate = 0.01;

/// Opens the calculator.
Future<void> showStampDutyCalculatorSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (_) => const _StampDutySheet(),
  );
}

class _StampDutySheet extends StatefulWidget {
  const _StampDutySheet();

  @override
  State<_StampDutySheet> createState() => _StampDutySheetState();
}

class _StampDutySheetState extends State<_StampDutySheet> {
  // Same seed as the portal (StampDutyCalculator.tsx:34-36).
  final TextEditingController _valueController = TextEditingController(
    text: '5000000',
  );
  String _state = 'maharashtra';
  String _gender = 'male';

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  /// Zero for a blank, non-numeric or non-positive input — the portal's
  /// `isNaN(value) || value <= 0` branch resets all three figures to 0.
  double get _propertyValue {
    final parsed = double.tryParse(_valueController.text.trim()) ?? 0;
    return parsed > 0 ? parsed : 0;
  }

  double get _rate => kStampDutyRates[_state]![_gender]!;

  double get _stampDuty => _propertyValue * _rate / 100;

  double get _registrationCharges => _propertyValue * kRegistrationRate;

  double get _totalCharges => _stampDuty + _registrationCharges;

  /// `EmiCalculatorWidget._formatCurrency`'s breakpoints, copied so the two
  /// calculators never disagree on how a figure is written: ₹1Cr and above in Cr,
  /// ₹1L and above in L, anything smaller in full rupees.
  ///
  /// The portal's own `formatCurrency` (StampDutyCalculator.tsx:57-64) uses the
  /// same two breakpoints and the same 2 decimal places.
  String _formatCurrency(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(2)} Cr';
    }
    if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(2)} L';
    return '₹${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
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
                  icon: Icons.receipt_long_rounded,
                  title: 'Stamp Duty Calculator',
                  subtitle: 'Stamp duty and registration charges',
                ),
                const SizedBox(height: AppConstants.spacingXL),

                _label('Property Value'),
                const SizedBox(height: AppConstants.spacingS),
                TextField(
                  controller: _valueController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: sheetFieldDecoration(hint: 'Enter property value')
                      .copyWith(
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 14, right: 8),
                          child: Text(
                            '₹',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                      ),
                ),
                const SizedBox(height: AppConstants.spacingL),

                _label('State'),
                const SizedBox(height: AppConstants.spacingS),
                DropdownButtonFormField<String>(
                  initialValue: _state,
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
                    for (final entry in kStampDutyStateLabels.entries)
                      DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _state = v);
                  },
                ),
                const SizedBox(height: AppConstants.spacingL),

                _label('Buyer'),
                const SizedBox(height: AppConstants.spacingS),
                Row(
                  children: [
                    Expanded(child: _genderChip('male', 'Male')),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(child: _genderChip('female', 'Female')),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingXL),

                _resultBlock(),
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

  /// Several states charge women a lower rate, so this changes the number — it is
  /// a rate input, not a demographic question, and the sub-card label spells out
  /// the percentage it produced.
  Widget _genderChip(String value, String label) {
    final bool selected = _gender == value;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _gender = value);
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(_kFieldRadius),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.hairline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Text(
              label,
              style: AppTextStyles.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultBlock() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Column(
        children: [
          Text(
            'Total Charges',
            style: AppTextStyles.caption.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatCurrency(_totalCharges),
              style: AppTextStyles.heading1.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
          Row(
            children: [
              Expanded(
                child: _subCard(
                  // The active rate is named, so a user can see why switching
                  // state or buyer changed the total.
                  'Stamp Duty (${_trimRate(_rate)}%)',
                  _formatCurrency(_stampDuty),
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              Expanded(
                child: _subCard(
                  'Registration (1%)',
                  _formatCurrency(_registrationCharges),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _subCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingM,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.body.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `6` not `6.0`, but `5.6` stays `5.6`.
  static String _trimRate(double rate) =>
      rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();
}
