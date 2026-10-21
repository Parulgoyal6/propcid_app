// models/search_query_params.dart
//
// The Flutter-side mirror of the sort/filter parameter set the website's
// Search.tsx actually supports. Kept free of Flutter/Material imports so it
// can be shared cleanly between FilterProvider (UI state), PropertyService
// (query building) and PropertyProvider (orchestration).

enum PropertySortOption { newest, priceAsc, priceDesc, popular }

extension PropertySortOptionX on PropertySortOption {
  /// The `properties` column each option orders by — matches Search.tsx's
  /// switch exactly (price sort uses `price_min`, not the free-text `price`).
  String get column {
    switch (this) {
      case PropertySortOption.newest:
        return 'created_at';
      case PropertySortOption.priceAsc:
      case PropertySortOption.priceDesc:
        return 'price_min';
      case PropertySortOption.popular:
        return 'likes';
    }
  }

  bool get ascending => this == PropertySortOption.priceAsc;

  String get label {
    switch (this) {
      case PropertySortOption.newest:
        return 'Newest';
      case PropertySortOption.priceAsc:
        return 'Price: Low to High';
      case PropertySortOption.priceDesc:
        return 'Price: High to Low';
      case PropertySortOption.popular:
        return 'Most Popular';
    }
  }
}

/// Immutable snapshot of every filter/sort/near-me field, handed from
/// FilterProvider to PropertyProvider/PropertyService. Budget is a plain
/// double range (not a Flutter RangeValues) to keep this file UI-agnostic.
class SearchQueryParams {
  final String searchText;
  final String? category;
  final String? listingType;
  final List<String> cities;
  final String? hashtag;
  final double budgetMin;
  final double budgetMax;
  final int? bhk;
  final String? subtype;
  final String? postedBy;
  final PropertySortOption sort;
  final bool nearMeEnabled;
  final double? nearMeLat;
  final double? nearMeLng;

  const SearchQueryParams({
    this.searchText = '',
    this.category,
    this.listingType,
    this.cities = const [],
    this.hashtag,
    required this.budgetMin,
    required this.budgetMax,
    this.bhk,
    this.subtype,
    this.postedBy,
    this.sort = PropertySortOption.newest,
    this.nearMeEnabled = false,
    this.nearMeLat,
    this.nearMeLng,
  });
}

/// Raw (not-yet-PropertyModel) result of one search query — PropertyProvider
/// does the `.map(PropertyModel.fromSupabase)` step, matching the existing
/// convention that PropertyService returns raw maps.
class PropertySearchPage {
  final List<Map<String, dynamic>> rows;
  final int? totalCount;

  const PropertySearchPage({required this.rows, this.totalCount});
}
