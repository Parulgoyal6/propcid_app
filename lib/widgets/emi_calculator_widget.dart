// widgets/emi_calculator_widget.dart
//
// Extracted from EmiCalculatorScreen (which is now a thin Scaffold/app-bar
// wrapper around this) so it can also be embedded inline on the property
// detail screen for sell-type properties — matching that the website
// embeds its EMI calculator directly on PropertyDetails.tsx. Pure
// extraction: same fields, same math, same widgets, same fade-in.
import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/constants/app_constants.dart';

class EmiCalculatorWidget extends StatefulWidget {
  final double? initialLoanAmount;
  const EmiCalculatorWidget({super.key, this.initialLoanAmount});

  @override
  State<EmiCalculatorWidget> createState() => _EmiCalculatorWidgetState();
}

class _EmiCalculatorWidgetState extends State<EmiCalculatorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeIn;

  // Sliders
  double _loanAmount = 50.0; // in lakhs
  double _interestRate = 8.5; // % per annum
  double _tenure = 20.0; // years

  // Results
  double get _emi {
    final p = _loanAmount * 100000;
    final r = _interestRate / 12 / 100;
    final n = _tenure * 12;
    if (r == 0) return p / n;
    return p * r * pow(1 + r, n) / (pow(1 + r, n) - 1);
  }

  double get _totalAmount => _emi * _tenure * 12;
  double get _totalInterest => _totalAmount - (_loanAmount * 100000);
  double get _principalPercent => (_loanAmount * 100000) / _totalAmount;

  @override
  void initState() {
    super.initState();
    if (widget.initialLoanAmount != null) {
      _loanAmount = widget.initialLoanAmount! / 100000;
    }
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount) {
    if (amount >= 10000000)
      return '₹${(amount / 10000000).toStringAsFixed(2)} Cr';
    if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(2)} L';
    return '₹${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeIn,
      child: Column(
        children: [
          _buildResultCard(),
          const SizedBox(height: 16),
          _buildSliders(),
          const SizedBox(height: 16),
          _buildBreakdownCard(),
          const SizedBox(height: 16),
          _buildAffordabilityTip(),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius + 4),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Column(
        children: [
          Text(
            'Monthly EMI',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '₹${_emi.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'per month',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildResultStat(
                  'Loan Amount',
                  _formatCurrency(_loanAmount * 100000),
                  Icons.account_balance_outlined,
                ),
              ),
              _buildDivider(),
              Expanded(
                child: _buildResultStat(
                  'Total Interest',
                  _formatCurrency(_totalInterest),
                  Icons.trending_up_rounded,
                ),
              ),
              _buildDivider(),
              Expanded(
                child: _buildResultStat(
                  'Total Amount',
                  _formatCurrency(_totalAmount),
                  Icons.summarize_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: Colors.white.withOpacity(0.75)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.65)),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withOpacity(0.2),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildSliders() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: [
          _buildSlider(
            label: 'Loan Amount',
            value: _loanAmount,
            min: 5,
            max: 500,
            displayValue: '${_loanAmount.toStringAsFixed(0)} L',
            onChanged: (v) => setState(() => _loanAmount = v),
            icon: Icons.account_balance_outlined,
          ),
          const Divider(height: 28),
          _buildSlider(
            label: 'Interest Rate',
            value: _interestRate,
            min: 6.0,
            max: 15.0,
            displayValue: '${_interestRate.toStringAsFixed(1)}%',
            divisions: 90,
            onChanged: (v) => setState(() => _interestRate = v),
            icon: Icons.percent_rounded,
          ),
          const Divider(height: 28),
          _buildSlider(
            label: 'Loan Tenure',
            value: _tenure,
            min: 1,
            max: 30,
            displayValue: '${_tenure.toStringAsFixed(0)} Yrs',
            divisions: 29,
            onChanged: (v) => setState(() => _tenure = v),
            icon: Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    required IconData icon,
    int? divisions,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.primaryLight,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withOpacity(0.1),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            trackHeight: 4,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions ?? (max - min).toInt(),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(min.toStringAsFixed(0), style: AppTextStyles.caption),
            Text(max.toStringAsFixed(0), style: AppTextStyles.caption),
          ],
        ),
      ],
    );
  }

  Widget _buildBreakdownCard() {
    final principalPct = _principalPercent;
    final interestPct = 1 - principalPct;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Loan Breakdown', style: AppTextStyles.heading3),
          const SizedBox(height: 16),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(
                    flex: (principalPct * 100).round(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: AppColors.primaryGradient,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: (interestPct * 100).round(),
                    child: Container(color: const Color(0xFFFECACA)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildLegend(
                'Principal',
                _formatCurrency(_loanAmount * 100000),
                '${(principalPct * 100).toStringAsFixed(1)}%',
                AppColors.primary,
              ),
              const SizedBox(width: 16),
              _buildLegend(
                'Interest',
                _formatCurrency(_totalInterest),
                '${(interestPct * 100).toStringAsFixed(1)}%',
                const Color(0xFFEF4444),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Payable', style: AppTextStyles.caption),
                    const SizedBox(height: 2),
                    Text(
                      _formatCurrency(_totalAmount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Over ${_tenure.toStringAsFixed(0)} years',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(_tenure * 12).toStringAsFixed(0)} EMIs',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(String label, String amount, String pct, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              pct,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAffordabilityTip() {
    final monthlyIncomeNeeded = _emi / 0.4; // 40% rule
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              size: 18,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Affordability Tip',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF92400E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For this EMI, a monthly income of ${_formatCurrency(monthlyIncomeNeeded)} is recommended (using the 40% EMI-to-income rule).',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF78350F),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
