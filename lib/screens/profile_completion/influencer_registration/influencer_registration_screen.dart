// screens/profile_completion/influencer_registration/influencer_registration_screen.dart
//
// Mirrors `InfluencerRegistration.tsx` field-for-field: same 8 real steps
// (Personal, Profile, Location, Social, Content, Documents, Account, Terms),
// same required-field map (`STEP_REQUIRED`), same regex patterns, same
// option lists, same upsert payload shape (`handleSubmit`).
//
// The portal's `stepsList` (its left-hand stepper) shows a 9th entry, "Bank
// Details", between Documents and Account — but `renderStepContent`'s switch
// has no `case` for it, `InfluencerFormData` has no bank fields, and nothing
// is ever submitted for it. It is a stale label with zero implementation, so
// it is dropped here too, along with `portfolioLinks`/
// `previousBrandCollaborations`/`areasCovered`, which are declared and
// submitted (always empty) but never have a rendered field either.
//
// Password IS on the Account step, alongside Username — same fix as the other
// two registration screens: auth_screen.dart's sign-up form now creates the
// account with a random placeholder password, and this step's Password/
// Confirm Password fields set the real one via Supabase's
// updateUser(password:) on submit.
//
// Validation is an imperative `_errors` map computed on "Continue"/"Submit",
// matching how the portal's `handleNext`/`handleSubmit` work.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/animations/page_transitions.dart';
import '../../../core/utils/registration_password_update.dart';
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

// ── Portal constants, transcribed verbatim (InfluencerRegistration.tsx:112-169)

const List<Map<String, String>> _kCountryCodes = [
  {'code': '+91', 'country': 'India'},
  {'code': '+1', 'country': 'USA'},
  {'code': '+44', 'country': 'UK'},
  {'code': '+971', 'country': 'UAE'},
];

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp _mobilePattern = RegExp(r'^[6-9]\d{9}$');
// Letters, spaces, hyphens and apostrophes only — no digits or other symbols.
final RegExp _namePattern = RegExp(r"^[a-zA-Z\s'-]+$");
final RegExp _websitePattern = RegExp(
  r'^https?:\/\/(www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b',
);

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

const List<String> _kCategoryOptions = [
  'Real Estate Influencer',
  'Lifestyle Creator',
  'YouTuber',
  'Instagram Creator',
  'Blogger',
  'Affiliate Marketer',
  'Property Reviewer',
  'Finance Creator',
];

const List<String> _kPlatformOptions = [
  'Instagram',
  'YouTube',
  'Facebook',
  'LinkedIn',
  'TikTok',
  'Blogger / Web',
  'Telegram / WhatsApp',
  'Twitter / X',
];

const List<String> _kAudienceOptions = [
  'Property Seekers / Buyers',
  'Real Estate Investors',
  'Millennials / First-time Buyers',
  'Luxury Property Buyers',
  'General Lifestyle Audience',
  'Brokers & Builders Network',
];

const List<String> _kContentTypeOptions = [
  'Reels',
  'Shorts',
  'YouTube Videos',
  'Property Tours',
  'Reviews',
  'Stories',
  'Posts',
  'Live Sessions',
];

const List<String> _kPromotionTypeOptions = [
  'Paid Promotion',
  'Affiliate Marketing',
  'Lead Generation',
  'Brand Collaboration',
];

/// `genderOpt === "Prefer not to say" ? "N/A" : genderOpt === "Non-Binary" ?
/// "Other" : genderOpt` (InfluencerRegistration.tsx:1170) — the label shown
/// differs from the value stored for two of the four options.
const List<String> _kGenderValues = [
  'Male',
  'Female',
  'Non-Binary',
  'Prefer not to say',
];
String _genderLabel(String value) => switch (value) {
  'Prefer not to say' => 'N/A',
  'Non-Binary' => 'Other',
  _ => value,
};

bool _isBlank(String? v) => v == null || v.trim().isEmpty;

class InfluencerRegistrationScreen extends StatefulWidget {
  const InfluencerRegistrationScreen({super.key});

  @override
  State<InfluencerRegistrationScreen> createState() =>
      _InfluencerRegistrationScreenState();
}

class _InfluencerRegistrationScreenState
    extends State<InfluencerRegistrationScreen> {
  int currentStep = 0;
  bool _isSubmitting = false;
  final Map<String, String> _errors = {};
  final _mediaService = ProfileMediaService();
  final Set<String> _uploading = {};
  final _draftStore = RegistrationDraftStore('influencer_registration_draft');

  // ─── Step 1 – Personal Information ───────────────────────────────────────
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _altMobileCtrl = TextEditingController();
  String _countryCode = '+91';
  String _alternateCountryCode = '+91';
  String? _gender;
  final _dobCtrl = TextEditingController();
  String? _avatarUrl;
  bool _isEmailUser = false;
  bool _isPhoneUser = false;

  // ─── Step 2 – Influencer Profile ─────────────────────────────────────────
  String? _category;
  final _bioCtrl = TextEditingController();
  final List<String> _languagesKnown = [];
  final _customLangCtrl = TextEditingController();
  final _yearsOfExpCtrl = TextEditingController();
  String? _audienceType;
  String? _primaryContentPlatform;

  // ─── Step 3 – Office / Work Location ─────────────────────────────────────
  final _officeAddressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  // Sent as social_media.latitude/longitude (InfluencerRegistration.tsx:941-942)
  // — unlike the builder/broker screens, the portal actually persists these.
  double? _pickedLat;
  double? _pickedLng;

  /// True while something OTHER than the user typing is writing
  /// [_officeAddressCtrl]'s text — a resolved map tap/autocomplete pick, or
  /// a restored draft. [_onOfficeAddressChanged] must not mistake any of
  /// those for a manual edit, or it would clear the very coordinates that
  /// same write is setting (or just restored).
  bool _suppressCoordClear = false;

  // ─── Step 4 – Social Media Details ───────────────────────────────────────
  final _instagramUsernameCtrl = TextEditingController();
  final _instagramFollowersCtrl = TextEditingController();
  final _youtubeChannelCtrl = TextEditingController();
  final _youtubeSubscribersCtrl = TextEditingController();
  final _facebookPageCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _twitterCtrl = TextEditingController();
  final _telegramCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

  // ─── Step 5 – Content & Promotion Details ────────────────────────────────
  final List<String> _contentTypes = [];
  final List<String> _preferredPromotionTypes = [];

  // ─── Step 6 – Verification & Documents ───────────────────────────────────
  String? _aadhaarCardUrl;
  String? _aadhaarCardBackUrl;
  String? _panCardUrl;

  // ─── Step 7 – Account Setup ───────────────────────────────────────────────
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  Timer? _usernameDebounce;
  bool? _usernameAvailable;
  bool _usernameTaken = false;

  // ─── Step 8 – Terms ───────────────────────────────────────────────────────
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _promoAccepted = false;

  final List<String> _stepTitles = [
    'Personal',
    'Profile',
    'Location',
    'Social',
    'Content',
    'Documents',
    'Account',
    'Submit',
  ];

  final List<IconData> _stepIcons = [
    Icons.person_outline,
    Icons.badge_outlined,
    Icons.location_on_outlined,
    Icons.share_outlined,
    Icons.trending_up_outlined,
    Icons.description_outlined,
    Icons.lock_outline,
    Icons.verified_outlined,
  ];

  @override
  void initState() {
    super.initState();
    // Mirrors InfluencerRegistration.tsx:438-476.
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

    // The sign-up form (auth_screen.dart) already asked for this and stored
    // it as Supabase auth's `display_name` user metadata — pre-fill instead
    // of asking a second time. Mirrors the portal's own
    // `fullName: basicInfo.fullName || ...` restore
    // (InfluencerRegistration.tsx), just reading Supabase auth metadata
    // instead of the portal's sessionStorage-based "basic info" step, which
    // this app doesn't have.
    final metadataName = authUser?.userMetadata?['display_name'] as String?;
    if (metadataName != null && metadataName.trim().isNotEmpty) {
      _fullNameCtrl.text = metadataName.trim();
    }

    _wireDraftAutoSave();
    // Separate from the draft-autosave listener: a manual edit to the
    // office address after a map pin was already dropped must forget that
    // pin, since the old coordinates no longer describe the new text.
    _officeAddressCtrl.addListener(_onOfficeAddressChanged);
    _restoreDraft();

    // Server-verified identity always wins over both the auth-prefill above
    // and whatever a restored draft put into these controllers — see
    // _onIdentityStatusChanged, which also runs on every later status
    // change (not just the first load).
    _identityProvider = context.read<IdentityVerificationProvider>();
    _identityProvider.addListener(_onIdentityStatusChanged);
    _identityProvider.ensureLoaded();
    _onIdentityStatusChanged();
  }

  late final IdentityVerificationProvider _identityProvider;

  /// Reconciles the canonical server-verified email/phone (if any) into
  /// `_emailCtrl`/`_mobileCtrl`/`_countryCode`, overriding both the
  /// auth-prefill in `initState` and anything a restored draft set.
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

  // ─── Test-only observability — see the Builder screen's identical comment.
  @visibleForTesting
  String get debugEmailForTest => _emailCtrl.text;
  @visibleForTesting
  String get debugMobileForTest => _mobileCtrl.text;
  @visibleForTesting
  String get debugCountryCodeForTest => _countryCode;

  // ─── Draft persistence — mirrors the portal's per-wizard localStorage
  // autosave (e.g. InfluencerRegistration.tsx:417-428's `autoSave`), restored
  // on reopen so a half-filled form isn't lost between sessions. See
  // RegistrationDraftStore for the save/load/expiry mechanics.
  void _wireDraftAutoSave() {
    for (final c in [
      _fullNameCtrl,
      _emailCtrl,
      _mobileCtrl,
      _altMobileCtrl,
      _dobCtrl,
      _bioCtrl,
      _yearsOfExpCtrl,
      _officeAddressCtrl,
      _cityCtrl,
      _stateCtrl,
      _pincodeCtrl,
      _landmarkCtrl,
      _instagramUsernameCtrl,
      _instagramFollowersCtrl,
      _youtubeChannelCtrl,
      _youtubeSubscribersCtrl,
      _facebookPageCtrl,
      _linkedinCtrl,
      _twitterCtrl,
      _telegramCtrl,
      _websiteCtrl,
      _whatsappCtrl,
      _usernameCtrl,
    ]) {
      c.addListener(_scheduleDraftSave);
    }
  }

  void _scheduleDraftSave() => _draftStore.scheduleSave(_draftToJson);

  Map<String, dynamic> _draftToJson() => {
    'currentStep': currentStep,
    'fullName': _fullNameCtrl.text,
    'email': _emailCtrl.text,
    'mobileNumber': _mobileCtrl.text,
    'countryCode': _countryCode,
    'alternateMobileNumber': _altMobileCtrl.text,
    'alternateCountryCode': _alternateCountryCode,
    'gender': _gender ?? '',
    'dob': _dobCtrl.text,
    'avatarUrl': _avatarUrl ?? '',
    'category': _category ?? '',
    'bio': _bioCtrl.text,
    'languagesKnown': _languagesKnown,
    'yearsOfExperience': _yearsOfExpCtrl.text,
    'audienceType': _audienceType ?? '',
    'primaryContentPlatform': _primaryContentPlatform ?? '',
    'officeAddress': _officeAddressCtrl.text,
    'city': _cityCtrl.text,
    'state': _stateCtrl.text,
    'pincode': _pincodeCtrl.text,
    'landmark': _landmarkCtrl.text,
    'pickedLat': _pickedLat,
    'pickedLng': _pickedLng,
    'instagramUsername': _instagramUsernameCtrl.text,
    'instagramFollowers': _instagramFollowersCtrl.text,
    'youtubeChannelLink': _youtubeChannelCtrl.text,
    'youtubeSubscribers': _youtubeSubscribersCtrl.text,
    'facebookPageLink': _facebookPageCtrl.text,
    'linkedinProfileUrl': _linkedinCtrl.text,
    'twitterProfileUrl': _twitterCtrl.text,
    'telegramChannelLink': _telegramCtrl.text,
    'websiteUrl': _websiteCtrl.text,
    'whatsappNumber': _whatsappCtrl.text,
    'contentTypes': _contentTypes,
    'preferredPromotionTypes': _preferredPromotionTypes,
    'aadhaarCardUrl': _aadhaarCardUrl ?? '',
    'aadhaarCardBackUrl': _aadhaarCardBackUrl ?? '',
    'panCardUrl': _panCardUrl ?? '',
    'username': _usernameCtrl.text,
    'termsAccepted': _termsAccepted,
    'privacyAccepted': _privacyAccepted,
    'promoAccepted': _promoAccepted,
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

      if (s('fullName').isNotEmpty) _fullNameCtrl.text = s('fullName');
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

      if (s('category').isNotEmpty) _category = s('category');
      if (s('bio').isNotEmpty) _bioCtrl.text = s('bio');
      final languages = l('languagesKnown');
      if (languages.isNotEmpty) {
        _languagesKnown
          ..clear()
          ..addAll(languages);
      }
      if (s('yearsOfExperience').isNotEmpty) {
        _yearsOfExpCtrl.text = s('yearsOfExperience');
      }
      if (s('audienceType').isNotEmpty) _audienceType = s('audienceType');
      if (s('primaryContentPlatform').isNotEmpty) {
        _primaryContentPlatform = s('primaryContentPlatform');
      }

      if (s('officeAddress').isNotEmpty)
        _officeAddressCtrl.text = s('officeAddress');
      if (s('city').isNotEmpty) _cityCtrl.text = s('city');
      if (s('state').isNotEmpty) _stateCtrl.text = s('state');
      if (s('pincode').isNotEmpty) _pincodeCtrl.text = s('pincode');
      if (s('landmark').isNotEmpty) _landmarkCtrl.text = s('landmark');
      _pickedLat = (data['pickedLat'] as num?)?.toDouble() ?? _pickedLat;
      _pickedLng = (data['pickedLng'] as num?)?.toDouble() ?? _pickedLng;

      if (s('instagramUsername').isNotEmpty) {
        _instagramUsernameCtrl.text = s('instagramUsername');
      }
      if (s('instagramFollowers').isNotEmpty) {
        _instagramFollowersCtrl.text = s('instagramFollowers');
      }
      if (s('youtubeChannelLink').isNotEmpty) {
        _youtubeChannelCtrl.text = s('youtubeChannelLink');
      }
      if (s('youtubeSubscribers').isNotEmpty) {
        _youtubeSubscribersCtrl.text = s('youtubeSubscribers');
      }
      if (s('facebookPageLink').isNotEmpty)
        _facebookPageCtrl.text = s('facebookPageLink');
      if (s('linkedinProfileUrl').isNotEmpty)
        _linkedinCtrl.text = s('linkedinProfileUrl');
      if (s('twitterProfileUrl').isNotEmpty)
        _twitterCtrl.text = s('twitterProfileUrl');
      if (s('telegramChannelLink').isNotEmpty)
        _telegramCtrl.text = s('telegramChannelLink');
      if (s('websiteUrl').isNotEmpty) _websiteCtrl.text = s('websiteUrl');
      if (s('whatsappNumber').isNotEmpty)
        _whatsappCtrl.text = s('whatsappNumber');

      final contentTypes = l('contentTypes');
      if (contentTypes.isNotEmpty) {
        _contentTypes
          ..clear()
          ..addAll(contentTypes);
      }
      final promotionTypes = l('preferredPromotionTypes');
      if (promotionTypes.isNotEmpty) {
        _preferredPromotionTypes
          ..clear()
          ..addAll(promotionTypes);
      }

      if (s('aadhaarCardUrl').isNotEmpty) _aadhaarCardUrl = s('aadhaarCardUrl');
      if (s('aadhaarCardBackUrl').isNotEmpty) {
        _aadhaarCardBackUrl = s('aadhaarCardBackUrl');
      }
      if (s('panCardUrl').isNotEmpty) _panCardUrl = s('panCardUrl');

      if (s('username').isNotEmpty) _usernameCtrl.text = s('username');
      _termsAccepted = data['termsAccepted'] as bool? ?? _termsAccepted;
      _privacyAccepted = data['privacyAccepted'] as bool? ?? _privacyAccepted;
      _promoAccepted = data['promoAccepted'] as bool? ?? _promoAccepted;
    });
    _suppressCoordClear = false;

    // Re-asserts the canonical verified value in case identity status had
    // already loaded (and already been applied) before this async restore
    // finished — see the Builder screen's identical comment for why this is
    // needed regardless of which of the two async loads resolves last.
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
      6 => _validateStep6(),
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
            'Please fill out or fix the required fields to continue.',
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
  // InfluencerRegistration.tsx:781-843 ──────────────────────────────────────
  Map<String, String> _validateStep0() {
    final e = <String, String>{};
    if ((_avatarUrl ?? '').isEmpty)
      e['avatarUrl'] = 'Profile photo is required.';
    if (_isBlank(_fullNameCtrl.text)) {
      e['fullName'] = 'Full name is required.';
    } else if (!_namePattern.hasMatch(_fullNameCtrl.text.trim())) {
      e['fullName'] = 'Name can only contain letters, spaces and hyphens.';
    }
    if (_isBlank(_emailCtrl.text)) {
      e['email'] = 'Email address is required.';
    } else if (!_emailPattern.hasMatch(_emailCtrl.text.trim())) {
      e['email'] = 'Please enter a valid email address.';
    }
    if (_isBlank(_mobileCtrl.text)) {
      e['mobileNumber'] = 'Mobile number is required.';
    } else {
      // Mirrors the portal exactly: unlike the alternate number below, the
      // primary mobile check here does not branch on country code.
      final digits = _mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (!_mobilePattern.hasMatch(digits)) {
        e['mobileNumber'] = 'Mobile number must be a valid 10-digit number.';
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
    return e;
  }

  Map<String, String> _validateStep1() {
    final e = <String, String>{};
    if (_category == null || _category!.isEmpty)
      e['category'] = 'Category is required.';
    if (_primaryContentPlatform == null || _primaryContentPlatform!.isEmpty) {
      e['primaryContentPlatform'] = 'Primary content platform is required.';
    }
    if (_isBlank(_yearsOfExpCtrl.text)) {
      e['yearsOfExperience'] = 'Years of experience is required.';
    }
    if (_audienceType == null || _audienceType!.isEmpty) {
      e['audienceType'] = 'Audience type is required.';
    }
    if (_isBlank(_bioCtrl.text)) e['bio'] = 'Bio is required.';
    if (_languagesKnown.isEmpty)
      e['languagesKnown'] = 'Languages known is required.';
    return e;
  }

  Map<String, String> _validateStep2() {
    final e = <String, String>{};
    if (_isBlank(_officeAddressCtrl.text)) {
      e['officeAddress'] = 'Office / work address is required.';
    }
    if (_isBlank(_cityCtrl.text)) e['city'] = 'City is required.';
    if (_isBlank(_stateCtrl.text)) e['state'] = 'State is required.';
    if (_isBlank(_pincodeCtrl.text)) e['pincode'] = 'Pincode is required.';
    if (_isBlank(_landmarkCtrl.text)) e['landmark'] = 'Landmark is required.';
    return e;
  }

  Map<String, String> _validateStep3() {
    final e = <String, String>{};
    if (_isBlank(_instagramUsernameCtrl.text)) {
      e['instagramUsername'] = 'Instagram username is required.';
    }
    if (_isBlank(_instagramFollowersCtrl.text)) {
      e['instagramFollowers'] = 'Instagram followers is required.';
    }
    if (_isBlank(_youtubeChannelCtrl.text)) {
      e['youtubeChannelLink'] = 'YouTube channel link is required.';
    } else if (!_websitePattern.hasMatch(_youtubeChannelCtrl.text.trim())) {
      e['youtubeChannelLink'] = 'Please enter a valid URL.';
    }
    if (_isBlank(_youtubeSubscribersCtrl.text)) {
      e['youtubeSubscribers'] = 'YouTube subscribers is required.';
    }
    if (_isBlank(_facebookPageCtrl.text)) {
      e['facebookPageLink'] = 'Facebook page link is required.';
    } else if (!_websitePattern.hasMatch(_facebookPageCtrl.text.trim())) {
      e['facebookPageLink'] = 'Please enter a valid URL.';
    }
    if (_isBlank(_linkedinCtrl.text)) {
      e['linkedinProfileUrl'] = 'LinkedIn profile URL is required.';
    } else if (!_websitePattern.hasMatch(_linkedinCtrl.text.trim())) {
      e['linkedinProfileUrl'] = 'Please enter a valid URL.';
    }
    if (_isBlank(_twitterCtrl.text)) {
      e['twitterProfileUrl'] = 'Twitter / X profile URL is required.';
    } else if (!_websitePattern.hasMatch(_twitterCtrl.text.trim())) {
      e['twitterProfileUrl'] = 'Please enter a valid URL.';
    }
    if (_isBlank(_telegramCtrl.text)) {
      e['telegramChannelLink'] = 'Telegram channel link is required.';
    } else if (!_websitePattern.hasMatch(_telegramCtrl.text.trim())) {
      e['telegramChannelLink'] = 'Please enter a valid URL.';
    }
    if (_websiteCtrl.text.trim().isNotEmpty &&
        !_websitePattern.hasMatch(_websiteCtrl.text.trim())) {
      e['websiteUrl'] = 'Please enter a valid URL.';
    }
    if (_isBlank(_whatsappCtrl.text)) {
      e['whatsappNumber'] = 'WhatsApp number is required.';
    }
    return e;
  }

  Map<String, String> _validateStep4() {
    final e = <String, String>{};
    if (_contentTypes.isEmpty) e['contentTypes'] = 'Content types is required.';
    if (_preferredPromotionTypes.isEmpty) {
      e['preferredPromotionTypes'] = 'Preferred promotion types is required.';
    }
    return e;
  }

  Map<String, String> _validateStep5() {
    // Aadhaar (front/back) and PAN card are optional uploads — nothing in
    // this step blocks submission.
    return <String, String>{};
  }

  Map<String, String> _validateStep6() {
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

  // ─── Username availability ────────────────────────────────────────────────
  void _onUsernameChanged(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
        .toLowerCase();
    if (cleaned != value) {
      _usernameCtrl.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
      return;
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
    setState(() {});
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

  // ─── Uploads — real files via ProfileMediaService ────────────────────────
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
          case 'aadhaarCardUrl':
            _aadhaarCardUrl = url;
          case 'panCardUrl':
            _panCardUrl = url;
        }
      });
      _scheduleDraftSave();
    } catch (e) {
      _showUploadError(e);
    } finally {
      if (mounted) setState(() => _uploading.remove(fieldKey));
    }
  }

  /// Aadhaar needs BOTH sides, as two genuine separate documents/URLs —
  /// `aadhaarCardUrl` (front) and `aadhaarCardBackUrl` (back) — matching the
  /// backend's `influencer-registration-submit` contract, which requires
  /// both as distinct fields. Each side uploads independently the moment
  /// it's picked, rather than being composited into one image.
  Future<void> _pickAadhaarSide({required bool front}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final key = front ? 'aadhaarFront' : 'aadhaarBack';
    setState(() => _uploading.add(key));
    try {
      final file = await _mediaService.pickDocument();
      if (file == null) return;
      if (!mounted) return;
      setState(() {
        if (front) {
          _aadhaarCardUrl = null;
        } else {
          _aadhaarCardBackUrl = null;
        }
        _errors.remove(key);
      });

      final url = await _mediaService.uploadDocument(
        userId: userId,
        kind: front
            ? ProfileDocumentKind.aadhaar
            : ProfileDocumentKind.aadhaarBack,
        file: file,
      );
      if (!mounted) return;
      setState(() {
        if (front) {
          _aadhaarCardUrl = url;
        } else {
          _aadhaarCardBackUrl = url;
        }
      });
      _scheduleDraftSave();
    } catch (e) {
      _showUploadError(e);
    } finally {
      if (mounted) setState(() => _uploading.remove(key));
    }
  }

  void _showUploadError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
    );
  }

  // ─── Languages pill picker ────────────────────────────────────────────────
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

  void _toggleContentType(String item) {
    setState(() {
      _contentTypes.contains(item)
          ? _contentTypes.remove(item)
          : _contentTypes.add(item);
    });
    _scheduleDraftSave();
  }

  void _togglePromotionType(String item) {
    setState(() {
      _preferredPromotionTypes.contains(item)
          ? _preferredPromotionTypes.remove(item)
          : _preferredPromotionTypes.add(item);
    });
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
      initialDate: DateTime(now.year - 25),
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

  // ─── Map picker — mirrors InfluencerRegistration.tsx:485-507's
  // handleLocationSelect: keep the existing value when the geocode result
  // didn't resolve that field.
  // [updateOfficeAddress] is false for the autocomplete field's selections:
  // it already wrote the full selected description into the controller
  // itself (matching the portal, which fills `officeAddress` with
  // `place.formatted_address`) — overwriting it here with the shorter parsed
  // `addressLine1` would fight that. The map tap path has no pre-filled
  // text, so it still wants this.
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
      if ((address?.landmark ?? '').isNotEmpty) _errors.remove('landmark');
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

  // ─── Submit — mirrors InfluencerRegistration.tsx:875-981 ─────────────────
  /// Builds the exact `form` map sent to `influencer-registration-submit`.
  /// Extracted so a test can assert every key the backend's
  /// `REQUIRED_FIELDS`/write logic actually reads is present and correctly
  /// named, without driving the whole wizard through a submit.
  @visibleForTesting
  Map<String, dynamic> buildSubmitFormForTest() => {
    'fullName': _fullNameCtrl.text.trim(),
    'email': _emailCtrl.text.trim(),
    'mobileNumber': _mobileCtrl.text.trim(),
    'alternateMobileNumber': _altMobileCtrl.text.trim(),
    'gender': _gender ?? '',
    'dob': _dobCtrl.text.trim(),
    'avatarUrl': _avatarUrl ?? '',
    'category': _category ?? '',
    'primaryContentPlatform': _primaryContentPlatform ?? '',
    'yearsOfExperience': _yearsOfExpCtrl.text.trim(),
    'audienceType': _audienceType ?? '',
    'bio': _bioCtrl.text.trim(),
    'languagesKnown': _languagesKnown,
    'officeAddress': _officeAddressCtrl.text.trim(),
    'city': _cityCtrl.text.trim(),
    'state': _stateCtrl.text.trim(),
    'pincode': _pincodeCtrl.text.trim(),
    'landmark': _landmarkCtrl.text.trim(),
    'latitude': _pickedLat,
    'longitude': _pickedLng,
    'instagramUsername': _instagramUsernameCtrl.text.trim(),
    'instagramFollowers': _instagramFollowersCtrl.text.trim(),
    'youtubeChannelLink': _youtubeChannelCtrl.text.trim(),
    'youtubeSubscribers': _youtubeSubscribersCtrl.text.trim(),
    'facebookPageLink': _facebookPageCtrl.text.trim(),
    'linkedinProfileUrl': _linkedinCtrl.text.trim(),
    'twitterProfileUrl': _twitterCtrl.text.trim(),
    'telegramChannelLink': _telegramCtrl.text.trim(),
    'websiteUrl': _websiteCtrl.text.trim(),
    'whatsappNumber': _whatsappCtrl.text.trim(),
    'contentTypes': _contentTypes,
    'preferredPromotionTypes': _preferredPromotionTypes,
    'aadhaarCardUrl': _aadhaarCardUrl ?? '',
    'aadhaarCardBackUrl': _aadhaarCardBackUrl ?? '',
    'panCardUrl': _panCardUrl ?? '',
    'username': _usernameCtrl.text.trim(),
  };

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

      // Phase 2: the portal's own backend validation/identity gate/username
      // check, instead of a direct client-side upsert the server never saw.
      await RegistrationSubmitService().influencerSubmit(
        form: buildSubmitFormForTest(),
        countryCode: _countryCode,
        alternateCountryCode: _alternateCountryCode,
        termsAccepted: _termsAccepted,
        privacyAccepted: _privacyAccepted,
      );

      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_user_type');
      await prefs.remove('pending_user_type_uid');
      await _draftStore.clear();
      await context.read<AuthProvider>().refreshProfile();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Influencer profile saved successfully'),
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
    bool hasError = false,
    EdgeInsetsGeometry? contentPadding,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label.isEmpty ? null : label,
      hintText: hint,
      suffixIcon: suffix,
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

  Widget _multiToggle({
    required String fieldKey,
    required String label,
    required List<String> selected,
    required List<String> options,
    required void Function(String) onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: true),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final active = selected.contains(o);
              return ChoiceChip(
                label: Text(
                  o,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
                selected: active,
                onSelected: (_) => onToggle(o),
              );
            }).toList(),
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

  // ─── Step 1 — Personal Information ───────────────────────────────────────
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Personal Information'),
        _uploadCard(
          fieldKey: 'avatarUrl',
          label: 'Profile Photo (Creator Photo)',
          url: _avatarUrl,
          onTap: _pickAndUploadAvatar,
          required: true,
          isImagePreview: true,
        ),
        _field(
          fieldKey: 'fullName',
          controller: _fullNameCtrl,
          label: 'Full Name',
          required: true,
          hint: 'e.g. Shubham Gosaii',
          // A name has no legitimate reason to contain digits.
          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[0-9]'))],
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
            label: 'Mobile Number',
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
          children: _kGenderValues.map((g) {
            final selected = _gender == g;
            return ChoiceChip(
              label: Text(_genderLabel(g)),
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
      ],
    );
  }

  // ─── Step 2 — Influencer Profile ─────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Influencer Profile'),
        _dropdown(
          fieldKey: 'category',
          label: 'Influencer Category',
          value: _category,
          items: _kCategoryOptions,
          onChanged: (v) {
            setState(() => _category = v);
            _scheduleDraftSave();
          },
          required: true,
        ),
        _dropdown(
          fieldKey: 'primaryContentPlatform',
          label: 'Primary Platform',
          value: _primaryContentPlatform,
          items: _kPlatformOptions,
          onChanged: (v) {
            setState(() => _primaryContentPlatform = v);
            _scheduleDraftSave();
          },
          required: true,
        ),
        _field(
          fieldKey: 'yearsOfExperience',
          controller: _yearsOfExpCtrl,
          label: 'Years of Experience as Creator',
          required: true,
          hint: 'e.g. 5',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _dropdown(
          fieldKey: 'audienceType',
          label: 'Audience Niche Type',
          value: _audienceType,
          items: _kAudienceOptions,
          onChanged: (v) {
            setState(() => _audienceType = v);
            _scheduleDraftSave();
          },
          required: true,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _bioCtrl,
                maxLines: 4,
                decoration: _inputDecoration(
                  'Bio / About Me * (Minimum 10 words)',
                  hint:
                      'Share your creator journey, previous successful property '
                      'walkthroughs, or review channels...',
                  hasError: _errors.containsKey('bio'),
                ),
              ),
              _errorText('bio'),
            ],
          ),
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
      ],
    );
  }

  // ─── Step 3 — Office / Work Location ─────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Office / Work Location'),
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
                  'Office / Work Address *',
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
          hint: '6-digit pincode',
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
          required: true,
          hint: 'Famous landmark near office',
        ),
      ],
    );
  }

  // ─── Step 4 — Social Media Details ───────────────────────────────────────
  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Social Media Details'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Connect your verified handle details and viewer statistics.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _field(
          fieldKey: 'instagramUsername',
          controller: _instagramUsernameCtrl,
          label: 'Instagram Profile Link',
          required: true,
          hint: 'https://instagram.com/creator_handle',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'instagramFollowers',
          controller: _instagramFollowersCtrl,
          label: 'Instagram Followers Count',
          required: true,
          hint: 'e.g. 50000',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _field(
          fieldKey: 'youtubeChannelLink',
          controller: _youtubeChannelCtrl,
          label: 'YouTube Channel Link',
          required: true,
          hint: 'https://youtube.com/c/yourchannel',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'youtubeSubscribers',
          controller: _youtubeSubscribersCtrl,
          label: 'YouTube Subscribers Count',
          required: true,
          hint: 'e.g. 100000',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _field(
          fieldKey: 'facebookPageLink',
          controller: _facebookPageCtrl,
          label: 'Facebook Page Link',
          required: true,
          hint: 'https://facebook.com/yourpage',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'linkedinProfileUrl',
          controller: _linkedinCtrl,
          label: 'LinkedIn Profile URL',
          required: true,
          hint: 'https://linkedin.com/in/username',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'twitterProfileUrl',
          controller: _twitterCtrl,
          label: 'Twitter / X Profile URL',
          required: true,
          hint: 'https://x.com/username',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'telegramChannelLink',
          controller: _telegramCtrl,
          label: 'Telegram Channel Link',
          required: true,
          hint: 'https://t.me/channelname',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'websiteUrl',
          controller: _websiteCtrl,
          label: 'Website / Blog URL',
          hint: 'https://mycreatorblog.com',
          keyboardType: TextInputType.url,
        ),
        _field(
          fieldKey: 'whatsappNumber',
          controller: _whatsappCtrl,
          label: 'WhatsApp Contact Number',
          required: true,
          hint: 'e.g. 9876543210',
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }

  // ─── Step 5 — Content & Promotion Details ────────────────────────────────
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Content & Promotion Details'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Specify your promotional channels and active content portfolio.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _multiToggle(
          fieldKey: 'contentTypes',
          label: 'Content Types',
          selected: _contentTypes,
          options: _kContentTypeOptions,
          onToggle: _toggleContentType,
        ),
        _multiToggle(
          fieldKey: 'preferredPromotionTypes',
          label: 'Preferred Promotion Type',
          selected: _preferredPromotionTypes,
          options: _kPromotionTypeOptions,
          onToggle: _togglePromotionType,
        ),
      ],
    );
  }

  // ─── Step 6 — Verification & Documents ───────────────────────────────────
  Widget _buildStep5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Verification & Documents'),
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Upload identification credentials to activate your Creator '
            'Verification Badge.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _uploadCard(
          fieldKey: 'aadhaarFront',
          label: 'Aadhaar Card - Front Side',
          url: _aadhaarCardUrl,
          onTap: () => _pickAadhaarSide(front: true),
          subtitle:
              'Government ID card details for verification. Upload both sides.',
        ),
        _uploadCard(
          fieldKey: 'aadhaarBack',
          label: 'Aadhaar Card - Back Side',
          url: _aadhaarCardBackUrl,
          onTap: () => _pickAadhaarSide(front: false),
        ),
        _uploadCard(
          fieldKey: 'panCardUrl',
          label: 'PAN Card',
          url: _panCardUrl,
          onTap: () =>
              _pickAndUploadDocument('panCardUrl', ProfileDocumentKind.pan),
          subtitle: 'Primary PAN Card details.',
        ),
      ],
    );
  }

  // ─── Step 7 — Account Setup ───────────────────────────────────────────────
  Widget _buildStep6() {
    final usernameLen = _usernameCtrl.text.trim().length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Account Setup'),
        _field(
          fieldKey: 'username',
          controller: _usernameCtrl,
          label: 'Select Unique Username',
          required: true,
          hint: 'e.g. shubham_gosaii',
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
          )
        else if (usernameLen == 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Only letters, numbers, and underscores are allowed. Min 3 characters.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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

  // ─── Step 8 — Terms & Submit Application ─────────────────────────────────
  // Mirrors InfluencerRegistration.tsx:1840-1901's accordion summary.
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
      MapEntry('Aadhaar Front', _aadhaarCardUrl),
      MapEntry('Aadhaar Back', _aadhaarCardBackUrl),
      MapEntry('PAN Card', _panCardUrl),
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
    final instagram = _instagramUsernameCtrl.text.trim().isEmpty
        ? '—'
        : '${_instagramUsernameCtrl.text.trim()} '
              '(${_instagramFollowersCtrl.text.trim().isEmpty ? "0" : _instagramFollowersCtrl.text.trim()} followers)';
    final youtube = _youtubeChannelCtrl.text.trim().isEmpty
        ? '—'
        : 'Channel (${_youtubeSubscribersCtrl.text.trim().isEmpty ? "0" : _youtubeSubscribersCtrl.text.trim()} subscribers)';

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
            MapEntry('Full Name', _fullNameCtrl.text),
            MapEntry(
              'Creator Username',
              _usernameCtrl.text.trim().isEmpty
                  ? ''
                  : '@${_usernameCtrl.text.trim()}',
            ),
            MapEntry('Email', _emailCtrl.text),
            MapEntry('Phone', '$_countryCode ${_mobileCtrl.text}'),
            MapEntry('Gender', _gender ?? ''),
            MapEntry('DOB', _dobCtrl.text),
          ], initiallyExpanded: true),
          divider,
          _reviewSection('Creator Profile', [
            MapEntry('Category', _category ?? ''),
            MapEntry('Experience', '${_yearsOfExpCtrl.text} Years'),
            MapEntry('Languages Spoken', _languagesKnown.join(', ')),
            MapEntry('Office Address', _officeAddressCtrl.text),
            MapEntry('City & State', '${_cityCtrl.text}, ${_stateCtrl.text}'),
            MapEntry('Pincode', _pincodeCtrl.text),
            MapEntry('Landmark', _landmarkCtrl.text),
            MapEntry('Bio / About', _bioCtrl.text),
          ]),
          divider,
          _reviewSection('Social Presence', [
            MapEntry('Instagram', instagram),
            MapEntry('YouTube', youtube),
            MapEntry('Website', _websiteCtrl.text),
            MapEntry('WhatsApp', _whatsappCtrl.text),
          ]),
          divider,
          _reviewSection('Content & Promotion', [
            MapEntry('Content Types', _contentTypes.join(', ')),
            MapEntry('Promotion Types', _preferredPromotionTypes.join(', ')),
          ]),
          divider,
          _reviewDocumentsSection(),
        ],
      ),
    );
  }

  Widget _buildStep7() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Terms & Submit Application'),
        _buildReviewSummary(),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Review guidelines and verify before launching.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ),
        _ConsentCheckboxRow(
          value: _termsAccepted,
          onChanged: (v) {
            setState(() => _termsAccepted = v ?? false);
            _scheduleDraftSave();
          },
          textSpans: [
            const TextSpan(text: 'I accept the '),
            _linkSpan(
              'Terms and Conditions',
              () =>
                  _openExternalUrl('https://propcid.com/terms-and-conditions'),
            ),
            const TextSpan(
              text:
                  ', content production standards and verified publisher '
                  'guidelines.',
            ),
          ],
        ),
        _ConsentCheckboxRow(
          value: _privacyAccepted,
          onChanged: (v) {
            setState(() => _privacyAccepted = v ?? false);
            _scheduleDraftSave();
          },
          textSpans: [
            const TextSpan(text: 'I accept the '),
            _linkSpan(
              'Privacy Policy',
              () => _openExternalUrl('https://propcid.com/privacy-policy'),
            ),
            const TextSpan(
              text:
                  ' and authorize PropCID to review social channel '
                  'analytical counts. ',
            ),
            _linkSpan('View Billing Policies', _openBillingPolicies),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _promoAccepted,
          onChanged: (v) {
            setState(() => _promoAccepted = v ?? false);
            _scheduleDraftSave();
          },
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Yes, sign me up for upcoming broker campaigns, brand collaborations, '
            'and creator tool updates.',
            style: TextStyle(fontSize: 13),
          ),
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
      case 7:
        return _buildStep7();
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
          'Influencer Registration',
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
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _altMobileCtrl.dispose();
    _dobCtrl.dispose();
    _bioCtrl.dispose();
    _customLangCtrl.dispose();
    _yearsOfExpCtrl.dispose();
    _officeAddressCtrl.removeListener(_onOfficeAddressChanged);
    _officeAddressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _landmarkCtrl.dispose();
    _instagramUsernameCtrl.dispose();
    _instagramFollowersCtrl.dispose();
    _youtubeChannelCtrl.dispose();
    _youtubeSubscribersCtrl.dispose();
    _facebookPageCtrl.dispose();
    _linkedinCtrl.dispose();
    _twitterCtrl.dispose();
    _telegramCtrl.dispose();
    _websiteCtrl.dispose();
    _whatsappCtrl.dispose();
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
