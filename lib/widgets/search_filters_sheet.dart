// widgets/search_filters_sheet.dart
//
// The quick "Filters" sheet for the Search screen: property Type, Listing,
// and a Budget histogram with a range slider and editable Minimum / Maximum
// fields - the portal's search filter modal (Search.tsx), same options and the
// same ₹0 - ₹50Cr+ range. Apply writes the choices to [FilterProvider], runs
// the search, and reports success to the caller.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../providers/filter_provider.dart';
import '../providers/property_provider.dart';

/// Opens the sheet. Completes with true when the user applied filters.
Future<bool?> showSearchFiltersSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SearchFiltersSheet(),
  );
}

const List<(String?, String)> _kTypes = [
  (null, 'All Types'),
  ('residential', 'Residential'),
  ('commercial', 'Commercial'),
  ('land', 'Land / Plot'),
  ('pg_coliving', 'PG / Co-living'),
  ('others', 'Others'),
];

const List<(String?, String)> _kListings = [
  (null, 'Any'),
  ('sell', 'For Sale'),
  ('rent', 'For Rent'),
  ('lease', 'Lease'),
];

/// ₹0, ₹50L, ₹1.5Cr - the portal's `formatPriceLabel`. The top of the range is
/// open-ended, so it reads "₹50Cr+".
String _priceLabel(double v) {
  if (v >= AppConstants.priceMax) return '₹50Cr+';
  if (v >= 10000000) {
    final cr = v / 10000000;
    return '₹${cr == cr.roundToDouble() ? cr.toStringAsFixed(0) : cr.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}Cr';
  }
  if (v >= 100000) {
    final l = v / 100000;
    return '₹${l == l.roundToDouble() ? l.toStringAsFixed(0) : l.toStringAsFixed(1)}L';
  }
  return '₹${v.round()}';
}

/// Parses what a user types into a Minimum/Maximum box: "2500000", "25L",
/// "1.5 cr", "₹50Cr+". Null when it is not a number.
double? _parsePrice(String raw) {
  var t = raw.toLowerCase().replaceAll(RegExp(r'[₹,\s+]'), '');
  if (t.isEmpty) return null;
  var mult = 1.0;
  if (t.endsWith('cr')) {
    mult = 10000000;
    t = t.substring(0, t.length - 2);
  } else if (t.endsWith('l') || t.endsWith('lac') || t.endsWith('lakh')) {
    mult = 100000;
    t = t.replaceAll(RegExp(r'(lakh|lac|l)$'), '');
  }
  final n = double.tryParse(t);
  return n == null ? null : n * mult;
}

class _SearchFiltersSheet extends StatefulWidget {
  const _SearchFiltersSheet();

  @override
  State<_SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends State<_SearchFiltersSheet> {
  late String? _type;
  late String? _listing;
  late RangeValues _range;

  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  final FocusNode _minFocus = FocusNode();
  final FocusNode _maxFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final f = context.read<FilterProvider>();
    _type = f.category;
    _listing = f.listingType;
    _range = f.budgetRange;
    _minCtrl = TextEditingController(text: _priceLabel(_range.start));
    _maxCtrl = TextEditingController(text: _priceLabel(_range.end));
    _minFocus.addListener(() {
      if (!_minFocus.hasFocus) _commitMin();
    });
    _maxFocus.addListener(() {
      if (!_maxFocus.hasFocus) _commitMax();
    });
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _minFocus.dispose();
    _maxFocus.dispose();
    super.dispose();
  }

  void _setRange(RangeValues v) {
    _range = v;
    _minCtrl.text = _priceLabel(v.start);
    _maxCtrl.text = _priceLabel(v.end);
  }

  void _commitMin() {
    final v = _parsePrice(_minCtrl.text);
    setState(() {
      if (v == null) {
        _minCtrl.text = _priceLabel(_range.start);
        return;
      }
      final start = v.clamp(AppConstants.priceMin, _range.end).toDouble();
      // Only this box is rewritten - the other may hold text not yet committed.
      _range = RangeValues(start, _range.end);
      _minCtrl.text = _priceLabel(start);
    });
  }

  void _commitMax() {
    final v = _parsePrice(_maxCtrl.text);
    setState(() {
      if (v == null) {
        _maxCtrl.text = _priceLabel(_range.end);
        return;
      }
      final end = v.clamp(_range.start, AppConstants.priceMax).toDouble();
      _range = RangeValues(_range.start, end);
      _maxCtrl.text = _priceLabel(end);
    });
  }

  void _resetAll() {
    setState(() {
      _type = null;
      _listing = null;
      _setRange(
        const RangeValues(AppConstants.priceMin, AppConstants.priceMax),
      );
    });
  }

  void _apply() {
    // Commit anything still being typed.
    _commitMin();
    _commitMax();
    final f = context.read<FilterProvider>();
    if (f.category != _type) {
      // A subtype / BHK belongs to one category - drop them when it changes.
      f.setSubtype(null);
      f.setBhk(null);
    }
    f.setCategory(_type);
    f.setListingType(_listing);
    f.setBudgetRange(_range);
    context.read<PropertyProvider>().runSearch(f.toQueryParams(), reset: true);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              _header(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dropdown(
                              label: 'TYPE',
                              value: _type,
                              options: _kTypes,
                              onChanged: (v) => setState(() => _type = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dropdown(
                              label: 'LISTING',
                              value: _listing,
                              options: _kListings,
                              onChanged: (v) => setState(() => _listing = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _label('BUDGET (₹)'),
                      const SizedBox(height: 2),
                      Text(
                        '${_priceLabel(_range.start)} — ${_priceLabel(_range.end)}',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _histogram(),
                      _slider(),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _priceField(
                              'MINIMUM',
                              _minCtrl,
                              _minFocus,
                              _commitMin,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _priceField(
                              'MAXIMUM',
                              _maxCtrl,
                              _maxFocus,
                              _commitMax,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            final nav = Navigator.of(context);
                            nav.pop();
                            nav.pushNamed(AppConstants.filtersScreen);
                          },
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Bedrooms, subtype & more'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 20, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Filters',
              style: AppTextStyles.heading2.copyWith(fontSize: 19),
            ),
          ),
          GestureDetector(
            onTap: _resetAll,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'RESET ALL',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTextStyles.caption.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      fontSize: 11,
      color: AppColors.textHint,
    ),
  );

  Widget _dropdown({
    required String label,
    required String? value,
    required List<(String?, String)> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: value,
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textHint,
              ),
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              items: [
                for (final o in options)
                  DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  /// A fixed bell-shaped histogram (the portal's is also static, decorative
  /// data); bars inside the selected range are orange, the rest pale.
  Widget _histogram() {
    const bars = 20;
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Builder(
                builder: (_) {
                  final x = (i - (bars - 1) / 2) / (bars / 3.2);
                  final h = 0.28 + 0.72 * _gauss(x);
                  final pos = i / (bars - 1) * AppConstants.priceMax;
                  final on = pos >= _range.start && pos <= _range.end;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 72 * h,
                    decoration: BoxDecoration(
                      color: on
                          ? AppColors.primary.withValues(alpha: 0.28)
                          : AppColors.hairline,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _gauss(double x) {
    // exp(-x^2 / 2) without dart:math import noise.
    var r = 1.0;
    final k = x * x / 2;
    // Taylor-free approximation good enough for a decorative curve.
    r = 1 / (1 + k + k * k / 2 + k * k * k / 6);
    return r;
  }

  Widget _slider() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.hairline,
        rangeThumbShape: const RoundRangeSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 0,
          pressedElevation: 0,
        ),
        thumbColor: Colors.white,
        overlayColor: AppColors.primary.withValues(alpha: 0.12),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      ),
      child: RangeSlider(
        values: _range,
        min: AppConstants.priceMin,
        max: AppConstants.priceMax,
        divisions:
            ((AppConstants.priceMax - AppConstants.priceMin) /
                    AppConstants.priceStep)
                .round(),
        onChanged: (v) => setState(() => _setRange(v)),
      ),
    );
  }

  Widget _priceField(
    String label,
    TextEditingController ctrl,
    FocusNode focus,
    VoidCallback onCommit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹lLcCrRaAkKhH+ ]')),
            ],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onCommit(),
            onTap: () => ctrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: ctrl.text.length,
            ),
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _apply,
                    child: Center(
                      child: Text(
                        'Apply Filters',
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
