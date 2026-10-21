// screens/add_project/project_submission_confirmation_screen.dart
//
// Shown after a project is created. Mirrors
// `post_property/property_submission_confirmation_screen.dart` so finishing
// either wizard feels the same.
//
// The copy comes from the reference's success toast (`BuilderProjectWizard.tsx
// :555-558`): "Project Created Successfully!" and "Now you can add inventory
// units (1 BHK, 2 BHK, plots, etc.) with floor plans to your project."
// Inventory is phase B5, so the promise is worded as what comes next rather than
// as a button that does not exist yet.
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ProjectSubmissionConfirmationScreen extends StatelessWidget {
  const ProjectSubmissionConfirmationScreen({
    super.key,
    required this.projectId,
  });

  /// The row just written. Held so this screen can offer to open it once the
  /// project detail screen lands in B4.
  final String projectId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Project Created',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.heading1.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your project is live and has been submitted for '
                  'verification. Next, you can add inventory units — 1 BHK, '
                  '2 BHK, plots — with their floor plans.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    // Back to the dashboard, whose project list now includes
                    // this row. `popUntil` is not used: the wizard replaced
                    // itself with this screen, so one pop is the dashboard.
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.buttonRadius,
                        ),
                      ),
                    ),
                    child: const Text('Back to Dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
