// screens/add_project/add_project_screen.dart
//
// The builder project wizard shell.
//
// Structure, layout and chrome are `PostPropertyScreen`'s — the same
// `PortalProgressCard`, the same two-column-above-900dp split, the same
// `PortalWizardFooter`, the same animated step switcher. Only the steps and the
// provider differ, so the two wizards are the same product to look at.
//
// `PostPropertyScreen` itself is untouched. The shared chrome lives in
// `post_property/portal_shell.dart`, whose progress card gained a second
// constructor for wizards with their own step enum — see `PortalStepInfo`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/project_model.dart';
import '../../providers/add_project_provider.dart';
import '../../providers/auth_provider.dart';
import '../post_property/listing_validation_rules.dart' show ListingIssue;
import '../post_property/portal_shell.dart';
import 'project_submission_confirmation_screen.dart';
import 'project_validation_rules.dart';
import 'steps/contact_media_step.dart';
import 'steps/project_amenities_step.dart';
import 'steps/project_details_step.dart';
import 'steps/project_basic_info_step.dart';
import 'steps/project_review_step.dart';

/// Entry point. Pass [editingProject] to open the wizard on an existing project.
class AddProjectScreen extends StatelessWidget {
  const AddProjectScreen({
    super.key,
    this.editingProject,
    this.providerOverride,
    this.builderIdOverride,
  });

  /// When set, the wizard pre-fills every field and submits an UPDATE.
  final ProjectModel? editingProject;

  /// Injected by tests. Production always builds a real provider.
  @visibleForTesting
  final AddProjectProvider? providerOverride;

  /// The workspace this project belongs to, when it differs from the
  /// signed-in user — a team member managing a builder's projects, never the
  /// builder's own use of this screen. `null` (the default) keeps the
  /// existing behaviour exactly as it was: the signed-in user's own id.
  final String? builderIdOverride;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AddProjectProvider>(
      // Seeded synchronously here — not in a post-frame callback — so the
      // draft is already populated before the first step widget's initState
      // reads it to seed its TextEditingControllers. See
      // `AddProjectWizardView.initState` for the create-mode counterpart.
      create: (_) {
        final provider = providerOverride ?? AddProjectProvider();
        if (editingProject != null) {
          provider.initFromProject(editingProject!);
        }
        return provider;
      },
      child: AddProjectWizardView(
        editingProject: editingProject,
        builderIdOverride: builderIdOverride,
      ),
    );
  }
}

/// The wizard without its provider.
///
/// Public only so layout tests can pump it against a provider they control —
/// exactly why `PostPropertyWizardView` is public.
@visibleForTesting
class AddProjectWizardView extends StatefulWidget {
  const AddProjectWizardView({
    super.key,
    this.editingProject,
    this.builderIdOverride,
  });

  final ProjectModel? editingProject;

  /// See `AddProjectScreen.builderIdOverride`.
  final String? builderIdOverride;

  @override
  State<AddProjectWizardView> createState() => _AddProjectWizardViewState();
}

class _AddProjectWizardViewState extends State<AddProjectWizardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<AddProjectProvider>();
      final editing = widget.editingProject;
      if (editing != null) {
        provider.initFromProject(editing);
      } else {
        // Only a create can have a draft to resume.
        provider.checkForSavedDraft();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AddProjectProvider>();

    // The reference shows this as a fullscreen prompt on mobile before the form
    // (`:575-600`), so the user decides once rather than finding half a project
    // already typed in.
    if (provider.hasSavedDraft) {
      return _ResumeDraftPrompt(provider: provider);
    }

    return PopScope(
      // The device's system back button used to always close this screen
      // outright — dropping the whole in-progress project draft — unlike
      // the in-app back arrow below, which only steps back one wizard step.
      // Mirror that same "step back, don't leave" logic here.
      canPop: provider.currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        provider.previousStep();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              if (provider.currentStep > 0) {
                provider.previousStep();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            provider.isEditMode ? 'Edit Project' : 'Add Project',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= kWideBreakpoint;
            final horizontalPadding = isWide ? 24.0 : 20.0;
            final maxContentWidth = isWide ? 720.0 : double.infinity;

            final progressCard = PortalProgressCard.custom(
              steps: [
                for (final step in provider.steps)
                  PortalStepInfo(
                    title: projectStepTitle(step),
                    icon: projectStepIcon(step),
                  ),
              ],
              currentIndex: provider.currentStep,
              compact: !isWide,
              onStepTap: (i) => context.read<AddProjectProvider>().goToStep(i),
            );

            final form = _StepBody(
              provider: provider,
              horizontalPadding: horizontalPadding,
              maxContentWidth: maxContentWidth,
            );

            if (isWide) {
              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 300,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                              child: progressCard,
                            ),
                          ),
                          Expanded(child: form),
                        ],
                      ),
                    ),
                    _NavigationBar(
                      provider: provider,
                      horizontalPadding: horizontalPadding,
                      builderIdOverride: widget.builderIdOverride,
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      12,
                    ),
                    child: progressCard,
                  ),
                  Expanded(child: form),
                  _NavigationBar(
                    provider: provider,
                    horizontalPadding: horizontalPadding,
                  ),
                ],
              ),
            );
          },
        ),
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}

/// The scrolling form column.
class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.provider,
    required this.horizontalPadding,
    required this.maxContentWidth,
  });

  final AddProjectProvider provider;
  final double horizontalPadding;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: SingleChildScrollView(
              key: ValueKey(provider.currentStep),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                24,
              ),
              child: switch (provider.currentProjectStep) {
                ProjectStep.basic => const ProjectBasicInfoStep(),
                ProjectStep.details => const ProjectDetailsStep(),
                ProjectStep.media => const ContactMediaStep(),
                ProjectStep.amenities => const ProjectAmenitiesStep(),
                ProjectStep.review => const ProjectReviewStep(),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.provider,
    required this.horizontalPadding,
    this.builderIdOverride,
  });

  final AddProjectProvider provider;
  final double horizontalPadding;

  /// See `AddProjectScreen.builderIdOverride`.
  final String? builderIdOverride;

  @override
  Widget build(BuildContext context) {
    return PortalWizardFooter(
      currentIndex: provider.currentStep,
      total: provider.totalSteps,
      isLastStep: provider.isLastStep,
      isEditing: provider.isEditMode,
      isSubmitting: provider.isSubmitting,
      onBack: provider.previousStep,
      onContinue: () => _onPrimaryAction(context),
      onSubmit: () => _onPrimaryAction(context),
    );
  }

  void _onPrimaryAction(BuildContext context) {
    final provider = context.read<AddProjectProvider>();

    if (!provider.isLastStep) {
      final issues = provider.nextStep();
      if (issues.isEmpty) {
        HapticFeedback.selectionClick();
        return;
      }
      // The reference's toast: "N fields still needed" + a summary (`:471-475`).
      _showIssues(
        context,
        title:
            '${issues.length} field${issues.length > 1 ? 's' : ''} '
            'still needed',
        issues: issues,
      );
      return;
    }

    _submit(context);
  }

  Future<void> _submit(BuildContext context) async {
    final provider = context.read<AddProjectProvider>();
    final builderId = builderIdOverride ?? context.read<AuthProvider>().userId;

    if (builderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to publish a project.'),
        ),
      );
      return;
    }

    try {
      final result = await provider.submit(builderId: builderId);
      if (!context.mounted) return;

      if (!result.isSuccess) {
        // Jumped to the offending step already; name it, as the reference does.
        final failure = result.failure!;
        _showIssues(
          context,
          title: 'Incomplete: ${projectStepTitle(failure.step)}',
          issues: failure.issues,
        );
        return;
      }

      if (provider.isEditMode) {
        Navigator.of(context).pop(true);
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ProjectSubmissionConfirmationScreen(projectId: result.projectId!),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.isEditMode
                ? 'Failed to update project. Please try again.'
                : 'Failed to create project. Please try again.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// `summariseIssues` — the labels, comma separated.
  static void _showIssues(
    BuildContext context, {
    required String title,
    required List<ListingIssue> issues,
  }) {
    final summary = issues.map((i) => i.label).join(', ');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              summary,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// "Resume Project?" — the reference's draft prompt (`:575-620`).
class _ResumeDraftPrompt extends StatelessWidget {
  const _ResumeDraftPrompt({required this.provider});

  final AddProjectProvider provider;

  @override
  Widget build(BuildContext context) {
    final saved = provider.savedDraft!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Resume Project?',
          style: AppTextStyles.heading2.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You have an unsaved project draft. Would you like to '
                  'continue where you left off or start fresh?',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                if (saved.title.trim().isNotEmpty ||
                    saved.location.trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (saved.title.trim().isNotEmpty)
                          Text(
                            saved.title,
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        if (saved.location.trim().isNotEmpty)
                          Text(
                            saved.location,
                            style: AppTextStyles.caption.copyWith(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: provider.restoreSavedDraft,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Continue Draft'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: provider.discardSavedDraft,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.hairline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Start Fresh'),
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
