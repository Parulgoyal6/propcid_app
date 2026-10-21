import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/filter_provider.dart';

// ── Prototype dimensions without an existing token ───────────────────────────

/// The sheet's own top corners, its drag handle, and the fraction of the
/// viewport it may occupy.
const double _kSheetRadius = 24;
const double _kHandleWidth = 36;
const double _kHandleHeight = 4;
const double _kMaxHeightFraction = 0.82;

/// Every dropdown field and the Minimum/Maximum readouts.
const double _kFieldHeight = 44;

/// A bedroom pill.
const double _kBhkChipHeight = 38;

/// The decorative budget histogram.
const double _kHistogramHeight = 44;

/// Footer buttons.
const double _kFooterButtonHeight = 48;

/// Static bar heights, as percentages — the redesign's own array, verbatim.
///
/// Decorative, and deliberately so. Real bucket counts would need an aggregate
/// over `properties.price`, which is a free-text column, and the web portal's
/// equivalent histogram is generated with `Math.random()` on every render. This
/// at least renders the same shape every time.
const List<double> _kHistogram = [
  30,
  38,
  45,
  52,
  60,
  68,
  74,
  80,
  86,
  92,
  96,
  100,
  98,
  90,
  84,
  76,
  68,
  58,
  48,
  38,
];

/// One selectable value in a dropdown. A null [value] is the "no filter" row.
class _Option {
  final String label;
  final String? value;

  const _Option({required this.label, this.value});
}

/// A labelled block of options, matching the redesign's grouped subtype list.
class _OptionGroup {
  final String? heading;
  final List<_Option> options;

  const _OptionGroup({this.heading, required this.options});
}

const List<_Option> _kCategoryOptions = [
  _Option(label: 'All Types'),
  _Option(label: 'Residential', value: 'residential'),
  _Option(label: 'Commercial', value: 'commercial'),
  _Option(label: 'Land / Plot', value: 'land'),
  _Option(label: 'PG / Co-living', value: 'pg_coliving'),
  _Option(label: 'Others', value: 'others'),
];

const List<_Option> _kListingOptions = [
  _Option(label: 'Any'),
  _Option(label: 'Buy', value: 'sell'),
  _Option(label: 'Rent', value: 'rent'),
  _Option(label: 'Lease', value: 'lease'),
];

/// The strings `PropertyService` maps onto `profiles.user_type` groups.
const List<_Option> _kPostedByOptions = [
  _Option(label: 'Anyone'),
  _Option(label: 'Owner', value: 'Owner'),
  _Option(label: 'Agent', value: 'Agent'),
  _Option(label: 'Builder', value: 'Builder'),
];

/// Residential subtypes, grouped exactly as the redesign groups them.
///
/// The VALUES are the web portal's `residentialSubTypeGroups` list, not the
/// redesign's — the redesign's mock omits Bungalow and Farm House, and dropdown
/// values are business data where React is the source of truth (CLAUDE.md), so
/// the shorter list would silently drop two real subtypes. The redesign's
/// *presentation* (two headed groups, an "All" row first) is what is reproduced.
///
/// Each value is also the literal `properties.residential_subtype` cell content,
/// which matters because `PropertyService` matches it with `ilike('%value%')`.
const List<_OptionGroup> _kSubtypeGroups = [
  _OptionGroup(options: [_Option(label: 'All Subtypes')]),
  _OptionGroup(
    heading: 'APARTMENT',
    options: [
      _Option(label: 'Flat', value: 'Flat'),
      _Option(
        label: 'Independent / Builder Floor',
        value: 'Independent / Builder Floor',
      ),
      _Option(
        label: 'Studio / Service Apartment',
        value: 'Studio / Service Apartment',
      ),
    ],
  ),
  _OptionGroup(
    heading: 'HOUSE',
    options: [
      _Option(
        label: 'Raw / Independent House',
        value: 'Raw / Independent House',
      ),
      _Option(label: 'Villa / Kothi', value: 'Villa / Kothi'),
      _Option(label: 'Duplex House', value: 'Duplex House'),
      _Option(label: 'Triplex House', value: 'Triplex House'),
      _Option(label: 'Pent House', value: 'Pent House'),
      _Option(label: 'Bungalow', value: 'Bungalow'),
      _Option(label: 'Farm House', value: 'Farm House'),
    ],
  ),
];

/// `null` is "Any"; 5 means "5 or more", which `PropertyService` turns into
/// `gte('bedrooms', 5)`.
const List<({String label, int? value})> _kBhkOptions = [
  (label: 'Any BHK', value: null),
  (label: '1 BHK', value: 1),
  (label: '2 BHK', value: 2),
  (label: '3 BHK', value: 3),
  (label: '4 BHK', value: 4),
  (label: '5+ BHK', value: 5),
];

/// Which dropdown is currently expanded. Only one at a time, as in the redesign.
enum _OpenField { none, category, listing, subtype, postedBy }

/// Opens the search filter sheet.
///
/// Returns true when the user pressed Apply, meaning [FilterProvider] now holds
/// new values and the caller should re-run its search. Returns false for Cancel,
/// a scrim tap, a swipe-down or a back gesture — in which case nothing was
/// committed and the caller has nothing to do.
Future<bool> showSearchFilterSheet(BuildContext context) async {
  final bool? applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (sheetContext) => const _FilterSheet(),
  );
  return applied ?? false;
}

/// The sheet body.
///
/// Holds every control's value in its own local draft state and writes to
/// [FilterProvider] only when Apply is pressed. That is what makes Cancel free:
/// there is nothing to roll back, because nothing was ever committed. The
/// alternative — mutating the provider live and snapshotting it on open — would
/// mean adding restore plumbing to a provider several other screens listen to.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet();

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static const RangeValues _kDefaultBudget = RangeValues(
    AppConstants.priceMin,
    AppConstants.priceMax,
  );

  String? _category;
  String? _listingType;
  RangeValues _budget = _kDefaultBudget;
  int? _bhk;
  String? _subtype;
  String? _postedBy;

  _OpenField _openField = _OpenField.none;

  @override
  void initState() {
    super.initState();
    // Seeded once, so every control opens showing what is currently applied.
    final filterProvider = context.read<FilterProvider>();
    _category = filterProvider.category;
    _listingType = filterProvider.listingType;
    _budget = filterProvider.budgetRange;
    _bhk = filterProvider.bhk;
    _subtype = filterProvider.subtype;
    _postedBy = filterProvider.postedBy;
  }

  bool get _isDefaultBudget =>
      _budget.start <= AppConstants.priceMin &&
      _budget.end >= AppConstants.priceMax;

  /// Mirrors [FilterProvider.activeFilterCount]'s rule exactly — category,
  /// listing type, non-default budget, bhk, subtype, posted by; never search
  /// text, cities, sort or near-me.
  ///
  /// Computed here rather than read from the provider because this badge has to
  /// track the DRAFT: the provider still holds the committed values until Apply.
  int get _draftFilterCount {
    int count = 0;
    if (_category != null) count++;
    if (_listingType != null) count++;
    if (!_isDefaultBudget) count++;
    if (_bhk != null) count++;
    if (_subtype != null) count++;
    if (_postedBy != null) count++;
    return count;
  }

  void _toggleField(_OpenField field) {
    setState(() {
      _openField = _openField == field ? _OpenField.none : field;
    });
  }

  /// Clears the draft only. Deliberately does NOT call
  /// [FilterProvider.resetFilters], which would both commit immediately and
  /// wipe `searchText` — the query the user is filtering is not a filter.
  void _resetDraft() {
    setState(() {
      _category = null;
      _listingType = null;
      _budget = _kDefaultBudget;
      _bhk = null;
      _subtype = null;
      _postedBy = null;
      _openField = _OpenField.none;
    });
  }

  /// The single commit point. Writes the draft through existing setters — no new
  /// provider API — then hands `true` back so the caller can re-run the search.
  void _apply() {
    // The one committing action in the sheet; everything before it was a draft.
    HapticFeedback.mediumImpact();
    final filterProvider = context.read<FilterProvider>();
    filterProvider.setCategory(_category);
    filterProvider.setListingType(_listingType);
    filterProvider.setBudgetRange(_budget);
    filterProvider.setBhk(_bhk);
    filterProvider.setSubtype(_subtype);
    filterProvider.setPostedBy(_postedBy);
    Navigator.pop(context, true);
  }

  /// Port of the portal's `formatPriceLabel`, which is what produces the
  /// redesign's "₹0 — ₹50Cr+" reading.
  String _priceLabel(double value) {
    final int crCeiling = (AppConstants.priceMax / 10000000).round();
    if (value >= AppConstants.priceMax) return '₹${crCeiling}Cr+';
    if (value <= 0) return '₹0';
    if (value >= 10000000) {
      final String cr = (value / 10000000)
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      return '₹${cr}Cr';
    }
    return '₹${(value / 100000).round()}L';
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight =
        MediaQuery.sizeOf(context).height * _kMaxHeightFraction;

    // The handle, header and footer are pinned; only the filter sections scroll.
    //
    // The redesign puts `overflow-y:auto` on the whole sheet, which would let the
    // footer scroll away with the content. Reproducing that literally made the
    // primary action unreachable: these sections total roughly 700 dp, so on any
    // viewport where 82% is less than that — a short phone, a landscape window —
    // Apply sits below the fold and cannot be tapped until the user scrolls past
    // every control. Verified: every tap on Apply missed its target before this
    // changed. Pinning is the one deviation here, and it is a reachability fix
    // rather than a style preference; the visual order and spacing are unchanged.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingXL,
                10,
                AppConstants.spacingXL,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [_buildHandle(), _buildHeader()],
              ),
            ),
            // Flexible, not Expanded: a short section list must leave the sheet
            // sized to its content rather than stretching it to the full 82%.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingXL,
                  18,
                  AppConstants.spacingXL,
                  22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTypeAndListing(),
                    const SizedBox(height: AppConstants.spacingXL),
                    _buildBudget(),
                    const SizedBox(height: 18),
                    _buildMinMax(),
                    // Bedrooms is residential-only, same as subtype; the
                    // portal hides the whole block (not just disables it)
                    // for every other category.
                    if (_category == 'residential') ...[
                      const SizedBox(height: AppConstants.spacingXL),
                      _buildBedrooms(),
                    ],
                    const SizedBox(height: AppConstants.spacingXL),
                    _buildSubtypeAndPostedBy(),
                  ],
                ),
              ),
            ),
            Container(height: 1, color: AppColors.hairlineStrong),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingXL,
                AppConstants.spacingL,
                AppConstants.spacingXL,
                AppConstants.spacingXL,
              ),
              child: _buildFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
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

  Widget _buildHeader() {
    final int count = _draftFilterCount;

    return Row(
      children: [
        const Icon(Icons.tune, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: AppConstants.spacingS),
        Text(
          'Filters',
          style: AppTextStyles.heading3.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: AppConstants.spacingS),
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$count',
              style: AppTextStyles.chip.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
        const Spacer(),
        Semantics(
          label: 'Reset all filters',
          button: true,
          child: GestureDetector(
            onTap: count == 0 ? null : _resetDraft,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppConstants.spacingS,
              ),
              child: Text(
                'RESET ALL',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  // Dimmed when there is nothing to reset, matching the portal's
                  // own disabled treatment for this control.
                  color: count == 0
                      ? AppColors.textHint
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Semantics(
          label: 'Close filters',
          button: true,
          child: GestureDetector(
            onTap: () => Navigator.pop(context, false),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textHint,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTypeAndListing() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildDropdown(
            label: 'TYPE',
            field: _OpenField.category,
            selectedLabel: _labelFor(_kCategoryOptions, _category),
            groups: const [_OptionGroup(options: _kCategoryOptions)],
            selectedValue: _category,
            onSelected: (value) => setState(() {
              _category = value;
              // Subtype and bedrooms only mean anything under Residential, so
              // neither can outlive a switch away from it — the same pairing
              // the results chip row enforces when the category chip is
              // cleared.
              if (value != 'residential') {
                _subtype = null;
                _bhk = null;
              }
              _openField = _OpenField.none;
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildDropdown(
            label: 'LISTING',
            field: _OpenField.listing,
            selectedLabel: _labelFor(_kListingOptions, _listingType),
            groups: const [_OptionGroup(options: _kListingOptions)],
            selectedValue: _listingType,
            onSelected: (value) => setState(() {
              _listingType = value;
              _openField = _OpenField.none;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtypeAndPostedBy() {
    // Subtype is residential-only; the portal gates it the same way.
    final bool subtypeEnabled = _category == 'residential';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildDropdown(
            label: 'SUBTYPE',
            field: _OpenField.subtype,
            selectedLabel: subtypeEnabled
                ? _labelForGroups(_kSubtypeGroups, _subtype)
                : 'Residential only',
            groups: _kSubtypeGroups,
            selectedValue: _subtype,
            enabled: subtypeEnabled,
            onSelected: (value) => setState(() {
              _subtype = value;
              _openField = _OpenField.none;
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildDropdown(
            label: 'POSTED BY',
            field: _OpenField.postedBy,
            selectedLabel: _labelFor(_kPostedByOptions, _postedBy),
            groups: const [_OptionGroup(options: _kPostedByOptions)],
            selectedValue: _postedBy,
            onSelected: (value) => setState(() {
              _postedBy = value;
              _openField = _OpenField.none;
            }),
          ),
        ),
      ],
    );
  }

  String _labelFor(List<_Option> options, String? value) {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return options.first.label;
  }

  String _labelForGroups(List<_OptionGroup> groups, String? value) {
    for (final group in groups) {
      for (final option in group.options) {
        if (option.value == value) return option.label;
      }
    }
    return groups.first.options.first.label;
  }

  /// A field that expands its options in place.
  ///
  /// In-place rather than an absolutely-positioned overlay: the redesign draws
  /// the panel floating over the content, but this sheet is itself a scroll view,
  /// and a panel escaping its parent would need `Overlay` plumbing and could not
  /// be tapped outside the sheet's bounds. Pushing the list down inside the same
  /// scroll gets the same result with none of that.
  Widget _buildDropdown({
    required String label,
    required _OpenField field,
    required String selectedLabel,
    required List<_OptionGroup> groups,
    required String? selectedValue,
    required ValueChanged<String?> onSelected,
    bool enabled = true,
  }) {
    final bool isOpen = enabled && _openField == field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 6),
        Semantics(
          label: '$label: $selectedLabel',
          button: true,
          child: GestureDetector(
            onTap: enabled ? () => _toggleField(field) : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: _kFieldHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingM,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                border: Border.all(color: AppColors.hairline),
                color: enabled ? null : AppColors.background,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedLabel,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isOpen)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(
                  AppConstants.searchBarRadius,
                ),
                border: Border.all(color: AppColors.hairlineStrong),
                boxShadow: AppColors.surfaceCardShadow,
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in groups) ...[
                    if (group.heading != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                        child: Text(
                          group.heading!,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textHint,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    for (final option in group.options)
                      _buildOptionRow(
                        option: option,
                        isSelected: option.value == selectedValue,
                        onTap: () => onSelected(option.value),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionRow({
    required _Option option,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: option.label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            // The redesign tints the selected row; `primaryLight` is the app's
            // established selection fill, reused here rather than introducing a
            // second one.
            color: isSelected ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(
              AppConstants.segmentedTabItemRadius,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 15,
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 15,
                        color: AppColors.primary,
                      )
                    : null,
              ),
              const SizedBox(width: AppConstants.spacingS),
              Expanded(
                child: Text(
                  option.label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBudget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('BUDGET (₹)'),
        const SizedBox(height: AppConstants.spacingXS),
        Text(
          '${_priceLabel(_budget.start)} — ${_priceLabel(_budget.end)}',
          style: AppTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        _buildHistogram(),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.hairline,
            rangeThumbShape: const _RingThumbShape(),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: RangeSlider(
            values: _budget,
            min: AppConstants.priceMin,
            max: AppConstants.priceMax,
            // Snaps to ₹10 L increments, matching the reference's
            // `step={PRICE_STEP}` (Search.tsx) — without this the slider
            // dragged continuously and landed on odd, non-round values that
            // never matched the reference's behavior.
            divisions:
                ((AppConstants.priceMax - AppConstants.priceMin) /
                        AppConstants.priceStep)
                    .round(),
            onChanged: (values) => setState(() => _budget = values),
          ),
        ),
      ],
    );
  }

  Widget _buildHistogram() {
    return SizedBox(
      height: _kHistogramHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (int i = 0; i < _kHistogram.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: FractionallySizedBox(
                heightFactor: _kHistogram[i] / 100,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    // Derived from the existing primary rather than adding a new
                    // lavender token; lands within a shade of the redesign's bar.
                    color: AppColors.primary.withValues(alpha: 0.25),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMinMax() {
    return Row(
      children: [
        Expanded(child: _buildReadout('MINIMUM', _priceLabel(_budget.start))),
        const SizedBox(width: 10),
        Expanded(child: _buildReadout('MAXIMUM', _priceLabel(_budget.end))),
      ],
    );
  }

  Widget _buildReadout(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(label),
        const SizedBox(height: 6),
        Container(
          height: _kFieldHeight,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBedrooms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('BEDROOMS'),
        const SizedBox(height: 10),
        Wrap(
          spacing: AppConstants.spacingS,
          runSpacing: AppConstants.spacingS,
          children: [
            for (final option in _kBhkOptions)
              _buildBhkChip(option.label, option.value),
          ],
        ),
      ],
    );
  }

  Widget _buildBhkChip(String label, int? value) {
    final bool isSelected = _bhk == value;

    return Semantics(
      label: label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: () => setState(() => _bhk = value),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _kBhkChipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryLight
                : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.hairline,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.chip.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: 'Cancel',
            button: true,
            child: GestureDetector(
              onTap: () => Navigator.pop(context, false),
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: _kFooterButtonHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                  border: Border.all(color: AppColors.hairline, width: 1.5),
                ),
                child: Text(
                  'Cancel',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          // flex 2 : 1 against Cancel, as in the redesign.
          flex: 2,
          child: Semantics(
            label: 'Apply filters',
            button: true,
            child: GestureDetector(
              onTap: _apply,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: _kFooterButtonHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                  boxShadow: AppColors.primaryActionShadow,
                ),
                child: Text(
                  'Apply Filters',
                  style: AppTextStyles.button.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The redesign's slider handle: a 16 dp white circle with a 2 dp primary ring.
/// Flutter's stock range thumb is a solid primary disc, so it needs replacing to
/// match.
class _RingThumbShape extends RangeSliderThumbShape {
  const _RingThumbShape();

  static const double _radius = 8;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    Animation<double>? activationAnimation,
    Animation<double>? enableAnimation,
    bool? isDiscrete,
    bool? isEnabled,
    bool? isOnTop,
    TextDirection? textDirection,
    SliderThemeData? sliderTheme,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final Canvas canvas = context.canvas;
    canvas.drawCircle(
      center,
      _radius,
      Paint()..color = AppColors.cardBackground,
    );
    canvas.drawCircle(
      center,
      _radius - 1,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
