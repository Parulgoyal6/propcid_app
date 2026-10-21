// core/constants/project_options.dart
//
// The builder project vocabularies. Every value here is a database value, not a
// label — the labels are what the user reads and are never stored.
//
// NOTHING IN THIS FILE MAY BE INVENTED
// -----------------------------------
// [kProjectTypes] is simultaneously the `project_type` CHECK constraint
// (`20250905144708_cc6b51bd…sql:7`) and the portal's `PROJECT_TYPES`
// (`BuilderProjectWizard.tsx:56-65`) — the two agree, and a value absent from
// either is rejected by Postgres with a `23514`. [kProjectStatuses] is the
// `status` CHECK from the same line 9. [kCommonAmenities] is
// `COMMON_AMENITIES` (`:67-72`) — suggestions only; `amenities` is a free `text[]`
// and the wizard lets the user add their own.
import 'package:flutter/foundation.dart';

/// One selectable value: what is stored, and what is shown.
@immutable
class ProjectOption {
  const ProjectOption(this.value, this.label);

  /// The database value.
  final String value;

  /// The label rendered to the user.
  final String label;
}

/// `project_type` — the CHECK constraint's eight values, in the portal's order.
const List<ProjectOption> kProjectTypes = [
  ProjectOption('plotted_development', 'Plotted Development'),
  ProjectOption('group_housing', 'Group Housing'),
  ProjectOption('integrated_township', 'Integrated Township'),
  ProjectOption(
    'gated_community_plots_villas',
    'Gated Community with Plots/Villas',
  ),
  ProjectOption('farm_houses', 'Farm Houses'),
  ProjectOption('service_apartment', 'Service Apartments'),
  ProjectOption('commercial_spaces', 'Commercial Spaces'),
  ProjectOption('office_spaces', 'Office Spaces'),
];

/// `status` — the CHECK constraint's four values. `active` is the column default
/// and the only one the public read policy exposes
/// (`USING (status = 'active')`), so a project moved off `active` disappears from
/// every public surface.
const List<ProjectOption> kProjectStatuses = [
  ProjectOption('active', 'Active'),
  ProjectOption('under_construction', 'Under Construction'),
  ProjectOption('completed', 'Completed'),
  ProjectOption('inactive', 'Inactive'),
];

/// The 19 amenity suggestions, verbatim and in the portal's order.
const List<String> kCommonAmenities = [
  'Swimming Pool',
  'Gymnasium',
  'Clubhouse',
  'Children Play Area',
  'Landscaped Gardens',
  'Security',
  '24/7 Power Backup',
  'Parking',
  'Elevator',
  'Sports Complex',
  'Community Hall',
  'Jogging Track',
  'Senior Citizen Park',
  'Library',
  'Shopping Complex',
  'School',
  'Hospital',
  'ATM',
  'Restaurant',
];

/// The label for a stored `project_type`, or the raw value when unrecognised.
///
/// Falls back rather than throwing: a value written by a future portal migration
/// should still render on a card instead of taking the screen down.
String projectTypeLabel(String? value) {
  if (value == null || value.isEmpty) return '';
  for (final option in kProjectTypes) {
    if (option.value == value) return option.label;
  }
  return value.replaceAll('_', ' ');
}

/// The label for a stored `status`, or the raw value when unrecognised.
String projectStatusLabel(String? value) {
  if (value == null || value.isEmpty) return '';
  for (final option in kProjectStatuses) {
    if (option.value == value) return option.label;
  }
  return value.replaceAll('_', ' ');
}

/// True when [value] is a legal `project_type`.
///
/// Used by the review step before submit, so an impossible value is caught here
/// rather than as a `23514` from Postgres.
bool isValidProjectType(String? value) =>
    kProjectTypes.any((option) => option.value == value);

/// True when [value] is a legal `status`.
bool isValidProjectStatus(String? value) =>
    kProjectStatuses.any((option) => option.value == value);

// ── Inventory: unit type, by project type ───────────────────────────────────
//
// `InventoryTableEditor.tsx:52-70`'s `getUnitTypeOptions`, verbatim — every
// project type not listed there falls through to its own `default: ['Unit']`.
// This is a UI suggestion list, not a CHECK constraint: `project_inventory.unit_type`
// is a free `VARCHAR(100)`, so unlike [kProjectTypes] nothing here is validated
// against the database.
List<String> unitTypeOptionsFor(String projectType) => switch (projectType) {
  'group_housing' || 'service_apartment' => const [
    'Studio',
    '1 BHK',
    '2 BHK',
    '3 BHK',
    '4 BHK',
    '5 BHK',
    'Duplex',
    'Penthouse',
  ],
  'plotted_development' || 'gated_community_plots_villas' => const [
    'Residential Plot',
    'Villa Plot',
    'Corner Plot',
    'Park Facing Plot',
  ],
  'farm_houses' => const ['Farm House', 'Farm Land', 'Agricultural Plot'],
  'commercial_spaces' || 'office_spaces' => const [
    'Office Space',
    'Shop',
    'Showroom',
    'Warehouse',
    'Co-working Space',
    'Food Court',
    'Retail Space',
  ],
  'integrated_township' => const [
    'Studio',
    '1 BHK',
    '2 BHK',
    '3 BHK',
    '4 BHK',
    'Villa',
    'Plot',
    'Commercial Space',
  ],
  _ => const ['Unit'],
};

/// `InventoryTableEditor.tsx:72-74`'s `plotTypes`/`isPlotType` — a plot has no
/// floor, so [ManageUnitsScreen] hides that field for these unit types rather
/// than showing a meaningless input.
const List<String> kPlotUnitTypes = [
  'Residential Plot',
  'Villa Plot',
  'Corner Plot',
  'Park Facing Plot',
  'Farm Land',
  'Agricultural Plot',
  'Plot',
];

bool isPlotUnitType(String unitType) => kPlotUnitTypes.contains(unitType);

/// `InventoryTableEditor.tsx:76`'s `facingOptions`, verbatim. Same
/// free-column caveat as [unitTypeOptionsFor] — `facing_direction` has no
/// CHECK constraint either.
const List<String> kInventoryFacingOptions = [
  'North',
  'South',
  'East',
  'West',
  'North-East',
  'North-West',
  'South-East',
  'South-West',
];
