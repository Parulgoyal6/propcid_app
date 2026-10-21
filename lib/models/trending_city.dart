// models/trending_city.dart
//
// One row of `public.trending_cities`, the admin-curated city rail shared
// with the web portal (`src/features/home/TrendingCitiesBanner.tsx` +
// `src/hooks/useTrendingCities.ts`).
//
// Purely a display model — there is no write path here. The portal derives
// no field client-side; every value shown on a city card is a stored column.
class TrendingCity {
  final String id;
  final String cityName;
  final String? state;
  final String? country;
  final String? featuredImageUrl;
  final double? growthPercentage;
  final double? avgPropertyPrice;
  final int? totalProperties;
  final String? description;
  final int displayOrder;

  const TrendingCity({
    required this.id,
    required this.cityName,
    this.state,
    this.country,
    this.featuredImageUrl,
    this.growthPercentage,
    this.avgPropertyPrice,
    this.totalProperties,
    this.description,
    required this.displayOrder,
  });

  factory TrendingCity.fromSupabase(Map<String, dynamic> row) {
    return TrendingCity(
      id: row['id']?.toString() ?? '',
      cityName: row['city_name']?.toString() ?? '',
      state: _text(row['state']),
      country: _text(row['country']),
      featuredImageUrl: _text(row['featured_image_url']),
      growthPercentage: _asDouble(row['growth_percentage']),
      avgPropertyPrice: _asDouble(row['avg_property_price']),
      totalProperties: _asInt(row['total_properties']),
      description: _text(row['description']),
      displayOrder: _asInt(row['display_order']) ?? 0,
    );
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
