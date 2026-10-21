// services/places_autocomplete_service.dart
//
// Powers the office-address field's type-ahead suggestions, mirroring the
// portal's `officeAddressAutocompleteRef` (a `google.maps.places.Autocomplete`
// bound directly to the office address `<Input>` in BuilderRegistration.tsx,
// BrokerRegistration.tsx and InfluencerRegistration.tsx). The portal loads
// the Maps JS SDK's `places` library and lets it manage the whole
// predict-then-fill flow; here the two REST calls it wraps (Autocomplete
// (New) and Place Details (New)) are called directly instead, reusing the
// existing GOOGLE_MAPS_API_KEY — the same key and Places API (New) product
// `NearbyPlacesService` already calls for `searchNearby`.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'geocoding_service.dart';

@immutable
class PlacePrediction {
  const PlacePrediction({required this.placeId, required this.description});

  final String placeId;
  final String description;
}

@immutable
class PlaceDetailsResult {
  const PlaceDetailsResult({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final GeocodedAddress address;
  final double latitude;
  final double longitude;
}

class PlacesAutocompleteService {
  PlacesAutocompleteService({http.Client? client})
    : _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '',
      _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;

  static const String _autocompleteEndpoint =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const String _detailsEndpointBase =
      'https://places.googleapis.com/v1/places';
  static const Duration _timeout = Duration(seconds: 8);

  /// Predictions for [input], biased to India — matching the portal's
  /// `componentRestrictions: { country: 'in' }`. Returns `[]` on any failure
  /// (missing key, network error, zero matches) rather than throwing, since a
  /// stalled suggestion list should never block typing.
  Future<List<PlacePrediction>> autocomplete(String input) async {
    if (_apiKey.isEmpty || input.trim().isEmpty) return const [];

    try {
      final response = await _client
          .post(
            Uri.parse(_autocompleteEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask':
                  'suggestions.placePrediction.placeId,suggestions.placePrediction.text',
            },
            body: jsonEncode({
              'input': input,
              'includedRegionCodes': ['in'],
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'PlacesAutocompleteService: request failed (${response.statusCode}).',
        );
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final suggestions = decoded['suggestions'] as List<dynamic>?;
      if (suggestions == null) return const [];

      final predictions = <PlacePrediction>[];
      for (final raw in suggestions) {
        final prediction =
            (raw as Map<String, dynamic>)['placePrediction']
                as Map<String, dynamic>?;
        if (prediction == null) continue;
        final placeId = prediction['placeId'] as String?;
        final text =
            (prediction['text'] as Map<String, dynamic>?)?['text'] as String?;
        if (placeId == null || text == null) continue;
        predictions.add(PlacePrediction(placeId: placeId, description: text));
      }
      return predictions;
    } catch (e) {
      debugPrint('PlacesAutocompleteService.autocomplete failed: $e');
      return const [];
    }
  }

  /// Resolves [placeId] to coordinates + the same [GeocodedAddress] shape
  /// [GeocodingService] returns, so both entry points (map tap, typed
  /// suggestion) feed the same `onLocationSelected` handler in each
  /// registration screen.
  Future<PlaceDetailsResult?> placeDetails(String placeId) async {
    if (_apiKey.isEmpty) return null;

    try {
      final response = await _client
          .get(
            Uri.parse('$_detailsEndpointBase/$placeId'),
            headers: {
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask': 'location,addressComponents,formattedAddress',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
          'PlacesAutocompleteService: details request failed (${response.statusCode}).',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final location = decoded['location'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      final components =
          (decoded['addressComponents'] as List<dynamic>?) ?? const [];

      String? locality;
      String? adminArea2;
      String? adminArea3;
      String? postalTown;
      String? state;
      String? pincode;
      String? landmark;
      String? addressLine1;

      // Places API (New) names this field `longText`, not the classic
      // Geocoding API's `long_name` — [GeocodingService.reverseGeocode]
      // parses the same type priority against that older shape.
      for (final raw in components) {
        final component = raw as Map<String, dynamic>;
        final types = (component['types'] as List<dynamic>).cast<String>();
        final longText = component['longText'] as String? ?? '';
        if (longText.isEmpty) continue;

        if (types.contains('locality')) {
          locality = longText;
        } else if (types.contains('administrative_area_level_2')) {
          adminArea2 = longText;
        } else if (types.contains('administrative_area_level_3')) {
          adminArea3 = longText;
        } else if (types.contains('postal_town')) {
          postalTown = longText;
        } else if (types.contains('administrative_area_level_1')) {
          state = longText;
        } else if (types.contains('postal_code')) {
          pincode = longText;
        } else if (types.contains('point_of_interest') ||
            types.contains('establishment')) {
          landmark = longText;
        } else if (types.contains('route') || types.contains('street_number')) {
          addressLine1 = addressLine1 == null
              ? longText
              : '$addressLine1 $longText';
        }
      }

      final city = locality ?? postalTown ?? adminArea3 ?? adminArea2;
      final formattedAddress = decoded['formattedAddress'] as String?;
      addressLine1 ??= formattedAddress?.split(',').first;

      return PlaceDetailsResult(
        address: GeocodedAddress(
          addressLine1: addressLine1,
          city: city,
          state: state,
          pincode: pincode,
          landmark: landmark,
          formattedAddress: formattedAddress,
        ),
        latitude: lat,
        longitude: lng,
      );
    } catch (e) {
      debugPrint('PlacesAutocompleteService.placeDetails failed: $e');
      return null;
    }
  }
}
