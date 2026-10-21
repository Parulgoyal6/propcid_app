// core/constants/property_status_options.dart
//
// The listing statuses a seller may set on their own listing from the dashboard.
//
// The `properties.status` CHECK accepts four values —
// `('active', 'inactive', 'sold', 'rented')`, declared in
// `20250719101351_…sql:14` — but the website's dashboard picker offers only two
// of them (BrokerContentManager.tsx:340-346). `inactive` and `rented` are set
// elsewhere (admin tooling and the rental flow), never by the owner from this
// screen, so exposing them here would be inventing a control the portal does not
// have.
//
// Kept in a file of its own rather than appended to a service so the wording and
// the vocabulary stay in one place, next to `project_options.dart` which does the
// same job for `builder_projects`.

/// A status the dashboard's inline picker can set, with its display label.
class PropertyStatusOption {
  const PropertyStatusOption(this.value, this.label);

  /// The exact string written to `properties.status`.
  final String value;

  /// Title case, as the website renders it.
  final String label;
}

/// The picker's contents, in the website's order.
const List<PropertyStatusOption> propertyStatusOptions = [
  PropertyStatusOption('active', 'Active'),
  PropertyStatusOption('sold', 'Sold'),
];

/// The label for any stored status, including the two the picker cannot set.
///
/// A listing an admin marked `inactive`, or one the rental flow marked `rented`,
/// still has to read correctly on the card. Falls back to `Pending` for anything
/// unrecognised, matching the badge this replaces.
String propertyStatusLabel(String? status) => switch (status) {
  'active' => 'Active',
  'sold' => 'Sold',
  'inactive' => 'Inactive',
  'rented' => 'Rented',
  _ => 'Pending',
};

/// Whether [status] is one the owner may switch between.
///
/// False for `inactive` and `rented`: the picker must not silently offer to
/// convert those into `active`, because it would be the only way to leave the
/// dropdown and the owner did not set them in the first place.
bool isOwnerSettableStatus(String? status) =>
    propertyStatusOptions.any((o) => o.value == status);
