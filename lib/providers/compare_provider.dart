// providers/compare_provider.dart
//
// Global Compare Properties state — the single source of truth for "which
// properties is the user currently comparing", shared by every property
// card in the app (Home, Search, Shortlist, Property Detail) and the Compare
// screen itself:
//
//   Property Card -> CompareProvider -> persisted ids -> Compare screen
//
// Deliberately does NOT hold a PropertyProvider reference or any fetching
// logic — this provider only owns the id set, the min/max rules and the
// category/listing-type lock. Resolving ids to PropertyModels (cache first,
// then a targeted fetch for anything missing) is the caller's job, exactly
// like PropertyProvider.findCached already is for other features. Keeping
// Shortlist and Compare fully decoupled is deliberate — see CLAUDE.md/Phase 7:
// Shortlist = saved property, Compare = temporary comparison selection.
import 'package:flutter/foundation.dart';

import '../models/property_model.dart';
import '../services/compare_service.dart';

/// Result of attempting to add a property to the comparison — lets callers
/// (property cards, the in-screen picker) show the right feedback without
/// duplicating the min/max/category rules themselves.
enum CompareAddResult { added, removed, limitReached, categoryMismatch }

class CompareProvider extends ChangeNotifier {
  /// Matches the portal's `MIN_COMPARE`/`MAX_COMPARE` (CompareContext.tsx).
  static const int minCompare = 2;
  static const int maxCompare = 4;

  final CompareService _service;

  List<String> _selectedIds = [];

  /// Set from the first property added (or restored); every later add must
  /// match both, mirroring the portal's `canAddProperty` rule. Reset to null
  /// once the selection is empty.
  String? _activeCategory;
  String? _activePropertyType;

  CompareProvider({CompareService? service})
    : _service = service ?? CompareService() {
    _restore();
  }

  List<String> get selectedIds => List.unmodifiable(_selectedIds);
  int get count => _selectedIds.length;
  bool get isFull => _selectedIds.length >= maxCompare;
  bool get canCompareNow => _selectedIds.length >= minCompare;
  String? get activeCategory => _activeCategory;
  String? get activePropertyType => _activePropertyType;

  bool isSelected(String propertyId) => _selectedIds.contains(propertyId);

  /// Trims and lowercases before comparing — guards against two rows that
  /// are genuinely the same category/listing type but differ in incidental
  /// casing or whitespace (e.g. a legacy row saved as `'Residential'` next
  /// to a newer `'residential'`). This narrows what counts as a
  /// *formatting* difference; it does not loosen the actual rule —
  /// `'residential'` vs `'commercial'` still never matches.
  String? _normalize(String? value) {
    final trimmed = value?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Whether [property] could be added right now, without side effects —
  /// lets a card grey out an incompatible property instead of only failing
  /// after the tap.
  bool canAdd(PropertyModel property) {
    if (_selectedIds.contains(property.id)) return true;
    if (isFull) return false;
    if (_activeCategory == null) return true;
    return _normalize(_activeCategory) == _normalize(property.category) &&
        _normalize(_activePropertyType) == _normalize(property.propertyType);
  }

  /// Adds/removes [property] and reports what happened, so the caller can
  /// show a SnackBar on `limitReached`/`categoryMismatch` — same contract as
  /// the portal's `addToCompare`/`removeFromCompare` pair.
  CompareAddResult toggle(PropertyModel property) {
    if (_selectedIds.contains(property.id)) {
      remove(property.id);
      return CompareAddResult.removed;
    }
    return add(property);
  }

  CompareAddResult add(PropertyModel property) {
    if (_selectedIds.contains(property.id)) return CompareAddResult.added;
    if (isFull) return CompareAddResult.limitReached;
    if (_activeCategory != null &&
        (_normalize(_activeCategory) != _normalize(property.category) ||
            _normalize(_activePropertyType) !=
                _normalize(property.propertyType))) {
      return CompareAddResult.categoryMismatch;
    }

    _selectedIds = [..._selectedIds, property.id];
    if (_selectedIds.length == 1) {
      _activeCategory = property.category;
      _activePropertyType = property.propertyType;
    }
    _persist();
    notifyListeners();
    return CompareAddResult.added;
  }

  void remove(String propertyId) {
    if (!_selectedIds.contains(propertyId)) return;
    _selectedIds = _selectedIds.where((id) => id != propertyId).toList();
    if (_selectedIds.isEmpty) {
      _activeCategory = null;
      _activePropertyType = null;
    }
    _persist();
    notifyListeners();
  }

  void clear() {
    if (_selectedIds.isEmpty) return;
    _selectedIds = [];
    _activeCategory = null;
    _activePropertyType = null;
    _persist();
    notifyListeners();
  }

  /// Re-derives the category/type lock from whichever selected property
  /// resolves first in [pool], and drops any other selected id that turns
  /// out to mismatch it — covers a selection restored from disk before any
  /// property data had loaded (the lock is unknown at restore time, see
  /// [_restore]). Ids not found in [pool] are left alone; they may simply not
  /// be loaded yet, so this never removes an id on their behalf — callers
  /// that have already tried a dedicated fetch and still can't resolve an id
  /// should call [remove] for it directly instead.
  void reconcileWithPool(List<PropertyModel> pool) {
    if (_selectedIds.isEmpty) return;
    final byId = {for (final p in pool) p.id: p};

    String? category;
    String? propertyType;
    for (final id in _selectedIds) {
      final match = byId[id];
      if (match == null) continue;
      category = match.category;
      propertyType = match.propertyType;
      break;
    }
    if (category == null) return;

    final before = _selectedIds.length;
    final next = _selectedIds.where((id) {
      final match = byId[id];
      if (match == null) return true;
      return _normalize(match.category) == _normalize(category) &&
          _normalize(match.propertyType) == _normalize(propertyType);
    }).toList();

    final changed = next.length != before;
    _selectedIds = next;
    _activeCategory = category;
    _activePropertyType = propertyType;
    if (changed) _persist();
    notifyListeners();
  }

  Future<void> _restore() async {
    final saved = await _service.loadIds();
    if (saved.isEmpty) return;
    // Cap defensively in case maxCompare ever shrinks between app versions —
    // never trust a persisted list to already satisfy the current rules.
    _selectedIds = saved.take(maxCompare).toList();
    notifyListeners();
  }

  Future<void> _persist() => _service.saveIds(_selectedIds);
}
