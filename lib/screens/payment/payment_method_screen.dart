import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/premium_button.dart';
import '../../models/payment_method_model.dart';
import 'widgets/payment_method_tile.dart';

/// Reusable Payment Method selection screen.
///
/// UI-only for now — no gateway is wired in. When Razorpay (or any provider)
/// is added later, the integration lives entirely in [onContinue]'s callback
/// or a service switching on the selected [PaymentMethodType]; the layout,
/// theming and selection UX need no changes.
///
/// Usage:
/// ```dart
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => PaymentMethodScreen(
///     amountLabel: '₹2,50,000',
///     onContinue: (type) { /* launch checkout for `type` */ },
///   ),
/// ));
/// ```
class PaymentMethodScreen extends StatefulWidget {
  const PaymentMethodScreen({
    super.key,
    this.amountLabel,
    this.title = 'Payment Method',
    this.methods,
    this.onContinue,
  });

  /// Optional formatted amount shown in the summary (e.g. '₹2,50,000').
  final String? amountLabel;

  final String title;

  /// Override the catalogue if a caller needs a custom subset/order.
  final List<PaymentMethod>? methods;

  /// Invoked with the chosen method when Continue is tapped. If null the screen
  /// simply pops returning the selected [PaymentMethodType].
  final void Function(PaymentMethodType type)? onContinue;

  @override
  State<PaymentMethodScreen> createState() => _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends State<PaymentMethodScreen> {
  late final List<PaymentMethod> _methods =
      widget.methods ?? PaymentMethod.defaults;

  PaymentMethodType? _selected;

  void _select(PaymentMethodType type) {
    setState(() => _selected = type);
  }

  void _onContinue() {
    final type = _selected;
    if (type == null) return;
    if (widget.onContinue != null) {
      widget.onContinue!(type);
    } else {
      Navigator.pop(context, type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canContinue = _selected != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(widget.title, style: AppTextStyles.heading2),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _SecureHeader(amountLabel: widget.amountLabel),
            const SizedBox(height: 20),
            Text(
              'Choose how you\'d like to pay',
              style: AppTextStyles.heading3,
            ),
            const SizedBox(height: 12),
            ..._buildMethodTiles(),
          ],
        ),
      ),
      bottomNavigationBar: _StickyContinueBar(
        enabled: canContinue,
        onContinue: _onContinue,
      ),
    );
  }

  List<Widget> _buildMethodTiles() {
    final tiles = <Widget>[];
    for (int i = 0; i < _methods.length; i++) {
      final method = _methods[i];
      tiles.add(
        PaymentMethodTile(
          method: method,
          isSelected: _selected == method.type,
          onTap: () => _select(method.type),
        ),
      );
      if (i != _methods.length - 1) {
        tiles.add(const SizedBox(height: 12));
      }
    }
    return tiles;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Secure payment header
// ─────────────────────────────────────────────────────────────────────────────
class _SecureHeader extends StatelessWidget {
  const _SecureHeader({this.amountLabel});

  final String? amountLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secure Payment',
                      style: AppTextStyles.heading3.copyWith(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '256-bit encrypted & PCI-DSS compliant',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (amountLabel != null) ...[
            const SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.2), height: 1),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Amount payable',
                  style: AppTextStyles.body.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
                Text(
                  amountLabel!,
                  style: AppTextStyles.price.copyWith(
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky Continue bar
// ─────────────────────────────────────────────────────────────────────────────
class _StickyContinueBar extends StatelessWidget {
  const _StickyContinueBar({required this.enabled, required this.onContinue});

  final bool enabled;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: AppColors.verifiedBadge,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'Safe & secure',
            style: AppTextStyles.caption.copyWith(fontSize: 12),
          ),
          const Spacer(),
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !enabled,
              child: PremiumButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                width: 180,
                onPressed: onContinue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
