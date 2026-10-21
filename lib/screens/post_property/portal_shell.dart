import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'listing_validation_rules.dart';
import 'portal_icon.dart';
import 'portal_theme.dart';

/// Wizard chrome: the portal's structure, the app's branding.
///
/// Layout follows `PropertyWizard.tsx` — `grid-cols-1 lg:grid-cols-12`, the
/// Progress panel at `lg:col-span-3` beside the form at `lg:col-span-9`,
/// collapsing to one column at mobile width. Colour and type come from
/// [PortalTheme], which resolves to `AppColors` / `AppTextStyles`.

/// Step icons, from the `icon` on each entry of `stepsRaw` — the real lucide
/// artwork, not Material equivalents.
String portalStepIcon(WizardStep step) => switch (step) {
  WizardStep.category => PortalStepIcons.category,
  WizardStep.basicInfo => PortalStepIcons.basicInfo,
  WizardStep.dimensions => PortalStepIcons.dimensions,
  WizardStep.condition => PortalStepIcons.condition,
  WizardStep.amenities => PortalStepIcons.amenities,
  WizardStep.legal => PortalStepIcons.legal,
  WizardStep.pricing => PortalStepIcons.pricing,
  WizardStep.media => PortalStepIcons.media,
  WizardStep.review => PortalStepIcons.review,
};

/// Step titles as the portal's `stepsRaw` names them.
String portalStepTitle(WizardStep step) => switch (step) {
  WizardStep.category => 'Category',
  WizardStep.basicInfo => 'Basic Info',
  WizardStep.dimensions => 'Dimensions',
  WizardStep.condition => 'Condition',
  WizardStep.amenities => 'Amenities',
  WizardStep.legal => 'Legal',
  WizardStep.pricing => 'Pricing',
  WizardStep.media => 'Media',
  WizardStep.review => 'Review',
};

/// One row of the stepper: what it is called, and which lucide glyph it shows.
///
/// Added so a wizard with a different step enum can render this same panel. The
/// listing wizard never constructs one directly — [PortalProgressCard]'s primary
/// constructor still takes `List<WizardStep>` and resolves it through
/// [portalStepTitle] / [portalStepIcon] exactly as before.
@immutable
class PortalStepInfo {
  const PortalStepInfo({required this.title, required this.icon});

  /// Row label.
  final String title;

  /// A key into `assets/lucide`, as [PortalIcon] expects.
  final String icon;

  /// The descriptor for a listing wizard step.
  factory PortalStepInfo.fromWizardStep(WizardStep step) =>
      PortalStepInfo(title: portalStepTitle(step), icon: portalStepIcon(step));
}

/// The "Progress" card: heading with a circular percentage ring, then the
/// vertical stepper.
class PortalProgressCard extends StatelessWidget {
  /// The listing wizard's entry point — unchanged.
  PortalProgressCard({
    super.key,
    required List<WizardStep> steps,
    required this.currentIndex,
    required this.onStepTap,
    this.compact = false,
  }) : steps = steps.map(PortalStepInfo.fromWizardStep).toList(growable: false);

  /// For a wizard with its own step enum — the builder project wizard uses this.
  ///
  /// Renders the identical panel; only where the titles and icons come from
  /// differs, so the two wizards cannot drift apart visually.
  const PortalProgressCard.custom({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.onStepTap,
    this.compact = false,
  });

  final List<PortalStepInfo> steps;
  final int currentIndex;

  /// Only fired for already-visited steps — the portal disables the button
  /// unless `stepNum < currentStep`.
  final ValueChanged<int> onStepTap;

  /// Mobile form: ring, current step title and counter on one row, without the
  /// full vertical stepper.
  ///
  /// The portal only ever draws this panel as a desktop sidebar
  /// (`lg:col-span-3`, `lg:h-full`, `overflow-y-auto`). Stacking all 9 stepper
  /// rows above the form on a phone consumes the entire viewport and leaves
  /// nothing for the form — the width adaptation CLAUDE.md allows. The full
  /// stepper still renders beside the form from [kWideBreakpoint] up.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // `Math.round((currentStep / steps.length) * 100)`, 1-based.
    final percent = ((currentIndex + 1) / steps.length * 100).round();
    final safeIndex = currentIndex.clamp(0, steps.length - 1);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PortalTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: PortalTheme.cardShadow,
      ),
      padding: const EdgeInsets.all(14), // p-3.5
      child: Column(
        // Without this the card takes every pixel its parent offers, starving
        // the form area below it.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: "Progress" + ring, with a bottom rule.
          Row(
            children: [
              const PortalIcon(
                'file-text',
                size: 22,
                color: PortalTheme.accent,
              ),
              const SizedBox(width: 10), // gap-2.5
              Expanded(
                child: compact
                    // The card no longer lists the steps, so it names the one
                    // the user is on instead of saying "Progress".
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            steps[safeIndex].title,
                            style: PortalTheme.progressHeading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Step ${safeIndex + 1} of ${steps.length}',
                            style: PortalTheme.stepperCounter,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      )
                    : Text(
                        'Progress',
                        style: PortalTheme.progressHeading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: 8),
              _ProgressRing(percent: percent),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 8), // pb-2
            Divider(height: 1, color: PortalTheme.slate200),
            const SizedBox(height: 16), // mb-4
            for (int i = 0; i < steps.length; i++)
              _StepperRow(
                info: steps[i],
                index: i,
                total: steps.length,
                currentIndex: currentIndex,
                isLast: i == steps.length - 1,
                onTap: i < currentIndex ? () => onStepTap(i) : null,
              ),
          ],
        ],
      ),
    );
  }
}

/// Width at or above which the portal's two-column layout is used — its own
/// `lg:` breakpoint is 1024px, lowered here so tablets get the sidebar too.
const double kWideBreakpoint = 900;

/// 40x40 ring, 3.5 stroke, neutral track, primary gradient sweep,
/// percentage centred. The portal's geometry, the app's colours.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: percent / 100),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, value, _) => CustomPaint(
              size: const Size(40, 40),
              painter: _RingPainter(value),
            ),
          ),
          Text('$percent%', style: PortalTheme.progressPercent),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    // r=18 in a 44 viewBox, scaled to the 40px box.
    final radius = 18 / 44 * size.width;
    final stroke = 3.5 / 44 * size.width;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = PortalTheme.slate100;
    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [PortalTheme.accent, PortalTheme.accentGradientEnd],
      ).createShader(rect);
    // `transform: -rotate-90` — start at 12 o'clock.
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, sweep);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// One stepper entry: node circle, connector, title and "Step n of m".
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.info,
    required this.index,
    required this.total,
    required this.currentIndex,
    required this.isLast,
    this.onTap,
  });

  final PortalStepInfo info;
  final int index;
  final int total;
  final int currentIndex;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;
    final isCompleted = index < currentIndex;

    final Color nodeBg = isCompleted
        ? PortalTheme.success
        : isActive
        ? PortalTheme.accent
        : PortalTheme.cardSurface;
    final Color nodeBorder = isCompleted
        ? PortalTheme.success
        : isActive
        ? PortalTheme.accent
        : PortalTheme.slate200;
    final Color nodeFg = (isCompleted || isActive)
        ? Colors.white
        : PortalTheme.slate400;
    final Color titleColor = isActive
        ? PortalTheme.accent
        : isCompleted
        ? PortalTheme.success
        : PortalTheme.slate600;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 40,
                  height: 40,
                  transform: isActive
                      ? (Matrix4.identity()
                          ..scaleByDouble(1.05, 1.05, 1.05, 1.0))
                      : Matrix4.identity(),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nodeBg,
                    border: Border.all(color: nodeBorder, width: 2),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: PortalTheme.accent.withAlpha(51),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: isCompleted
                        ? PortalIcon('check', size: 20, color: nodeFg)
                        : PortalIcon(info.icon, size: 20, color: nodeFg),
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: isCompleted
                      ? PortalTheme.success
                      : PortalTheme.slate200,
                ),
            ],
          ),
          const SizedBox(width: 12), // ml-3
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8), // pt-2
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.title, style: PortalTheme.stepperTitle(titleColor)),
                  const SizedBox(height: 2), // mt-0.5
                  Text(
                    'Step ${index + 1} of $total',
                    style: PortalTheme.stepperCounter,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed footer: step counter on the left, Back + Continue/Publish on the
/// right, separated by a top rule.
class PortalWizardFooter extends StatelessWidget {
  const PortalWizardFooter({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.isLastStep,
    required this.isEditing,
    required this.isSubmitting,
    required this.onBack,
    required this.onContinue,
    required this.onSubmit,
  });

  final int currentIndex;
  final int total;
  final bool isLastStep;
  final bool isEditing;
  final bool isSubmitting;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final backDisabled = currentIndex == 0;

    final back = Opacity(
      opacity: backDisabled ? 0.5 : 1,
      child: SizedBox(
        height: 40, // h-10
        child: OutlinedButton.icon(
          onPressed: backDisabled ? null : onBack,
          icon: const PortalIcon(
            'arrow-left',
            size: 18,
            color: PortalTheme.slate700,
          ),
          label: Text(
            'Back',
            style: PortalTheme.navButton.copyWith(color: PortalTheme.slate700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: PortalTheme.slate700,
            side: BorderSide(color: PortalTheme.slate200),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );

    final primary = _primaryButton();

    return Container(
      padding: const EdgeInsets.all(8), // p-2
      decoration: BoxDecoration(
        color: PortalTheme.cardSurface,
        border: Border(top: BorderSide(color: PortalTheme.slate200)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The portal's footer is one row: counter left, buttons right. That
          // needs ~430px; below it the counter is dropped (the Progress card
          // above already says "Step n of m") and the two buttons share the
          // width instead of overflowing.
          final tight = constraints.maxWidth < 420;

          if (tight) {
            return Row(
              children: [
                Expanded(child: back),
                const SizedBox(width: 8), // gap-2
                Expanded(child: primary),
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Step ${currentIndex + 1} of $total',
                  style: PortalTheme.footerCounter,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  back,
                  const SizedBox(width: 8), // gap-2
                  primary,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _primaryButton() => isLastStep
      ? _GradientButton(
          // emerald-600 -> teal-600
          colors: const [PortalTheme.success, PortalTheme.successDark],
          onPressed: isSubmitting ? null : onSubmit,
          child: isSubmitting
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Publishing...',
                      style: PortalTheme.navButton.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                )
              : Text(
                  isEditing ? 'Update Property' : 'Publish Listing',
                  style: PortalTheme.navButton.copyWith(color: Colors.white),
                ),
        )
      : _GradientButton(
          // The app's primary gradient.
          colors: const [PortalTheme.accent, PortalTheme.accentGradientEnd],
          onPressed: onContinue,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Continue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PortalTheme.navButton.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              const PortalIcon('arrow-right', size: 18, color: Colors.white),
            ],
          ),
        );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.colors,
    required this.onPressed,
    required this.child,
  });

  final List<Color> colors;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.7 : 1,
      child: Container(
        height: 40, // h-10
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(6),
          boxShadow: onPressed == null
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ], // shadow-md
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16), // px-4
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
