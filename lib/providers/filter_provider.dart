import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../models/search_query_params.dart';

/// Single source of truth for property search/filter/sort state — the
/// Flutter mirror of the website's Search.tsx URL search params. This is a
/// pure state holder: it never calls PropertyService/PropertyProvider
/// itself. Every call site that changes a filter must call the setter here
/// AND THEN trigger PropertyProvider.runSearch(filterProvider.toQueryParams())
/// (or loadMapResults, for map-mode changes).
class FilterProvider extends ChangeNotifier {
  static const Set<String> validCategories = {
    'residential',
    'commercial',
    'land',
    'pg_coliving',
    'others',
  };
  static const Set<String> validListingTypes = {'sell', 'rent', 'lease'};

  String _searchText = '';
  String? _category;
  String? _listingType;
  List<String> _cities = [];
  String? _hashtag;
  RangeValues _budgetRange = const RangeValues(
    AppConstants.priceMin,
    AppConstants.priceMax,
  );
  int? _bhk;
  String? _subtype;
  String? _postedBy;
  PropertySortOption _sort = PropertySortOption.newest;
  bool _nearMeEnabled = false;
  double? _nearMeLat;
  double? _nearMeLng;

  String get searchText => _searchText;
  String? get category => _category;
  String? get listingType => _listingType;
  List<String> get cities => _cities;
  String? get hashtag => _hashtag;
  RangeValues get budgetRange => _budgetRange;
  int? get bhk => _bhk;
  String? get subtype => _subtype;
  String? get postedBy => _postedBy;
  PropertySortOption get sort => _sort;
  bool get nearMeEnabled => _nearMeEnabled;
  double? get nearMeLat => _nearMeLat;
  double? get nearMeLng => _nearMeLng;

  void setSearchText(String value) {
    _searchText = value;
    notifyListeners();
  }

  void setCategory(String? value) {
    _category = (value != null && validCategories.contains(value))
        ? value
        : null;
    notifyListeners();
  }

  void setListingType(String? value) {
    _listingType = (value != null && validListingTypes.contains(value))
        ? value
        : null;
    notifyListeners();
  }

  void setCities(List<String> value) {
    _cities = List<String>.from(value);
    notifyListeners();
  }

  void toggleCity(String city) {
    if (_cities.contains(city)) {
      _cities = _cities.where((c) => c != city).toList();
    } else {
      _cities = [..._cities, city];
    }
    notifyListeners();
  }

  void setHashtag(String? value) {
    _hashtag = value;
    notifyListeners();
  }

  void setBudgetRange(RangeValues value) {
    _budgetRange = value;
    notifyListeners();
  }

  void setBhk(int? value) {
    _bhk = value;
    notifyListeners();
  }

  void setSubtype(String? value) {
    _subtype = value;
    notifyListeners();
  }

  void setPostedBy(String? value) {
    _postedBy = value;
    notifyListeners();
  }

  void setSort(PropertySortOption value) {
    _sort = value;
    notifyListeners();
  }

  void enableNearMe(double lat, double lng) {
    _nearMeEnabled = true;
    _nearMeLat = lat;
    _nearMeLng = lng;
    notifyListeners();
  }

  void disableNearMe() {
    _nearMeEnabled = false;
    _nearMeLat = null;
    _nearMeLng = null;
    notifyListeners();
  }

  void resetFilters() {
    _searchText = '';
    _category = null;
    _listingType = null;
    _cities = [];
    _hashtag = null;
    _budgetRange = const RangeValues(
      AppConstants.priceMin,
      AppConstants.priceMax,
    );
    _bhk = null;
    _subtype = null;
    _postedBy = null;
    _sort = PropertySortOption.newest;
    _nearMeEnabled = false;
    _nearMeLat = null;
    _nearMeLng = null;
    notifyListeners();
  }

  /// Mirrors the website's filter-badge count exactly: category, listingType,
  /// budget (only if non-default), bhk, subtype, postedBy — NOT searchText,
  /// cities, sort, or nearMe.
  int get activeFilterCount {
    int count = 0;
    if (_category != null) count++;
    if (_listingType != null) count++;
    if (_budgetRange.start > AppConstants.priceMin ||
        _budgetRange.end < AppConstants.priceMax) {
      count++;
    }
    if (_bhk != null) count++;
    if (_subtype != null) count++;
    if (_postedBy != null) count++;
    return count;
  }

  SearchQueryParams toQueryParams() {
    // Mirrors the website's commitPriceRange: once the slider is dragged to
    // its ceiling, send the unbounded sentinel instead of the literal max.
    final double effectiveMax = _budgetRange.end >= AppConstants.priceMax
        ? AppConstants.priceUnbounded
        : _budgetRange.end;

    return SearchQueryParams(
      searchText: _searchText,
      category: _category,
      listingType: _listingType,
      cities: _cities,
      hashtag: _hashtag,
      budgetMin: _budgetRange.start,
      budgetMax: effectiveMax,
      bhk: _bhk,
      subtype: _subtype,
      postedBy: _postedBy,
      sort: _sort,
      nearMeEnabled: _nearMeEnabled,
      nearMeLat: _nearMeLat,
      nearMeLng: _nearMeLng,
    );
  }
}
