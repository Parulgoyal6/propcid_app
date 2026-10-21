import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/wizard_kit.dart';
import '../../../providers/post_property_provider.dart';
import '../listing_constants.dart';

/// Step 5: utilities/parking/key-facilities for Residential/Land/Other/PG-base,
/// or the full Commercial amenities section (usage, business info, features,
/// washrooms, parking, utilities & licenses) for Commercial — plus a PG-only
/// amenities & safety block appended regardless of the base branch. Mirrors
/// the React AmenitiesStep.
class AmenitiesStep extends StatefulWidget {
  const AmenitiesStep({super.key});

  @override
  State<AmenitiesStep> createState() => _AmenitiesStepState();
}

class _AmenitiesStepState extends State<AmenitiesStep> {
  /// Working-day options, verbatim from the buildingInventory.workingDays
  /// select in AmenitiesStep.tsx.
  static const List<String> _kWorkingDays = [
    'Monday to Friday',
    'Monday to Saturday',
    'All Days',
  ];

  late final TextEditingController _buildingWorkingHoursController;
  late final TextEditingController _liftCountController;
  late final TextEditingController _securityGuardsController;
  late final TextEditingController _buildingMaintenanceController;
  late final TextEditingController _totalCarParkingController;
  late final TextEditingController _totalBikeParkingController;
  late final TextEditingController _serviceLiftCountController;
  late final TextEditingController _camChargesController;

  /// Building facility toggles, all under buildingInventory
  /// (AmenitiesStep.tsx:585-991) — none are required by the portal's rules,
  /// so these were simply missing rather than blocking anything.
  static const _buildingFacilityToggles = [
    ('access24x7', '24x7 Access'),
    ('powerBackup', 'Power Backup'),
    ('dgBackupAvailable', 'DG Backup Available'),
    ('fireSafetySystem', 'Fire Safety System'),
    ('smokeDetectors', 'Smoke Detectors'),
    ('sprinklerSystem', 'Sprinkler System'),
    ('emergencyExits', 'Emergency Exits'),
    ('cctvCoverage', 'CCTV Coverage'),
    ('accessControlSystem', 'Access Control System'),
    ('visitorManagementSystem', 'Visitor Management System'),
    ('wheelchairAccessibility', 'Wheelchair Accessibility'),
    ('centralAirConditioning', 'Central Air Conditioning'),
    ('waterSupply', 'Water Supply'),
    ('sewageConnection', 'Sewage Connection'),
    ('highSpeedInternet', 'High Speed Internet'),
    ('basementParking', 'Basement Parking'),
    ('surfaceParking', 'Surface Parking'),
    ('multiLevelParking', 'Multi-Level Parking'),
    // Portal genuinely renders Visitor Parking twice — once here
    // (buildingInventory-scoped, AmenitiesStep.tsx:966-976) and once in the
    // general Parking Details card above (top-level field, same label,
    // different key) — not a Flutter duplication bug, matched intentionally.
    ('visitorParking', 'Visitor Parking'),
    ('evChargingStations', 'EV Charging Stations'),
  ];

  static const _suitableForOptions = [
    'Office',
    'Retail',
    'Restaurant',
    'Clinic',
    'Salon',
    'Gym',
    'Warehouse',
    'Manufacturing',
    'Startup',
    'IT Company',
    'Franchise',
    'Showroom',
  ];

  // Portal's commercialOfficeBuildingAmenityList (AmenitiesStep.tsx) — one
  // 19-item list, all toggled into the shared `amenities` array. Flutter used
  // to split this across two lists (one of them writing to a separate
  // `officeFeatures` key the portal never reads), which also dropped "DG
  // Backup" and "Wheelchair Accessibility" and relabelled "Waiting Lounge" as
  // "Waiting Area".
  static const _officeBuildingFeatures = [
    'Reception Area',
    'Waiting Lounge',
    'Conference Room',
    'Meeting Room',
    'Open Workspace',
    'Cafeteria',
    'Biometric Entry',
    'Service Lift',
    'Escalator',
    'Security Guard',
    'CCTV',
    'Fire Fighting System',
    'Fire Exit',
    'Fiber Connectivity',
    'Intercom',
    'DG Backup',
    'Solar Backup',
    'ATM',
    'Wheelchair Accessibility',
  ];

  static const _retailFeatures = [
    'Glass Frontage',
    'Display Area',
    'Signage Space',
    'Dock Height',
    'Truck Parking',
    'Loading Area',
    'Crane Facility',
    'Storage Racks',
    'Ventilation',
  ];

  static const _parkingToggles = [
    ('visitorParking', 'Visitor Parking'),
    ('reservedParking', 'Reserved Parking'),
    ('bikeParking', 'Bike Parking'),
    ('carParking', 'Car Parking'),
    ('truckParking', 'Truck Parking'),
    ('loadingVehicleAccess', 'Loading Vehicle Access'),
  ];

  static const _pgSafetyToggles = [
    ('cctvCoverage', 'CCTV Coverage'),
    ('biometricAccess', 'Biometric Access'),
    ('policeVerificationRequired', 'Police Verification'),
    ('visitorEntryRegister', 'Visitor Entry Register'),
  ];

  late final TextEditingController _coveredParkingController;
  late final TextEditingController _openParkingController;
  late final TextEditingController _liftsController;
  late final TextEditingController _businessTypeController;
  late final TextEditingController _washroomsController;
  late final TextEditingController _westernSeatsController;
  late final TextEditingController _indianSeatsController;
  late final TextEditingController _totalParkingController;

  @override
  void initState() {
    super.initState();
    final inv = context.read<PostPropertyProvider>();
    _buildingWorkingHoursController = TextEditingController(
      text: inv.buildingInventoryText('buildingWorkingHours'),
    );
    _liftCountController = TextEditingController(
      text: inv.buildingInventoryText('liftCount'),
    );
    _securityGuardsController = TextEditingController(
      text: inv.buildingInventoryText('securityGuards'),
    );
    _buildingMaintenanceController = TextEditingController(
      text: inv.buildingInventoryText('maintenanceCharges'),
    );
    _totalCarParkingController = TextEditingController(
      text: inv.buildingInventoryText('totalCarParking'),
    );
    _totalBikeParkingController = TextEditingController(
      text: inv.buildingInventoryText('totalBikeParking'),
    );
    _serviceLiftCountController = TextEditingController(
      text: inv.buildingInventoryText('serviceLiftCount'),
    );
    _camChargesController = TextEditingController(
      text: inv.buildingInventoryText('commonAreaMaintenanceCharges'),
    );
    final p = context.read<PostPropertyProvider>();
    _coveredParkingController = TextEditingController(text: p.coveredParking);
    _openParkingController = TextEditingController(text: p.openParking);
    _liftsController = TextEditingController(text: p.numberOfLifts);
    _businessTypeController = TextEditingController(
      text: p.text('businessType'),
    );
    _washroomsController = TextEditingController(text: p.text('washrooms'));
    _westernSeatsController = TextEditingController(
      text: p.text('westernSeats'),
    );
    _indianSeatsController = TextEditingController(text: p.text('indianSeats'));
    _totalParkingController = TextEditingController(
      text: p.text('totalParking'),
    );
  }

  @override
  void dispose() {
    _buildingWorkingHoursController.dispose();
    _liftCountController.dispose();
    _securityGuardsController.dispose();
    _buildingMaintenanceController.dispose();
    _totalCarParkingController.dispose();
    _totalBikeParkingController.dispose();
    _serviceLiftCountController.dispose();
    _camChargesController.dispose();
    _coveredParkingController.dispose();
    _openParkingController.dispose();
    _liftsController.dispose();
    _businessTypeController.dispose();
    _washroomsController.dispose();
    _westernSeatsController.dispose();
    _indianSeatsController.dispose();
    _totalParkingController.dispose();
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
        if (isCommercial)
          _buildBuildingFacilities(context, provider)
        else
          _buildDefaultSection(context, provider),
        if (provider.category == PropertyCategory.residential) ...[
          const SizedBox(height: 20),
          _buildResidentialSections(context, provider),
        ],
        if (provider.category == PropertyCategory.other) ...[
          const SizedBox(height: 20),
          _buildOtherAmenitiesSection(context, provider),
        ],
        if (isPg) ...[
          const SizedBox(height: 20),
          _buildPgAmenitiesSection(context, provider),
        ],
      ],
    );
  }

  /// Residential amenity pickers, ported from AmenitiesStep.tsx.
  ///
  /// All three lists — Society/Building (47), Flat/Unit (23) and Parking (4) —
  /// toggle into the SAME `amenities` array in React, which is what backs the
  /// web's amenity filters. They are shown as separate groups purely for
  /// scanning; the stored value is one flat list.
  ///
  /// Tenant preferences are not amenities: each is its own boolean metadata key
  /// (familyAllowed, bachelorAllowed, ...), so they write through the bag.
  Widget _buildResidentialSections(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    final selected = provider.listVal('amenities');

    void toggleInto(List<String> group, List<String> next) {
      // Replace only this group's entries, leaving the other groups' choices
      // in the shared array untouched.
      final others = selected.where((a) => !group.contains(a)).toList();
      context.read<PostPropertyProvider>().setListVal('amenities', [
        ...others,
        ...next,
      ]);
    }

    List<String> selectionFor(List<String> group) =>
        selected.where(group.contains).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardCard(
          icon: Icons.apartment_outlined,
          title: 'Society & Building Amenities',
          child: WizardMultiChipGroup(
            // The React array lists 'Visitor Parking' twice; de-duplicated for
            // display only — the stored strings are unchanged.
            options: kResidentialSocietyAmenities.toSet().toList(),
            selected: selectionFor(kResidentialSocietyAmenities),
            onChanged: (v) => toggleInto(kResidentialSocietyAmenities, v),
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.chair_outlined,
          title: 'Flat / Unit Features',
          child: WizardMultiChipGroup(
            options: kResidentialFlatAmenities,
            selected: selectionFor(kResidentialFlatAmenities),
            onChanged: (v) => toggleInto(kResidentialFlatAmenities, v),
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.local_parking_outlined,
          title: 'Parking',
          child: WizardMultiChipGroup(
            options: kResidentialParkingAmenities,
            selected: selectionFor(kResidentialParkingAmenities),
            onChanged: (v) => toggleInto(kResidentialParkingAmenities, v),
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.groups_outlined,
          title: 'Tenant Preferences',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pref in kResidentialTenantPreferences)
                WizardCheckboxTile(
                  label: pref.label,
                  value: provider.boolVal(pref.id),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setBoolVal(pref.id, v),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// General amenities for the "Others" category.
  ///
  /// React renders `OtherGeneralAmenitiesList` (12 items) into the same
  /// `amenities` array every other category uses, and its rule requires at
  /// least one (`amenities` applies isResidential || isOthers). Flutter had no
  /// picker for this category, so that rule could never be satisfied.
  Widget _buildOtherAmenitiesSection(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    return WizardCard(
      icon: Icons.check_circle_outline,
      title: 'General Amenities',
      child: WizardMultiChipGroup(
        options: kOtherGeneralAmenities,
        selected: provider
            .listVal('amenities')
            .where(kOtherGeneralAmenities.contains)
            .toList(),
        onChanged: (v) {
          // Preserve any selection outside this list, so a listing switched
          // from another category does not silently lose amenities.
          final others = provider
              .listVal('amenities')
              .where((a) => !kOtherGeneralAmenities.contains(a))
              .toList();
          context.read<PostPropertyProvider>().setListVal('amenities', [
            ...others,
            ...v,
          ]);
        },
      ),
    );
  }

  /// Utilities / Parking & Lifts / Key Facilities used to render here for
  /// every non-commercial category — none of the three has any counterpart
  /// anywhere in the portal's AmenitiesStep.tsx, for any category. Removed
  /// per explicit request; the category-specific sections below (Residential,
  /// PG, Others) are the only things the portal actually shows here.
  Widget _buildDefaultSection(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    return const SizedBox.shrink();
  }

  /// Building facilities, all stored inside the nested `buildingInventory`
  /// object. Every one of these is required by the rules for commercial, and
  /// none had an input — `maintenanceCharges` in particular blocked the
  /// Amenities step while the only maintenance field on screen (on Pricing)
  /// wrote to a different key entirely, so commercial listings could not be
  /// published at all.
  Widget _buildBuildingFacilities(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    void setInv(String key, String value) => context
        .read<PostPropertyProvider>()
        .setBuildingInventoryValue(key, value);

    Widget numField(String key, String label, TextEditingController c) =>
        WizardField(
          label: label,
          child: WizardTextField(
            controller: c,
            hint: '0',
            keyboardType: TextInputType.number,
            onChanged: (v) => setInv(key, v),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardCard(
          icon: Icons.business_center_outlined,
          title: 'Building Facilities',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WizardField(
                label: 'Working Days *',
                child: WizardChipGroup(
                  options: _kWorkingDays,
                  selected:
                      provider.buildingInventoryText('workingDays').isEmpty
                      ? null
                      : provider.buildingInventoryText('workingDays'),
                  onSelected: (v) => setInv('workingDays', v),
                ),
              ),
              const WizardDivider(),
              WizardField(
                label: 'Building Working Hours *',
                child: WizardTextField(
                  controller: _buildingWorkingHoursController,
                  hint: 'e.g., 9:00 AM - 7:00 PM',
                  onChanged: (v) => setInv('buildingWorkingHours', v),
                ),
              ),
              const WizardDivider(),
              Row(
                children: [
                  Expanded(
                    child: numField(
                      'liftCount',
                      'Lift Count *',
                      _liftCountController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: numField(
                      'securityGuards',
                      'Security Guards *',
                      _securityGuardsController,
                    ),
                  ),
                ],
              ),
              const WizardDivider(),
              numField(
                'maintenanceCharges',
                'Maintenance Charges *',
                _buildingMaintenanceController,
              ),
              const WizardDivider(),
              Row(
                children: [
                  Expanded(
                    child: numField(
                      'totalCarParking',
                      'Total Car Parking *',
                      _totalCarParkingController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: numField(
                      'totalBikeParking',
                      'Total Bike Parking *',
                      _totalBikeParkingController,
                    ),
                  ),
                ],
              ),
              const WizardDivider(),
              numField(
                'serviceLiftCount',
                'Service Lift Count',
                _serviceLiftCountController,
              ),
              const WizardDivider(),
              numField(
                'commonAreaMaintenanceCharges',
                'Common Area Maintenance Charges',
                _camChargesController,
              ),
              const WizardDivider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildingFacilityToggles.map((t) {
                  final value =
                      (provider.buildingInventoryValue(t.$1) as bool?) ?? false;
                  return WizardCheckboxTile(
                    label: t.$2,
                    value: value,
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBuildingInventoryValue(t.$1, v),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildCommercialSections(context, provider),
      ],
    );
  }

  Widget _buildCommercialSections(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WizardCard(
          icon: Icons.business_center_outlined,
          title: 'Suitable For (Usage Details)',
          child: WizardMultiChipGroup(
            options: _suitableForOptions,
            selected: provider.listVal('suitableFor'),
            onChanged: (v) => context.read<PostPropertyProvider>().setListVal(
              'suitableFor',
              v,
            ),
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.storefront_outlined,
          title: 'Current Business',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WizardCheckboxTile(
                label: 'Current Business Running',
                value: provider.boolVal('currentBusinessRunning'),
                onChanged: (v) => context
                    .read<PostPropertyProvider>()
                    .setBoolVal('currentBusinessRunning', v),
              ),
              const WizardDivider(),
              WizardField(
                label: 'Business Type',
                child: WizardTextField(
                  controller: _businessTypeController,
                  hint: 'e.g., IT Services, Retail Outlet',
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                  ],
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setText('businessType', v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.domain_outlined,
          title: 'Commercial & Building Features',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WizardField(
                label: 'Office & Building Features',
                child: WizardMultiChipGroup(
                  options: _officeBuildingFeatures,
                  selected: provider
                      .listVal('amenities')
                      .where(_officeBuildingFeatures.contains)
                      .toList(),
                  onChanged: (v) {
                    final others = provider
                        .listVal('amenities')
                        .where((a) => !_officeBuildingFeatures.contains(a))
                        .toList();
                    context.read<PostPropertyProvider>().setListVal(
                      'amenities',
                      [...others, ...v],
                    );
                  },
                ),
              ),
              const WizardDivider(),
              WizardField(
                label: 'Retail & Warehouse Features',
                child: WizardMultiChipGroup(
                  options: _retailFeatures,
                  selected: provider.listVal('retailFeatures'),
                  onChanged: (v) => context
                      .read<PostPropertyProvider>()
                      .setListVal('retailFeatures', v),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.wc_outlined,
          title: 'Washroom Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'Total Washrooms',
                      child: WizardTextField(
                        controller: _washroomsController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setText('washrooms', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Western Seats',
                      child: WizardTextField(
                        controller: _westernSeatsController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setText('westernSeats', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Indian Seats',
                      child: WizardTextField(
                        controller: _indianSeatsController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setText('indianSeats', v),
                      ),
                    ),
                  ),
                ],
              ),
              const WizardDivider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WizardCheckboxTile(
                    label: 'Male Washroom',
                    value: provider.boolVal('maleWashroom'),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBoolVal('maleWashroom', v),
                  ),
                  WizardCheckboxTile(
                    label: 'Female Washroom',
                    value: provider.boolVal('femaleWashroom'),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBoolVal('femaleWashroom', v),
                  ),
                  WizardCheckboxTile(
                    label: 'Common Washroom',
                    value: provider.boolVal('commonWashroom'),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBoolVal('commonWashroom', v),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        WizardCard(
          icon: Icons.local_parking_outlined,
          title: 'Parking Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // commercialParkingList (AmenitiesStep.tsx:78-82) — three
              // numeric fields; Covered/Open Parking were missing here.
              Row(
                children: [
                  Expanded(
                    child: WizardField(
                      label: 'Total Parking',
                      child: WizardTextField(
                        controller: _totalParkingController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setText('totalParking', v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Covered Parking',
                      child: WizardTextField(
                        controller: _coveredParkingController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setCoveredParking(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: WizardField(
                      label: 'Open Parking',
                      child: WizardTextField(
                        controller: _openParkingController,
                        hint: '0',
                        keyboardType: TextInputType.number,
                        onChanged: (v) => context
                            .read<PostPropertyProvider>()
                            .setOpenParking(v),
                      ),
                    ),
                  ),
                ],
              ),
              const WizardDivider(),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _parkingToggles.map((t) {
                  return WizardCheckboxTile(
                    label: t.$2,
                    value: provider.boolVal(t.$1),
                    onChanged: (v) => context
                        .read<PostPropertyProvider>()
                        .setBoolVal(t.$1, v),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPgAmenitiesSection(
    BuildContext context,
    PostPropertyProvider provider,
  ) {
    return WizardCard(
      icon: Icons.home_work_outlined,
      title: 'PG & Co-Living Amenities',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WizardField(
            label: 'Room Amenities',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kPgRoomAmenities.map((o) {
                return WizardCheckboxTile(
                  label: o.label,
                  value: provider.boolVal(o.id),
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setBoolVal(o.id, v),
                );
              }).toList(),
            ),
          ),
          const WizardDivider(),
          WizardMultiChipGroup(
            // From the T0 constants: Flutter's hand-typed copy had
            // 'Gym/Fitness Center' where React writes
            // 'Gym / Fitness Center', so that value never matched
            // on the web.
            options: kPgCommonAreaAmenities.map((o) => o.label).toList(),
            selected: provider.listVal('pgAmenities'),
            onChanged: (v) => context.read<PostPropertyProvider>().setListVal(
              'pgAmenities',
              v,
            ),
          ),
          const WizardDivider(),
          WizardField(
            label: 'Safety & Security',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _pgSafetyToggles.map((t) {
                return WizardCheckboxTile(
                  label: t.$2,
                  value: provider.boolVal(t.$1),
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setBoolVal(t.$1, v),
                );
              }).toList(),
            ),
          ),
          const WizardDivider(),
          WizardField(
            label: 'Tenant Rules',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kPgTenantRules.map((o) {
                return WizardCheckboxTile(
                  label: o.label,
                  value: provider.boolVal(o.id),
                  onChanged: (v) =>
                      context.read<PostPropertyProvider>().setBoolVal(o.id, v),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
