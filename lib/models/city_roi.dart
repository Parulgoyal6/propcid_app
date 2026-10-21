// models/city_roi.dart
//
// One row of `public.city_roi_index`, the admin-curated city ROI rail shared
// with the web portal (`src/features/home/CityROIIndexBanner.tsx` +
// `src/hooks/useCityROIIndex.ts`).
class CityRoi {
  final String id;
  final String cityName;
  final String? state;
  final double roiPercentage;
  final double? yoyGrowth;
  final double? avgPropertyPrice;
  final double? rentalYield;
  final String? featuredImageUrl;
  final int displayOrder;

  const CityRoi({
    required this.id,
    required this.cityName,
    this.state,
    required this.roiPercentage,
    this.yoyGrowth,
    this.avgPropertyPrice,
    this.rentalYield,
    this.featuredImageUrl,
    required this.displayOrder,
  });

  factory CityRoi.fromSupabase(Map<String, dynamic> row) {
    return CityRoi(
      id: row['id']?.toString() ?? '',
      cityName: row['city_name']?.toString() ?? '',
      state: _text(row['state']),
      roiPercentage: _asDouble(row['roi_percentage']) ?? 0,
      yoyGrowth: _asDouble(row['yoy_growth']),
      avgPropertyPrice: _asDouble(row['avg_property_price']),
      rentalYield: _asDouble(row['rental_yield']),
      featuredImageUrl: _text(row['featured_image_url']),
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
