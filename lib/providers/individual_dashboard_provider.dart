import 'package:flutter/material.dart';
import '../models/property_model.dart';
import '../services/property_service.dart';

class IndividualDashboardProvider extends ChangeNotifier {
  bool _loading = false;
  List<PropertyModel> _myProperties = [];
  String? _lastUserId;

  bool get loading => _loading;
  List<PropertyModel> get myProperties => List.unmodifiable(_myProperties);

  Future<void> loadProperties(String userId) async {
    _loading = true;
    _lastUserId = userId;
    notifyListeners();

    try {
      _myProperties = await PropertyService().getPropertiesByUser(userId);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_lastUserId == null) return;
    await loadProperties(_lastUserId!);
  }

  Future<void> deleteProperty(String propertyId) async {
    await PropertyService().deleteProperty(propertyId);
    _myProperties = _myProperties.where((p) => p.id != propertyId).toList();
    notifyListeners();
  }
}
