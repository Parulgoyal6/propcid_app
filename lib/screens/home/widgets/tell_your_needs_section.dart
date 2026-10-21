// screens/home/widgets/tell_your_needs_section.dart
//
// Home's "Tell Your Needs" lead form — an inline section, not a sheet trigger,
// matching how the portal embeds `<LeadForm />` directly in the page.
//
// COPY AND VOCABULARY ARE THE PORTAL'S
// ------------------------------------
// Heading, subtitle, every placeholder, the five budget slugs, the five property
// type slugs, the submit label and the footer reassurance are all
// `features/leads/LeadForm.tsx` verbatim (:325-470 for the fields, :385-431 for
// the option values, :487 and :494 for the button and footer). The slugs are what
// the admin panel filters on, so they are values, not labels — the label is only
// what the user reads.
//
// VALIDATION IS THE PORTAL'S, PLUS A FORMAT CHECK
// -----------------------------------------------
// `LeadForm.tsx:121-128` requires name, phone and budget and shows one combined
// message. That is reproduced exactly, including the wording. It has no phone
// *format* check at all, so a single digit is accepted on the web; this adds
// `Validators.phone` (the app's existing 10-digit rule) because a lead the team
// cannot call back is not a lead. That is stricter than the reference, never
// looser.
//
// On success the form clears and the user stays put — the portal does not
// navigate away either.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/validation/validators.dart';
import '../../../services/requirement_service.dart';
import '../../../widgets/area_converter_sheet.dart' show sheetFieldDecoration;

/// One dropdown option: the slug that is stored, and the label that is shown.
class _Option {
  const _Option(this.value, this.label);

  final String value;
  final String label;
}

/// `LeadForm.tsx:385-393`.
const List<_Option> _kBudgetOptions = [
  _Option('under-50l', 'Under ₹50 Lakhs'),
  _Option('50l-1cr', '₹50L - ₹1 Crore'),
  _Option('1cr-2cr', '₹1 - ₹2 Crores'),
  _Option('2cr-5cr', '₹2 - ₹5 Crores'),
  _Option('above-5cr', 'Above ₹5 Cr'),
];

/// `LeadForm.tsx:423-431`.
const List<_Option> _kPropertyTypeOptions = [
  _Option('apartment', 'Apartment'),
  _Option('villa', 'Villa'),
  _Option('plot', 'Plot/Land'),
  _Option('commercial', 'Commercial'),
  _Option('office', 'Office Space'),
];

class TellYourNeedsSection extends StatefulWidget {
  const TellYourNeedsSection({super.key});

  @override
  State<TellYourNeedsSection> createState() => _TellYourNeedsSectionState();
}

class _TellYourNeedsSectionState extends State<TellYourNeedsSection>
    with AutomaticKeepAliveClientMixin {
  // Preserves the four text controllers/dropdown selections across Home's
  // own scroll — without this, scrolling this section far enough off/on
  // screen disposes and rebuilds it from scratch, clearing whatever the
  // user had already typed.
  @override
  bool get wantKeepAlive => true;

  final RequirementService _service = RequirementService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _requirementsController = TextEditingController();

  String? _budget;
  String? _propertyType;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _requirementsController.dispose();
    super.dispose();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    // The portal's single combined message, word for word (LeadForm.tsx:123).
    if (name.isEmpty || phone.isEmpty || _budget == null) {
      _toast('Please fill in name, phone and budget', isError: true);
      return;
    }

    final String? phoneError = Validators.phone(phone);
    if (phoneError != null) {
      _toast(phoneError, isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.submit(
        name: name,
        phone: phone,
        budget: _budget!,
        propertyType: _propertyType,
        location: _locationController.text,
        requirements: _requirementsController.text,
      );

      if (!mounted) return;
      _toast(
        'Request submitted! Our team will review your requirements and get '
        'back to you soon.',
      );
      _nameController.clear();
      _phoneController.clear();
      _locationController.clear();
      _requirementsController.clear();
      setState(() {
        _budget = null;
        _propertyType = null;
      });
    } catch (e) {
      // Portal copy (LeadForm.tsx:221).
      _toast('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: AppConstants.spacingL),

            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
              ],
              style: AppTextStyles.body.copyWith(fontSize: 13.5),
              decoration: sheetFieldDecoration(hint: 'Your Name*'),
            ),
            const SizedBox(height: AppConstants.spacingM),

            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: AppTextStyles.body.copyWith(fontSize: 13.5),
              decoration: sheetFieldDecoration(hint: 'Contact Number*'),
            ),
            const SizedBox(height: AppConstants.spacingM),

            _dropdown(
              value: _budget,
              hint: 'Budget Range*',
              options: _kBudgetOptions,
              onChanged: (v) => setState(() => _budget = v),
            ),
            const SizedBox(height: AppConstants.spacingM),

            _dropdown(
              value: _propertyType,
              hint: 'Property Type (Optional)',
              options: _kPropertyTypeOptions,
              onChanged: (v) => setState(() => _propertyType = v),
            ),
            const SizedBox(height: AppConstants.spacingM),

            TextField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyles.body.copyWith(fontSize: 13.5),
              decoration: sheetFieldDecoration(
                hint: 'Preferred Location (Optional)',
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),

            TextField(
              controller: _requirementsController,
              maxLines: 4,
              style: AppTextStyles.body.copyWith(fontSize: 13.5),
              decoration: sheetFieldDecoration(
                hint:
                    'Describe your requirements in detail (e.g., number of '
                    'bedrooms, amenities, specific area, etc.)',
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),

            _submitButton(),
            const SizedBox(height: AppConstants.spacingM),
            _footer(),
          ],
        ),
      ),
    );
  }

  /// Two-tone headline, the portal's own split: "Tell" plain, "Your Needs"
  /// accented (LeadForm.tsx:241-246 gradients the second half).
  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            boxShadow: AppColors.primaryGlow,
          ),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: AppTextStyles.heading2.copyWith(fontSize: 19),
                  children: [
                    const TextSpan(text: 'Tell '),
                    TextSpan(
                      text: 'Your Needs',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Share your property requirement and our team will connect '
                'with you shortly.',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<_Option> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(14),
      icon: const Icon(
        Icons.keyboard_arrow_down_rounded,
        color: AppColors.textSecondary,
      ),
      style: AppTextStyles.body.copyWith(
        fontSize: 13.5,
        color: AppColors.textPrimary,
      ),
      hint: Text(
        hint,
        style: AppTextStyles.body.copyWith(
          fontSize: 13,
          color: AppColors.textHint,
        ),
      ),
      decoration: sheetFieldDecoration(),
      items: [
        for (final option in options)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _submitButton() {
    return Semantics(
      button: true,
      enabled: !_submitting,
      label: 'Submit my requirement',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: _submitting ? null : _submit,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              boxShadow: AppColors.primaryGlow,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.send_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        'Submit My Requirement',
                        style: AppTextStyles.button.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.verified_user_rounded,
          size: 13,
          color: AppColors.primary,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Your information is safe and 100% secure with us.',
            style: AppTextStyles.caption.copyWith(fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}
