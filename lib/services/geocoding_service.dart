// services/geocoding_service.dart
//
// Reverse-geocodes a tapped map point into an address, mirroring
// `GoogleLocationPicker.tsx`'s `performGeocode` (lines 45-100) exactly —
// same `address_components` type priority, same fallback to the formatted
// address's first segment when no route/street_number component exists.
//
// The portal calls `google.maps.Geocoder` from the loaded JS SDK, which is
// itself a thin wrapper over this same REST endpoint. Calling the endpoint
// directly here avoids adding a Maps JS-SDK-equivalent plugin for a single
// lookup. Uses the same GOOGLE_MAPS_API_KEY already in `.env` — the identical
// key `NearbyPlacesService` calls the Places API (New) with.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Mirrors the portal's `AddressDetails` interface. Any field may be null
/// when the corresponding address component wasn't present in the result.
@immutable
class GeocodedAddress {
  const GeocodedAddress({
    this.addressLine1,
    this.city,
    this.state,
    this.pincode,
    this.landmark,
    this.formattedAddress,
  });

  final String? addressLine1;
  final String? city;
  final String? state;
  final String? pincode;
  final String? landmark;

  /// Google's own full formatted address for this result (e.g. "123 MG
  /// Road, Indiranagar, Bengaluru, Karnataka 560038, India") — not split or
  /// truncated the way [addressLine1] is (route + street-number components
  /// only, or a lossy first-comma-segment fallback). Callers that want the
  /// most complete address text to show the user should prefer this over
  /// [addressLine1] when it's available, falling back to [addressLine1]
  /// only when it isn't (e.g. a geocode result with no formatted_address at
  /// all, which the API does not guarantee).
  final String? formattedAddress;
}

class GeocodingService {
  GeocodingService({http.Client? client})
    : _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '',
      _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static const String _endpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';
  static const Duration _timeout = Duration(seconds: 10);

  /// Reverse-geocodes [lat]/[lng]. Returns null on any failure (missing key,
  /// network error, zero results) rather than throwing — a failed lookup
  /// should leave the address fields as the user last had them, not block
  /// the map tap that triggered it.
  Future<GeocodedAddress?> reverseGeocode(double lat, double lng) async {
    if (_apiKey.isEmpty) {
      debugPrint('GeocodingService: GOOGLE_MAPS_API_KEY is missing or empty.');
      return null;
    }

    try {
      final uri = Uri.parse(
        _endpoint,
      ).replace(queryParameters: {'latlng': '$lat,$lng', 'key': _apiKey});

      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint(
          'GeocodingService: request failed (${response.statusCode}).',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['status'] != 'OK') {
        return null;
      }

      final results = decoded['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      final result = results.first as Map<String, dynamic>;
      final components =
          (result['address_components'] as List<dynamic>?) ?? const [];

      String? locality;
      String? adminArea2;
      String? adminArea3;
      String? postalTown;
      String? state;
      String? pincode;
      String? landmark;
      String? addressLine1;

      for (final raw in components) {
        final component = raw as Map<String, dynamic>;
        final types = (component['types'] as List<dynamic>).cast<String>();
        final longName = component['long_name'] as String;

        if (types.contains('locality')) {
          locality = longName;
        } else if (types.contains('administrative_area_level_2')) {
          adminArea2 = longName;
        } else if (types.contains('administrative_area_level_3')) {
          adminArea3 = longName;
        } else if (types.contains('postal_town')) {
          postalTown = longName;
        } else if (types.contains('administrative_area_level_1')) {
          state = longName;
        } else if (types.contains('postal_code')) {
          pincode = longName;
        } else if (types.contains('point_of_interest') ||
            types.contains('establishment')) {
          landmark = longName;
        } else if (types.contains('route') || types.contains('street_number')) {
          addressLine1 = addressLine1 == null
              ? longName
              : '$addressLine1 $longName';
        }
      }

      final city = locality ?? postalTown ?? adminArea3 ?? adminArea2;
      final formattedAddress = result['formatted_address'] as String?;
      addressLine1 ??= formattedAddress?.split(',').first;

      return GeocodedAddress(
        addressLine1: addressLine1,
        city: city,
        state: state,
        pincode: pincode,
        landmark: landmark,
        formattedAddress: formattedAddress,
      );
    } catch (e) {
      debugPrint('GeocodingService.reverseGeocode failed: $e');
      return null;
    }
  }
}
