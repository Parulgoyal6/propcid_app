// models/available_location.dart
//
// Mirrors the website's `available_locations` table row (used for its city
// chips / autocomplete seeding). Same table, read verbatim — no new backend
// behavior.
class AvailableLocation {
  final String id;
  final String city;
  final String? state;
  final String country;
  final double? latitude;
  final double? longitude;

  const AvailableLocation({
    required this.id,
    required this.city,
    this.state,
    this.country = 'India',
    this.latitude,
    this.longitude,
  });

  factory AvailableLocation.fromSupabase(Map<String, dynamic> json) {
    return AvailableLocation(
      id: json['id']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString(),
      country: json['country']?.toString() ?? 'India',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}
