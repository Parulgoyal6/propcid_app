import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/navigation/banner_destination_resolver.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/banner_destination.dart';
import '../../../widgets/section_header.dart';

class _BudgetBucket {
  const _BudgetBucket({
    required this.label,
    required this.icon,
    required this.color,
    required this.image,
    this.budgetMin,
    this.budgetMax,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String image;

  /// Bucket bounds in rupees, same fields `BannerDestination.collection`
  /// already uses for the hero banner's "Luxury Collection" tile — null
  /// means unbounded on that side (`BannerDestinationResolver` fills the
  /// gap with `AppConstants.priceMin`/`priceMax`).
  final double? budgetMin;
  final double? budgetMax;
}

/// Same 4 buckets as before; each tile now applies its price range to
/// `FilterProvider` (via `BannerDestinationResolver`, the same mechanism
/// the hero banner's budget tile uses) before opening search results,
/// instead of navigating there with no filter applied.
class BudgetSection extends StatelessWidget {
  const BudgetSection({super.key});

  static const List<_BudgetBucket> _budgets = [
    _BudgetBucket(
      label: 'Under ₹50L',
      icon: Icons.home_outlined,
      color: Color(0xFF22C55E),
      image:
          'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=400&h=300&fit=crop',
      budgetMax: 5000000,
    ),
    _BudgetBucket(
      label: '₹50L – ₹1Cr',
      icon: Icons.apartment,
      color: Color(0xFF3B82F6),
      image:
          'https://images.unsplash.com/photo-1545324418-cc1a3fa10c00?w=400&h=300&fit=crop',
      budgetMin: 5000000,
      budgetMax: 10000000,
    ),
    _BudgetBucket(
      label: '₹1Cr – ₹2Cr',
      icon: Icons.villa,
      color: AppColors.primary,
      image:
          'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=400&h=300&fit=crop',
      budgetMin: 10000000,
      budgetMax: 20000000,
    ),
    _BudgetBucket(
      label: '₹2Cr+',
      icon: Icons.business_center,
      color: Color(0xFFF97316),
      image:
          'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=400&h=300&fit=crop',
      budgetMin: 20000000,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Browse by Budget'),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
            itemCount: _budgets.length,
            itemBuilder: (context, index) {
              final budget = _budgets[index];
              return GestureDetector(
                onTap: () => BannerDestinationResolver.navigate(
                  context,
                  BannerDestination.collection(
                    budgetMin: budget.budgetMin,
                    budgetMax: budget.budgetMax,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // The only Home rail still on raw `Image.network`
                        // (no disk cache, no placeholder) — every other rail
                        // uses `CachedNetworkImage`; matching that here too.
                        // The source URL already asks Unsplash for 400x300
                        // (`?w=400&h=300&fit=crop`), so the decode is bounded
                        // to that regardless of device pixel ratio.
                        CachedNetworkImage(
                          imageUrl: budget.image,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          memCacheHeight: 300,
                          placeholder: (context, url) =>
                              Container(color: budget.color.withOpacity(0.15)),
                          errorWidget: (context, url, error) =>
                              Container(color: budget.color.withOpacity(0.15)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                budget.color.withOpacity(0.05),
                                Colors.black.withOpacity(0.75),
                              ],
                              stops: const [0.3, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                              ),
                            ),
                            child: Icon(
                              budget.icon,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Text(
                            budget.label,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
