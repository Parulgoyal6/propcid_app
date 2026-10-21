// services/nearby_places_service.dart
//
// Fetches real nearby places (hospitals, schools, malls, airports, metro
// stations) around a property's coordinates using the Places API (New)
// `searchNearby` endpoint, mirroring the behaviour of the PropCID website's
// google.maps.places.PlacesService implementation.
//
// No dummy data: every result comes from a live Places API (New) call using
// the existing GOOGLE_MAPS_API_KEY already stored in the Flutter .env file.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/nearby_place.dart';

/// Thrown for configuration/input problems only — a missing API key or
/// invalid property coordinates. A single category returning zero results,
/// or one category's request failing over the network, is NOT an error:
/// it's simply treated as "no results for that category" so one flaky
/// category never blanks the whole Nearby Places section.
class NearbyPlacesException implements Exception {
  final String message;
  const NearbyPlacesException(this.message);

  @override
  String toString() => 'NearbyPlacesException: $message';
}

/// Static description of one of the categories we search for, matching the
/// website's `placeTypes` array (type + label + icon + colour) exactly.
class _PlaceCategory {
  final String apiType; // Places API (New) "includedTypes" value
  final String label; // Human readable label shown in NearbyPlaceRow
  final IconData icon;
  final Color color;

  const _PlaceCategory({
    required this.apiType,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Internal helper pairing a parsed [NearbyPlace] with its raw straight-line
/// distance (in km) so the full, multi-category result set can be sorted
/// globally before the distance strings are (re-)used for display.
class _RankedPlace {
  final double distanceKm;
  final NearbyPlace place;
  const _RankedPlace(this.distanceKm, this.place);
}

class NearbyPlacesService {
  NearbyPlacesService() : _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  final String _apiKey;

  static const String _endpoint =
      'https://places.googleapis.com/v1/places:searchNearby';

  static const double _radiusMeters = 5000; // 5 km, per requirements
  static const int _maxResultsPerCategory = 5; // "up to 5" per category
  static const Duration _requestTimeout = Duration(seconds: 12);

  /// Categories searched — same set & order as the website:
  /// metro/subway, school, hospital, shopping mall, airport.
  static const List<_PlaceCategory> _categories = <_PlaceCategory>[
    _PlaceCategory(
      apiType: 'subway_station',
      label: 'Metro Station',
      icon: Icons.train,
      color: Color(0xFF3B82F6), // blue-500
    ),
    _PlaceCategory(
      apiType: 'school',
      label: 'Education',
      icon: Icons.school,
      color: Color(0xFFEF4444), // red-500
    ),
    _PlaceCategory(
      apiType: 'hospital',
      label: 'Hospital',
      icon: Icons.local_hospital,
      color: Color(0xFFDC2626), // red-600
    ),
    _PlaceCategory(
      apiType: 'shopping_mall',
      label: 'Shopping Mall',
      icon: Icons.shopping_bag,
      color: Color(0xFF374151), // gray-700
    ),
    _PlaceCategory(
      apiType: 'airport',
      label: 'Airport',
      icon: Icons.flight,
      color: Color(0xFF2563EB), // blue-600
    ),
  ];

  static _PlaceCategory _categoryFor(String type) {
    return _categories.firstWhere(
      (c) => c.apiType == type,
      orElse: () => _categories.first,
    );
  }

  /// Icon to use for a given internal category key (e.g. "hospital").
  /// Safe to call directly from NearbyPlaceRow(icon: ...).
  static IconData iconForType(String type) => _categoryFor(type).icon;

  /// Colour to use for a given internal category key.
  /// Safe to call directly from NearbyPlaceRow(color: ...).
  static Color colorForType(String type) => _categoryFor(type).color;

  /// Human readable label (e.g. "Hospital", "Metro Station") for a given
  /// internal category key. Use this for NearbyPlaceRow(type: ...).
  static String labelForType(String type) => _categoryFor(type).label;

  /// Fetches nearby places around [latitude]/[longitude] across all
  /// categories, sorted nearest-first.
  ///
  /// Throws [NearbyPlacesException] only when the API key is missing or the
  /// coordinates are invalid. All other failures (network errors, non-200
  /// responses, empty results) are handled per-category and simply
  /// contribute zero results instead of throwing.
  Future<List<NearbyPlace>> fetchNearbyPlaces({
    required double? latitude,
    required double? longitude,
  }) async {
    if (_apiKey.isEmpty) {
      throw const NearbyPlacesException(
        'GOOGLE_MAPS_API_KEY is missing or empty in the .env file.',
      );
    }

    if (!_isValidCoordinate(latitude, longitude)) {
      throw const NearbyPlacesException(
        'Invalid property coordinates — cannot fetch nearby places.',
      );
    }

    final double lat = latitude!;
    final double lng = longitude!;

    final List<List<_RankedPlace>> perCategoryResults = await Future.wait(
      _categories.map(
        (category) =>
            _searchCategory(category: category, latitude: lat, longitude: lng),
      ),
    );

    final List<_RankedPlace> ranked =
        perCategoryResults.expand((results) => results).toList()
          ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return ranked.map((r) => r.place).toList();
  }

  bool _isValidCoordinate(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat == 0 && lng == 0) return false; // classic "unset" sentinel
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  /// Runs a single `searchNearby` request for one category. Never throws —
  /// network failures, timeouts, non-200 responses, and malformed payloads
  /// are all caught and logged, resolving to an empty list instead.
  Future<List<_RankedPlace>> _searchCategory({
    required _PlaceCategory category,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final http.Response response = await http
          .post(
            Uri.parse(_endpoint),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              // Only request the fields we actually need to keep billing
              // and payload size minimal.
              'X-Goog-FieldMask':
                  'places.id,places.displayName,places.location,places.types',
            },
            body: jsonEncode(<String, dynamic>{
              'includedTypes': <String>[category.apiType],
              'maxResultCount': _maxResultsPerCategory,
              'locationRestriction': <String, dynamic>{
                'circle': <String, dynamic>{
                  'center': <String, double>{
                    'latitude': latitude,
                    'longitude': longitude,
                  },
                  'radius': _radiusMeters,
                },
              },
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[NearbyPlacesService] "${category.apiType}" request failed '
          '(${response.statusCode}): ${response.body}',
        );
        return const <_RankedPlace>[];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '[NearbyPlacesService] "${category.apiType}" returned an '
          'unexpected payload shape.',
        );
        return const <_RankedPlace>[];
      }

      final List<dynamic> places =
          (decoded['places'] as List<dynamic>?) ?? const <dynamic>[];

      if (places.isEmpty) return const <_RankedPlace>[];

      final List<_RankedPlace> results = <_RankedPlace>[];
      for (final dynamic raw in places) {
        if (raw is! Map<String, dynamic>) continue;

        final Map<String, dynamic>? location =
            raw['location'] as Map<String, dynamic>?;
        final double? placeLat = (location?['latitude'] as num?)?.toDouble();
        final double? placeLng = (location?['longitude'] as num?)?.toDouble();

        // Skip malformed entries with missing/invalid coordinates.
        if (!_isValidCoordinate(placeLat, placeLng)) continue;

        final Map<String, dynamic>? displayName =
            raw['displayName'] as Map<String, dynamic>?;
        final String name =
            (displayName?['text'] as String?)?.trim().isNotEmpty == true
            ? (displayName!['text'] as String)
            : 'Unnamed place';

        final double distanceKm = _haversineKm(
          latitude,
          longitude,
          placeLat!,
          placeLng!,
        );

        results.add(
          _RankedPlace(
            distanceKm,
            NearbyPlace(
              name: name,
              type: category.apiType,
              distance: _formatDistance(distanceKm),
              duration: _formatDuration(distanceKm),
              latitude: placeLat,
              longitude: placeLng,
            ),
          ),
        );
      }

      // Nearest-first within this category (also re-sorted globally later).
      results.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return results;
    } on Exception catch (e) {
      // Covers SocketException, TimeoutException, FormatException, etc.
      debugPrint('[NearbyPlacesService] "${category.apiType}" error: $e');
      return const <_RankedPlace>[];
    }
  }

  /// Straight-line (great-circle) distance between two lat/lng points, in km.
  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// 250 m / 1.3 km / 5.6 km — matches the required formatting exactly.
  String _formatDistance(double km) {
    if (km < 1) {
      final int meters = (km * 1000).round();
      return '$meters m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// <1 km → 2 min, 1–3 km → 5 min, 3–5 km → 10 min, >5 km → 15+ min.
  String _formatDuration(double km) {
    if (km < 1) return '2 min';
    if (km <= 3) return '5 min';
    if (km <= 5) return '10 min';
    return '15+ min';
  }
}
