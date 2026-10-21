// screens/add_project/steps/project_amenities_step.dart
//
// Step 4 of 5 — `renderStep4` in `BuilderProjectWizard.tsx`.
//
// One rule: at least one amenity (`amenityRules`, `projectRules.ts:73`).
// `amenities` is a free `text[]`, so the 19 suggestions are chips and anything
// typed is accepted — the reference's `newAmenity` input and `handleAmenityAdd`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/project_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/add_project_provider.dart';
import '../../post_property/portal_kit.dart';

class ProjectAmenitiesStep extends StatefulWidget {
  const ProjectAmenitiesStep({super.key});

  @override
  State<ProjectAmenitiesStep> createState() => _ProjectAmenitiesStepState();
}

class _ProjectAmenitiesStepState extends State<ProjectAmenitiesStep> {
  final TextEditingController _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _addCustom() {
    final value = _custom.text.trim();
    if (value.isEmpty) return;
    context.read<AddProjectProvider>().addAmenity(value);
    _custom.clear();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddProjectProvider>();
    final selected = provider.draft.amenities;

    // Anything the user typed that is not one of the 19 suggestions. Shown
    // separately so a custom entry is visibly removable rather than lost among
    // the chips.
    final custom = selected
        .where((a) => !kCommonAmenities.contains(a))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PortalStepHeader(
          icon: 'sparkles',
          title: 'Amenities',
          subtitle: 'What does this project offer its residents?',
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
              const PortalSectionDivider(
                icon: 'list',
                title: 'Common Amenities',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final amenity in kCommonAmenities)
                    _AmenityChip(
                      label: amenity,
                      selected: selected.contains(amenity),
                      onTap: () => provider.toggleAmenity(amenity),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              const PortalSectionDivider(
                icon: 'sparkles',
                title: 'Add Your Own',
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PortalTextField(
                      controller: _custom,
                      hint: 'e.g. Rooftop Lounge',
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _addCustom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Add'),
                    ),
                  ),
                ],
              ),

              if (custom.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amenity in custom)
                      _AmenityChip(
                        label: amenity,
                        selected: true,
                        removable: true,
                        onTap: () => provider.removeAmenity(amenity),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 16),
              Text(
                selected.isEmpty
                    ? 'Select at least one amenity to continue.'
                    : '${selected.length} '
                          'amenit${selected.length == 1 ? 'y' : 'ies'} selected',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11.5,
                  color: selected.isEmpty
                      ? AppColors.textHint
                      : AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AmenityChip extends StatelessWidget {
  const _AmenityChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.removable = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A custom amenity's chip removes itself rather than toggling.
  final bool removable;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryLight : Colors.white,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.hairline,
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected && !removable) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
                if (removable) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
