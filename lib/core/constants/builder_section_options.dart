// core/constants/builder_section_options.dart
//
// The vocabularies of the builder dashboard's four management sections.
//
// Every list here is transcribed from a CHECK constraint or from the portal's own
// picker, and each entry says which. Nothing is invented: a value outside these
// sets is either a `23514` or a status no portal screen can produce.

// ── Inventory: the project status picker ────────────────────────────────────
//
// `builder_projects.status` is CHECK-constrained to
// ('active','inactive','completed','under_construction')
// — 20250905144708_cc6b51bd…sql:9. `BuilderInventoryManager.tsx:544-551` offers
// all four, which is why this list is the full constraint rather than a subset
// (contrast `propertyStatusOptions`, where the portal deliberately exposes two of
// four).

/// One selectable project status, with the label the portal shows.
class BuilderProjectStatusOption {
  const BuilderProjectStatusOption(this.value, this.label);

  final String value;
  final String label;
}

/// The picker's contents, in `BuilderInventoryManager.tsx`'s order.
const List<BuilderProjectStatusOption> kProjectStatusPickerOptions = [
  BuilderProjectStatusOption('active', 'Active'),
  BuilderProjectStatusOption('under_construction', 'Under Construction'),
  BuilderProjectStatusOption('completed', 'Completed'),
  BuilderProjectStatusOption('inactive', 'Inactive'),
];

/// Whether [status] is one the builder may switch to.
bool isSettableProjectStatus(String? status) =>
    kProjectStatusPickerOptions.any((o) => o.value == status);

// ── Inventory: unit status ──────────────────────────────────────────────────
//
// `project_inventory.status` CHECK: ('available','booked','sold','blocked')
// — 20250905144708:100.

/// Label for a stored `project_inventory.status`.
String inventoryUnitStatusLabel(String? status) => switch (status) {
  'available' => 'Available',
  'booked' => 'Booked',
  'sold' => 'Sold',
  'blocked' => 'Blocked',
  _ => 'Unknown',
};

/// The CHECK constraint's four values, for a unit-status picker.
///
/// `ProjectInventoryManager.tsx`'s own unit form offers the same four in a
/// plain `<select>`; this is the first Flutter unit-level editor, so this
/// list didn't need to exist until now.
const List<BuilderProjectStatusOption> kInventoryUnitStatusOptions = [
  BuilderProjectStatusOption('available', 'Available'),
  BuilderProjectStatusOption('booked', 'Booked'),
  BuilderProjectStatusOption('sold', 'Sold'),
  BuilderProjectStatusOption('blocked', 'Blocked'),
];

// ── Team Workspace: lead status picker ──────────────────────────────────────
//
// `network_leads.status` has no CHECK constraint, so different surfaces use
// different vocabularies for the same free-text column — the broker-side "My
// Leads" screen's four values (`LeadStatusCounts`) are a different set.
// `TeamLeadsView.tsx:25`'s `STATUS_OPTIONS` is this picker's source of truth.
const List<BuilderProjectStatusOption> kTeamLeadStatusOptions = [
  BuilderProjectStatusOption('new', 'New'),
  BuilderProjectStatusOption('contacted', 'Contacted'),
  BuilderProjectStatusOption('qualified', 'Qualified'),
  BuilderProjectStatusOption('converted', 'Converted'),
  BuilderProjectStatusOption('lost', 'Lost'),
];

// ── Site visits: booking status ─────────────────────────────────────────────
//
// `project_visit_bookings.status` has **no** CHECK constraint (20260304164434:12
// is a bare `TEXT NOT NULL DEFAULT 'pending'`), so the five values below are the
// portal's picker (`SiteVisitBookingsManager.tsx:45-51`) rather than a database
// rule. A sixth value would store fine and read as itself.

/// One selectable booking status.
class SiteVisitStatusOption {
  const SiteVisitStatusOption(this.value, this.label);

  final String value;
  final String label;
}

/// The picker's contents, in the portal's order.
const List<SiteVisitStatusOption> kSiteVisitStatusOptions = [
  SiteVisitStatusOption('pending', 'Pending'),
  SiteVisitStatusOption('confirmed', 'Confirmed'),
  SiteVisitStatusOption('completed', 'Completed'),
  SiteVisitStatusOption('cancelled', 'Cancelled'),
  SiteVisitStatusOption('rescheduled', 'Rescheduled'),
];

/// Label for a stored booking status.
///
/// Falls back to the raw value title-cased, because the column is unconstrained
/// and a row may legitimately hold something this list does not know.
String siteVisitStatusLabel(String? status) {
  for (final option in kSiteVisitStatusOptions) {
    if (option.value == status) return option.label;
  }
  final raw = (status ?? '').trim();
  if (raw.isEmpty) return 'Pending';
  return '${raw[0].toUpperCase()}${raw.substring(1)}';
}

/// The three statuses whose change notifies the visitor.
///
/// `SiteVisitBookingsManager.tsx:177` — `['confirmed','cancelled','rescheduled']`.
/// `completed` deliberately does not notify, even though
/// `notifyVisitBookingUpdate` has copy for it: the portal never passes it.
const Set<String> kNotifyingSiteVisitStatuses = {
  'confirmed',
  'cancelled',
  'rescheduled',
};

// ── Team: modules and limits ────────────────────────────────────────────────
//
// `builder_team_members.modules` is CHECK-constrained with
// `modules <@ ARRAY['inventory','offers','leads','site_visits']`
// — 20270201000000_builder_team_members.sql:57-58. The invitations table adds
// `array_length(modules,1) >= 1`, so an empty grant is refused by the database as
// well as by the form.

/// One grantable module, with the label the invite form shows.
class BuilderTeamModule {
  const BuilderTeamModule(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

/// The four values the CHECK constraint accepts.
const List<BuilderTeamModule> kBuilderTeamModules = [
  BuilderTeamModule('inventory', 'Inventory', 'View and update project status'),
  BuilderTeamModule(
    'offers',
    'Marketed Offers',
    'Manage offers shared with brokers',
  ),
  BuilderTeamModule('leads', 'Leads', 'See and work incoming enquiries'),
  BuilderTeamModule(
    'site_visits',
    'Site Visits',
    'Confirm and reschedule bookings',
  ),
];

/// Label for a stored module value.
String builderTeamModuleLabel(String value) {
  for (final module in kBuilderTeamModules) {
    if (module.value == value) return module.label;
  }
  return value.replaceAll('_', ' ');
}

/// Whether every entry of [modules] is one the CHECK constraint accepts.
bool areValidTeamModules(Iterable<String> modules) =>
    modules.every((m) => kBuilderTeamModules.any((k) => k.value == m));

/// Active team members per builder.
///
/// Enforced by `enforce_team_member_cap()`, a trigger — so exceeding it raises
/// rather than silently truncating. Checked client-side so the builder is told
/// before an invite is sent (`BuilderTeamManager.tsx:183`).
const int kMaxBuilderTeamMembers = 10;

/// Label for a member or invitation `status`.
///
/// Members: ('active','revoked'). Invitations:
/// ('pending','accepted','revoked','expired') — 20270201000000:28 and :51.
String builderTeamStatusLabel(String? status) => switch (status) {
  'active' => 'Active',
  'revoked' => 'Revoked',
  'pending' => 'Pending',
  'accepted' => 'Accepted',
  'expired' => 'Expired',
  _ => 'Unknown',
};

/// Verb for a `builder_team_activity.action` value (lowercased `TG_OP`).
///
/// Mirrors `BuilderTeamManager.tsx`'s `ACTION_VERB` map/fallback exactly: an
/// unrecognised value renders as the raw string rather than "Unknown" —
/// this is an audit log, so showing the database's own term beats hiding
/// it behind a generic label.
String builderTeamActivityActionLabel(String action) => switch (action) {
  'insert' => 'added',
  'update' => 'updated',
  'delete' => 'removed',
  _ => action,
};
