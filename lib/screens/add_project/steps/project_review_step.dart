// screens/add_project/steps/project_review_step.dart
//
// Step 5 of 5 — `renderStep5` in `BuilderProjectWizard.tsx`.
//
// No rules of its own (`PROJECT_STEP_RULES.review` is empty). Submitting from
// here re-runs every earlier step and jumps to the first that fails, so this
// screen's job is to show what is about to be written.
//
// It also reports the two things the payload derives rather than asks for — the
// master plan taken from the first layout, and the flattened gallery — so a
// builder is not surprised by what appears on their project page.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/project_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/property_model.dart';
import '../../../providers/add_project_provider.dart';
import '../../post_property/portal_kit.dart';

class ProjectReviewStep extends StatelessWidget {
  const ProjectReviewStep({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddProjectProvider>();
    final d = provider.draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PortalStepHeader(
          icon: 'shield-check',
          title: 'Review & Submit',
          subtitle: provider.isEditMode
              ? 'Check your changes before saving'
              : 'Check everything before you publish',
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
              const PortalSectionDivider(icon: 'building', title: 'Basic Info'),
              const SizedBox(height: 12),
              _Row(label: 'Title', value: d.title),
              _Row(label: 'Type', value: projectTypeLabel(d.projectType)),
              _Row(label: 'City', value: d.location),
              _Row(label: 'Description', value: d.description, multiline: true),
            ],
          ),
        ),
        const SizedBox(height: 14),

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(icon: 'map-pin', title: 'Details'),
              const SizedBox(height: 12),
              _Row(
                label: 'Units',
                value: d.totalUnits == null
                    ? ''
                    : '${d.availableUnits ?? 0} of ${d.totalUnits} available',
              ),
              _Row(
                label: 'Price',
                value: _range(d.priceRangeMin, d.priceRangeMax, money: true),
              ),
              _Row(
                label: 'Size',
                value: _range(d.areaSqftMin, d.areaSqftMax, suffix: ' sq ft'),
              ),
              _Row(label: 'Completion', value: d.completionDate),
              _Row(label: 'Possession', value: d.possessionDate),
              _Row(label: 'RERA', value: d.reraNumber),
            ],
          ),
        ),
        const SizedBox(height: 14),

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(
                icon: 'image',
                title: 'Contact & Media',
              ),
              const SizedBox(height: 12),
              _Row(label: 'Website', value: d.websiteUrl),
              _Row(label: 'Contact', value: d.contactNumber),
              _Row(label: 'Logo', value: d.logoUrl.isEmpty ? '' : 'Uploaded'),
              _Row(
                label: 'Brochure',
                value: d.brochureUrl.isEmpty ? '' : 'Uploaded',
              ),
              _Row(
                label: 'Master plan',
                value: d.mapImages.isEmpty
                    ? ''
                    : '${d.mapImages.length} layout'
                          '${d.mapImages.length == 1 ? '' : 's'}',
              ),
              _Row(label: 'Images', value: '${d.otherImages.length}'),
              _Row(label: 'Videos', value: '${d.videosUrls.length}'),
              if (d.mapImages.isNotEmpty || d.otherImages.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DerivedNote(
                  'Your project gallery will show '
                  '${d.otherImages.length + d.mapImages.length} image'
                  '${d.otherImages.length + d.mapImages.length == 1 ? '' : 's'}'
                  '${d.mapImages.isEmpty ? '' : ', and the first layout becomes '
                            'the master plan'}.',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        PortalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PortalSectionDivider(icon: 'sparkles', title: 'Amenities'),
              const SizedBox(height: 12),
              if (d.amenities.isEmpty)
                const PortalReadOnlyBox('None selected')
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final amenity in d.amenities)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          amenity,
                          style: AppTextStyles.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // What happens after Publish. `approval_status` defaults to 'pending'
        // and only an admin can change it, but the public read policy is
        // `status = 'active'` alone — so the project is visible immediately
        // (PD2). Saying so is better than implying a review gate that is not
        // enforced.
        if (!provider.isEditMode)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your project goes live straight away and is submitted for '
                    'verification. You can add inventory units and edit any '
                    'detail afterwards.',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// "₹45.0 L – ₹95.0 L" or "850 – 1850 sq ft". Blank when neither end is set,
  /// so the review row hides rather than showing a bare dash.
  static String _range(
    double? min,
    double? max, {
    bool money = false,
    String suffix = '',
  }) {
    // The app's one price formatter, already used by the filters screen and the
    // search header, so a project's price range reads like every other price.
    String one(double v) => money
        ? PropertyModel.formatIndianPrice(v)
        : '${v.toStringAsFixed(0)}$suffix';

    if (min == null && max == null) return '';
    if (min != null && max != null) {
      return min == max ? one(min) : '${one(min)} – ${one(max)}';
    }
    return one((min ?? max)!);
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    // An unfilled field is omitted entirely — the summary is what will be saved,
    // and the step rules already name what is missing.
    if (value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textHint,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: multiline ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: multiline ? 1.4 : 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A note about a value the payload derives rather than collects.
class _DerivedNote extends StatelessWidget {
  const _DerivedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.auto_awesome_outlined,
          size: 13,
          color: AppColors.textHint,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(fontSize: 11, height: 1.35),
          ),
        ),
      ],
    );
  }
}
