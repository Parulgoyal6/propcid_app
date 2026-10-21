import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/reels_provider.dart';
import 'reels_screen.dart';

class ReelsOnboardingScreen extends StatefulWidget {
  const ReelsOnboardingScreen({super.key});

  @override
  State<ReelsOnboardingScreen> createState() => _ReelsOnboardingScreenState();
}

class _ReelsOnboardingScreenState extends State<ReelsOnboardingScreen> {
  int _currentStep = 0;
  late PageController _pageController;

  final List<String> _cities = [
    'Mumbai',
    'Delhi NCR',
    'Bangalore',
    'Pune',
    'Hyderabad',
    'Chennai',
    'Kolkata',
    'Ahmedabad',
  ];

  final List<String> _budgets = [
    'Under ₹50L',
    '₹50L – ₹1Cr',
    '₹1Cr – ₹2Cr',
    '₹2Cr – ₹5Cr',
    '₹5Cr+',
  ];

  final List<String> _propertyTypes = [
    'Apartment',
    'Villa',
    'Plot',
    'Commercial',
    'Studio',
  ];

  String? _selectedCity;
  String? _selectedBudget;
  String? _selectedPropertyType;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B1E),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: [
                  _buildCitySelection(),
                  _buildBudgetSelection(),
                  _buildPropertyTypeSelection(),
                ],
              ),
            ),

            // Navigation buttons
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: List.generate(3, (index) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index < 2 ? 8 : 0),
              height: 4,
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? AppColors.primary
                    : AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCitySelection() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.2),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.location_city_rounded,
                  size: 48,
                  color: AppColors.primary,
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                Text(
                  'Where are you looking?',
                  style: AppTextStyles.heading1.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.3),
                const SizedBox(height: 8),
                Text(
                  'Select your preferred city',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.3),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // City grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: _cities.length,
              itemBuilder: (context, index) {
                final city = _cities[index];
                final isSelected = _selectedCity == city;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCity = city;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? AppColors.primaryGradient
                          : LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.05),
                                Colors.white.withOpacity(0.02),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.white.withOpacity(0.1),
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 32,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          city,
                          style: AppTextStyles.body.copyWith(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.7),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: (index * 100).ms).scale();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetSelection() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.2),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 48,
                  color: AppColors.primary,
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                Text(
                  'What\'s your budget?',
                  style: AppTextStyles.heading1.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.3),
                const SizedBox(height: 8),
                Text(
                  'Select your price range',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.3),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Budget list
          Expanded(
            child: ListView.builder(
              itemCount: _budgets.length,
              itemBuilder: (context, index) {
                final budget = _budgets[index];
                final isSelected = _selectedBudget == budget;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child:
                      GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedBudget = budget;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? AppColors.primaryGradient
                                    : LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.05),
                                          Colors.white.withOpacity(0.02),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.white.withOpacity(0.1),
                                  width: 2,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(
                                            0.3,
                                          ),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.payments_rounded,
                                    size: 28,
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.primary,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      budget,
                                      style: AppTextStyles.body.copyWith(
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.7),
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                ],
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(delay: (index * 100).ms)
                          .slideX(begin: -0.2),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyTypeSelection() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),

          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.2),
                  AppColors.primary.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.home_work_rounded,
                  size: 48,
                  color: AppColors.primary,
                ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                const SizedBox(height: 16),
                Text(
                  'Property type?',
                  style: AppTextStyles.heading1.copyWith(
                    color: Colors.white,
                    fontSize: 28,
                  ),
                ).animate().fadeIn(delay: 200.ms).slideX(begin: -0.3),
                const SizedBox(height: 8),
                Text(
                  'What are you looking for?',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withOpacity(0.6),
                  ),
                ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.3),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Property type grid
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: _propertyTypes.length,
              itemBuilder: (context, index) {
                final type = _propertyTypes[index];
                final isSelected = _selectedPropertyType == type;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPropertyType = type;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? AppColors.primaryGradient
                          : LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.05),
                                Colors.white.withOpacity(0.02),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : Colors.white.withOpacity(0.1),
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getPropertyIcon(type),
                          size: 32,
                          color: isSelected ? Colors.white : AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          type,
                          style: AppTextStyles.body.copyWith(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withOpacity(0.7),
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: (index * 100).ms).scale();
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPropertyIcon(String type) {
    switch (type) {
      case 'Apartment':
        return Icons.apartment_rounded;
      case 'Villa':
        return Icons.villa_rounded;
      case 'Plot':
        return Icons.landscape_rounded;
      case 'Commercial':
        return Icons.business_rounded;
      case 'Studio':
        return Icons.weekend_rounded;
      default:
        return Icons.home_rounded;
    }
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: _canProceed() ? _handleNext : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: _canProceed() ? AppColors.primaryGradient : null,
                  color: _canProceed() ? null : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _canProceed()
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  _currentStep < 2 ? 'Next' : 'Start Watching',
                  style: TextStyle(
                    color: _canProceed()
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _selectedCity != null;
      case 1:
        return _selectedBudget != null;
      case 2:
        return _selectedPropertyType != null;
      default:
        return false;
    }
  }

  void _handleNext() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Save preferences and navigate to reels screen
      final reelsProvider = Provider.of<ReelsProvider>(context, listen: false);
      reelsProvider.completeOnboarding(
        city: _selectedCity!,
        budget: _selectedBudget!,
        propertyType: _selectedPropertyType!,
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReelsScreen()),
      );
    }
  }
}
