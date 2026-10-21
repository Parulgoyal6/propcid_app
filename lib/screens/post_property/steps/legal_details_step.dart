import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_constants.dart';

/// Step 6: available legal documents (shared) — plus Land ownership,
/// Commercial-specific approvals/licenses and PG-specific house rules &
/// legal approvals. Mirrors the React LegalDetailsStep.
class LegalDetailsStep extends StatefulWidget {
  const LegalDetailsStep({super.key});

  @override
  State<LegalDetailsStep> createState() => _LegalDetailsStepState();
}

class _LegalDetailsStepState extends State<LegalDetailsStep> {
  /// Land's document/status flags, verbatim from the portal's
  /// LandGeneralDocuments() (LegalDetailsStep.tsx:47-62) — 9 total, in the
  /// same 3-per-row order; Sale Deed / Khatoni is rendered separately below
  /// since it's a named provider field shared with every other category's
  /// documents card, not a bag key like the rest of these.
  static const List<(String, String)> _kLandLegalFlags = [
    ('registeredAgreement', 'Registered Agreement'),
    ('unregisteredAgreement', 'Unregistered Agreement'),
    ('mutationAvailable', 'Mutation'),
    ('pattaAvailable', 'Patta / Chitta'),
    ('khataAvailable', 'Khata Certificate'),
    ('jamabandiAvailable', 'Jamabandi / Fard'),
    ('courtCasePending', 'Court Case (if any)'),
    ('bankLoanApproved', 'Bank Loan'),
  ];

  late final TextEditingController _ownerNameController;

  static const _commercialApprovals = [
    ('fireNoc', 'Fire NOC / License'),
    ('tradeLicenseAvailable', 'Trade License'),
    ('foodLicense', 'Food License'),
    ('pollutionClearance', 'Pollution Clearance'),
    ('industrialApproval', 'Industrial Approval'),
    ('propertyTaxPaid', 'Property Tax Paid'),
    ('approvedByAuthority', 'Approved by Authority'),
  ];

  static const _pgHouseRules = [
    ('studentsAllowed', 'Students Allowed'),
    ('workingProfessionalsAllowed', 'Working Professionals Allowed'),
    ('maleAllowed', 'Male Allowed'),
    ('femaleAllowed', 'Female Allowed'),
    ('couplesAllowed', 'Couples Allowed'),
    ('foreignNationalsAllowed', 'Foreign Nationals Allowed'),
    ('petsAllowedPg', 'Pets Allowed'),
    ('visitorsAllowedPg', 'Visitors Allowed'),
  ];

  late final TextEditingController _quietHoursController;

  @override
  void initState() {
    super.initState();
    final providerAtInit = context.read<PostPropertyProvider>();
    _ownerNameController = TextEditingController(
      text: providerAtInit.text('ownerName'),
    );
    final provider = context.read<PostPropertyProvider>();
    _quietHoursController = TextEditingController(
      text: provider.text('quietHours'),
    );
    // TEMPORARY — P0 real-device edit-hydration trace.
    debugPrint(
      '[EDIT_TRACE][LEGAL] provider.ownerName="${providerAtInit.text('ownerName')}" '
      'controller.ownerName="${_ownerNameController.text}"',
    );
    debugPrint(
      '[EDIT_TRACE][LEGAL] provider.ownershipType="${providerAtInit.text('ownershipType')}"',
    );
    debugPrint(
      '[EDIT_TRACE][LEGAL] provider.registeredAgreement=${providerAtInit.boolVal('registeredAgreement')} '
      'mutationAvailable=${providerAtInit.boolVal('mutationAvailable')}',
    );
  }

  @override
  void dispose() {
    _ownerNameController.dispose();
    _quietHoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();
    final isCommercial = provider.category == PropertyCategory.commercial;
    final isPg = provider.category == PropertyCategory.pg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Land: documents/status first, then ownership + upload — matching
        // the portal's Legal & Approvals screen order for this category.
        // React renders these only for land (LegalDetailsStep.tsx) and its
        // rules require ownershipType and ownerName for that category;
        // Flutter had no land block at all, so both rules fired with nothing
        // on screen to satisfy them.
        if (provider.category == PropertyCategory.land) ...[
          WizardCard(
            icon: Icons.fact_check_outlined,
            title: 'Available Documents & Status',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WizardCheckboxTile(
                  label: 'Sale Deed / Khatoni',
                  value: provider.saleDeed,
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setSaleDeed(v),
                ),
                for (final flag in _kLandLegalFlags)
                  WizardCheckboxTile(
                    label: flag.$2,
                    value: provider.boolVal(flag.$1),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBoolVal(flag.$1, v),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.gavel_outlined,
            title: 'Land Ownership & Legal Documents',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WizardField(
                  label: 'Ownership Type *',
                  child: WizardChipGroup(
                    options: kLandOwnershipTypes,
                    selected: provider.text('ownershipType').isEmpty
                        ? null
                        : provider.text('ownershipType'),
                    onSelected: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('ownershipType', v),
                  ),
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Owner Name *',
                  child: WizardTextField(
                    controller: _ownerNameController,
                    hint: 'As recorded on the title',
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                    ],
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setText('ownerName', v),
                  ),
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Ownership Document Upload',
                  child: _OwnershipDocumentPicker(
                    existingPaths: provider.existingOwnershipDocumentPaths,
                    files: provider.ownershipDocuments,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // RERA has no counterpart anywhere in the portal's
        // LegalDetailsStep.tsx, for any category — it belongs to the
        // Builder Project flow, not a per-listing field. Removed per
        // explicit request (confirmed against source for Land, Residential
        // and Commercial).
        // Portal's generic documents card (ResidentialDocuments /
        // CommercialResidentialDocuments) never renders for Land — Land gets
        // only its own "Available Documents & Status" card above.
        if (provider.category != PropertyCategory.land) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.description_outlined,
            title: 'Available Documents & Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Standalone, above the grid — matches ResidentialDocuments()/
                // CommercialResidentialDocuments() exactly. "Loan Approved"
                // used to sit in the grid below with no portal counterpart
                // anywhere in this step (a dead metadata field, never
                // rendered on the website) — removed.
                WizardCheckboxTile(
                  label: 'Property Approved by Authority',
                  value: provider.propertyApproved,
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setPropertyApproved(v),
                ),
                const WizardDivider(),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    WizardCheckboxTile(
                      label: 'Sale Deed',
                      value: provider.saleDeed,
                      onChanged: (v) =>
                          context.read<PostPropertyProvider>().setSaleDeed(v),
                    ),
                    // CommercialResidentialDocuments() omits Registry Copy —
                    // only ResidentialDocuments() (and the categories that
                    // share it) has it (LegalDetailsStep.tsx:152 vs 172-177).
                    if (!isCommercial)
                      WizardCheckboxTile(
                        label: 'Registry Copy',
                        value: provider.registryCopy,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setRegistryCopy(v),
                      ),
                    WizardCheckboxTile(
                      label: 'Registered Agreement',
                      value: provider.boolVal('registeredAgreement'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('registeredAgreement', v),
                    ),
                    WizardCheckboxTile(
                      label: 'Unregistered Agreement',
                      value: provider.boolVal('unregisteredAgreement'),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal('unregisteredAgreement', v),
                    ),
                    WizardCheckboxTile(
                      label: "NOC's Available",
                      value: provider.nocAvailable,
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setNocAvailable(v),
                    ),
                    WizardCheckboxTile(
                      label: 'Encumbrance Free',
                      value: provider.encumbranceFree,
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setEncumbranceFree(v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (isCommercial) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.gavel_outlined,
            title: 'Commercial Approvals & Licenses',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commercialApprovals.map((t) {
                return WizardCheckboxTile(
                  label: t.$2,
                  value: provider.boolVal(t.$1),
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setBoolVal(t.$1, v),
                );
              }).toList(),
            ),
          ),
        ],
        if (isPg) ...[
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.rule_outlined,
            title: 'PG & Co-Living House Rules',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _pgHouseRules.map((t) {
                    return WizardCheckboxTile(
                      label: t.$2,
                      value: provider.boolVal(t.$1),
                      onChanged: (v) => context
                          .read<PostPropertyProvider>()
                          .setBoolVal(t.$1, v),
                    );
                  }).toList(),
                ),
                const WizardDivider(),
                WizardField(
                  label: 'Quiet Hours / Gate Closing Time',
                  child: WizardTextField(
                    controller: _quietHoursController,
                    hint: 'e.g., 10:00 PM to 6:00 AM',
                    onChanged: (v) {
                      final p = context.read<PostPropertyProvider>();
                      p.setText('quietHours', v);
                      p.setText('pgGateClosingTime', v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          WizardCard(
            icon: Icons.shield_outlined,
            title: 'PG Legal Approvals',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WizardCheckboxTile(
                  label: 'Hostel / PG License',
                  value: provider.boolVal('hostelLicense'),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setBoolVal('hostelLicense', v),
                ),
                WizardCheckboxTile(
                  label: 'Building Approval / OC',
                  value: provider.boolVal('buildingApproval'),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setBoolVal('buildingApproval', v),
                ),
              ],
            ),
          ),
        ],
        // Facing has no counterpart in LegalDetailsStep.tsx for any category
        // (the portal's facing selector lives on the Dimensions step, PG
        // only) and Approved By Banks is defined but never invoked anywhere
        // in the portal's component — both removed per explicit request.
      ],
    );
  }
}

/// Land's "Ownership Document Upload" dropzone (LegalDetailsStep.tsx's land
/// branch) — PDF/JPG/PNG, capped at 10MB same as the Media step's photo
/// ceiling, multiple files allowed (matching the portal's `multiple` file
/// input). [existingPaths] are already saved on this listing (edit mode
/// only) — shown read-only, same as the portal: this step only ever adds
/// new documents on top of them, it never edits or removes an already-saved
/// one. Uploading itself happens on submit (`PropertyService`), same as the
/// Property Images picker's own established pattern.
class _OwnershipDocumentPicker extends StatelessWidget {
  const _OwnershipDocumentPicker({
    required this.existingPaths,
    required this.files,
  });

  final List<String> existingPaths;
  final List<PlatformFile> files;

  static const int _maxBytes = 10 * 1024 * 1024;

  // Flutter-only cap (no portal precedent) requested to keep this list
  // bounded, counting both already-saved documents and ones picked locally.
  static const int _maxDocuments = 5;

  Future<void> _pick(BuildContext context) async {
    final remaining = _maxDocuments - existingPaths.length - files.length;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can upload up to $_maxDocuments documents.'),
        ),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      // Mirrors `ProfileMediaService.pickDocument`'s same-purpose Aadhaar/PAN
      // picker: without this, `PlatformFile.bytes` is null on mobile (only
      // web always populates it), and the upload at submit time would have
      // nothing to read.
      withData: true,
    );
    final picked = result?.files ?? const <PlatformFile>[];
    if (picked.isEmpty) return;

    final valid = <PlatformFile>[];
    final skipped = <String>[];
    var overLimit = 0;
    for (final file in picked) {
      if (file.size > _maxBytes) {
        skipped.add(file.name);
      } else if (valid.length >= remaining) {
        overLimit++;
      } else {
        valid.add(file);
      }
    }

    if (skipped.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            skipped.length == 1
                ? '${skipped.first} is over 10MB and was skipped.'
                : '${skipped.length} files were over 10MB and were skipped.',
          ),
        ),
      );
    } else if (overLimit > 0 && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can upload up to $_maxDocuments documents.'),
        ),
      );
    }
    if (valid.isNotEmpty && context.mounted) {
      context.read<PostPropertyProvider>().addOwnershipDocuments(valid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (existingPaths.isNotEmpty) ...[
          Text(
            'Already uploaded:',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 6),
          for (int i = 0; i < existingPaths.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Document ${i + 1}',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Uploading new files below will add to these, not replace them.',
            style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
          ),
          const SizedBox(height: 10),
        ],
        if (files.isNotEmpty) ...[
          for (int i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      files[i].name,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => context
                        .read<PostPropertyProvider>()
                        .removeOwnershipDocumentAt(i),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
        InkWell(
          onTap: () => _pick(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairline, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_outlined, color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Text(
                  'Click to upload ownership documents',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'PDF, JPG, PNG (Max 10MB)',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
