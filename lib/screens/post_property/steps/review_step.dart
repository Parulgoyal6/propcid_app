import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_constants.dart';
import '../listing_validation_rules.dart';

/// Step 9: read-only review of everything entered across the wizard, with
/// per-section "Edit" links that jump back to the relevant step. This is a
/// Flutter-only addition — the React source submits directly from its media
/// step — added here as a UX improvement, not a ported field/workflow.
class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key});

  static String _categoryLabel(PropertyCategory? c) {
    switch (c) {
      case PropertyCategory.residential:
        return 'Residential';
      case PropertyCategory.commercial:
        return 'Commercial';
      case PropertyCategory.land:
        return 'Land / Plot';
      case PropertyCategory.pg:
        return 'PG / Co-living';
      case PropertyCategory.other:
        return 'Other';
      case null:
        return '—';
    }
  }

  /// Same category ids as `MediaContactStep._isVideoCategory` — kept local
  /// rather than shared, since that widget's version is private and this is
  /// the only other place that needs the distinction.
  static bool _isVideoCategory(String category) =>
      category == 'property_video' || category == 'land_video';

  static int _mediaCount(PostPropertyProvider provider, {required bool video}) {
    bool matches(String category) => _isVideoCategory(category) == video;
    return provider.mediaItems.where((m) => matches(m.category)).length +
        provider.existingMedia.where((m) => matches(m.category)).length;
  }

  static String _intentLabel(ListingIntent? i) {
    switch (i) {
      case ListingIntent.sell:
        return 'Sell';
      case ListingIntent.rent:
        return 'Rent';
      case ListingIntent.lease:
        return 'Lease';
      case null:
        return '—';
    }
  }

  static String _humanize(String key) {
    final spaced = key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}');
    final words = spaced.trim().split(RegExp(r'\s+'));
    return words
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _dash(String value) => value.trim().isEmpty ? '—' : value;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final category = provider.category;

    final enabledFeatures =
        provider.allBoolFields.entries
            .where((e) => e.value)
            .map((e) => _humanize(e.key))
            .toList()
          ..sort();

    final selectedLists = provider.allListFields.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    final visibleSteps = provider.visibleSteps;
    final isRentOrLease =
        provider.listingIntent == ListingIntent.rent ||
        provider.listingIntent == ListingIntent.lease;
    // Mirrors PricingStep._isApartmentRental — the combination React shows
    // "Society charges" for instead of "Maintenance charges".
    final isApartmentRental =
        category == PropertyCategory.residential &&
        kApartmentSubtypes.contains(provider.residentialSubType ?? '') &&
        isRentOrLease;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Category & Listing',
          onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
            WizardStep.category,
          ),
          rows: [
            ('Category', _categoryLabel(category)),
            ('Listing Type', _intentLabel(provider.listingIntent)),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Basic Info',
          onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
            WizardStep.basicInfo,
          ),
          rows: [
            ('Title', _dash(provider.title)),
            if (category != PropertyCategory.pg)
              ('Price', _dash(provider.price)),
            ('Address', _dash(provider.location)),
            ('City', _dash(provider.city)),
            ('State', _dash(provider.state)),
            ('Pincode', _dash(provider.pincode)),
            if (provider.landmark.isNotEmpty) ('Landmark', provider.landmark),
            ('Description', _dash(provider.description)),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Dimensions',
          onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
            WizardStep.dimensions,
          ),
          rows: [
            // `provider.areaUnit` is the raw canonical id (e.g. 'sq_ft',
            // 'acres') the dropdown stores, not a human label — this
            // previously rendered the raw id verbatim (e.g. "2.75 acres"
            // instead of "2.75 Acres").
            (
              'Area',
              '${_dash(provider.area)} '
                  '${kAreaUnitLabels[provider.areaUnit] ?? provider.areaUnit}',
            ),
            if (provider.carpetArea.isNotEmpty)
              ('Carpet Area', provider.carpetArea),
            if (category == PropertyCategory.residential) ...[
              ('BHK Type', _dash(provider.bhkType ?? '')),
              ('Bedrooms', _dash(provider.bedrooms)),
              ('Bathrooms', _dash(provider.bathrooms)),
            ],
            // Facing is only collected here, on Dimensions, and only for PG
            // (property_dimensions_step.dart) — it has no counterpart on
            // Legal for any category and no counterpart at all for Land.
            if (category == PropertyCategory.pg)
              ('Facing', _dash(provider.facing ?? '')),
          ],
        ),
        // Only summarise steps the wizard actually showed: React hides
        // Condition for land + residential and Amenities for land
        // (PropertyWizard.tsx stepsRaw), so rendering them here would offer an
        // Edit link to a screen this listing never had.
        if (visibleSteps.contains(WizardStep.condition)) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'Condition & Furnishing',
            onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
              WizardStep.condition,
            ),
            rows: [
              ('Condition', _dash(provider.propertyCondition ?? '')),
              ('Furnishing', _dash(provider.furnishingType ?? '')),
              ('Availability', _dash(provider.availabilityStatus ?? '')),
            ],
          ),
        ],
        if (visibleSteps.contains(WizardStep.amenities)) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'Amenities & Features',
            onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
              WizardStep.amenities,
            ),
            rows: [
              ('Electricity Backup', _dash(provider.electricityBackup ?? '')),
              ('Water Availability', _dash(provider.waterAvailability ?? '')),
            ],
            chipGroups: selectedLists
                .map((e) => (_humanize(e.key), e.value))
                .toList(),
            chips: enabledFeatures,
          ),
        ],
        // No "Legal & Approvals" section here: RERA has no input anywhere in
        // this wizard, for any category (confirmed against the portal's own
        // LegalDetailsStep.tsx, which has no RERA field either — it's a
        // Builder Project-only concept). Showing "RERA Registered: No" here
        // implied a choice was made when there was never an input to make it
        // with, for every single listing.
        const SizedBox(height: 16),
        _Section(
          title: 'Pricing & Terms',
          onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
            WizardStep.pricing,
          ),
          rows: [
            // Same visibility rule as PricingStep: apartments on rent/lease
            // get "Society Charges", other rent/lease listings except Land
            // get "Maintenance Charges", and Land/sell listings get neither
            // (propertyListingRules.ts: societyCharges applies isApartment
            // && rent/lease; maintenanceCharges applies !isApartment &&
            // !isLand && rent/lease).
            if (isApartmentRental)
              ('Society Charges', _dash(provider.text('societyCharges')))
            else if (isRentOrLease && category != PropertyCategory.land)
              ('Maintenance Charges', _dash(provider.maintenanceCharges)),
            ('Brokerage', _dash(provider.brokerage)),
            // Same gate as PricingStep's own checkbox (and the portal's own
            // commented-out OtherDetails() for Commercial/Other): Land and
            // Residential only. Showing this for every category implied a
            // choice was made for Commercial/PG/Other listings, which have
            // no Price Negotiable input at all.
            if (category == PropertyCategory.land ||
                category == PropertyCategory.residential)
              ('Negotiable', provider.priceNegotiable ? 'Yes' : 'No'),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Media & Contact',
          onEdit: () => context.read<PostPropertyProvider>().goToWizardStep(
            WizardStep.media,
          ),
          rows: [
            // Include existingMedia (populated when editing a listing that
            // already has photos) — matching the count the media-step
            // validation rule itself uses, so Review can't show a lower
            // number than what's actually required/saved.
            //
            // Split by type: a video (category 'property_video'/
            // 'land_video' — see MediaContactStep._isVideoCategory) was
            // previously folded into this same "Images Selected" count,
            // so attaching a video showed as an image.
            (
              'Images Selected',
              '${_mediaCount(provider, video: false)}',
            ),
            if (_mediaCount(provider, video: true) > 0)
              ('Videos Selected', '${_mediaCount(provider, video: true)}'),
            ('Contact Name', _dash(provider.contactName)),
            ('Contact Phone', _dash(provider.contactPhone)),
            if (provider.whatsappNumber.isNotEmpty)
              ('WhatsApp Number', provider.whatsappNumber),
            ('Contact Email', _dash(provider.contactEmail)),
            if (provider.hashtags.isNotEmpty) ('Hashtags', provider.hashtags),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Review everything above before submitting — use Edit on '
                  'any section to make changes.',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final VoidCallback onEdit;
  final List<(String, String)> rows;
  final List<String> chips;
  final List<(String, List<String>)> chipGroups;

  const _Section({
    required this.title,
    required this.onEdit,
    required this.rows,
    this.chips = const [],
    this.chipGroups = const [],
  });

  @override
  Widget build(BuildContext context) {
    return WizardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.heading3.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Edit',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      r.$1,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final group in chipGroups) ...[
            const SizedBox(height: 6),
            Text(
              group.$1,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: group.$2.map((v) => _chip(v)).toList(),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Enabled Features',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: chips.map((v) => _chip(v)).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}
