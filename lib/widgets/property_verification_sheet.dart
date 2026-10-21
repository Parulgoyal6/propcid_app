// widgets/property_verification_sheet.dart
//
// "Verify with Experts" — the property verification request form.
//
// STRUCTURE IS THE PORTAL'S
// -------------------------
// Field order, labels, placeholders, helper text and button copy all come from
// `features/property/PropertyVerificationModal.tsx:320-620`. That order is
// property-first, identity-last:
//
//   Choose Verification Method  →  UPID | property address + 11 optional fields
//   →  Your Inquiry  →  Your Name*  →  Contact Number* + OTP  →  Submit
//
// ONLY THE SUBMIT BUTTON IS GATED
// -------------------------------
// The portal disables exactly two things: the contact input once the number is
// verified, and the Submit button until it is (`disabled={loading ||
// !otpVerified}`, :617). Every property field stays editable from the moment the
// form opens. An earlier revision of this file dimmed the whole property block
// until the phone was verified, which made the form look interactive and answer
// no taps — that is not in the reference and is not here now.
//
// The hard rule that IS reproduced: `handleSubmit` refuses without a verified
// phone (:231-238), and `handleInputChange` resets
// `otpSent`/`otpVerified`/`otp` whenever the number changes (:66-72), so a
// verified number can never be swapped for an unverified one before submit.
//
// OTP CALLS ARE NOT REIMPLEMENTED
// -------------------------------
// `EdgeFunctionsService` already wraps the same deployed `send-otp` function the
// portal calls, and `Validators.toE164` already normalises the number the way
// that function expects. The portal's inline `normalizePhone` (:80-88) produces
// the same `+91XXXXXXXXXX`, so no second normaliser is introduced.
//
// The row itself is written by `PropertyVerificationService`, which owns the
// UPID/address exclusivity so this sheet cannot leak an abandoned half.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../core/validation/validators.dart';
import '../services/edge_functions_service.dart';
import '../services/property_verification_service.dart';
import 'area_converter_sheet.dart'
    show SheetDragHandle, SheetToolHeader, sheetFieldDecoration;

const double _kSheetRadius = 24;
const double _kFieldRadius = 14;

/// The sheet may grow to this fraction of the viewport. This form is long — the
/// portal's is `max-h-[90vh] overflow-y-auto` — so it scrolls inside that bound
/// rather than pushing its own handle off-screen.
const double _kMaxHeightFraction = 0.9;

/// Cosmetic resend throttle. The edge function does its own rate limiting; this
/// only stops a user tapping Resend six times in two seconds.
const int _kResendCooldownSeconds = 30;

/// Whether the form may be submitted.
///
/// `PropertyVerificationModal.tsx:231-265`'s four guards, in one place: the phone
/// must be verified, there must be a name, and the active path's own required
/// field must be filled. A top-level function rather than a method so the rule
/// can be asserted directly — it is the hard gate this feature is built around,
/// and a UI-only `onTap: null` is not something a test can read.
@visibleForTesting
bool canSubmitVerification({
  required bool otpVerified,
  required String name,
  required bool useUpid,
  required String upid,
  required String propertyAddress,
}) {
  if (!otpVerified) return false;
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) return false;
  // PropertyVerificationModal.tsx:267-274 — same regex as the submit-time
  // "Full name should only contain alphabets" guard in _submit().
  if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmedName)) return false;
  if (useUpid) return upid.trim().isNotEmpty;
  return propertyAddress.trim().isNotEmpty;
}

/// Opens the verification form.
Future<void> showPropertyVerificationSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardBackground,
    barrierColor: AppColors.textPrimary.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(_kSheetRadius)),
    ),
    builder: (_) => const PropertyVerificationSheet(),
  );
}

/// The sheet body. Public only so a widget test can pump it directly.
@visibleForTesting
class PropertyVerificationSheet extends StatefulWidget {
  const PropertyVerificationSheet({super.key});

  @override
  State<PropertyVerificationSheet> createState() =>
      _PropertyVerificationSheetState();
}

class _PropertyVerificationSheetState extends State<PropertyVerificationSheet> {
  final EdgeFunctionsService _functions = EdgeFunctionsService();
  final PropertyVerificationService _service = PropertyVerificationService();

  /// Name/place fields (Your Name, Seller Name, Registered in the Name,
  /// Property Type, Mauja, Tehsil, District, State, Country) — letters and
  /// spaces only, the same character set `PropertyVerificationModal.tsx:543`
  /// strips Your Name down to live (`e.target.value.replace(/[^a-zA-Z\s]/g,
  /// '')`) and the same `FilteringTextInputFormatter.allow` pattern already
  /// used for name fields in `media_contact_step.dart`/`legal_details_step
  /// .dart`. The portal never applied this to the other eight fields, but a
  /// place/type name containing a digit or symbol is invalid input on both
  /// platforms regardless, so it is applied consistently here.
  static final List<TextInputFormatter> _lettersOnly = [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
  ];

  /// Plot/Flat No. and Khasra No. — real-world values look like "12-A",
  /// "45/B" or "Khasra 67/2", so digits, letters, spaces, `-` and `/` are
  /// allowed; anything else (emoji, other punctuation) is not a legitimate
  /// plot/khasra identifier.
  static final List<TextInputFormatter> _plotOrKhasraNo = [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\s\-/]')),
  ];

  // Field set and the "India" default from PropertyVerificationModal.tsx:46-61.
  final TextEditingController _upidController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _sellerNameController = TextEditingController();
  final TextEditingController _registeredInNameController =
      TextEditingController();
  final TextEditingController _plotFlatNoController = TextEditingController();
  final TextEditingController _propertyTypeController = TextEditingController();
  final TextEditingController _colonyNameController = TextEditingController();
  final TextEditingController _khasraNoController = TextEditingController();
  final TextEditingController _maujaController = TextEditingController();
  final TextEditingController _tehsilController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _countryController = TextEditingController(
    text: PropertyVerificationService.defaultCountry,
  );
  final TextEditingController _inquiryController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _useUpid = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _submitting = false;

  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void initState() {
    super.initState();
    // Every control that gates a button re-evaluates on each keystroke: Send
    // unlocks at 10 digits, Verify at 6, Submit on the rule above.
    _phoneController.addListener(_onPhoneChanged);
    _otpController.addListener(_rebuild);
    _nameController.addListener(_rebuild);
    _upidController.addListener(_rebuild);
    _addressController.addListener(_rebuild);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.removeListener(_onPhoneChanged);
    for (final controller in [
      _upidController,
      _addressController,
      _sellerNameController,
      _registeredInNameController,
      _plotFlatNoController,
      _propertyTypeController,
      _colonyNameController,
      _khasraNoController,
      _maujaController,
      _tehsilController,
      _districtController,
      _stateController,
      _countryController,
      _inquiryController,
      _nameController,
      _phoneController,
      _otpController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// `PropertyVerificationModal.tsx:66-72` — any change to the number
  /// invalidates the verification, so a verified number can never be swapped for
  /// another one before submit.
  void _onPhoneChanged() {
    if (_otpSent || _otpVerified || _otpController.text.isNotEmpty) {
      _resendTimer?.cancel();
      _otpController.clear();
      setState(() {
        _otpSent = false;
        _otpVerified = false;
        _resendIn = 0;
      });
      return;
    }
    _rebuild();
  }

  String get _rawPhone => _phoneController.text.replaceAll(RegExp(r'\D'), '');

  bool get _phoneLooksValid => _rawPhone.length == 10;

  /// The submit gate — see [canSubmitVerification].
  bool get _canSubmit => canSubmitVerification(
    otpVerified: _otpVerified,
    name: _nameController.text,
    useUpid: _useUpid,
    upid: _upidController.text,
    propertyAddress: _addressController.text,
  );

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _kResendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
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

  Future<void> _sendOtp() async {
    if (!_phoneLooksValid) {
      // Portal copy, PropertyVerificationModal.tsx:94-95.
      _toast('Please enter a valid 10-digit phone number', isError: true);
      return;
    }

    setState(() => _sendingOtp = true);
    try {
      await _functions.sendOtp(Validators.toE164(_phoneController.text));
      if (!mounted) return;
      setState(() => _otpSent = true);
      _startResendCooldown();
      _toast('OTP sent. Please check your phone for the verification code.');
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _resendOtp() async {
    if (_resendIn > 0) return;
    setState(() => _sendingOtp = true);
    try {
      await _functions.resendOtp(Validators.toE164(_phoneController.text));
      if (!mounted) return;
      _startResendCooldown();
      _toast('OTP resent. Please check your phone for the new code.');
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _toast('Please enter the 6-digit OTP', isError: true);
      return;
    }

    setState(() => _verifyingOtp = true);
    try {
      await _functions.verifyOtp(
        phoneNumber: Validators.toE164(_phoneController.text),
        otp: code,
      );
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _otpVerified = true;
        _resendIn = 0;
      });
      _toast('Phone verified successfully.');
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  /// The portal's four guards in order, each with its own message
  /// (PropertyVerificationModal.tsx:231-265), so a blocked submit says which
  /// field is missing instead of leaving a dead button.
  Future<void> _submit() async {
    if (_submitting) return;

    if (!_otpVerified) {
      _toast(
        'Please verify your phone number before submitting',
        isError: true,
      );
      return;
    }
    if (_useUpid && _upidController.text.trim().isEmpty) {
      _toast('Please provide the UPID', isError: true);
      return;
    }
    if (!_useUpid && _addressController.text.trim().isEmpty) {
      _toast('Please provide either UPID or property address', isError: true);
      return;
    }
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Please provide your name', isError: true);
      return;
    }
    // PropertyVerificationModal.tsx:267-274 — same regex, same message.
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(name)) {
      _toast('Full name should only contain alphabets', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await _service.submit(
        requesterName: _nameController.text,
        contactNumber: _phoneController.text,
        useUpid: _useUpid,
        upid: _upidController.text,
        propertyAddress: _addressController.text,
        sellerName: _sellerNameController.text,
        registeredInName: _registeredInNameController.text,
        plotFlatNo: _plotFlatNoController.text,
        propertyType: _propertyTypeController.text,
        colonyName: _colonyNameController.text,
        khasraNo: _khasraNoController.text,
        mauja: _maujaController.text,
        tehsil: _tehsilController.text,
        district: _districtController.text,
        state: _stateController.text,
        country: _countryController.text,
        inquiryDetails: _inquiryController.text,
      );

      if (!mounted) return;
      Navigator.of(context).maybePop();
      _toast('Verification request submitted. We\'ll contact you soon.');
    } catch (e) {
      // Portal copy, PropertyVerificationModal.tsx:313-315.
      _toast(
        'There was an error submitting your request. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: media.size.height * _kMaxHeightFraction,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: AppConstants.spacingM),
                child: SheetDragHandle(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingXL,
                ),
                child: SheetToolHeader(
                  icon: Icons.verified_user_rounded,
                  // Portal's dialog title (:337).
                  title: 'Property Verification Request',
                  subtitle: 'Our experts will verify and get back to you',
                ),
              ),
              const SizedBox(height: AppConstants.spacingL),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingXL,
                    0,
                    AppConstants.spacingXL,
                    AppConstants.spacingL,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Choose Verification Method (:344-362) ───────────
                      Text(
                        'Choose Verification Method',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingM),
                      Row(
                        children: [
                          Expanded(
                            child: _methodButton(
                              label: 'Use UPID',
                              selected: _useUpid,
                              onTap: () => setState(() => _useUpid = true),
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingM),
                          Expanded(
                            child: _methodButton(
                              label: 'Enter Property Details',
                              selected: !_useUpid,
                              onTap: () => setState(() => _useUpid = false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spacingXL),

                      // ── The chosen path (:365-511) ──────────────────────
                      if (_useUpid)
                        _field(
                          label: 'UPID',
                          required: true,
                          controller: _upidController,
                          hint: 'Enter UPID (e.g., R0123456)',
                          helper:
                              'UPID can be found on the property details '
                              'page for properties listed on PropCID',
                        )
                      else
                        ..._addressPathFields(),

                      const SizedBox(height: AppConstants.spacingS),

                      // ── Common fields (:514-545) ────────────────────────
                      _field(
                        label: 'Your Inquiry',
                        controller: _inquiryController,
                        hint:
                            'Describe what you want to verify about this '
                            'property...',
                        maxLines: 3,
                      ),
                      _field(
                        label: 'Your Name',
                        required: true,
                        controller: _nameController,
                        hint: 'Enter your full name',
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: _lettersOnly,
                      ),
                      _contactField(),
                      if (_otpSent && !_otpVerified) _otpBlock(),
                    ],
                  ),
                ),
              ),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  /// The address path's twelve fields, in the portal's order and with its labels
  /// and placeholders (:384-511).
  ///
  /// Single column. The portal's grid is `grid-cols-1 md:grid-cols-2`, so one
  /// column *is* its mobile rendering — and at 320 dp two of these side by side
  /// would clip labels like "Registered in the Name". All of them stay visible:
  /// the portal hides none of them behind a disclosure.
  List<Widget> _addressPathFields() {
    return [
      _field(
        label: 'Property Address',
        required: true,
        controller: _addressController,
        hint: 'Enter complete property address',
        maxLines: 3,
      ),
      _field(
        label: 'Seller Name',
        controller: _sellerNameController,
        hint: 'Enter seller name',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'Registered in the Name',
        controller: _registeredInNameController,
        hint: 'Enter registered name',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'Plot No/Flat No',
        controller: _plotFlatNoController,
        hint: 'Enter plot or flat number',
        inputFormatters: _plotOrKhasraNo,
      ),
      _field(
        label: 'Property Type',
        controller: _propertyTypeController,
        hint: 'Plot/House/Flat/Land/etc',
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'Colony Name',
        controller: _colonyNameController,
        hint: 'Enter colony name',
        textCapitalization: TextCapitalization.words,
      ),
      _field(
        label: 'Khasra No',
        controller: _khasraNoController,
        hint: 'Enter khasra number',
        inputFormatters: _plotOrKhasraNo,
      ),
      _field(
        label: 'Mauja',
        controller: _maujaController,
        hint: 'Enter mauja',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'Tehsil',
        controller: _tehsilController,
        hint: 'Enter tehsil',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'District',
        controller: _districtController,
        hint: 'Enter district',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'State',
        controller: _stateController,
        hint: 'Enter state',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
      _field(
        label: 'Country',
        controller: _countryController,
        hint: 'Enter country',
        textCapitalization: TextCapitalization.words,
        inputFormatters: _lettersOnly,
      ),
    ];
  }

  /// A labelled field, the portal's `<Label>` + `<Input>` + optional helper `<p>`
  /// composition. Every field on this form has a visible label — none is
  /// placeholder-only.
  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool required = false,
    int maxLines = 1,
    String? helper,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            style: AppTextStyles.body.copyWith(fontSize: 13.5),
            decoration: sheetFieldDecoration(hint: hint),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            Text(
              helper,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A field label, with a red asterisk when the field is required.
  ///
  /// Two `Text` widgets in a `Row` rather than one `RichText`: the label is then
  /// findable by its own exact string, and `Flexible` keeps a long one like
  /// "Registered in the Name" from overflowing at a large text scale.
  Widget _label(String text, {bool required = false}) {
    final style = AppTextStyles.body.copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );

    return Row(
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (required) Text(' *', style: style.copyWith(color: AppColors.error)),
      ],
    );
  }

  /// Contact number + Send/Resend, or a Verified chip once done (:388-424).
  Widget _contactField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Contact Number', required: true),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  // The one input the portal disables, and only once verified
                  // (:397). Editing before that is allowed and clears the OTP
                  // state — see _onPhoneChanged.
                  enabled: !_otpVerified,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: AppTextStyles.body.copyWith(fontSize: 13.5),
                  decoration: sheetFieldDecoration(
                    hint: 'Enter your 10-digit mobile number',
                    enabled: !_otpVerified,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              if (_otpVerified)
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(_kFieldRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Verified',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _smallButton(
                  label: _otpSent ? 'Resend OTP' : 'Send OTP',
                  busy: _sendingOtp,
                  // Resend respects the cooldown; a first send only needs a
                  // complete number (:412).
                  enabled: _phoneLooksValid && (!_otpSent || _resendIn == 0),
                  onTap: _otpSent ? _resendOtp : _sendOtp,
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _otpSent && !_otpVerified && _resendIn > 0
                ? 'You can resend the code in ${_resendIn}s'
                : 'We\'ll contact you on this number with verification details',
            style: AppTextStyles.caption.copyWith(fontSize: 10.5, height: 1.3),
          ),
        ],
      ),
    );
  }

  /// The tinted, bordered OTP block the portal shows once a code is sent
  /// (:578-608).
  Widget _otpBlock() {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Enter OTP'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  style: AppTextStyles.body.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                  textAlign: TextAlign.center,
                  decoration: sheetFieldDecoration(hint: '••••••'),
                ),
              ),
              const SizedBox(width: AppConstants.spacingM),
              _smallButton(
                label: 'Verify',
                busy: _verifyingOtp,
                enabled: _otpController.text.trim().length == 6,
                onTap: _verifyOtp,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Enter the 6-digit OTP sent to your mobile number',
            style: AppTextStyles.caption.copyWith(fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _methodButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 46,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              // Selected is filled, unselected outlined — the portal's
              // `variant={useUpid ? "default" : "outline"}` (:348).
              gradient: selected ? AppColors.primaryGradient : null,
              color: selected ? null : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
              border: Border.all(
                color: selected ? Colors.transparent : AppColors.hairline,
              ),
              boxShadow: selected ? AppColors.primaryGlow : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallButton({
    required String label,
    required bool busy,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final bool live = enabled && !busy;

    return Semantics(
      button: true,
      enabled: live,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: live ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: live ? AppColors.primaryGradient : null,
              color: live ? null : AppColors.hairline,
              borderRadius: BorderRadius.circular(_kFieldRadius),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: AppTextStyles.button.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: live ? Colors.white : AppColors.textHint,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final bool live = _canSubmit && !_submitting;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingXL,
        AppConstants.spacingM,
        AppConstants.spacingXL,
        AppConstants.spacingL,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        children: [
          if (!_otpVerified)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 5),
                  // Flexible, not bare: a Row hands a plain Text unbounded
                  // width, so this line overflows at a large text scale.
                  Flexible(
                    child: Text(
                      'Verify your phone number to submit',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          Semantics(
            button: true,
            enabled: !_submitting,
            label: 'Submit verification request',
            child: ExcludeSemantics(
              child: GestureDetector(
                // Always tappable so the guards above can name the missing
                // field. A dead button that explains nothing is what the portal
                // avoids by validating inside `handleSubmit`.
                onTap: _submitting ? null : _submit,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: live ? AppColors.primaryGradient : null,
                    color: live ? null : AppColors.hairline,
                    borderRadius: BorderRadius.circular(
                      AppConstants.buttonRadius,
                    ),
                    boxShadow: live ? AppColors.primaryGlow : null,
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
                      : Text(
                          'Submit Verification Request',
                          style: AppTextStyles.button.copyWith(
                            fontWeight: FontWeight.w700,
                            color: live ? Colors.white : AppColors.textHint,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
