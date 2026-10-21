// screens/add_project/steps/project_details_step.dart
//
// Step 2 of 5 — `renderStep2` in `BuilderProjectWizard.tsx`.
//
// Nine required fields: unit counts, price range, area range, both dates and the
// RERA number. `detailRules` (`projectRules.ts:51-61`) gates every one, and the
// cross-field rule "available cannot exceed total" is checked on submit.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/amount_in_words.dart';
import '../../../providers/add_project_provider.dart';
import '../../post_property/portal_kit.dart';
import '../project_field_keys.dart';

class ProjectDetailsStep extends StatefulWidget {
  const ProjectDetailsStep({super.key});

  @override
  State<ProjectDetailsStep> createState() => _ProjectDetailsStepState();
}

class _ProjectDetailsStepState extends State<ProjectDetailsStep> {
  late final TextEditingController _totalUnits;
  late final TextEditingController _availableUnits;
  late final TextEditingController _priceMin;
  late final TextEditingController _priceMax;
  late final TextEditingController _areaMin;
  late final TextEditingController _areaMax;
  late final TextEditingController _rera;

  @override
  void initState() {
    super.initState();
    final d = context.read<AddProjectProvider>().draft;
    _totalUnits = TextEditingController(text: _num(d.totalUnits));
    _availableUnits = TextEditingController(text: _num(d.availableUnits));
    _priceMin = TextEditingController(text: _num(d.priceRangeMin));
    _priceMax = TextEditingController(text: _num(d.priceRangeMax));
    _areaMin = TextEditingController(text: _num(d.areaSqftMin));
    _areaMax = TextEditingController(text: _num(d.areaSqftMax));
    _rera = TextEditingController(text: d.reraNumber);
  }

  /// A null shows as blank, and a whole number shows without a trailing `.0`.
  static String _num(num? value) {
    if (value == null) return '';
    if (value is int) return value.toString();
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    for (final c in [
      _totalUnits,
      _availableUnits,
      _priceMin,
      _priceMax,
      _areaMin,
      _areaMax,
      _rera,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mirrors `<AmountInWords value={...}/>` (BuilderProjectWizard.tsx:1089,
  /// 1113), rendered under both price-range fields.
  Widget _amountWords(String value) {
    final words = amountToWordsIndian(value);
    if (words.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '₹${groupIndianDigits(value)} · $words Rupees',
        style: AppTextStyles.caption,
      ),
    );
  }

  Future<void> _pickDate({
    required String currentIso,
    required ValueChanged<String> onPicked,
    // Possession cannot be picked before Completion — passed only for that
    // field, once a completion date has been set.
    DateTime? minDate,
  }) async {
    final now = DateTime.now();
    final earliest = (minDate != null && minDate.isAfter(now)) ? minDate : now;
    final initial = DateTime.tryParse(currentIso) ?? earliest;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      // A completion or possession date is always in the future for a project
      // being listed, and the column is a plain `date`.
      firstDate: earliest,
      lastDate: DateTime(now.year + 25),
    );
    if (picked == null) return;
    onPicked(picked.toIso8601String().split('T').first);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddProjectProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PortalStepHeader(
          icon: 'map-pin',
          title: 'Project Details',
          subtitle: 'Units, pricing, sizes and approvals',
        ),
        const SizedBox(height: 20),

        if (provider.stepIssues.isNotEmpty) ...[
          PortalValidationSummary(
            messages: provider.stepIssues
                .map((issue) => issue.message)
                .toList(),
          ),
          const SizedBox(height: 16),
        ],

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(icon: 'building', title: 'Inventory'),
              const SizedBox(height: 14),
              _pair(
                left: PortalLabelledField(
                  label: 'Total Units',
                  required: true,
                  child: PortalTextField(
                    controller: _totalUnits,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hasError: provider.hasIssue(kProjectTotalUnits),
                    onChanged: provider.setTotalUnits,
                  ),
                ),
                right: PortalLabelledField(
                  label: 'Available Units',
                  required: true,
                  // The one field where 0 is a legitimate answer — a sold-out
                  // project. `nonNegativeNumber`, not `positiveNumber`.
                  helper: 'Use 0 if the project is fully sold.',
                  child: PortalTextField(
                    controller: _availableUnits,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hasError: provider.hasIssue(kProjectAvailableUnits),
                    onChanged: provider.setAvailableUnits,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const PortalSectionDivider(
                icon: 'indian-rupee',
                title: 'Price Range',
              ),
              const SizedBox(height: 14),
              _pair(
                left: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PortalLabelledField(
                      label: 'Minimum Price',
                      required: true,
                      child: PortalTextField(
                        controller: _priceMin,
                        hint: '0',
                        prefix: const Text('₹'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        hasError: provider.hasIssue(kProjectPriceMin),
                        onChanged: provider.setPriceMin,
                      ),
                    ),
                    _amountWords(_priceMin.text),
                  ],
                ),
                right: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PortalLabelledField(
                      label: 'Maximum Price',
                      required: true,
                      child: PortalTextField(
                        controller: _priceMax,
                        hint: '0',
                        prefix: const Text('₹'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        hasError: provider.hasIssue(kProjectPriceMax),
                        onChanged: provider.setPriceMax,
                      ),
                    ),
                    _amountWords(_priceMax.text),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              const PortalSectionDivider(icon: 'ruler', title: 'Unit Sizes'),
              const SizedBox(height: 14),
              _pair(
                left: PortalLabelledField(
                  label: 'Minimum Area',
                  required: true,
                  child: PortalTextField(
                    controller: _areaMin,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hasError: provider.hasIssue(kProjectAreaMin),
                    onChanged: provider.setAreaMin,
                    suffix: Text(
                      'sq ft',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                right: PortalLabelledField(
                  label: 'Maximum Area',
                  required: true,
                  child: PortalTextField(
                    controller: _areaMax,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    hasError: provider.hasIssue(kProjectAreaMax),
                    onChanged: provider.setAreaMax,
                    suffix: Text(
                      'sq ft',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const PortalSectionDivider(
                icon: 'file-text',
                title: 'Timeline & Approvals',
              ),
              const SizedBox(height: 14),
              _DateField(
                label: 'Completion Date',
                value: provider.draft.completionDate,
                hasError: provider.hasIssue(kProjectCompletionDate),
                onTap: () => _pickDate(
                  currentIso: provider.draft.completionDate,
                  onPicked: provider.setCompletionDate,
                ),
              ),
              const SizedBox(height: 16),
              _DateField(
                label: 'Possession Date',
                value: provider.draft.possessionDate,
                hasError: provider.hasIssue(kProjectPossessionDate),
                onTap: () => _pickDate(
                  currentIso: provider.draft.possessionDate,
                  onPicked: provider.setPossessionDate,
                  minDate: DateTime.tryParse(provider.draft.completionDate),
                ),
              ),
              const SizedBox(height: 16),
              PortalLabelledField(
                label: 'RERA Number',
                required: true,
                icon: 'shield-check',
                child: PortalTextField(
                  controller: _rera,
                  hint: 'e.g. P52100012345',
                  hasError: provider.hasIssue(kProjectReraNumber),
                  onChanged: provider.setReraNumber,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Two fields side by side above 420 dp, stacked below — the same width
  /// adaptation the listing wizard's paired fields use.
  Widget _pair({required Widget left, required Widget right}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [left, const SizedBox(height: 16), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// A read-only field that opens a date picker.
///
/// `completion_date` and `possession_date` are the only two nullable columns in
/// the payload, so a blank here really is a null — which is why both are made
/// required by the step rules.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.hasError,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool hasError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PortalLabelledField(
      label: label,
      required: true,
      icon: 'calendar',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError ? AppColors.error : AppColors.hairline,
              width: hasError ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.isEmpty ? 'Select a date' : value,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    color: value.isEmpty
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
