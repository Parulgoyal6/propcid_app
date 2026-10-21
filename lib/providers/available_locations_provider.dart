import 'package:flutter/material.dart';
import '../models/available_location.dart';
import '../services/property_service.dart';

/// Loads the `available_locations` table once (same convention as
/// PropertyProvider's own constructor-triggered load) for the city picker
/// used on the search screens.
class AvailableLocationsProvider extends ChangeNotifier {
  List<AvailableLocation> _locations = [];
  bool _isLoading = true;

  List<AvailableLocation> get locations => _locations;
  bool get isLoading => _isLoading;

  final PropertyService _propertyService = PropertyService();

  AvailableLocationsProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      _locations = await _propertyService.getAvailableLocations();
    } catch (e) {
      debugPrint('[AvailableLocationsProvider] load failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
