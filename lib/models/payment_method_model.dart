import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Identifies a payment channel. Kept as an enum (not free strings) so the
/// gateway integration layer can switch on it exhaustively later without any
/// UI redesign.
enum PaymentMethodType {
  card,
  upi,
  googlePay,
  phonePe,
  paytm,
  netBanking,
  wallet,
}

/// A selectable payment option rendered on the Payment Method screen.
///
/// This is a pure view-model: it carries only what the UI needs. When Razorpay
/// (or any gateway) is wired in later, the integration reads [type] to decide
/// how to launch the checkout — no change to this model or the screen required.
class PaymentMethod {
  final PaymentMethodType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  /// When true the option is shown but not selectable (e.g. Wallet).
  final bool comingSoon;

  const PaymentMethod({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    this.comingSoon = false,
  });

  bool get isEnabled => !comingSoon;

  /// The default catalogue of supported methods. Ordered by typical preference.
  static const List<PaymentMethod> defaults = [
    PaymentMethod(
      type: PaymentMethodType.card,
      title: 'Credit / Debit Card',
      subtitle: 'Visa, Mastercard, RuPay & more',
      icon: Icons.credit_card_rounded,
      accent: AppColors.primary,
    ),
    PaymentMethod(
      type: PaymentMethodType.upi,
      title: 'UPI',
      subtitle: 'Pay using any UPI app',
      icon: Icons.account_balance_wallet_rounded,
      accent: AppColors.amenityIndigo,
    ),
    PaymentMethod(
      type: PaymentMethodType.googlePay,
      title: 'Google Pay',
      subtitle: 'Fast & secure UPI payments',
      icon: Icons.g_mobiledata_rounded,
      accent: AppColors.amenityBlue,
    ),
    PaymentMethod(
      type: PaymentMethodType.phonePe,
      title: 'PhonePe',
      subtitle: 'Pay with your PhonePe account',
      icon: Icons.phone_android_rounded,
      accent: Color(0xFF5F259F),
    ),
    PaymentMethod(
      type: PaymentMethodType.paytm,
      title: 'Paytm',
      subtitle: 'Wallet, UPI & Paytm balance',
      icon: Icons.payments_rounded,
      accent: Color(0xFF00BAF2),
    ),
    PaymentMethod(
      type: PaymentMethodType.netBanking,
      title: 'Net Banking',
      subtitle: 'All major banks supported',
      icon: Icons.account_balance_rounded,
      accent: AppColors.amenityGreen,
    ),
    PaymentMethod(
      type: PaymentMethodType.wallet,
      title: 'Wallet',
      subtitle: 'Coming soon',
      icon: Icons.wallet_rounded,
      accent: AppColors.textHint,
      comingSoon: true,
    ),
  ];
}
