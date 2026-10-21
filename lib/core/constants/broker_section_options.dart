// core/constants/broker_section_options.dart
//
// The vocabularies of the broker dashboard's Spec I sections.
//
// THE LEAD STATUS MAPPING IS THE INTERESTING PART
// -----------------------------------------------
// `property_inquiries.status` is a Postgres ENUM, not free text:
//
//   CREATE TYPE inquiry_status AS ENUM ('pending','contacted','scheduled','closed')
//     — 20250724173621:10
//   ALTER TYPE inquiry_status ADD VALUE 'approved'
//     — 20250918141743_add_approved_to_inquiry_status.sql:3
//
// Five values, and writing anything else is a `22P02 invalid input value for enum`.
//
// `BrokerLeadsManager.tsx` presents a different, CRM-flavoured vocabulary on top
// of it and maps between the two (`:113-120` reading, `:183-191` writing):
//
//   new               ⇄ pending
//   contacted         ⇄ contacted
//   viewing_scheduled ⇄ scheduled
//   negotiation       ⇄ approved
//   closed            ⇄ closed
//   lost              → pending          ← one-way, and lossy
//
// That last row is the portal's own comment: `'lost': 'pending', // Map lost back
// to pending for now` (`:188`). The column has no `lost`, so a broker who marks a
// lead Lost sees it read back as **New** after any refresh — their input is
// discarded silently.
//
// So `lost` is deliberately absent from [kBrokerLeadStatuses] below. Offering a
// control that throws the user's answer away is worse than not offering it, and
// this is a data-integrity defect rather than a business rule — the same call the
// PD9 decision made for `sanitizeText`. Reported as a parity gap instead.

/// One selectable lead status, and the enum value it maps to.
class BrokerLeadStatus {
  const BrokerLeadStatus({
    required this.value,
    required this.label,
    required this.dbValue,
  });

  /// The app-side CRM value, matching the portal's `Lead['status']`.
  final String value;

  final String label;

  /// The `inquiry_status` enum value this reads from and writes to.
  final String dbValue;
}

/// The five statuses that round-trip. Portal order, `lost` omitted — see above.
const List<BrokerLeadStatus> kBrokerLeadStatuses = [
  BrokerLeadStatus(value: 'new', label: 'New', dbValue: 'pending'),
  BrokerLeadStatus(
    value: 'contacted',
    label: 'Contacted',
    dbValue: 'contacted',
  ),
  BrokerLeadStatus(
    value: 'viewing_scheduled',
    label: 'Viewing Scheduled',
    dbValue: 'scheduled',
  ),
  BrokerLeadStatus(
    value: 'negotiation',
    label: 'Negotiation',
    dbValue: 'approved',
  ),
  BrokerLeadStatus(value: 'closed', label: 'Closed', dbValue: 'closed'),
];

/// App status for a stored `inquiry_status`.
///
/// Unknown values fall back to `new`, which is the portal's
/// `statusMap[inquiry.status] || 'new'` (`:130`).
String brokerLeadStatusFromDb(String? dbValue) {
  for (final status in kBrokerLeadStatuses) {
    if (status.dbValue == dbValue) return status.value;
  }
  return 'new';
}

/// The enum value to write for an app status.
///
/// Returns null for anything unmapped rather than defaulting to `pending`. That
/// is the one place this deliberately diverges: the portal's `|| 'pending'` is
/// exactly what makes "Lost" destructive, so an unmappable status is refused at
/// the service boundary instead of quietly becoming New.
String? brokerLeadStatusToDb(String value) {
  for (final status in kBrokerLeadStatuses) {
    if (status.value == value) return status.dbValue;
  }
  return null;
}

/// Display label for an app status.
String brokerLeadStatusLabel(String? value) {
  for (final status in kBrokerLeadStatuses) {
    if (status.value == value) return status.label;
  }
  // `lost` can still arrive from nowhere — no row can hold it — but a future
  // enum value could, and it should read as itself rather than as New.
  final raw = (value ?? '').replaceAll('_', ' ').trim();
  if (raw.isEmpty) return 'New';
  return raw
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// The statuses `BrokerLeadsManager.tsx:143-145` counts as still in play.
const Set<String> kActiveBrokerLeadStatuses = {
  'new',
  'contacted',
  'viewing_scheduled',
  'negotiation',
};

// ── Unified leads (inquiries + visit bookings together) ─────────────────────
//
// `IncomingLeadsManager.tsx` folds `property_visit_bookings` (and
// `project_visit_bookings`/`profile_visit_requests`, not ported here — nothing
// in this app creates those two yet) into the *same* CRM vocabulary
// [kBrokerLeadStatuses] already used for inquiries, via its own
// `visitStatusMap`/`visitReverseStatusMap` (`:71-87`):
//
//   pending     ⇄ new / contacted   (both map back to pending — see below)
//   confirmed   ⇄ viewing_scheduled
//   rescheduled  → viewing_scheduled   ← one-way; the 5-option picker never
//                                        writes 'rescheduled' back
//   completed   ⇄ negotiation / closed (both map back to completed)
//   cancelled    → lost                ← one-way, and 'lost' is excluded
//                                        from the picker, same reasoning as
//                                        inquiries' own missing 'lost'
//
// Unlike inquiries (one dbValue per app value), two DB values fold onto one
// app value here, and two app values fold onto one DB value on the way back
// — hence separate functions rather than reusing [BrokerLeadStatus].

/// App status for a stored `property_visit_bookings.status`.
///
/// Unmapped values (there are none today; the column has no CHECK) fall back
/// to `new`, matching `visitStatusMap[...] || 'new'` (`IncomingLeadsManager
/// .tsx:130`).
String visitLeadStatusFromDb(String? dbValue) => switch (dbValue) {
  'pending' => 'new',
  'confirmed' => 'viewing_scheduled',
  'rescheduled' => 'viewing_scheduled',
  'completed' => 'negotiation',
  'cancelled' => 'lost',
  _ => 'new',
};

/// The booking status to write for an app status picked from
/// [kBrokerLeadStatuses] — always one of pending/confirmed/completed, since
/// the picker never offers 'lost' and this app's Leads tab never reschedules
/// a slot (that stays the Visits tab's job).
String visitLeadStatusToDb(String value) => switch (value) {
  'new' => 'pending',
  'contacted' => 'pending',
  'viewing_scheduled' => 'confirmed',
  'negotiation' => 'completed',
  'closed' => 'completed',
  _ => 'pending',
};

// ── Broker profile ──────────────────────────────────────────────────────────
//
// `broker_profiles` (20260423000001_create_broker_profiles_table.sql). Only
// `full_name` is NOT NULL; `years_of_experience` defaults to 0 and both array
// columns default to `'{}'`. `approval_status` is CHECK-constrained to
// ('pending','approved','rejected') and is **not** editable by the broker — the
// portal's form never sends it, and neither does this app.

/// Label for a stored `approval_status`.
String brokerProfileApprovalLabel(String? status) => switch (status) {
  'approved' => 'Approved',
  'rejected' => 'Rejected',
  _ => 'Pending Review',
};

// `property_types` and `operating_cities` have deliberately **no** option list
// here. `BrokerProfileManager.tsx:461-490` renders both as read-only badges — it
// has no editor for either, and its `handleSave` sends whatever it loaded straight
// back (`:147-148`). Both arrays are populated by the broker registration flow,
// which is under a standing instruction not to be modified.
//
// So the mobile form shows them and preserves them byte for byte. Inventing a
// checkbox list would both add a control the portal lacks and risk dropping a
// stored value the app does not know about — the hazard decision 5.1 was written
// for.
