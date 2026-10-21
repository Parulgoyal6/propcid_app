// screens/profile/actions/rating_sheet.dart
//
// Rate a user: five stars, an optional review, submit.
//
// A port of features/profile/UserRatingModal.tsx — same star labels, the same
// 500-character cap with a live counter, the same "Update rating" wording when one
// already exists. Presented as a bottom sheet rather than a dialog, matching every
// other overlay in this app.
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../services/profile_rating_service.dart';
import '../../../widgets/shared/app_action_button.dart';

/// What the sheet returns on submit.
@immutable
class RatingSubmission {
  final int rating;
  final String? review;

  const RatingSubmission({required this.rating, this.review});
}

/// Opens the sheet. Returns null when dismissed without submitting.
Future<RatingSubmission?> showRatingSheet(
  BuildContext context, {
  required String userName,
  MyRating? existing,
}) {
  return showModalBottomSheet<RatingSubmission>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RatingSheet(userName: userName, existing: existing),
  );
}

class _RatingSheet extends StatefulWidget {
  final String userName;
  final MyRating? existing;

  const _RatingSheet({required this.userName, this.existing});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  late int _rating;
  late final TextEditingController _review;

  @override
  void initState() {
    super.initState();
    _rating = widget.existing?.rating ?? 0;
    _review = TextEditingController(text: widget.existing?.review ?? '');
  }

  @override
  void dispose() {
    _review.dispose();
    super.dispose();
  }

  /// UserRatingModal.tsx:160-164.
  static const List<String> _labels = [
    'Poor',
    'Fair',
    'Good',
    'Very Good',
    'Excellent',
  ];

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.existing != null;

    return Padding(
      // Lifts the sheet above the keyboard while the review is being typed.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingXL,
          10,
          AppConstants.spacingXL,
          AppConstants.spacingXL,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingL),
              Text(
                isUpdate ? 'Update your review' : 'Rate ${widget.userName}',
                style: AppTextStyles.heading3.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Share your experience working with them.',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // ── Stars ──────────────────────────────────────────────────
              Center(
                child: Semantics(
                  label: _rating == 0
                      ? 'No rating selected'
                      : '$_rating of 5 stars, ${_labels[_rating - 1]}',
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var star = 1; star <= 5; star++)
                          ScaleTap(
                            onTap: () => setState(() => _rating = star),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Icon(
                                Icons.star_rounded,
                                // 34 dp keeps each star's 42 dp tap area close to
                                // the 44 dp minimum without crowding five of them
                                // onto a 320 dp screen.
                                size: 34,
                                color: star <= _rating
                                    ? AppColors.warning
                                    : AppColors.hairlineStrong,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              Center(
                child: Text(
                  _rating == 0 ? 'Tap to rate' : _labels[_rating - 1],
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _rating == 0
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXL),

              // ── Review ─────────────────────────────────────────────────
              Text(
                'Review (optional)',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _review,
                maxLines: 4,
                maxLength: ProfileRatingService.maxReviewLength,
                style: AppTextStyles.body.copyWith(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Share your experience…',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppConstants.spacingL),

              Row(
                children: [
                  Expanded(
                    child: AppActionButton(
                      label: 'Cancel',
                      variant: AppActionButtonVariant.outline,
                      height: 46,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    child: AppActionButton(
                      label: isUpdate ? 'Update' : 'Submit',
                      variant: AppActionButtonVariant.solid,
                      elevated: true,
                      height: 46,
                      // Disabled until a star is chosen — the portal validates
                      // this after the tap and shows an error; refusing the tap is
                      // the same rule expressed earlier.
                      onTap: _rating == 0
                          ? null
                          : () => Navigator.of(context).pop(
                              RatingSubmission(
                                rating: _rating,
                                review: _review.text,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
