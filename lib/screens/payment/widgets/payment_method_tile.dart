import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/payment_method_model.dart';

/// A single selectable payment option card.
///
/// Selection is communicated purely via [isSelected] + [onTap] so the parent
/// screen owns the state (single-select). The card animates its border, fill,
/// shadow and trailing radio on selection for a polished fintech feel.
class PaymentMethodTile extends StatelessWidget {
  const PaymentMethodTile({
    super.key,
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool enabled = method.isEnabled;

    return ScaleTap(
      onTap: enabled ? onTap : null,
      scaleDown: enabled ? 0.98 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.textHint.withOpacity(0.2),
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: isSelected ? AppColors.primaryGlow : null,
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Row(
            children: [
              // Leading icon chip
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: method.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(method.icon, color: method.accent, size: 24),
              ),
              const SizedBox(width: 14),

              // Title + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            method.title,
                            style: AppTextStyles.heading3.copyWith(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (method.comingSoon) ...[
                          const SizedBox(width: 8),
                          _comingSoonPill(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      method.subtitle,
                      style: AppTextStyles.caption.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Trailing selection indicator
              _selectionIndicator(enabled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionIndicator(bool enabled) {
    if (!enabled) {
      return Icon(
        Icons.lock_outline_rounded,
        size: 20,
        color: AppColors.textHint,
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.textHint,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  Widget _comingSoonPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Coming soon',
        style: AppTextStyles.chip.copyWith(
          color: AppColors.warning,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
