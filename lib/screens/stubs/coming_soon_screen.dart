import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';

/// Honest placeholder for destinations that are reachable from the Workspace
/// Drawer / More sheet but are not part of this workstream — Network, Social,
/// Subscription & Billing and Upgrade (blueprint §16.12), plus Messages until
/// Phase 4 replaces it with the real screen.
///
/// Deliberately contains no data, real or fabricated: the prototype itself
/// stubs these screens, and §9 marks them as out of scope rather than
/// unavailable. It exists only so navigation never dead-ends.
class ComingSoonScreen extends StatelessWidget {
  /// Destination name, shown in the app bar.
  final String title;

  /// Optional one-line explanation shown beneath the heading.
  final String? message;

  const ComingSoonScreen({super.key, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back',
        ),
        title: Text(title, style: AppTextStyles.heading3),
      ),
      body: Center(
        child: EmptyStateView(
          icon: Icons.grid_view_rounded,
          title: '$title is coming soon',
          message:
              message ??
              "This section isn't available in the app yet. "
                  "We'll let you know as soon as it is.",
        ),
      ),
    );
  }
}
