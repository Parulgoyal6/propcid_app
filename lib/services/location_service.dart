// services/location_service.dart
//
// Wraps the `geolocator` package (declared in pubspec.yaml but unused
// anywhere in the app until now) for the "near me" search flow. Mirrors the
// website's CityContext geolocation flow: check services enabled -> check/
// request permission -> read the current position.
import 'package:geolocator/geolocator.dart';

enum LocationFailureReason {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unknown,
}

class LocationResult {
  final double? latitude;
  final double? longitude;
  final LocationFailureReason? failureReason;

  const LocationResult.success(this.latitude, this.longitude)
    : failureReason = null;
  const LocationResult.failure(this.failureReason)
    : latitude = null,
      longitude = null;

  bool get isSuccess => failureReason == null;
}

class LocationService {
  Future<LocationResult> getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationResult.failure(
        LocationFailureReason.servicesDisabled,
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(
        LocationFailureReason.permissionDenied,
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failure(
        LocationFailureReason.permissionDeniedForever,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return LocationResult.success(position.latitude, position.longitude);
    } catch (_) {
      return const LocationResult.failure(LocationFailureReason.unknown);
    }
  }
}
