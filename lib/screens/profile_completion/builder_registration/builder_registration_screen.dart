// screens/profile_completion/builder_registration/builder_registration_screen.dart
//
// Mirrors `BuilderRegistration.tsx` field-for-field: same 7 steps (Personal,
// Company, Address, Documents, Social, Account, Terms), same required-field
// map (`STEP_REQUIRED`), same regex patterns (`PATTERNS`), same option lists
// (`EXPERTISE_OPTIONS` / `LANGUAGE_OPTIONS` / `COUNTRY_CODES`), same upsert
// payload shape (`handleSubmit`).
//
// The portal's old "Step 4: Project Information" has no JSX anywhere in that
// file — `projectName`/`projectType`/… exist only in its TypeScript interface
// and are never submitted. It is dropped here too, not carried over.
//
// Validation is modelled as an imperative `_errors` map keyed by field name,
// computed on "Continue"/"Submit" — not live per-keystroke — because that is
// exactly how the portal's `handleNext`/`handleSubmit` work: errors appear
// only after an advance attempt, not while typing.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/animations/page_transitions.dart';
import '../../../core/utils/registration_password_update.dart';
import '../../../core/utils/text_input_formatters.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/identity_verification_provider.dart';
import '../../profile/actions/logout_dialog.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/identity_verification_service.dart';
import '../../../services/profile_media_service.dart';
import '../../../services/registration_draft_store.dart';
import '../../../services/registration_submit_service.dart';
import '../../../widgets/address_autocomplete_field.dart';
import '../../../widgets/location_picker_map.dart';
import '../../../widgets/verify_identifier_field.dart';
import '../../role_home_router.dart';
import '../../subscription/billing_policies_screen.dart';

// ── Portal constants, transcribed verbatim ──────────────────────────────────
// (`BuilderRegistration.tsx:118-213`)

const List<Map<String, String>> _kCountryCodes = [
  {'code': '+91', 'country': 'India'},
  {'code': '+1', 'country': 'USA'},
  {'code': '+44', 'country': 'UK'},
  {'code': '+61', 'country': 'Australia'},
  {'code': '+971', 'country': 'UAE'},
];

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _mobilePattern = RegExp(r'^[6-9]\d{9}$');
final RegExp _pincodePattern = RegExp(r'^\d{6}$');
final RegExp _websitePattern = RegExp(
  r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b',
);
final RegExp _gstPattern = RegExp(
  r'^\d{2}[A-Z]{5}\d{4}[A-Z]{1}[A-Z\d]{1}[Z]{1}[A-Z\d]{1}$',
);
final RegExp _panPattern = RegExp(r'^[A-Z]{5}\d{4}[A-Z]{1}$');

const List<String> _kCompanyTypes = [
  'Individual',
  'Partnership',
  'LLP',
  'Private Limited',
];

const List<String> _kExpertiseOptions = [
  'Luxury Properties',
  'High-Rise Apartments',
  'Commercial Leasing',
  'Farmhouses & Land',
  'Affordable Housing',
  'First-Time Home Buyers',
  'Industrial Spaces',
  'Real Estate Investment Advisor',
];

const List<String> _kLanguageOptions = [
  'English',
  'Hindi',
  'Marathi',
  'Gujarati',
  'Tamil',
  'Telugu',
  'Kannada',
  'Malayalam',
  'Bengali',
  'Punjabi',
];

const List<String> _kGenderOptions = ['Male', 'Female', 'Other', 'Skip'];

bool _isBlank(String? v) => v == null || v.trim().isEmpty;

class BuilderRegistrationScreen extends StatefulWidget {
  const BuilderRegistrationScreen({super.key});

  @override
  State<BuilderRegistrationScreen> createState() =>
      _BuilderRegistrationScreenState();
}

class _BuilderRegistrationScreenState extends State<BuilderRegistrationScreen> {
  int currentStep = 0;
  bool _isSubmitting = false;
  final Map<String, String> _errors = {};
  final _mediaService = ProfileMediaService();
  final Set<String> _uploading = {};
  final _draftStore = RegistrationDraftStore('builder_registration_draft');

  // ─── Step 1 – Personal Information ───────────────────────────────────────
  final _companyNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _altMobileCtrl = TextEditingController();
  String _countryCode = '+91';
  String _alternateCountryCode = '+91';
  String? _gender;
  final _dobCtrl = TextEditingController();
  String? _avatarUrl;
  String? _companyLogoUrl;
  bool _isEmailUser = false;
  bool _isPhoneUser = false;

  // ─── Step 2 – Company Details ─────────────────────────────────────────────
  String? _companyType;
  final _gstNumberCtrl = TextEditingController();
  final _panNumberCtrl = TextEditingController();
  final _yearsOfExpCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _aboutCompanyCtrl = TextEditingController();
  final List<String> _areasOfExpertise = [];
  final List<String> _languagesKnown = [];
  final _customAreaCtrl = TextEditingController();
  final _customLangCtrl = TextEditingController();

  // ─── Step 3 – Address Information ────────────────────────────────────────
  final _officeAddressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  // Not submitted — mirrors the portal, which only ever uses these to drive
  // the map picker and geocoding, never to populate the profiles upsert.
  double? _pickedLat;
  double? _pickedLng;

  /// True while something OTHER than the user typing is writing
  /// [_officeAddressCtrl]'s text — a resolved map tap/autocomplete pick, or
  /// a restored draft. [_onOfficeAddressChanged] must not mistake any of
  /// those for a manual edit, or it would clear the very coordinates that
  /// same write is setting (or just restored).
  bool _suppressCoordClear = false;

  // ─── Step 4 – Documents ──────────────────────────────────────────────────
  String? _reraCertificateUrl;
  String? _gstCertificateUrl;
  String? _panCardUrl;
  String? _registrationProofUrl;
  // Required by builder-registration-submit but not previously collected at
  // all — the portal's own Step 5 requires both as separate documents.
  String? _aadhaarCardUrl;
  String? _aadhaarCardBackUrl;

  // ─── Step 5 – Social Media ────────────────────────────────────────────────
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _telegramCtrl = TextEditingController();

  // ─── Step 6 – Account Setup ───────────────────────────────────────────────
  // Password is asked for here now, not on auth_screen.dart's sign-up form —
  // that form creates the account with a random placeholder password, and
  // _onSubmit below sets the real one via Supabase's updateUser(password:)
  // once this step is actually submitted.
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  Timer? _usernameDebounce;
  bool? _usernameAvailable;
  bool _usernameTaken = false;

  // ─── Step 7 – Terms ───────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _privacyAccepted = false;

  final List<String> _stepTitles = [
    'Personal Info',
    'Company Details',
    'Address',
    'Documents',
    'Socials',
    'Account',
    'Submit',
  ];

  final List<IconData> _stepIcons = [
    Icons.person_outline,
    Icons.business_outlined,
    Icons.location_on_outlined,
    Icons.description_outlined,
    Icons.share_outlined,
    Icons.lock_outline,
    Icons.verified_outlined,
  ];

  @override
  void initState() {
    super.initState();
    // Mirrors BuilderRegistration.tsx:534-573 — the auth identity the user
    // signed up with is pre-filled and locked so it can't drift from the
    // account it actually belongs to.
    final authUser = Supabase.instance.client.auth.currentUser;
    final rawEmail = authUser?.email;
    final rawPhone = authUser?.phone;

    _isEmailUser =
        rawEmail != null &&
        rawEmail.isNotEmpty &&
        !rawEmail.endsWith('@propcid.app');
    _isPhoneUser =
        (rawPhone != null && rawPhone.isNotEmpty) ||
        (rawEmail != null && rawEmail.endsWith('@propcid.app'));

    if (_isEmailUser) _emailCtrl.text = rawEmail!;
    if (_isPhoneUser) {
      if (rawPhone != null && rawPhone.isNotEmpty) {
        final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
        _mobileCtrl.text = digits.length > 10
            ? digits.substring(digits.length - 10)
            : digits;
      } else if (rawEmail != null) {
        final m = RegExp(r'u(\d+)@').firstMatch(rawEmail);
        if (m != null) _mobileCtrl.text = m.group(1)!;
      }
    }

    _wireDraftAutoSave();
    // Separate from the draft-autosave listener: a manual edit to the
    // office address after a map pin was already dropped must forget that
    // pin, since the old coordinates no longer describe the new text.
    _officeAddressCtrl.addListener(_onOfficeAddressChanged);
    _restoreDraft();

    // Server-verified identity always wins over both the auth-prefill above
    // and whatever a restored draft put into these controllers — see
    // _onIdentityStatusChanged, which runs again on every later status
    // change too (not just the first load), so a verification completed
    // mid-wizard is reflected immediately without re-running _restoreDraft.
    _identityProvider = context.read<IdentityVerificationProvider>();
    _identityProvider.addListener(_onIdentityStatusChanged);
    _identityProvider.ensureLoaded();
    _onIdentityStatusChanged();
  }

  late final IdentityVerificationProvider _identityProvider;

  /// Reconciles the canonical server-verified email/phone (if any) into
  /// `_emailCtrl`/`_mobileCtrl`/`_countryCode` — overriding both the
  /// auth-prefill in `initState` and anything a restored draft set, per the
  /// plan's "canonical identifiers win" requirement. A verified channel is
  /// also locked the same way the old session-presence check used to.
  void _onIdentityStatusChanged() {
    final status = _identityProvider.status;
    if (status == null || !mounted) return;
    final email = status.email;
    final phone = status.phone;

    setState(() {
      if (status.emailVerified) {
        _isEmailUser = true;
        if (email != null && email.isNotEmpty) _emailCtrl.text = email;
      }
      if (status.phoneVerified) {
        _isPhoneUser = true;
        if (phone != null && phone.isNotEmpty) _mobileCtrl.text = phone;
        _countryCode = '+91';
      }
    });
  }

  // ─── Test-only observability ──────────────────────────────────────────────
  // `_emailCtrl`/`_mobileCtrl`/`_countryCode` drive the final-save payload
  // and are otherwise only ever rendered in the review step, many required
  // fields deep in the wizard — these let a widget test confirm draft
  // reconciliation (_onIdentityStatusChanged above) without filling out the
  // entire form to reach that step. No production code reads these.
  @visibleForTesting
  String get debugEmailForTest => _emailCtrl.text;
  @visibleForTesting
  String get debugMobileForTest => _mobileCtrl.text;
  @visibleForTesting
  String get debugCountryCodeForTest => _countryCode;

  // ─── Draft persistence — mirrors the portal's per-wizard localStorage
  // autosave (e.g. BuilderRegistration.tsx:481-491's `autoSave`), restored on
  // reopen so a half-filled form isn't lost between sessions. See
  // RegistrationDraftStore for the save/load/expiry mechanics.
  void _wireDraftAutoSave() {
    for (final c in [
      _companyNameCtrl,
      _emailCtrl,
      _mobileCtrl,
      _altMobileCtrl,
      _dobCtrl,
      _gstNumberCtrl,
      _panNumberCtrl,
      _yearsOfExpCtrl,
      _websiteCtrl,
      _aboutCompanyCtrl,
      _officeAddressCtrl,
      _cityCtrl,
      _stateCtrl,
      _pincodeCtrl,
      _landmarkCtrl,
      _facebookCtrl,
      _instagramCtrl,
      _linkedinCtrl,
      _youtubeCtrl,
      _whatsappCtrl,
      _telegramCtrl,
      _usernameCtrl,
    ]) {
      c.addListener(_scheduleDraftSave);
    }
  }

  void _scheduleDraftSave() => _draftStore.scheduleSave(_draftToJson);

  Map<String, dynamic> _draftToJson() => {
    'currentStep': currentStep,
    'companyName': _companyNameCtrl.text,
    'email': _emailCtrl.text,
    'mobileNumber': _mobileCtrl.text,
    'countryCode': _countryCode,
    'alternateMobileNumber': _altMobileCtrl.text,
    'alternateCountryCode': _alternateCountryCode,
    'gender': _gender ?? '',
    'dob': _dobCtrl.text,
    'avatarUrl': _avatarUrl ?? '',
    'companyLogoUrl': _companyLogoUrl ?? '',
    'companyType': _companyType ?? '',
    'gstNumber': _gstNumberCtrl.text,
    'panNumber': _panNumberCtrl.text,
    'yearsOfExperience': _yearsOfExpCtrl.text,
    'websiteUrl': _websiteCtrl.text,
    'aboutCompany': _aboutCompanyCtrl.text,
    'areasOfExpertise': _areasOfExpertise,
    'languagesKnown': _languagesKnown,
    'officeAddress': _officeAddressCtrl.text,
    'city': _cityCtrl.text,
    'state': _stateCtrl.text,
    'pincode': _pincodeCtrl.text,
    'landmark': _landmarkCtrl.text,
    'pickedLat': _pickedLat,
    'pickedLng': _pickedLng,
    'reraCertificateUrl': _reraCertificateUrl ?? '',
    'gstCertificateUrl': _gstCertificateUrl ?? '',
    'panCardUrl': _panCardUrl ?? '',
    'registrationProofUrl': _registrationProofUrl ?? '',
    'aadhaarCardUrl': _aadhaarCardUrl ?? '',
    'aadhaarCardBackUrl': _aadhaarCardBackUrl ?? '',
    'facebookUrl': _facebookCtrl.text,
    'instagramUrl': _instagramCtrl.text,
    'linkedinUrl': _linkedinCtrl.text,
    'youtubeUrl': _youtubeCtrl.text,
    'whatsappNumber': _whatsappCtrl.text,
    'telegramUrl': _telegramCtrl.text,
    'username': _usernameCtrl.text,
    'termsAccepted': _termsAccepted,
    'privacyAccepted': _privacyAccepted,
  };

  Future<void> _restoreDraft() async {
    final data = await _draftStore.load();
    if (!mounted || data == null) return;

    String s(String key) => data[key] as String? ?? '';
    List<String> l(String key) =>
        (data[key] as List<dynamic>?)?.cast<String>() ?? const [];

    _suppressCoordClear = true;
    setState(() {
      final step = data['currentStep'] as int?;
      if (step != null && step >= 0 && step < _stepTitles.length)
        currentStep = step;

      if (s('companyName').isNotEmpty) _companyNameCtrl.text = s('companyName');
      if (s('email').isNotEmpty) _emailCtrl.text = s('email');
      if (s('mobileNumber').isNotEmpty) _mobileCtrl.text = s('mobileNumber');
      if (s('countryCode').isNotEmpty) _countryCode = s('countryCode');
      if (s('alternateMobileNumber').isNotEmpty) {
        _altMobileCtrl.text = s('alternateMobileNumber');
      }
      if (s('alternateCountryCode').isNotEmpty) {
        _alternateCountryCode = s('alternateCountryCode');
      }
      if (s('gender').isNotEmpty) _gender = s('gender');
      if (s('dob').isNotEmpty) _dobCtrl.text = s('dob');
      if (s('avatarUrl').isNotEmpty) _avatarUrl = s('avatarUrl');
      if (s('companyLogoUrl').isNotEmpty) _companyLogoUrl = s('companyLogoUrl');

      if (s('companyType').isNotEmpty) _companyType = s('companyType');
      if (s('gstNumber').isNotEmpty) _gstNumberCtrl.text = s('gstNumber');
      if (s('panNumber').isNotEmpty) _panNumberCtrl.text = s('panNumber');
      if (s('yearsOfExperience').isNotEmpty) {
        _yearsOfExpCtrl.text = s('yearsOfExperience');
      }
      if (s('websiteUrl').isNotEmpty) _websiteCtrl.text = s('websiteUrl');
      if (s('aboutCompany').isNotEmpty)
        _aboutCompanyCtrl.text = s('aboutCompany');
      final expertise = l('areasOfExpertise');
      if (expertise.isNotEmpty) {
        _areasOfExpertise
          ..clear()
          ..addAll(expertise);
      }
      final languages = l('languagesKnown');
      if (languages.isNotEmpty) {
        _languagesKnown
          ..clear()
          ..addAll(languages);
      }

      if (s('officeAddress').isNotEmpty)
        _officeAddressCtrl.text = s('officeAddress');
      if (s('city').isNotEmpty) _cityCtrl.text = s('city');
      if (s('state').isNotEmpty) _stateCtrl.text = s('state');
      if (s('pincode').isNotEmpty) _pincodeCtrl.text = s('pincode');
      if (s('landmark').isNotEmpty) _landmarkCtrl.text = s('landmark');
      _pickedLat = (data['pickedLat'] as num?)?.toDouble() ?? _pickedLat;
      _pickedLng = (data['pickedLng'] as num?)?.toDouble() ?? _pickedLng;

      if (s('reraCertificateUrl').isNotEmpty) {
        _reraCertificateUrl = s('reraCertificateUrl');
      }
      if (s('gstCertificateUrl').isNotEmpty) {
        _gstCertificateUrl = s('gstCertificateUrl');
      }
      if (s('panCardUrl').isNotEmpty) _panCardUrl = s('panCardUrl');
      if (s('registrationProofUrl').isNotEmpty) {
        _registrationProofUrl = s('registrationProofUrl');
      }
      if (s('aadhaarCardUrl').isNotEmpty) _aadhaarCardUrl = s('aadhaarCardUrl');
      if (s('aadhaarCardBackUrl').isNotEmpty) {
        _aadhaarCardBackUrl = s('aadhaarCardBackUrl');
      }

      if (s('facebookUrl').isNotEmpty) _facebookCtrl.text = s('facebookUrl');
      if (s('instagramUrl').isNotEmpty) _instagramCtrl.text = s('instagramUrl');
      if (s('linkedinUrl').isNotEmpty) _linkedinCtrl.text = s('linkedinUrl');
      if (s('youtubeUrl').isNotEmpty) _youtubeCtrl.text = s('youtubeUrl');
      if (s('whatsappNumber').isNotEmpty)
        _whatsappCtrl.text = s('whatsappNumber');
      if (s('telegramUrl').isNotEmpty) _telegramCtrl.text = s('telegramUrl');

      if (s('username').isNotEmpty) _usernameCtrl.text = s('username');
      _termsAccepted = data['termsAccepted'] as bool? ?? _termsAccepted;
      _privacyAccepted = data['privacyAccepted'] as bool? ?? _privacyAccepted;
    });
    _suppressCoordClear = false;

    // The draft just unconditionally overwrote email/mobile/countryCode
    // above. If identity status had ALREADY loaded and _onIdentityStatusChanged
    // had already applied the canonical verified value before this (async)
    // restore finished — a real ordering this app allows, not a hypothetical
    // — that value is now clobbered, and nothing would otherwise re-fire
    // this reconciliation (it's listener-driven, and the status isn't
    // changing again). Re-running it here, unconditionally, re-asserts the
    // canonical value regardless of which of the two async loads finished
    // last. A no-op if status still isn't loaded yet.
    _onIdentityStatusChanged();
  }

  // ─── Navigation ───────────────────────────────────────────────────────────
  void _nextStep() {
    final stepErrors = switch (currentStep) {
      0 => _validateStep0(),
      1 => _validateStep1(),
      2 => _validateStep2(),
      3 => _validateStep3(),
      4 => _validateStep4(),
      5 => _validateStep5(),
      _ => <String, String>{},
    };

    setState(() {
      _errors.clear();
      _errors.addAll(stepErrors);
    });

    if (stepErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill all required fields and verify formats correctly.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (currentStep < _stepTitles.length - 1) {
      setState(() => currentStep++);
      _scheduleDraftSave();
    }
  }

  void _previousStep() {
    if (currentStep > 0) {
      setState(() {
        currentStep--;
        _errors.clear();
      });
      _scheduleDraftSave();
    }
  }

  // ─── Per-step validation — mirrors STEP_REQUIRED + the custom checks in
  // BuilderRegistration.tsx:786-875 ─────────────────────────────────────────
  Map<String, String> _validateStep0() {
    final e = <String, String>{};
    if (_isBlank(_companyNameCtrl.text))
      e['companyName'] = 'Company name is required.';
    if (_isBlank(_emailCtrl.text)) {
      e['email'] = 'Email address is required.';
    } else if (!_emailPattern.hasMatch(_emailCtrl.text.trim())) {
      e['email'] = 'Please enter a valid email address.';
    }
    if (_isBlank(_mobileCtrl.text)) {
      e['mobileNumber'] = 'Mobile number is required.';
    } else {
      final digits = _mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (_countryCode == '+91') {
        if (!_mobilePattern.hasMatch(digits)) {
          e['mobileNumber'] = 'Mobile number must be a valid 10-digit number.';
        }
      } else if (digits.length < 8 || digits.length > 12) {
        e['mobileNumber'] = 'Phone number must be between 8 and 12 digits.';
      }
    }
    if (_altMobileCtrl.text.trim().isNotEmpty) {
      final digits = _altMobileCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (_alternateCountryCode == '+91') {
        if (!_mobilePattern.hasMatch(digits)) {
          e['alternateMobileNumber'] =
              'Alternate number must be a valid 10-digit Indian mobile number.';
        }
      } else if (digits.length < 8 || digits.length > 12) {
        e['alternateMobileNumber'] =
            'Alternate number must be between 8 and 12 digits.';
      }
    }
    // Format being well-formed is not the same as server-verified — both
    // the real email and the primary phone must be proven via OTP before
    // this step (and final submission, re-checked in _onSubmit) can pass.
    if (!(_identityProvider.status?.bothVerified ?? false)) {
      e['identityVerification'] =
          'Please verify your email and phone number above to continue.';
    }
    if (_gender == null || _gender!.isEmpty)
      e['gender'] = 'Gender is required.';
    if (_isBlank(_dobCtrl.text)) {
      e['dob'] = 'Date of birth is required.';
    } else if (!_isAtLeast18(_dobCtrl.text.trim())) {
      e['dob'] = 'You must be at least 18 years old to register.';
    }
    if ((_avatarUrl ?? '').isEmpty)
      e['avatarUrl'] = 'Profile photo is required.';
    if ((_companyLogoUrl ?? '').isEmpty) {
      e['companyLogoUrl'] = 'Company logo is required.';
    }
    return e;
  }

  Map<String, String> _validateStep1() {
    final e = <String, String>{};
    if (_companyType == null || _companyType!.isEmpty) {
      e['companyType'] = 'Company type is required.';
    }
    if (_isBlank(_gstNumberCtrl.text)) {
      e['gstNumber'] = 'GST number is required.';
    } else if (!_gstPattern.hasMatch(_gstNumberCtrl.text.trim())) {
      e['gstNumber'] = 'GST Number must be a valid 15-character GSTIN format.';
    }
    if (_isBlank(_panNumberCtrl.text)) {
      e['panNumber'] = 'PAN number is required.';
    } else if (!_panPattern.hasMatch(_panNumberCtrl.text.trim())) {
      e['panNumber'] = 'PAN Card must be a valid 10-character PAN format.';
    }
    if (_isBlank(_yearsOfExpCtrl.text)) {
      e['yearsOfExperience'] = 'Years of experience is required.';
    }
    if (_areasOfExpertise.isEmpty) {
      e['areasOfExpertise'] = 'Areas of expertise is required.';
    }
    if (_languagesKnown.isEmpty)
      e['languagesKnown'] = 'Languages known is required.';
    if (_isBlank(_aboutCompanyCtrl.text)) {
      e['aboutCompany'] = 'About the company is required.';
    }
    return e;
  }

  Map<String, String> _validateStep2() {
    final e = <String, String>{};
    if (_isBlank(_officeAddressCtrl.text))
      e['officeAddress'] = 'Office address is required.';
    if (_isBlank(_cityCtrl.text)) e['city'] = 'City is required.';
    if (_isBlank(_stateCtrl.text)) e['state'] = 'State is required.';
    if (_isBlank(_pincodeCtrl.text)) {
      e['pincode'] = 'Pincode is required.';
    } else if (!_pincodePattern.hasMatch(_pincodeCtrl.text.trim())) {
      e['pincode'] = 'Pincode must be a 6-digit number.';
    }
    return e;
  }

  Map<String, String> _validateStep3() {
    // No RERA certificate upload for builders — the portal's Step 5
    // (BuilderRegistration.tsx) never collects one. GST certificate, PAN,
    // company registration proof, and Aadhaar (front/back) are all optional
    // uploads — nothing in this step blocks submission.
    return <String, String>{};
  }

  Map<String, String> _validateStep4() {
    final e = <String, String>{};
    if (_facebookCtrl.text.trim().isNotEmpty &&
        !_websitePattern.hasMatch(_facebookCtrl.text.trim())) {
      e['facebookUrl'] = 'Invalid URL format.';
    }
    if (_instagramCtrl.text.trim().isNotEmpty &&
        !_websitePattern.hasMatch(_instagramCtrl.text.trim())) {
      e['instagramUrl'] = 'Invalid URL format.';
    }
    if (_linkedinCtrl.text.trim().isNotEmpty &&
        !_websitePattern.hasMatch(_linkedinCtrl.text.trim())) {
      e['linkedinUrl'] = 'Invalid URL format.';
    }
    if (_youtubeCtrl.text.trim().isNotEmpty &&
        !_websitePattern.hasMatch(_youtubeCtrl.text.trim())) {
      e['youtubeUrl'] = 'Invalid URL format.';
    }
    return e;
  }

  Map<String, String> _validateStep5() {
    final e = <String, String>{};
    final username = _usernameCtrl.text.trim();
    if (username.length < 3) {
      e['username'] = 'Username must be at least 3 characters.';
    } else if (_usernameAvailable == null) {
      e['username'] = 'Checking username availability. Please wait.';
    } else if (_usernameTaken) {
      e['username'] = 'This username is already taken.';
    }
    final passwordErr = _validatePassword();
    if (passwordErr != null) e['password'] = passwordErr;
    return e;
  }

  /// Same rule the sign-up form used to enforce directly (auth_screen.dart)
  /// before password collection moved here.
  String? _validatePassword() {
    if (_passwordCtrl.text.isEmpty) return 'Password is required.';
    if (_passwordCtrl.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_confirmPasswordCtrl.text.isEmpty)
      return 'Please confirm your password.';
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  // ─── Username availability — mirrors BuilderRegistration.tsx:493-528 ─────
  void _onUsernameChanged(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    if (cleaned != value) {
      _usernameCtrl.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
      return; // the recursive onChanged(cleaned) call handles the debounce
    }

    _usernameDebounce?.cancel();
    if (cleaned.length < 3) {
      setState(() {
        _usernameAvailable = null;
        _usernameTaken = false;
      });
      return;
    }
    _usernameDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _checkUsername(cleaned),
    );
    setState(() {}); // repaint the suffix icon while the debounce is pending
  }

  Future<void> _checkUsername(String username) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('username, user_id')
          .eq('username', username)
          .maybeSingle();
      if (!mounted) return;
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final taken = data != null && data['user_id'] != currentUserId;
      setState(() {
        _usernameTaken = taken;
        _usernameAvailable = !taken;
      });
    } catch (e) {
      debugPrint('Username availability check failed: $e');
    }
  }

  // ─── Uploads — real files via ProfileMediaService, replacing the old
  // placeholder-string assignments ──────────────────────────────────────────
  Future<void> _pickAndUploadAvatar() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _uploading.add('avatarUrl'));
    try {
      final file = await _mediaService.pickAvatar();
      if (file == null) return;
      final url = await _mediaService.uploadAvatar(userId: userId, file: file);
      if (mounted) {
        setState(() => _avatarUrl = url);
        _scheduleDraftSave();
      }
    } catch (e) {
      _showUploadError(e);
    } finally {
      if (mounted) setState(() => _uploading.remove('avatarUrl'));
    }
  }

  /// Handles the company logo and all four verification documents — every
  /// kind other than the avatar goes through `uploadDocument`, which returns
  /// the URL without writing it anywhere (see ProfileMediaService's
  /// docstring); this screen holds the URL locally and sends it with the rest
  /// of the form on submit.
  Future<void> _pickAndUploadDocument(
    String fieldKey,
    ProfileDocumentKind kind,
  ) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _uploading.add(fieldKey));
    try {
      final file = await _mediaService.pickDocument();
      if (file == null) return;
      final url = await _mediaService.uploadDocument(
        userId: userId,
        kind: kind,
        file: file,
      );
      if (!mounted) return;
      setState(() {
        switch (fieldKey) {
          case 'companyLogoUrl':
            _companyLogoUrl = url;
          case 'reraCertificateUrl':
            _reraCertificateUrl = url;
          case 'gstCertificateUrl':
            _gstCertificateUrl = url;
          case 'panCardUrl':
            _panCardUrl = url;
          case 'registrationProofUrl':
            _registrationProofUrl = url;
          case 'aadhaarCardUrl':
            _aadhaarCardUrl = url;
          case 'aadhaarCardBackUrl':
            _aadhaarCardBackUrl = url;
        }
      });
      _scheduleDraftSave();
    } catch (e) {
      _showUploadError(e);
    } finally {
      if (mounted) setState(() => _uploading.remove(fieldKey));
    }
  }

  void _showUploadError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
    );
  }

  // ─── Pill pickers — mirrors handleToggleArrayItem / handleAddCustomPill /
  // handleRemoveArrayItem (BuilderRegistration.tsx:579-602) ─────────────────
  void _toggleExpertise(String item) {
    setState(() {
      _areasOfExpertise.contains(item)
          ? _areasOfExpertise.remove(item)
          : _areasOfExpertise.add(item);
    });
    _scheduleDraftSave();
  }

  void _removeExpertise(String item) {
    setState(() => _areasOfExpertise.remove(item));
    _scheduleDraftSave();
  }

  void _addCustomExpertise(String value) {
    final v = value.trim();
    _customAreaCtrl.clear();
    if (v.isEmpty || _areasOfExpertise.contains(v)) return;
    setState(() => _areasOfExpertise.add(v));
    _scheduleDraftSave();
  }

  void _toggleLanguage(String item) {
    setState(() {
      _languagesKnown.contains(item)
          ? _languagesKnown.remove(item)
          : _languagesKnown.add(item);
    });
    _scheduleDraftSave();
  }

  void _removeLanguage(String item) {
    setState(() => _languagesKnown.remove(item));
    _scheduleDraftSave();
  }

  void _addCustomLanguage(String value) {
    final v = value.trim();
    _customLangCtrl.clear();
    if (v.isEmpty || _languagesKnown.contains(v)) return;
    setState(() => _languagesKnown.add(v));
    _scheduleDraftSave();
  }

  // ─── Date picker ──────────────────────────────────────────────────────────
  /// True when [dobText] (`yyyy-MM-dd`) is a valid date at least 18 years
  /// before today. Invalid/unparseable text fails closed (returns false).
  bool _isAtLeast18(String dobText) {
    final dob = DateTime.tryParse(dobText);
    if (dob == null) return false;
    final now = DateTime.now();
    final eighteenthBirthday = DateTime(dob.year + 18, dob.month, dob.day);
    return !eighteenthBirthday.isAfter(now);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final maxDob = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 30),
      firstDate: DateTime(1950),
      lastDate: maxDob,
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text =
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}';
      });
      _scheduleDraftSave();
    }
  }

  // ─── Map picker — mirrors BuilderRegistration.tsx:626-641's
  // handleLocationSelect: keep the existing value when the geocode result
  // didn't resolve that field, exactly like `addressDetails?.city || prev.city`.
  // [updateOfficeAddress] is false for the autocomplete field's selections:
  // it already wrote the full selected description into the controller
  // itself (matching the portal's officeAddressAutocompleteRef, which fills
  // `officeAddress` with `place.formatted_address`) — overwriting it here
  // with the shorter parsed `addressLine1` would fight that. The map tap
  // path has no such pre-filled text, so it still wants this.
  void _onLocationSelected(
    double lat,
    double lng,
    GeocodedAddress? address, {
    bool updateOfficeAddress = true,
  }) {
    _suppressCoordClear = true;
    setState(() {
      _pickedLat = lat;
      _pickedLng = lng;
      if (updateOfficeAddress) {
        // Prefer the complete formatted address over the narrower
        // addressLine1 (route + street number only, or a lossy
        // first-comma-segment fallback) — a tapped pin should read as a
        // real address, not just a street name.
        final full = address?.formattedAddress?.trim();
        final line1 = address?.addressLine1?.trim();
        final text = (full != null && full.isNotEmpty) ? full : line1;
        if (text != null && text.isNotEmpty) _officeAddressCtrl.text = text;
      }
      if ((address?.city ?? '').isNotEmpty) _cityCtrl.text = address!.city!;
      if ((address?.state ?? '').isNotEmpty) _stateCtrl.text = address!.state!;
      if ((address?.pincode ?? '').isNotEmpty)
        _pincodeCtrl.text = address!.pincode!;
      if ((address?.landmark ?? '').isNotEmpty)
        _landmarkCtrl.text = address!.landmark!;
      _errors.remove('officeAddress');
      _errors.remove('city');
      _errors.remove('state');
      _errors.remove('pincode');
    });
    _suppressCoordClear = false;
    _scheduleDraftSave();
  }

  /// Forgets a previously-dropped pin the moment the office address no
  /// longer matches it — a manual edit with no accompanying map tap or
  /// autocomplete pick. Guarded by [_suppressCoordClear] so
  /// [_onLocationSelected]'s own programmatic write, and a restored draft,
  /// never trip this.
  void _onOfficeAddressChanged() {
    if (_suppressCoordClear) return;
    if (_pickedLat != null || _pickedLng != null) {
      setState(() {
        _pickedLat = null;
        _pickedLng = null;
      });
    }
  }

  /// A tapped suggestion's place-details lookup failed — the office address
  /// field already shows that suggestion's full text (written before the
  /// lookup even started), but no coordinates were ever resolved for it.
  void _onPlaceSelectionFailed() {
    _suppressCoordClear = false;
    if (_pickedLat != null || _pickedLng != null) {
      setState(() {
        _pickedLat = null;
        _pickedLng = null;
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't resolve that address. Please pick a suggestion again "
          'or tap the map to set the location.',
        ),
      ),
    );
  }

  /// Builds the exact `form` map sent to `builder-registration-submit`.
  /// Extracted (not inlined in `_onSubmit`) so a test can assert every key
  /// the backend's `REQUIRED_FIELDS`/write logic actually reads is present
  /// and correctly named, without driving the whole wizard through a submit.
  @visibleForTesting
  Map<String, dynamic> buildSubmitFormForTest(String fullName) => {
    'fullName': fullName,
    'companyName': _companyNameCtrl.text.trim(),
    'email': _emailCtrl.text.trim(),
    'mobileNumber': _mobileCtrl.text.trim(),
    'alternateMobileNumber': _altMobileCtrl.text.trim(),
    'gender': _gender ?? '',
    'dob': _dobCtrl.text.trim(),
    'avatarUrl': _avatarUrl ?? '',
    'companyLogoUrl': _companyLogoUrl ?? '',
    'companyType': _companyType ?? '',
    'gstNumber': _gstNumberCtrl.text.trim(),
    'panNumber': _panNumberCtrl.text.trim(),
    'yearsOfExperience': _yearsOfExpCtrl.text.trim(),
    'websiteUrl': _websiteCtrl.text.trim(),
    'aboutCompany': _aboutCompanyCtrl.text.trim(),
    'areasOfExpertise': _areasOfExpertise,
    'languagesKnown': _languagesKnown,
    'officeAddress': _officeAddressCtrl.text.trim(),
    'city': _cityCtrl.text.trim(),
    'state': _stateCtrl.text.trim(),
    'pincode': _pincodeCtrl.text.trim(),
    'landmark': _landmarkCtrl.text.trim(),
    'gstCertificateUrl': _gstCertificateUrl ?? '',
    'panCardUrl': _panCardUrl ?? '',
    'registrationProofUrl': _registrationProofUrl ?? '',
    'aadhaarCardUrl': _aadhaarCardUrl ?? '',
    'aadhaarCardBackUrl': _aadhaarCardBackUrl ?? '',
    'facebookUrl': _facebookCtrl.text.trim(),
    'instagramUrl': _instagramCtrl.text.trim(),
    'linkedinUrl': _linkedinCtrl.text.trim(),
    'youtubeUrl': _youtubeCtrl.text.trim(),
    'whatsappNumber': _whatsappCtrl.text.trim(),
    'telegramUrl': _telegramCtrl.text.trim(),
    'username': _usernameCtrl.text.trim(),
  };

  // ─── Submit — mirrors BuilderRegistration.tsx:908-1021 ───────────────────
  Future<void> _onSubmit() async {
    // Re-checked here, not just on the personal-info step's Continue — a
    // resumed draft can land straight on the review step with both fields
    // still showing unverified.
    if (!(_identityProvider.status?.bothVerified ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please verify your email and phone number first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_termsAccepted || !_privacyAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the Terms & Conditions and Privacy Policy.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final passwordErr = _validatePassword();
    if (passwordErr != null) {
      setState(() => _errors['password'] = passwordErr);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordErr), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Sets the real, person-chosen password over the random placeholder
      // auth_screen.dart's sign-up created the account with. `same_password`
      // means a previous, partially-successful submit already set this exact
      // password — not a real failure, so registration still proceeds; every
      // other auth error still aborts before anything is submitted.
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: _passwordCtrl.text),
        );
      } on AuthException catch (e) {
        if (!isHarmlessSamePasswordError(e)) rethrow;
      }
      if (!mounted) return;

      // Phase 2: the portal's own backend validation/identity gate/username
      // check, instead of a direct client-side upsert the server never saw.
      // `fullName` is the real person's name already collected on
      // AccountTypeScreen (AuthProvider.userName) — distinct from
      // `companyName` below, and never re-asked here.
      final fullName = context.read<AuthProvider>().userName;
      await RegistrationSubmitService().builderSubmit(
        form: buildSubmitFormForTest(fullName),
        countryCode: _countryCode,
        alternateCountryCode: _alternateCountryCode,
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
        basicInfoFullName: fullName,
      );

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_user_type');
      await prefs.remove('pending_user_type_uid');
      await _draftStore.clear();
      await context.read<AuthProvider>().refreshProfile();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Builder profile saved successfully'),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleHomeRouter()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── Shared UI widgets ────────────────────────────────────────────────────
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    String? hint,
    Widget? suffix,
    Widget? prefix,
    bool hasError = false,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hint,
      suffixIcon: suffix,
      prefixIcon: prefix,
      filled: true,
      fillColor: scheme.surfaceVariant.withOpacity(0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? scheme.error : scheme.outline.withOpacity(0.3),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: hasError ? scheme.error : scheme.primary,
          width: 2,
        ),
      ),
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _errorText(String fieldKey) {
    final msg = _errors[fieldKey];
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.red),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String fieldKey,
    required TextEditingController controller,
    required String label,
    bool required = false,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    bool obscureText = false,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    void Function(String)? onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLines: maxLines,
            obscureText: obscureText,
            readOnly: readOnly,
            onTap: onTap,
            onChanged: onChanged,
            enabled: enabled,
            decoration: _inputDecoration(
              required ? '$label *' : label,
              hint: hint,
              suffix: suffixIcon,
              hasError: _errors.containsKey(fieldKey),
            ),
          ),
          _errorText(fieldKey),
        ],
      ),
    );
  }

  Widget _dropdown({
    required String fieldKey,
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: value,
            decoration: _inputDecoration(
              required ? '$label *' : label,
              hasError: _errors.containsKey(fieldKey),
            ),
            items: items
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onChanged,
          ),
          _errorText(fieldKey),
        ],
      ),
    );
  }

  Widget _phoneField({
    required String fieldKey,
    required TextEditingController controller,
    required String label,
    required String countryCode,
    required void Function(String) onCountryChanged,
    bool enabled = true,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  value: countryCode,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  decoration: _inputDecoration(
                    '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                  ),
                  items: _kCountryCodes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['code'],
                          child: Text(
                            c['code']!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: enabled
                      ? (v) {
                          if (v != null) onCountryChanged(v);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration(
                    required ? '$label *' : label,
                    hasError: _errors.containsKey(fieldKey),
                  ),
                ),
              ),
            ],
          ),
          _errorText(fieldKey),
        ],
      ),
    );
  }

  Widget _uploadCard({
    required String fieldKey,
    required String label,
    required String? url,
    required VoidCallback onTap,
    bool required = false,
    String subtitle = '',
    bool isImagePreview = false,
  }) {
    final busy = _uploading.contains(fieldKey);
    final has = (url ?? '').isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          GestureDetector(
            onTap: busy ? null : onTap,
            child: Container(
              height: 108,
              width: double.infinity,
              decoration: BoxDecoration(
                color: scheme.surfaceVariant.withOpacity(0.4),
                border: Border.all(
                  color: _errors.containsKey(fieldKey)
                      ? scheme.error
                      : (has
                            ? scheme.primary
                            : scheme.outline.withOpacity(0.4)),
                  width: has ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: busy
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(height: 8),
                          Text('Uploading...', style: TextStyle(fontSize: 12)),
                        ],
                      )
                    : has
                    ? (isImagePreview
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url!,
                                height: 64,
                                width: 64,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 30,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Uploaded',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.upload_file,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tap to upload',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          _errorText(fieldKey),
        ],
      ),
    );
  }

  Widget _pillPicker({
    required String fieldKey,
    required String label,
    required List<String> selected,
    required List<String> options,
    required TextEditingController customCtrl,
    required void Function(String) onToggle,
    required void Function(String) onRemove,
    required void Function(String) onAddCustom,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceVariant.withOpacity(0.3),
              border: Border.all(color: scheme.outline.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: selected.isEmpty
                ? Text(
                    'Select from below or add a custom entry',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selected
                        .map(
                          (s) => Chip(
                            label: Text(
                              s,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                            onDeleted: () => onRemove(s),
                            deleteIcon: const Icon(Icons.close, size: 14),
                          ),
                        )
                        .toList(),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: customCtrl,
                  decoration: _inputDecoration('Add custom...'),
                  onSubmitted: onAddCustom,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => onAddCustom(customCtrl.text),
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options
                .where((o) => !selected.contains(o))
                .map(
                  (o) => ActionChip(
                    label: Text(
                      '+ $o',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                    ),
                    onPressed: () => onToggle(o),
                  ),
                )
                .toList(),
          ),
          _errorText(fieldKey),
        ],
      ),
    );
  }

  // ─── Progress Header ──────────────────────────────────────────────────────
  Widget _buildProgressHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _stepTitles[currentStep],
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${currentStep + 1} / ${_stepTitles.length}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (currentStep + 1) / _stepTitles.length,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ─── Step 1 — Personal & Primary Information ─────────────────────────────
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Personal & Primary Information'),
        _field(
          fieldKey: 'companyName',
          controller: _companyNameCtrl,
          label: 'Builder/Company Name',
          required: true,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: VerifyIdentifierField(
            channel: IdentityChannel.email,
            label: 'Email Address',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
            normalizeTarget: (raw) => raw.trim(),
            fieldValidator: (raw) => _emailPattern.hasMatch(raw.trim())
                ? null
                : 'Enter a valid email address.',
            externalError: _errors['email'],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: VerifyIdentifierField(
            channel: IdentityChannel.phone,
            label: 'Phone Number',
            hint: '10-digit mobile number',
            keyboardType: TextInputType.phone,
            prefixText: '+91  ',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            normalizeTarget: (raw) => raw.trim(),
            fieldValidator: (raw) => _mobilePattern.hasMatch(raw.trim())
                ? null
                : 'Enter a valid 10-digit mobile number.',
            externalError: _errors['mobileNumber'],
          ),
        ),
        _errorText('identityVerification'),
        _phoneField(
          fieldKey: 'alternateMobileNumber',
          controller: _altMobileCtrl,
          label: 'Alternate Mobile Number',
          countryCode: _alternateCountryCode,
          onCountryChanged: (v) {
            setState(() => _alternateCountryCode = v);
            _scheduleDraftSave();
          },
        ),
        _label('Gender', required: true),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kGenderOptions.map((g) {
            final selected = _gender == g;
            return ChoiceChip(
              label: Text(g == 'Skip' ? 'N/A' : g),
              selected: selected,
              onSelected: (_) {
                setState(() => _gender = g);
                _scheduleDraftSave();
              },
            );
          }).toList(),
        ),
        _errorText('gender'),
        const SizedBox(height: 16),
        _field(
          fieldKey: 'dob',
          controller: _dobCtrl,
          label: 'Date of Birth',
          required: true,
          readOnly: true,
          onTap: _pickDob,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        _buildSectionTitle('Photos'),
        _uploadCard(
          fieldKey: 'avatarUrl',
          label: 'Profile Photo',
          url: _avatarUrl,
          onTap: _pickAndUploadAvatar,
          required: true,
          isImagePreview: true,
        ),
        _uploadCard(
          fieldKey: 'companyLogoUrl',
          label: 'Company Logo',
          url: _companyLogoUrl,
          onTap: () => _pickAndUploadDocument(
            'companyLogoUrl',
            ProfileDocumentKind.companyLogo,
          ),
          required: true,
          isImagePreview: true,
        ),
      ],
    );
  }

  // ─── Step 2 — Company Details & Registrations ────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Company Details & Registrations'),
        _dropdown(
          fieldKey: 'companyType',
          label: 'Company Type',
          value: _companyType,
          items: _kCompanyTypes,
          onChanged: (v) {
            setState(() => _companyType = v);
            _scheduleDraftSave();
          },
          required: true,
        ),
        _field(
          fieldKey: 'gstNumber',
          controller: _gstNumberCtrl,
          label: 'GST Number',
          required: true,
          hint: '15-digit GSTIN',
          inputFormatters: [
            const UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(15),
          ],
        ),
        _field(
          fieldKey: 'panNumber',
          controller: _panNumberCtrl,
          label: 'PAN Number',
          required: true,
          hint: '10-character PAN number',
          inputFormatters: [
            const UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        _field(
          fieldKey: 'yearsOfExperience',
          controller: _yearsOfExpCtrl,
          label: 'Years of Experience',
          required: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _pillPicker(
          fieldKey: 'areasOfExpertise',
          label: 'Areas of Expertise',
          selected: _areasOfExpertise,
          options: _kExpertiseOptions,
          customCtrl: _customAreaCtrl,
          onToggle: _toggleExpertise,
          onRemove: _removeExpertise,
          onAddCustom: _addCustomExpertise,
        ),
        _pillPicker(
          fieldKey: 'languagesKnown',
          label: 'Languages Known',
          selected: _languagesKnown,
          options: _kLanguageOptions,
          customCtrl: _customLangCtrl,
          onToggle: _toggleLanguage,
          onRemove: _removeLanguage,
          onAddCustom: _addCustomLanguage,
        ),
        _field(
          fieldKey: 'websiteUrl',
          controller: _websiteCtrl,
          label: 'Website URL',
          keyboardType: TextInputType.url,
          hint: 'e.g. https://www.mycompany.com',
        ),
        _field(
          fieldKey: 'aboutCompany',
          controller: _aboutCompanyCtrl,
          label: 'About Company / Corporate Bio',
          required: true,
          maxLines: 4,
          hint: 'Write brief history and milestones about your company',
        ),
      ],
    );
  }

  // ─── Step 3 — Office Address & Location ──────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Office Address & Location'),
        _label('Google Maps Location Picker'),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: LocationPickerMap(
            initialLat: _pickedLat,
            initialLng: _pickedLng,
            onLocationSelected: _onLocationSelected,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AddressAutocompleteField(
                controller: _officeAddressCtrl,
                decoration: _inputDecoration(
                  'Office Address *',
                  hasError: _errors.containsKey('officeAddress'),
                ),
                maxLines: 2,
                onSelectionStart: () => _suppressCoordClear = true,
                onPlaceSelected: (address, lat, lng) => _onLocationSelected(
                  lat,
                  lng,
                  address,
                  updateOfficeAddress: false,
                ),
                onPlaceSelectionFailed: _onPlaceSelectionFailed,
              ),
              _errorText('officeAddress'),
            ],
          ),
        ),
        _field(
          fieldKey: 'city',
          controller: _cityCtrl,
          label: 'Work City',
          required: true,
        ),
        _field(
          fieldKey: 'state',
          controller: _stateCtrl,
          label: 'State',
          required: true,
        ),
        _field(
          fieldKey: 'pincode',
          controller: _pincodeCtrl,
          label: 'Pincode',
          required: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
        ),
        _field(
          fieldKey: 'landmark',
          controller: _landmarkCtrl,
          label: 'Landmark',
          hint: 'Famous landmark near office',
        ),
      ],
    );
  }

  // ─── Step 4 — Verification Documents Upload ──────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Verification Documents Upload'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Upload official corporate documentation. Images required for approval.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _uploadCard(
          fieldKey: 'gstCertificateUrl',
          label: 'GST Certificate',
          url: _gstCertificateUrl,
          onTap: () => _pickAndUploadDocument(
            'gstCertificateUrl',
            ProfileDocumentKind.gst,
          ),
          subtitle: 'Corporate GST identification copy.',
        ),
        _uploadCard(
          fieldKey: 'panCardUrl',
          label: 'Company/Owner PAN Card',
          url: _panCardUrl,
          onTap: () =>
              _pickAndUploadDocument('panCardUrl', ProfileDocumentKind.pan),
          subtitle: 'Government approved PAN Card.',
        ),
        _uploadCard(
          fieldKey: 'registrationProofUrl',
          label: 'Company Registration Proof',
          url: _registrationProofUrl,
          onTap: () => _pickAndUploadDocument(
            'registrationProofUrl',
            ProfileDocumentKind.registrationProof,
          ),
          subtitle: 'Incorporation certificate, Partnership deed etc.',
        ),
        _uploadCard(
          fieldKey: 'aadhaarCardUrl',
          label: 'Aadhaar Card - Front Side',
          url: _aadhaarCardUrl,
          onTap: () => _pickAndUploadDocument(
            'aadhaarCardUrl',
            ProfileDocumentKind.aadhaar,
          ),
        ),
        _uploadCard(
          fieldKey: 'aadhaarCardBackUrl',
          label: 'Aadhaar Card - Back Side',
          url: _aadhaarCardBackUrl,
          onTap: () => _pickAndUploadDocument(
            'aadhaarCardBackUrl',
            ProfileDocumentKind.aadhaarBack,
          ),
        ),
      ],
    );
  }

  // ─── Step 5 — Social Media Links & Connectivity ──────────────────────────
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Social Media Links & Connectivity'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Connect your professional networks — all optional.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _field(
          fieldKey: 'facebookUrl',
          controller: _facebookCtrl,
          label: 'Facebook Business Profile',
          hint: 'e.g. https://facebook.com/mycompany',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'instagramUrl',
          controller: _instagramCtrl,
          label: 'Instagram Business Handle',
          hint: 'e.g. https://instagram.com/mycompany',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'linkedinUrl',
          controller: _linkedinCtrl,
          label: 'LinkedIn Corporate Page',
          hint: 'e.g. https://linkedin.com/company/mycompany',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'youtubeUrl',
          controller: _youtubeCtrl,
          label: 'YouTube Channel Link',
          hint: 'e.g. https://youtube.com/c/mycompany',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'whatsappNumber',
          controller: _whatsappCtrl,
          label: 'WhatsApp Business Number',
          hint: 'WhatsApp active number',
        ),
        _field(
          fieldKey: 'telegramUrl',
          controller: _telegramCtrl,
          label: 'Telegram Link',
          hint: 'https://t.me/yourchannel',
        ),
      ],
    );
  }

  // ─── Step 6 — Account Setup & Verifications ──────────────────────────────
  Widget _buildStep5() {
    final usernameLen = _usernameCtrl.text.trim().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Account Setup & Verifications'),
        _field(
          fieldKey: 'username',
          controller: _usernameCtrl,
          label: 'Choose Unique Username',
          required: true,
          hint: 'Choose username',
          onChanged: _onUsernameChanged,
          suffixIcon: usernameLen >= 3
              ? (_usernameTaken
                    ? const Icon(Icons.close, color: Colors.red)
                    : (_usernameAvailable == true
                          ? const Icon(Icons.check, color: Colors.green)
                          : null))
              : null,
        ),
        if (usernameLen >= 3 && !_usernameTaken && _usernameAvailable == true)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Username is available!',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ),
        _field(
          fieldKey: 'password',
          controller: _passwordCtrl,
          label: 'Password',
          required: true,
          hint: 'Min. 6 characters',
          obscureText: !_passwordVisible,
          suffixIcon: IconButton(
            icon: Icon(
              _passwordVisible ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () =>
                setState(() => _passwordVisible = !_passwordVisible),
          ),
        ),
        _field(
          fieldKey: 'confirmPassword',
          controller: _confirmPasswordCtrl,
          label: 'Confirm Password',
          required: true,
          hint: 'Re-enter your password',
          obscureText: !_confirmPasswordVisible,
          suffixIcon: IconButton(
            icon: Icon(
              _confirmPasswordVisible ? Icons.visibility_off : Icons.visibility,
            ),
            onPressed: () => setState(
              () => _confirmPasswordVisible = !_confirmPasswordVisible,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Step 7 — Terms Acceptance & Submission ──────────────────────────────
  /// Opens a policy/document link without disturbing wizard state — used by
  /// both the review step's Terms/Privacy links and its document previews.
  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  /// Billing Policies already has a native screen (used from Subscription/
  /// Upgrade) — reused here rather than an external link, same screen either
  /// way.
  void _openBillingPolicies() {
    Navigator.of(
      context,
    ).push(PremiumPageRoute(builder: (_) => const BillingPoliciesScreen()));
  }

  /// An inline tappable word/phrase inside a consent sentence — a
  /// [WidgetSpan] around a [GestureDetector] rather than a [TextSpan] with a
  /// [TapGestureRecognizer], so there's no recognizer-disposal lifecycle to
  /// manage across rebuilds.
  InlineSpan _linkSpan(String text, VoidCallback onTap) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.primary,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// A single uploaded verification document in the review step — a small
  /// thumbnail (falling back to a document icon for a non-image file, e.g. a
  /// PDF) plus a "View" link. These documents are already public URLs (see
  /// `ProfileMediaService.uploadDocument`'s own doc comment: every
  /// registration-screen caller uploads to the public avatar bucket, unlike
  /// `EditProfileProvider`'s private-document path), so this opens the
  /// stored URL directly — no signed-URL resolution needed here.
  Widget _reviewDocumentRow(String label, String? url) {
    final has = (url ?? '').isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: !has
                ? const Text(
                    '—',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  )
                : GestureDetector(
                    onTap: () => _openExternalUrl(url),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            url!,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 36,
                              height: 36,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceVariant,
                              child: const Icon(
                                Icons.description_outlined,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'View',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _reviewDocumentsSection() {
    final docs = <MapEntry<String, String?>>[
      MapEntry('GST Certificate', _gstCertificateUrl),
      MapEntry('PAN Card', _panCardUrl),
      MapEntry('Aadhaar Front', _aadhaarCardUrl),
      MapEntry('Aadhaar Back', _aadhaarCardBackUrl),
      MapEntry('Registration Proof', _registrationProofUrl),
      MapEntry('RERA Certificate', _reraCertificateUrl),
    ];
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: const Text(
          'Documents',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        children: docs.map((d) => _reviewDocumentRow(d.key, d.value)).toList(),
      ),
    );
  }

  // Builder's own portal (BuilderRegistration.tsx) has no review/summary
  // section on this step at all — unlike broker's and influencer's, which
  // both show one. Added here anyway for parity with the other two
  // registration screens and so the user can double-check before submitting.
  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewSection(
    String title,
    List<MapEntry<String, String>> rows, {
    bool initiallyExpanded = false,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        children: rows.map((r) => _reviewRow(r.key, r.value)).toList(),
      ),
    );
  }

  Widget _buildReviewSummary() {
    final divider = Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _reviewSection('Personal Information', [
            MapEntry('Company Name', _companyNameCtrl.text),
            MapEntry('Email', _emailCtrl.text),
            MapEntry('Phone', '$_countryCode ${_mobileCtrl.text}'),
            MapEntry('DOB', _dobCtrl.text),
          ], initiallyExpanded: true),
          divider,
          _reviewSection('Company Details', [
            MapEntry('Company Type', _companyType ?? ''),
            MapEntry('Experience', '${_yearsOfExpCtrl.text} Years'),
            MapEntry('About Company', _aboutCompanyCtrl.text),
          ]),
          divider,
          _reviewSection('Address Details', [
            MapEntry('Office Address', _officeAddressCtrl.text),
            MapEntry('City & State', '${_cityCtrl.text}, ${_stateCtrl.text}'),
            MapEntry('Pincode', _pincodeCtrl.text),
          ]),
          divider,
          _reviewDocumentsSection(),
        ],
      ),
    );
  }

  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Terms Acceptance & Submission'),
        _buildReviewSummary(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Platform Undertakings & Rules:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 8),
              Text(
                '•  I verify that the listed RERA certificate matches all details of my company.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '•  I authorize PropCID real estate platform audit members to check RERA status.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '•  We will process and verify your registration values in 24-48 hours.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 4),
              Text(
                '•  We do not charge listing commissions or fees unless specified under '
                'separate corporate contracts.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ConsentCheckboxRow(
          value: _termsAccepted,
          onChanged: (v) {
            setState(() => _termsAccepted = v ?? false);
            _scheduleDraftSave();
          },
          textSpans: [
            const TextSpan(text: 'I accept the '),
            _linkSpan(
              'Terms & Conditions',
              () =>
                  _openExternalUrl('https://propcid.com/terms-and-conditions'),
            ),
            const TextSpan(text: '.'),
          ],
        ),
        _ConsentCheckboxRow(
          value: _privacyAccepted,
          onChanged: (v) {
            setState(() => _privacyAccepted = v ?? false);
            _scheduleDraftSave();
          },
          textSpans: [
            const TextSpan(text: 'I agree to the '),
            _linkSpan(
              'Privacy Policy',
              () => _openExternalUrl('https://propcid.com/privacy-policy'),
            ),
            const TextSpan(text: ' of the platform. '),
            _linkSpan('View Billing Policies', _openBillingPolicies),
          ],
        ),
      ],
    );
  }

  // ─── Step content router ──────────────────────────────────────────────────
  Widget _buildCurrentStep() {
    switch (currentStep) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      case 3:
        return _buildStep3();
      case 4:
        return _buildStep4();
      case 5:
        return _buildStep5();
      case 6:
        return _buildStep6();
      default:
        return const SizedBox();
    }
  }

  // ─── Bottom Navigation Buttons ────────────────────────────────────────────
  Widget _buildNavigationButtons() {
    final isLastStep = currentStep == _stepTitles.length - 1;
    // SafeArea so this bar clears the system nav bar / gesture inset on
    // devices with on-screen navigation buttons — it sits in `body`, not
    // `bottomNavigationBar`, so Scaffold doesn't reserve that space itself.
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            if (currentStep > 0)
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _previousStep,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : (isLastStep ? _onSubmit : _nextStep),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isLastStep
                            ? Icons.check_circle_outline
                            : Icons.arrow_forward,
                        size: 18,
                      ),
                label: Text(
                  _isSubmitting
                      ? 'Submitting...'
                      : (isLastStep ? 'Submit Registration' : 'Continue'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Builder Registration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          // See broker_registration_screen.dart for why this is the only
          // real way to leave the form at Step 1 — the reference's own
          // Step 1 has no working Previous control either, and the AppBar
          // back arrow here has nothing to pop to (pushNamedAndRemoveUntil
          // cleared the stack on the way in).
          TextButton.icon(
            onPressed: () => showLogoutDialog(context),
            icon: const Icon(Icons.logout, size: 16, color: Colors.white),
            label: const Text('Logout', style: TextStyle(color: Colors.white)),
            style: TextButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _stepIcons[currentStep],
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProgressHeader(),
                  _buildCurrentStep(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _identityProvider.removeListener(_onIdentityStatusChanged);
    _draftStore.dispose();
    _usernameDebounce?.cancel();
    _companyNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _altMobileCtrl.dispose();
    _dobCtrl.dispose();
    _gstNumberCtrl.dispose();
    _panNumberCtrl.dispose();
    _yearsOfExpCtrl.dispose();
    _websiteCtrl.dispose();
    _aboutCompanyCtrl.dispose();
    _customAreaCtrl.dispose();
    _customLangCtrl.dispose();
    _officeAddressCtrl.removeListener(_onOfficeAddressChanged);
    _officeAddressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _landmarkCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _linkedinCtrl.dispose();
    _youtubeCtrl.dispose();
    _whatsappCtrl.dispose();
    _telegramCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }
}

/// A required-consent row whose label can contain inline tappable links
/// (Terms/Privacy/Billing) — deliberately not a [CheckboxListTile]: that
/// widget's entire title area is one tap target, which would also toggle
/// consent on a link tap. A plain [Checkbox] isolates the toggle to just the
/// checkbox square itself.
class _ConsentCheckboxRow extends StatelessWidget {
  const _ConsentCheckboxRow({
    required this.value,
    required this.onChanged,
    required this.textSpans,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final List<InlineSpan> textSpans;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(value: value, onChanged: onChanged),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                children: textSpans,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
