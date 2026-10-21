// models/smart_query_result.dart
//
// Structured filters extracted from a natural-language search query by the
// AI Search feature (see AiSearchService).
class SmartQueryResult {
  final String? city;
  final int? bhk;
  final String? category;
  final String? listingType;
  final double? budgetMin;
  final double? budgetMax;

  /// A residential subtype, as the literal `properties.residential_subtype`
  /// cell content (e.g. `Villa / Kothi`) — never a loose label.
  ///
  /// Null unless the query actually named one. `AiSearchService` both validates
  /// this against the real column vocabulary and refuses to accept it when the
  /// query contains no subtype word at all, so a bedroom count can never be
  /// turned into a property style.
  final String? subtype;

  final String keywords;

  const SmartQueryResult({
    this.city,
    this.bhk,
    this.category,
    this.listingType,
    this.budgetMin,
    this.budgetMax,
    this.subtype,
    this.keywords = '',
  });

  factory SmartQueryResult.fromJson(Map<String, dynamic> json) {
    return SmartQueryResult(
      city: json['city'] as String?,
      bhk: (json['bhk'] as num?)?.toInt(),
      category: json['category'] as String?,
      listingType: json['listingType'] as String?,
      budgetMin: (json['budgetMin'] as num?)?.toDouble(),
      budgetMax: (json['budgetMax'] as num?)?.toDouble(),
      subtype: json['subtype']?.toString(),
      keywords: json['keywords']?.toString() ?? '',
    );
  }

  /// True if the AI extracted at least one structured filter (as opposed to
  /// a plain-text fallback with only `keywords` set).
  bool get hasStructuredFilters =>
      city != null ||
      bhk != null ||
      category != null ||
      listingType != null ||
      budgetMin != null ||
      budgetMax != null ||
      subtype != null;
}
