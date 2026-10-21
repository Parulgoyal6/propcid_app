import 'package:flutter/material.dart';

import '../config/launch_features.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/premium_button.dart';
import '../models/launch_offer_content.dart';

/// Controls whether the launch-offer bottom sheet has already been shown for
/// the current login. Deliberately an in-memory flag (not persisted) — the
/// requirement is "once per login", not "once ever": [AuthProvider] calls
/// [resetForNewLogin] on every sign-out so the very next successful login
/// (in the same app run or a new one) shows the sheet again, and "Maybe
/// Later" only ever suppresses it until that next login.
class LaunchOfferSessionGate {
  LaunchOfferSessionGate._();

  static bool _shownThisSession = false;

  static bool get canShow => !_shownThisSession;

  static void markShown() => _shownThisSession = true;

  static void resetForNewLogin() => _shownThisSession = false;
}

/// Premium "PropCID Pro" upsell sheet, shown once per session from the home
/// screen. Mirrors the polish of subscription prompts in high-quality apps:
/// badge, title, value proposition, benefit list, price, and two clear actions.
class PremiumLaunchBottomSheet extends StatefulWidget {
  const PremiumLaunchBottomSheet({super.key});

  /// Presents the sheet if it hasn't been shown yet this session. Safe to call
  /// unconditionally from `initState`/post-frame callbacks.
  static Future<void> showOnce(BuildContext context) async {
    if (!LaunchOfferSessionGate.canShow) return;
    // Checked after the session-gate check but before it is burned: a
    // disabled build must never show this sheet, and must not spend the
    // one-time gate doing so — re-enabling the feature later must still get
    // the sheet its first real showing.
    if (!LaunchFeatures.subscriptions) return;
    LaunchOfferSessionGate.markShown();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PremiumLaunchBottomSheet(),
    );
  }

  @override
  State<PremiumLaunchBottomSheet> createState() =>
      _PremiumLaunchBottomSheetState();
}

class _PremiumLaunchBottomSheetState extends State<PremiumLaunchBottomSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _upgradeNow() {
    Navigator.pop(context);
    // Routes to the real Upgrade module (plan ladder + Razorpay checkout),
    // not the standalone PaymentMethodScreen — that screen is explicitly
    // UI-only with no gateway wired in (see its own doc comment).
    Navigator.pushNamed(context, AppConstants.upgradeScreen);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          // Wrapped in a scroll view — the fixed-height Column below was
          // overflowing on shorter viewports because the benefit list
          // (LaunchOfferContent.benefits) plus every other section didn't
          // always fit within the modal's available height. Now it scrolls
          // instead of clipping/overflowing.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDragHandle(),
                const SizedBox(height: 16),
                _buildBadge(),
                const SizedBox(height: 14),
                Text(
                  'PropCID Pro',
                  style: AppTextStyles.heading1.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  LaunchOfferContent.valueProposition,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ..._buildBenefitRows(),
                const SizedBox(height: 18),
                _buildPriceRow(),
                const SizedBox(height: 18),
                PremiumButton(
                  label: 'Upgrade Now',
                  icon: Icons.arrow_forward_rounded,
                  width: double.infinity,
                  onPressed: _upgradeNow,
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Maybe Later',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textHint.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: Colors.white, size: 13),
          const SizedBox(width: 4),
          Text(
            LaunchOfferContent.badgeLabel,
            style: AppTextStyles.chip.copyWith(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBenefitRows() {
    return LaunchOfferContent.benefits
        .map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(b.icon, color: AppColors.primary, size: 15),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    b.label,
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  Widget _buildPriceRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            LaunchOfferContent.tagline,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            LaunchOfferContent.priceLabel,
            style: AppTextStyles.price.copyWith(fontSize: 20),
          ),
        ],
      ),
    );
  }
}
