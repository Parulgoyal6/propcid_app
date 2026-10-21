import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state_view.dart';

/// Shown when a search failed outright, as opposed to matching nothing.
///
/// Built on the shared `EmptyStateView` rather than reimplementing its
/// treatment: that widget already renders exactly this composition — a soft
/// primary-tinted circle behind an icon, a bold title, a muted message and a
/// solid primary action carrying `primaryActionShadow` — to the redesign's spec,
/// and it is used by several other surfaces. Reused as-is, not modified.
///
/// Wrapped in a scroll view here rather than at each call site so the state
/// cannot overflow on a short viewport. That is not hypothetical: the sibling
/// empty state overflowed by 17 px once the AI confirmation strip took height
/// above it, and this content is taller.
class SearchErrorState extends StatelessWidget {
  /// Re-issues the identical search. Wired to the screen, which owns the
  /// filter snapshot — this widget never builds a query itself.
  final VoidCallback onRetry;

  const SearchErrorState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: EmptyStateView(
          // Connectivity is by far the likeliest cause, and the advice below is
          // harmless if the fault was actually server-side.
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load results",
          message:
              'We could not complete that search. Check your connection '
              'and try again.',
          actionLabel: 'Retry',
          onAction: onRetry,
          titleFontSize: 18,
        ),
      ),
    );
  }
}
