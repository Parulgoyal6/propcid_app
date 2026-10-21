// models/investor_opportunity.dart
//
// One row of `public.investors_corner`, the admin-curated investment-pitch
// rail shared with the web portal (`src/features/home/InvestorsCornerSection.tsx`
// + `src/hooks/useInvestorsCorner.ts`).
class InvestorOpportunity {
  final String id;
  final String title;
  final String? description;
  final String location;
  final double? investmentAmount;
  final double? expectedRoiPercentage;
  final double? rentalYieldPercentage;
  final double? appreciationPercentage;
  final int? timePeriodMonths;
  final String featuredImageUrl;
  final int displayOrder;

  const InvestorOpportunity({
    required this.id,
    required this.title,
    this.description,
    required this.location,
    this.investmentAmount,
    this.expectedRoiPercentage,
    this.rentalYieldPercentage,
    this.appreciationPercentage,
    this.timePeriodMonths,
    required this.featuredImageUrl,
    required this.displayOrder,
  });

  factory InvestorOpportunity.fromSupabase(Map<String, dynamic> row) {
    return InvestorOpportunity(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      description: _text(row['description']),
      location: row['location']?.toString() ?? '',
      investmentAmount: _asDouble(row['investment_amount']),
      expectedRoiPercentage: _asDouble(row['expected_roi_percentage']),
      rentalYieldPercentage: _asDouble(row['rental_yield_percentage']),
      appreciationPercentage: _asDouble(row['appreciation_percentage']),
      timePeriodMonths: _asInt(row['time_period_months']),
      featuredImageUrl: row['featured_image_url']?.toString() ?? '',
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
