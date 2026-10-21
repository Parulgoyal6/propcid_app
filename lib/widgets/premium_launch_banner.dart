import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config/launch_features.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/gradient_text.dart';
import '../core/widgets/scale_tap.dart';
import '../models/launch_offer_content.dart';

/// Premium banner promoting "PropCID Pro" for builders/brokers.
///
/// V2.1 visual pass: reskinned to the dark "deep space" card from the design
/// reference — near-black violet surface, ambient purple bloom, glass panels,
/// gradient headline/price/CTA — replacing the earlier flat-purple card.
///
/// Behavior is deliberately untouched: [_openPaymentMethod] still pushes
/// [AppConstants.paymentMethodScreen] with the same arguments, and every string
/// still comes from [LaunchOfferContent] so this surface and the launch bottom
/// sheet cannot drift apart.
class PremiumLaunchBanner extends StatefulWidget {
  const PremiumLaunchBanner({super.key, @visibleForTesting bool? enabled})
    : _enabled = enabled;

  /// Overrides [LaunchFeatures.subscriptions] for this instance. Null in
  /// every production call site. The rendering/overflow regression suite
  /// (`premium_launch_banner_layout_test.dart`) passes `true` explicitly to
  /// keep validating this card's own layout, since the compiled-in flag
  /// default is false for every `flutter test` run.
  final bool? _enabled;

  @override
  State<PremiumLaunchBanner> createState() => _PremiumLaunchBannerState();
}

class _PremiumLaunchBannerState extends State<PremiumLaunchBanner>
    with SingleTickerProviderStateMixin {
  // Single ticker drives every ambient animation (sheen sweep, pulsing badge
  // dot, glowing CTA) — keeps the card cheap to render.
  late final AnimationController _ambient;

  // ── Palette, sampled from the design reference ─────────────────────────
  static const Color _ink = Color(0xFF0A0718);
  static const Color _inkMid = Color(0xFF150E33);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _magenta = Color(0xFFE879F9);
  static const Color _iris = Color(0xFF6D5BF6);

  static const double _radius = 26;

  static const LinearGradient _accentGradient = LinearGradient(
    colors: [_violet, _magenta],
  );
  static const LinearGradient _ctaGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [_iris, _violet, Color(0xFFD65DE0)],
  );

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  // ── Behavior (unchanged from V2) ───────────────────────────────────────

  void _openPaymentMethod(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppConstants.paymentMethodScreen,
      arguments: {
        'amountLabel': LaunchOfferContent.amountLabel,
        'title': 'PropCID Pro',
      },
    );
  }

  /// Splits the single `title` constant into its lead-in and its accent half
  /// ("PropCID Pro" / "Builders & Brokers") so the headline can render the
  /// two-tone treatment from the reference without duplicating the copy.
  (String, String) get _headlineParts {
    const String title = LaunchOfferContent.title;
    final int i = title.indexOf(' for ');
    if (i < 0) return (title, '');
    return (title.substring(0, i), title.substring(i + 5));
  }

  @override
  Widget build(BuildContext context) {
    // Defensive: this banner isn't mounted anywhere in the live Home layout
    // today, but if it ever is, it must never render while subscriptions are
    // disabled for this build.
    if (!(widget._enabled ?? LaunchFeatures.subscriptions)) {
      return const SizedBox.shrink();
    }

    final (String lead, String accent) = _headlineParts;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DecoratedBox(
        // Outer soft premium shadow — sits outside the clip so it can bloom.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: _iris.withOpacity(0.34),
              blurRadius: 30,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_ink, _inkMid, _ink],
                stops: [0.0, 0.55, 1.0],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Stack(
              children: [
                // Ambient blooms. Positioned children are safe here because the
                // content Padding below is non-positioned and gives this Stack
                // its size.
                Positioned(
                  top: -90,
                  right: -70,
                  child: _bloom(230, _violet.withOpacity(0.38)),
                ),
                Positioned(
                  bottom: -110,
                  left: -80,
                  child: _bloom(220, _iris.withOpacity(0.22)),
                ),
                _buildSheen(),

                // ── Content ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(child: _offerChip()),
                          const SizedBox(width: 10),
                          Flexible(child: _trustedBy()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        lead,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading1.copyWith(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (accent.isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              'for ',
                              style: AppTextStyles.heading1.copyWith(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Flexible(
                              child: GradientText(
                                text: accent,
                                gradient: _accentGradient,
                                style: AppTextStyles.heading1.copyWith(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  height: 1.2,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 7),
                      Text(
                        LaunchOfferContent.valueProposition,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: Colors.white.withOpacity(0.68),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _benefitStrip(),
                      const SizedBox(height: 12),
                      _pricePanel(context),
                      const SizedBox(height: 9),
                      _assuranceRow(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }

  // ── Decorative helpers ─────────────────────────────────────────────────

  Widget _bloom(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }

  Widget _buildSheen() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double w = constraints.maxWidth;
              return AnimatedBuilder(
                animation: _ambient,
                builder: (context, _) {
                  final double t = const Interval(
                    0.0,
                    0.45,
                    curve: Curves.easeInOutCubic,
                  ).transform(_ambient.value);
                  final double dx = (-1.3 + 2.6 * t) * w;

                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: Transform.rotate(
                      angle: -0.35,
                      child: Container(
                        width: w * 0.42,
                        height: 900,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.055),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Frosted panel used by the feature grid and the price block.
  BoxDecoration _glassPanel({double radius = 18}) {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.045),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.09)),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _offerChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final double pulse = math.sin(_ambient.value * 2 * math.pi).abs();
              return Icon(
                Icons.rocket_launch_rounded,
                size: 13,
                color: Color.lerp(_magenta, Colors.white, pulse * 0.7),
              );
            },
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              LaunchOfferContent.offerChipLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.chip.copyWith(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustedBy() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Icon(
            Icons.verified_user_rounded,
            size: 15,
            color: _magenta.withOpacity(0.9),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'TRUSTED BY',
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.7,
                  height: 1.1,
                ),
              ),
              Text(
                LaunchOfferContent.trustedByCount,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: AppTextStyles.heading3.copyWith(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              Text(
                LaunchOfferContent.trustedByCaption,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 7.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -- Benefit strip (compact scrollable pills) ----------------------------

  Widget _benefitStrip() {
    final items = LaunchOfferContent.benefits;
    if (items.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final b = items[i];
          return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _violet.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _violet.withOpacity(0.26)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(b.icon, size: 12, color: _magenta),
                    const SizedBox(width: 5),
                    Text(
                      b.label,
                      style: AppTextStyles.chip.copyWith(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
              .animate()
              .fadeIn(delay: (70 * i).ms, duration: 340.ms)
              .slideX(begin: 0.15, curve: Curves.easeOutCubic);
        },
      ),
    );
  }

  // -- Price panel (compact: price + CTA share one row) --------------------

  Widget _pricePanel(BuildContext context) {
    // '₹299/month' -> big '₹299' + small '/month', without hardcoding either.
    const String full = LaunchOfferContent.priceLabel;
    const String amount = LaunchOfferContent.amountLabel;
    final String suffix = full.startsWith(amount)
        ? full.substring(amount.length)
        : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: _glassPanel(radius: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Launch Price',
                        maxLines: 1,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white.withOpacity(0.62),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _savingsChip(),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GradientText(
                        text: amount,
                        gradient: _accentGradient,
                        style: AppTextStyles.price.copyWith(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -0.4,
                        ),
                      ),
                      if (suffix.isNotEmpty)
                        Text(
                          suffix,
                          style: AppTextStyles.body.copyWith(
                            color: Colors.white.withOpacity(0.62),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: _upgradeButton(context)),
        ],
      ),
    );
  }

  Widget _savingsChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _magenta.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _magenta.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 12,
            color: Color(0xFFFF7A59),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              LaunchOfferContent.savingsLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.chip.copyWith(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upgradeButton(BuildContext context) {
    return ScaleTap(
      onTap: () => _openPaymentMethod(context),
      child: AnimatedBuilder(
        animation: _ambient,
        builder: (context, child) {
          final double pulse =
              0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: _ctaGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _violet.withOpacity(0.34 + 0.20 * pulse),
                  blurRadius: 16 + 8 * pulse,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: child,
          );
        },
        // scaleDown rather than ellipsis: a CTA must never read "Upgrade to…".
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                LaunchOfferContent.ctaLabel,
                maxLines: 1,
                style: AppTextStyles.button.copyWith(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Assurance footer ───────────────────────────────────────────────────

  Widget _assuranceRow() {
    final style = AppTextStyles.caption.copyWith(
      color: Colors.white.withOpacity(0.50),
      fontSize: 10,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.lock_rounded,
          size: 11,
          color: Colors.white.withOpacity(0.50),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            LaunchOfferContent.assurances.join('  •  '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ],
    );
  }
}
