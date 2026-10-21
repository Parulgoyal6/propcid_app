import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/property_provider.dart';
import '../../providers/filter_provider.dart';
import '../../models/property_model.dart';
import '../../widgets/bottom_nav_bar.dart';

/// Only exposes filters Search.tsx (the website's canonical search
/// reference) actually applies server-side: listing type, property
/// category/subtype, budget, bedrooms (bhk), and posted-by. The old
/// Bathrooms/Area/"More Filters" (Furnishing/Availability/Amenities/Age/
/// Facing) sections are removed rather than left decorative — the website's
/// own search doesn't filter on any of them either, and keeping controls
/// that promise filtering they can't deliver is worse than not having them.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  // Subtype match terms are real substrings confirmed against the live
  // `residential_subtype` column (verified via a direct query against the
  // production database), NOT guessed labels — the actual values sellers
  // enter are things like "Flat", "Villa / Kothi", "Independent / Builder
  // Floor", "Raw / Independent House", so the filter term has to be a
  // substring of those, not of a generic label, or `.ilike()` matches
  // nothing and the chip silently returns zero results.
  static const List<Map<String, dynamic>> _propertyTypes = [
    {'label': 'Any', 'icon': Icons.apps, 'category': null, 'subtype': null},
    {
      'label': 'Apartment / Flat',
      'icon': Icons.apartment,
      'category': 'residential',
      'subtype': 'Flat',
    },
    {
      'label': 'Villa',
      'icon': Icons.villa,
      'category': 'residential',
      'subtype': 'Villa',
    },
    {
      'label': 'Independent House',
      'icon': Icons.home,
      'category': 'residential',
      // Matches both "Raw / Independent House" and "Independent / Builder
      // Floor" — the literal "Independent House" substring only matched
      // the former.
      'subtype': 'Independent',
    },
    {
      'label': 'Plot / Land',
      'icon': Icons.landscape,
      'category': 'land',
      'subtype': null,
    },
    {
      'label': 'Commercial',
      'icon': Icons.store,
      'category': 'commercial',
      'subtype': null,
    },
  ];

  // Local "draft" state for the budget slider while dragging, committed to
  // FilterProvider on release — mirrors the website's own onValueChange
  // (live) / onValueCommit (final) split on its PriceRangeSlider.
  late RangeValues _draftBudgetRange;

  @override
  void initState() {
    super.initState();
    _draftBudgetRange = Provider.of<FilterProvider>(
      context,
      listen: false,
    ).budgetRange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: SingleChildScrollView(
                child: Consumer<FilterProvider>(
                  builder: (context, filterProvider, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        _buildListingTypeToggle(filterProvider),
                        const SizedBox(height: 24),
                        _buildPropertyTypeSection(filterProvider),
                        const SizedBox(height: 24),
                        _buildPriceRangeSection(filterProvider),
                        const SizedBox(height: 24),
                        _buildBedroomsSection(filterProvider),
                        const SizedBox(height: 24),
                        _buildPostedBySection(filterProvider),
                        const SizedBox(height: 100),
                      ],
                    );
                  },
                ),
              ),
            ),
            _buildApplyButton(context),
          ],
        ),
      ),
      bottomNavigationBar: Consumer<NavigationProvider>(
        builder: (context, navigationProvider, child) {
          return BottomNavBar(
            currentIndex: 1,
            onTap: (index) {
              navigationProvider.setIndex(index);
              if (index == 0) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 16),
          Text('Filters', style: AppTextStyles.heading2),
          const Spacer(),
          TextButton(
            onPressed: () {
              final filterProvider = Provider.of<FilterProvider>(
                context,
                listen: false,
              );
              filterProvider.resetFilters();
              setState(() {
                _draftBudgetRange = filterProvider.budgetRange;
              });
              Provider.of<PropertyProvider>(
                context,
                listen: false,
              ).runSearch(filterProvider.toQueryParams(), reset: true);
            },
            child: const Text('Reset All ↺'),
          ),
        ],
      ),
    );
  }

  Widget _buildListingTypeToggle(FilterProvider filterProvider) {
    const options = [
      {'label': 'Buy', 'icon': Icons.shopping_bag, 'value': 'sell'},
      {'label': 'Rent', 'icon': Icons.home, 'value': 'rent'},
      {'label': 'Lease', 'icon': Icons.assignment_outlined, 'value': 'lease'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.textHint.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _buildToggleButton(
                label: option['label'] as String,
                icon: option['icon'] as IconData,
                isSelected: filterProvider.listingType == option['value'],
                onTap: () {
                  final value = option['value'] as String;
                  filterProvider.setListingType(
                    filterProvider.listingType == value ? null : value,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.body.copyWith(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyTypeSection(FilterProvider filterProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Property Type', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          SizedBox(
            height: AppConstants.propertyTypeChipHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _propertyTypes.length,
              itemBuilder: (context, index) {
                final type = _propertyTypes[index];
                final isSelected =
                    filterProvider.category == type['category'] &&
                    filterProvider.subtype == type['subtype'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      filterProvider.setCategory(type['category'] as String?);
                      filterProvider.setSubtype(type['subtype'] as String?);
                    },
                    child: Container(
                      width: AppConstants.propertyTypeChipWidth,
                      height: AppConstants.propertyTypeChipHeight,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryLight
                            : AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textHint.withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            type['icon'] as IconData,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            type['label'] as String,
                            style: AppTextStyles.caption.copyWith(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
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
      ),
    );
  }

  Widget _buildPriceRangeSection(FilterProvider filterProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price Range', style: AppTextStyles.heading3),
          const SizedBox(height: 16),
          RangeSlider(
            values: _draftBudgetRange,
            min: AppConstants.priceMin,
            max: AppConstants.priceMax,
            // Snaps to ₹10 L increments, matching the reference's
            // `step={PRICE_STEP}` (Search.tsx) and filter_sheet.dart's slider.
            divisions:
                ((AppConstants.priceMax - AppConstants.priceMin) /
                        AppConstants.priceStep)
                    .round(),
            activeColor: AppColors.primary,
            inactiveColor: AppColors.textHint.withOpacity(0.3),
            // Draft-only, like every other control on this screen's Apply
            // button now expects — committing to FilterProvider on
            // `onChangeEnd` (release) rather than on Apply meant dragging
            // the slider and then backing out of this screen without
            // tapping Apply still silently changed the applied budget.
            onChanged: (values) {
              setState(() => _draftBudgetRange = values);
            },
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${PropertyModel.formatIndianPrice(_draftBudgetRange.start)} '
              '– ${_draftBudgetRange.end >= AppConstants.priceMax ? '${PropertyModel.formatIndianPrice(AppConstants.priceMax)}+' : PropertyModel.formatIndianPrice(_draftBudgetRange.end)}',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBedroomsSection(FilterProvider filterProvider) {
    const bedroomOptions = [
      'Any',
      '1 BHK',
      '2 BHK',
      '3 BHK',
      '4 BHK',
      '4+ BHK',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bedrooms', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: bedroomOptions.map((label) {
              final int? value = label == 'Any'
                  ? null
                  : (label == '4+ BHK' ? 5 : int.parse(label[0]));
              final isSelected = filterProvider.bhk == value;
              return GestureDetector(
                onTap: () => filterProvider.setBhk(isSelected ? null : value),
                child: Container(
                  width: AppConstants.selectableChipWidth,
                  height: AppConstants.selectableChipHeight,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textHint.withOpacity(0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPostedBySection(FilterProvider filterProvider) {
    const options = ['Any', 'Owner', 'Agent', 'Builder'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Posted By', style: AppTextStyles.heading3),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((label) {
              final String? value = label == 'Any' ? null : label;
              final isSelected = filterProvider.postedBy == value;
              return GestureDetector(
                onTap: () =>
                    filterProvider.setPostedBy(isSelected ? null : value),
                child: Container(
                  height: AppConstants.selectableChipHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryLight
                        : AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textHint.withOpacity(0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: AppTextStyles.body.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.textHint, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: AppConstants.showResultsButtonHeight,
        child: ElevatedButton(
          onPressed: () {
            final filterProvider = Provider.of<FilterProvider>(
              context,
              listen: false,
            );
            // The one commit point for the budget draft — every other
            // control on this screen already writes straight through to
            // FilterProvider, but the slider is held in local `_draftBudgetRange`
            // (see _buildPriceRangeSection) until Apply, exactly like the
            // bottom-sheet filter flow's Apply button.
            filterProvider.setBudgetRange(_draftBudgetRange);
            Provider.of<PropertyProvider>(
              context,
              listen: false,
            ).runSearch(filterProvider.toQueryParams(), reset: true);
            // Signals "filters were actually applied" (vs. just backing out)
            // to whichever screen pushed this one — see SearchScreen's filter
            // chips, which use this to know whether to forward the user to
            // the results screen.
            Navigator.pop(context, true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Apply Filters'),
        ),
      ),
    );
  }
}
