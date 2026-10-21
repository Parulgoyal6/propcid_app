// screens/dashboard/widgets/builder_section_kit.dart
//
// The three primitives the four new builder sections share.
//
// WHY A NEW FILE RATHER THAN AN EXTRACTION
// ----------------------------------------
// `my_projects_section.dart` and `my_videos_section.dart` each carry their own
// private `_Pill` and `_Action`. Hoisting those out would mean editing two working
// files to no functional end, so they are left exactly as they are. Spec H adds
// four more sections, and writing the same two widgets six times over is the thing
// worth avoiding — so the new sections share these, and a later cleanup can adopt
// them for the older two if anyone wants to.
//
// Everything here is presentation only. No queries, no state, no business rules.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';

/// A small tinted chip — status, count or tag.
///
/// Same 7×2 padding, 6 dp radius and 12 % tint the projects and videos cards use,
/// so a builder scrolling the Content tab sees one chip style throughout.
class BuilderPill extends StatelessWidget {
  const BuilderPill({super.key, required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}

/// One action in a card's footer row.
///
/// `FittedBox(scaleDown)` for the reason established in B4 and reconfirmed in
/// Spec D: three of these share a 320 dp card, which leaves ~89 dp each, and
/// "Delete" does not fit at the default text scale let alone a raised one.
/// Scaling beats ellipsising an action label.
class BuilderAction extends StatelessWidget {
  const BuilderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;

  /// Null disables the action and greys it, rather than removing it — a builder
  /// should see that an action exists even while a write is in flight.
  final VoidCallback? onTap;

  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled ? AppColors.textHint : (tint ?? AppColors.primary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The load / fail / empty / content states every one of the four sections has.
///
/// Codifies the contract `MyProjectsSection` established and `MyVideosSection`
/// followed, so all six behave alike:
///
///   * `items == null` → still loading, show a spinner. **Not** the same as empty:
///     collapsing on "not loaded yet" flashes the section away and back;
///   * `failed` → an error state with a retry. A failed fetch is not an empty
///     list, and collapsing here would take the retry with it;
///   * empty → collapse to nothing. The Content tab already offers a create
///     action, so an in-section empty state would be the second prompt in one
///     column.
class BuilderSectionShell extends StatelessWidget {
  const BuilderSectionShell({
    super.key,
    required this.failed,
    required this.loaded,
    required this.isEmpty,
    required this.onRetry,
    required this.errorTitle,
    required this.child,
    this.emptyMessage,
  });

  final bool failed;

  /// False while the first fetch is in flight.
  final bool loaded;

  final bool isEmpty;
  final VoidCallback onRetry;

  /// e.g. "Couldn't load your offers".
  final String errorTitle;

  /// When supplied, an empty section renders this single muted line instead of
  /// collapsing. Used by Site Visits, where "no bookings yet" is information a
  /// builder wants rather than clutter — there is no create action for it, so it
  /// cannot be the second prompt.
  final String? emptyMessage;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: errorTitle,
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      );
    }

    if (!loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (isEmpty) {
      final message = emptyMessage;
      if (message == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ),
      );
    }

    return child;
  }
}

/// The card every row in these sections sits in.
///
/// Same surface, radius and shadow as `MyProjectsSection`'s card.
class BuilderSectionCard extends StatelessWidget {
  const BuilderSectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: child,
    );
  }
}

/// The busy spinner that replaces a card's action row mid-write.
class BuilderActionBusyRow extends StatelessWidget {
  const BuilderActionBusyRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
