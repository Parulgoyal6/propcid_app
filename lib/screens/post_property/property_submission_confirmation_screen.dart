import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/premium_button.dart';
import '../../providers/auth_provider.dart';
import '../../services/property_service.dart';
import '../social/publish_everywhere_dialog.dart';

/// Terminal screen shown after the post-property wizard submits a listing to
/// Supabase. A non-null [propertyId] only means the row was inserted — it
/// does NOT mean the listing is live. Whether it's actually live is decided
/// by [approvalStatus] (the real `approval_status` column value returned by
/// the insert), matching the `== 'approved'` convention every buyer-facing
/// query in `property_service.dart` already uses.
///
/// For an approved listing, also auto-opens "Publish everywhere" once the
/// property's title/media are in hand — the same trigger point as the
/// portal's `PostProperty.tsx`, which opens `PublishEverywhereDialog`
/// immediately after a new property is created (`:205-213`). Best-effort: if
/// the detail fetch fails, the confirmation screen still shows normally and
/// the dialog is simply skipped, since a stray publish prompt is not worth
/// blocking the confirmation over. A pending (not-yet-approved) listing never
/// triggers this dialog — there is nothing live to publish yet.
class PropertySubmissionConfirmationScreen extends StatefulWidget {
  final String? propertyId;
  final String? approvalStatus;

  const PropertySubmissionConfirmationScreen({
    this.propertyId,
    this.approvalStatus,
    super.key,
  });

  @override
  State<PropertySubmissionConfirmationScreen> createState() =>
      _PropertySubmissionConfirmationScreenState();
}

class _PropertySubmissionConfirmationScreenState
    extends State<PropertySubmissionConfirmationScreen> {
  bool _offeredPublish = false;

  /// Same convention as every buyer-facing query in `property_service.dart`:
  /// only `'approved'` means live. `null`/`'pending'`/`'rejected'`/anything
  /// else is treated as not-yet-live, never as "assume approved".
  bool get _isApproved => widget.approvalStatus == 'approved';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_offeredPublish || widget.propertyId == null || !_isApproved) return;
    _offeredPublish = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerPublish());
  }

  Future<void> _offerPublish() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || !mounted) return;
    try {
      final detail = await PropertyService().getPropertyDetail(
        widget.propertyId!,
      );
      if (!mounted) return;
      await showPublishEverywhereDialog(
        context,
        userId: userId,
        contentType: 'property',
        contentId: widget.propertyId!,
        title: detail.property.title,
        mediaUrls: detail.property.imageUrls,
      );
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  String? get propertyId => widget.propertyId;

  @override
  Widget build(BuildContext context) {
    final bool isLive = propertyId != null && _isApproved;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: AppColors.primaryGlow,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 28),
              Text(
                isLive
                    ? 'Your listing is live!'
                    : propertyId != null
                    ? 'Listing sent for admin approval'
                    : 'Your listing is ready',
                textAlign: TextAlign.center,
                style: AppTextStyles.heading1.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ).animate().fadeIn(delay: 150.ms, duration: 300.ms),
              const SizedBox(height: 12),
              Text(
                isLive
                    ? 'Your property has been submitted and is now visible to buyers.'
                    : propertyId != null
                    ? 'Your property has been submitted successfully. '
                          'It will go live after admin approval.'
                    : "You've completed every step of the property wizard.",
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ).animate().fadeIn(delay: 250.ms, duration: 300.ms),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: PremiumButton(
                  label: 'Done',
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ).animate().fadeIn(delay: 350.ms, duration: 300.ms),
            ],
          ),
        ),
      ),
    );
  }
}
