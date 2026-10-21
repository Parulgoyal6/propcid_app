// core/utils/geo_utils.dart
//
// Haversine distance helper for the "near me" search flow only. This is a
// deliberate, separate copy from NearbyPlacesService's own private haversine
// (used for Google Places nearby-amenities) — that file already works
// correctly and is unrelated to property search, so it's left untouched.
import 'dart:math';

/// Great-circle distance between two lat/lng points, in kilometers.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(lat2 - lat1);
  final dLon = _degToRad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_degToRad(lat1)) *
          cos(_degToRad(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _degToRad(double deg) => deg * (pi / 180.0);

/// Whether [lat]/[lng] form a usable, resolved map coordinate — not merely
/// "present". Shared by every form/screen that needs to tell a real pinned
/// location apart from an unset, corrupted, or `(0, 0)`-default one (a
/// stale/never-resolved pair has repeatedly reached map pickers, "Get
/// Directions" links and submit payloads as if it were valid).
///
/// A pair is valid when both are non-null, finite, and within the physical
/// range a coordinate can hold (±90 latitude, ±180 longitude). `(0, 0)` —
/// "Null Island", off the coast of west Africa — is explicitly rejected: no
/// real listing resolves there, and it is exactly the default/placeholder
/// value every known stale-coordinate bug this guards against produces.
bool isValidCoordinatePair(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (!lat.isFinite || !lng.isFinite) return false;
  if (lat < -90 || lat > 90) return false;
  if (lng < -180 || lng > 180) return false;
  if (lat == 0 && lng == 0) return false;
  return true;
}
