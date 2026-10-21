import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// IntentStash key under which the Search Entry screen leaves the AI's parse for
/// the Results screen to read once.
///
/// IntentStash rather than a new provider or a route argument: it is already a
/// generic in-memory stash, the Results screen already consults it in
/// `initState` for the voice agent's filters, and `/search-results` is registered
/// without forwarding `RouteSettings`, so route arguments would not survive the
/// trip. Read-and-remove, exactly as the voice-agent key is handled, so a later
/// visit does not resurrect a stale strip.
const String kAiUnderstandingKey = 'ai_search_understanding';

/// "Here's what we understood" — the facets the AI pulled out of a
/// natural-language query, shown once beneath the Results header.
///
/// Deliberately shows what the active-filter chip row does NOT: it includes the
/// detected city (the chip row excludes cities, matching the website's own
/// filter-badge rule) and it frames the values as an interpretation that can be
/// wrong, which is the honest way to present a model's output. It is dismissible
/// and disappears the moment the user touches any other control.
///
/// Not drawn by the redesign — composed from existing tokens and the app's
/// established sparkle-for-AI language.
class AiConfirmationStrip extends StatelessWidget {
  /// Human-readable facet labels, already formatted by the caller.
  final List<String> facets;

  final VoidCallback onEditFilters;
  final VoidCallback onDismiss;

  const AiConfirmationStrip({
    super.key,
    required this.facets,
    required this.onEditFilters,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
          margin: const EdgeInsets.fromLTRB(
            AppConstants.spacingXL,
            0,
            AppConstants.spacingXL,
            AppConstants.spacingM,
          ),
          padding: const EdgeInsets.all(AppConstants.spacingM),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Searched for',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Semantics(
                    label: 'Dismiss search interpretation',
                    button: true,
                    child: GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(
                        Icons.close,
                        size: 15,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingS),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final facet in facets) _buildPill(facet)],
              ),
              const SizedBox(height: AppConstants.spacingS),
              Semantics(
                label: 'Edit filters',
                button: true,
                child: GestureDetector(
                  onTap: onEditFilters,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    'Not quite right? Edit filters',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 220.ms)
        .slideY(begin: -0.15, end: 0, duration: 220.ms, curve: Curves.easeOut);
  }

  Widget _buildPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.chip.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
