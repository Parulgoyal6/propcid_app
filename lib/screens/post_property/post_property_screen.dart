import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/gradient_text.dart';
import '../../providers/auth_provider.dart';
import '../../providers/post_property_provider.dart';
import 'listing_validation_rules.dart';
import 'portal_shell.dart';

import '../../services/property_service.dart';
import 'steps/type_selection_step.dart';
import 'steps/basic_info_step.dart';
import 'steps/property_dimensions_step.dart';
import 'steps/condition_step.dart';
import 'steps/amenities_step.dart';
import 'steps/legal_details_step.dart';
import 'steps/pricing_step.dart';
import 'steps/media_contact_step.dart';
import 'steps/review_step.dart';
import 'property_submission_confirmation_screen.dart';

/// Steps already reproduced from the React portal, which render their own
/// heading block. Grows as each step is converted.
const Set<WizardStep> kPortalConvertedSteps = {
  WizardStep.category,
  WizardStep.basicInfo,
  WizardStep.dimensions,
};

/// Post Property wizard shell.
///
/// Implements the full 9-step frontend flow (type selection, basic info,
/// dimensions, condition, amenities, legal, pricing, media & contact, review)
/// across all 5 property categories. On the final step, tapping Publish
/// triggers [PostPropertyProvider.submit] → [PropertyService.createProperty]
/// which uploads media and writes to Supabase.
///
/// Pass [editPropertyId] + [editBundle] when opening for an existing listing —
/// the wizard pre-fills all fields via [PostPropertyProvider.initFromRawData]
/// and switches submit to UPDATE mode.
class PostPropertyScreen extends StatelessWidget {
  final String? editPropertyId;
  final PropertyEditBundle? editBundle;

  const PostPropertyScreen({super.key, this.editPropertyId, this.editBundle});

  /// Short label per step, shown in the progress indicator. Keyed by identity
  /// because which steps appear — and therefore their positions — depends on
  /// the chosen category (T3).
  static const Map<WizardStep, String> stepLabels = {
    WizardStep.category: 'Type',
    WizardStep.basicInfo: 'Basic Info',
    WizardStep.dimensions: 'Dimensions',
    WizardStep.condition: 'Condition',
    WizardStep.amenities: 'Amenities',
    WizardStep.legal: 'Legal',
    WizardStep.pricing: 'Pricing',
    WizardStep.media: 'Media',
    WizardStep.review: 'Review',
  };

  static const Map<WizardStep, (String, String)> stepHeadings = {
    WizardStep.category: (
      'What are you listing?',
      'Choose a category and how you want to list it',
    ),
    WizardStep.basicInfo: (
      'Tell us the basics',
      'Add the core details buyers will see first',
    ),
    WizardStep.dimensions: (
      'Dimensions & Layout',
      'Specify the physical size and layout of the property',
    ),
    WizardStep.condition: (
      'Condition & Furnishing',
      "Tell us about the property's age, availability and furnishings",
    ),
    WizardStep.amenities: (
      'Amenities & Facilities',
      'What facilities are available at this property?',
    ),
    WizardStep.legal: (
      'Legal & Approvals',
      'Provide legal and documentation status for transparency',
    ),
    WizardStep.pricing: (
      'Pricing & Terms',
      'Provide pricing details, terms and conditions',
    ),
    WizardStep.media: (
      'Media & Contact',
      'Add photos and how buyers can reach you',
    ),
    WizardStep.review: (
      'Review Your Listing',
      'Check everything before you finish',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PostPropertyProvider(),
      child: PostPropertyWizardView(
        stepLabels: stepLabels,
        stepHeadings: stepHeadings,
        editPropertyId: editPropertyId,
        editBundle: editBundle,
      ),
    );
  }
}

/// The wizard itself, without the [ChangeNotifierProvider] that
/// [PostPropertyScreen] wraps it in.
///
/// Public only so layout tests can pump it against a provider they control —
/// [PostPropertyScreen] remains the entry point and nothing about how the app
/// navigates into this flow changes.
class PostPropertyWizardView extends StatefulWidget {
  final Map<WizardStep, String> stepLabels;
  final Map<WizardStep, (String, String)> stepHeadings;
  final String? editPropertyId;
  final PropertyEditBundle? editBundle;

  const PostPropertyWizardView({
    required this.stepLabels,
    required this.stepHeadings,
    this.editPropertyId,
    this.editBundle,
  });

  @override
  State<PostPropertyWizardView> createState() => _PostPropertyWizardState();
}

class _PostPropertyWizardState extends State<PostPropertyWizardView> {
  @override
  void initState() {
    super.initState();
    final bundle = widget.editBundle;
    final id = widget.editPropertyId;
    if (bundle != null && id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<PostPropertyProvider>().initFromRawData(
          editingPropertyId: id,
          propertyRow: bundle.propertyRow,
          subtableRow: bundle.subtableRow,
          contactRow: bundle.contactRow,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostPropertyProvider>();

    return PopScope(
      // The device's system back button used to always close this screen
      // outright — dropping the whole in-progress listing — unlike the
      // in-app back arrow below, which only steps back one wizard step.
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
            provider.isEditMode ? 'Edit Property' : 'Post Property',
            style: AppTextStyles.heading2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // The portal's own split: `grid-cols-1 lg:grid-cols-12` with the
            // Progress panel at `lg:col-span-3` and the form at `lg:col-span-9`.
            final isWide = constraints.maxWidth >= kWideBreakpoint;
            final horizontalPadding = isWide ? 24.0 : 20.0;
            final maxContentWidth = isWide ? 720.0 : double.infinity;

            final progressCard = PortalProgressCard(
              steps: provider.visibleSteps,
              currentIndex: provider.currentStep,
              compact: !isWide,
              onStepTap: (i) =>
                  context.read<PostPropertyProvider>().goToStep(i),
            );

            final form = _StepBody(
              provider: provider,
              stepHeadings: widget.stepHeadings,
              horizontalPadding: horizontalPadding,
              maxContentWidth: maxContentWidth,
              buildStepContent: _buildStepContent,
            );

            if (isWide) {
              // Two columns. Each side owns its own scrollable, so a tall
              // stepper never pushes the form off screen and vice versa.
              return SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 300, // ~3/12 of the portal's max-w-7xl
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
                      maxContentWidth: double.infinity,
                      horizontalPadding: horizontalPadding,
                    ),
                  ],
                ),
              );
            }

            // Single column, as the portal's `grid-cols-1` does at mobile width.
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
                    maxContentWidth: maxContentWidth,
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

  Widget _buildStepContent(WizardStep step) {
    return switch (step) {
      WizardStep.category => const TypeSelectionStep(),
      WizardStep.basicInfo => const BasicInfoStep(),
      WizardStep.dimensions => const PropertyDimensionsStep(),
      WizardStep.condition => const ConditionStep(),
      WizardStep.amenities => const AmenitiesStep(),
      WizardStep.legal => const LegalDetailsStep(),
      WizardStep.pricing => const PricingStep(),
      WizardStep.media => const MediaContactStep(),
      WizardStep.review => const ReviewStep(),
    };
  }
}

/// The scrolling form column, shared by both layouts.
class _StepBody extends StatelessWidget {
  const _StepBody({
    required this.provider,
    required this.stepHeadings,
    required this.horizontalPadding,
    required this.maxContentWidth,
    required this.buildStepContent,
  });

  final PostPropertyProvider provider;
  final Map<WizardStep, (String, String)> stepHeadings;
  final double horizontalPadding;
  final double maxContentWidth;
  final Widget Function(WizardStep) buildStepContent;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Portal-converted steps render their own heading, exactly
                  // as each React step component does. The app's own step
                  // header stays for steps not yet converted, so they are not
                  // left untitled mid-migration.
                  if (!kPortalConvertedSteps.contains(
                    provider.currentWizardStep,
                  )) ...[
                    _StepHeader(
                      stepNumber: provider.currentStep + 1,
                      totalSteps: provider.totalSteps,
                      title: stepHeadings[provider.currentWizardStep]!.$1,
                      subtitle: stepHeadings[provider.currentWizardStep]!.$2,
                    ),
                    const SizedBox(height: 24),
                  ],
                  buildStepContent(provider.currentWizardStep),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int stepNumber;
  final int totalSteps;
  final String title;
  final String subtitle;

  const _StepHeader({
    required this.stepNumber,
    required this.totalSteps,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STEP $stepNumber OF $totalSteps',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        GradientText(
          text: title,
          style: AppTextStyles.heading1.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _NavigationBar extends StatelessWidget {
  final PostPropertyProvider provider;
  final double maxContentWidth;
  final double horizontalPadding;

  const _NavigationBar({
    required this.provider,
    required this.maxContentWidth,
    required this.horizontalPadding,
  });

  @override
  Widget build(BuildContext context) {
    // Portal footer: step counter left, Back + Continue/Publish right, with a
    // top rule. Replaces the app's rounded raised bar.
    return PortalWizardFooter(
      currentIndex: provider.currentStep,
      total: provider.totalSteps,
      isLastStep: provider.isLastStep,
      isEditing: provider.isEditMode,
      isSubmitting: provider.isSubmitting,
      onBack: provider.previousStep,
      onContinue: () => _onPrimaryAction(context, provider),
      onSubmit: () => _onPrimaryAction(context, provider),
    );
  }

  /// Wires the already-ported validation engine
  /// (`PostPropertyProvider.issuesForStep`/`allStepIssues`/`firstInvalidStep`,
  /// a verbatim port of the portal's rule tables) to actual user feedback.
  /// Previously `nextStep()`/`submit()` ran unconditionally — a step with a
  /// blank required field just silently failed to advance with no message at
  /// all, since nothing in the UI ever asked the provider whether the step
  /// was valid.
  void _onPrimaryAction(BuildContext context, PostPropertyProvider provider) {
    if (!provider.isLastStep) {
      final issues = provider.issuesForStep(provider.currentStep);
      if (issues.isNotEmpty) {
        _showValidationIssues(context, issues);
        return;
      }
      provider.nextStep();
      return;
    }

    // Mirrors the portal's handleSubmit re-validating every step and jumping
    // back to the first offending one before publishing.
    final allIssues = provider.allStepIssues;
    if (allIssues.isNotEmpty) {
      final firstStep = provider.firstInvalidStep;
      if (firstStep != null) {
        provider.goToStep(firstStep);
        _showValidationIssues(context, allIssues[firstStep]!);
      }
      return;
    }

    _submitProperty(context, provider);
  }

  void _showValidationIssues(BuildContext context, List<ListingIssue> issues) {
    if (issues.isEmpty) return;
    final labels = issues.map((i) => i.label).join(', ');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Please complete: $labels'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _submitProperty(
    BuildContext context,
    PostPropertyProvider provider,
  ) async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to publish a listing.'),
        ),
      );
      return;
    }

    try {
      final result = await provider.submit(PropertyService(), userId);
      if (!context.mounted) return;
      if (provider.isEditMode) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertySubmissionConfirmationScreen(
              propertyId: result.propertyId,
              approvalStatus: result.approvalStatus,
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }
}
