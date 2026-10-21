import 'package:flutter/material.dart';

class ShortlistProvider extends ChangeNotifier {
  final List<String> _shortlistedIds = [];

  List<String> get shortlistedIds => _shortlistedIds;

  bool isShortlisted(String propertyId) {
    return _shortlistedIds.contains(propertyId);
  }

  void toggleShortlist(String propertyId) {
    if (_shortlistedIds.contains(propertyId)) {
      _shortlistedIds.remove(propertyId);
    } else {
      _shortlistedIds.add(propertyId);
    }
    notifyListeners();
  }

  void removeShortlist(String propertyId) {
    _shortlistedIds.remove(propertyId);
    notifyListeners();
  }

  void clearShortlist() {
    _shortlistedIds.clear();
    notifyListeners();
  }

  int get shortlistCount => _shortlistedIds.length;
}
