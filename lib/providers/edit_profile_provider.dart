// providers/edit_profile_provider.dart
//
// State for the Edit Profile screen: load, hold, validate, save.
//
// Field selection and payload shape are a port of EditProfile.tsx's `fetchProfile`
// and `handleSubmit`. The read side coalesces the same fallbacks the portal reads
// (`company_description || bio`, `rera_number || license_number`, ...); the write
// side reproduces its role branches exactly.
//
// APPROVED DECISION 5.1 — legacy multi-select values are preserved. Each chip
// group keeps the stored list as its source of truth, so a value the React
// vocabulary does not contain stays selected until the user removes it. Nothing is
// filtered against the canonical options on load or on save.
// `widgets` already re-exports everything from `foundation` that this file needs
// (ChangeNotifier, debugPrint, visibleForTesting), so importing both is redundant.
import 'package:flutter/widgets.dart';

import '../core/validation/profile_validators.dart';
import '../core/validation/validators.dart';
import '../models/identity_status.dart';
import '../models/user_profile.dart';
import '../services/profile_media_service.dart';
import '../services/profile_write_service.dart';
import '../services/user_profile_service.dart';

class EditProfileProvider extends ChangeNotifier {
  EditProfileProvider({
    UserProfileService? profileService,
    ProfileWriteService? writeService,
    ProfileMediaService? mediaService,
  }) : _profileService = profileService ?? UserProfileService(),
       _writeService = writeService ?? ProfileWriteService(),
       _mediaService = mediaService ?? ProfileMediaService();

  final UserProfileService _profileService;
  final ProfileWriteService _writeService;
  final ProfileMediaService _mediaService;

  // ── Lifecycle state ───────────────────────────────────────────────────────
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _userId;
  UserProfile? _profile;

  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
  bool get saving => _saving;
  UserProfile? get profile => _profile;

  /// Role drives which sections render and which columns are written.
  String? get userType => _profile?.userType;
  bool get isBuilder => _profile?.isBuilder ?? false;
  bool get isBroker => _profile?.isBroker ?? false;
  bool get isInfluencer => _profile?.isInfluencer ?? false;

  /// Individual profiles write only the basic columns — EditProfile.tsx:426 gates
  /// the whole business block on the other three roles.
  bool get isBusinessRole => isBuilder || isBroker || isInfluencer;

  /// Once `user_type` is set the database trigger refuses to change it, so the
  /// control is shown read-only rather than editable-but-ignored.
  bool get roleLocked => (_profile?.userType ?? '').isNotEmpty;

  // ── Controllers ───────────────────────────────────────────────────────────
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final username = TextEditingController();
  final companyName = TextEditingController();
  final reraNumber = TextEditingController();
  final city = TextEditingController();
  final yearsExperience = TextEditingController();
  final website = TextEditingController();
  final bio = TextEditingController();
  final officeAddress = TextEditingController();
  final state = TextEditingController();
  final pincode = TextEditingController();
  final landmark = TextEditingController();
  final alternateMobile = TextEditingController();
  final email = TextEditingController();
  final gstNumber = TextEditingController();
  final panNumber = TextEditingController();
  final facebook = TextEditingController();
  final instagram = TextEditingController();
  final linkedin = TextEditingController();
  final youtube = TextEditingController();
  final whatsapp = TextEditingController();
  final telegram = TextEditingController();
  final twitter = TextEditingController();
  final instagramFollowers = TextEditingController();
  final youtubeSubscribers = TextEditingController();
  final audienceType = TextEditingController();
  final commissionDetails = TextEditingController();
  final priceRangeMin = TextEditingController();
  final priceRangeMax = TextEditingController();

  /// Approved decision 5.2 — persisted-but-previously-uneditable fields.
  final portfolioLinks = TextEditingController();
  final previousCollaborations = TextEditingController();

  List<TextEditingController> get _allControllers => [
    fullName,
    phone,
    username,
    companyName,
    reraNumber,
    city,
    yearsExperience,
    website,
    bio,
    officeAddress,
    state,
    pincode,
    landmark,
    alternateMobile,
    email,
    gstNumber,
    panNumber,
    facebook,
    instagram,
    linkedin,
    youtube,
    whatsapp,
    telegram,
    twitter,
    instagramFollowers,
    youtubeSubscribers,
    audienceType,
    commissionDetails,
    priceRangeMin,
    priceRangeMax,
    portfolioLinks,
    previousCollaborations,
  ];

  // ── Single-select state ───────────────────────────────────────────────────
  String _countryCode = '+91';
  String? _gender;
  String? _dob;
  String? _companyType;
  String? _brokerType;
  String? _category;
  String? _primaryPlatform;

  String get countryCode => _countryCode;
  String? get gender => _gender;
  String? get dob => _dob;
  String? get companyType => _companyType;
  String? get brokerType => _brokerType;
  String? get category => _category;
  String? get primaryPlatform => _primaryPlatform;

  set countryCode(String value) {
    _countryCode = value;
    notifyListeners();
  }

  void setGender(String? v) => _setSingle(() => _gender = v);
  void setDob(String? v) => _setSingle(() => _dob = v);
  void setCompanyType(String? v) => _setSingle(() => _companyType = v);
  void setBrokerType(String? v) => _setSingle(() => _brokerType = v);
  void setCategory(String? v) => _setSingle(() => _category = v);
  void setPrimaryPlatform(String? v) => _setSingle(() => _primaryPlatform = v);

  void _setSingle(VoidCallback apply) {
    apply();
    notifyListeners();
  }

  // ── Media state (Phase 4) ─────────────────────────────────────────────────
  //
  // Avatar and cover are written to their columns by `ProfileMediaService` the
  // moment the upload succeeds, so they persist even if the user abandons the
  // form. Document URLs are held here and saved with the rest of the payload,
  // because they live inside `social_media` and must go through the
  // merge-preserving writer.

  String? _avatarUrl;
  String? _backgroundImageUrl;
  String? _companyLogoUrl;
  final Map<ProfileDocumentKind, String> _documentUrls = {};

  /// Raw `social_media.document_reviews` jsonb, kept mutable so a resubmit
  /// (below) can flip one entry's status locally while preserving every
  /// field neither this screen nor the portal's own edit form models
  /// (`requested_at`, etc.) for every other entry — mirrors
  /// EditProfile.tsx's `documentReviews` state.
  Map<String, dynamic> _documentReviewsRaw = {};

  /// Which upload is in flight, so the UI can show a spinner on that row only.
  ProfileMediaTarget? _uploading;

  String? get avatarUrl => _avatarUrl;
  String? get backgroundImageUrl => _backgroundImageUrl;
  String? get companyLogoUrl => _companyLogoUrl;
  ProfileMediaTarget? get uploading => _uploading;

  String? documentUrl(ProfileDocumentKind kind) => _documentUrls[kind];

  /// The admin's review state for [kind], or null if it has never been
  /// reviewed. EditProfile.tsx:970 — the only KYC document upload control
  /// this screen shows is scoped to whichever kind(s) this is
  /// `reupload_requested` for.
  DocumentReviewEntry? reviewFor(ProfileDocumentKind kind) =>
      DocumentReviewEntry.fromValue(_documentReviewsRaw[kind.slug]);

  /// Whether any document is currently flagged for re-upload — gates the
  /// "Action Needed" banner.
  bool get hasFlaggedDocuments => _documentReviewsRaw.values.any(
    (v) => DocumentReviewEntry.fromValue(v)?.isReuploadRequested ?? false,
  );

  /// Picks and uploads the avatar. Returns null on success, else a message.
  Future<String?> pickAndUploadAvatar() =>
      _runUpload(ProfileMediaTarget.avatar, () async {
        final file = await _mediaService.pickAvatar();
        if (file == null) return null;
        _avatarUrl = await _mediaService.uploadAvatar(
          userId: _userId!,
          file: file,
        );
        return null;
      });

  Future<String?> pickAndUploadCover() =>
      _runUpload(ProfileMediaTarget.cover, () async {
        final file = await _mediaService.pickCover();
        if (file == null) return null;
        _backgroundImageUrl = await _mediaService.uploadCover(
          userId: _userId!,
          file: file,
        );
        return null;
      });

  /// Picks and uploads a document. The company logo lands in its own column; the
  /// rest are held for the next save.
  Future<String?> pickAndUploadDocument(ProfileDocumentKind kind) =>
      _runUpload(ProfileMediaTarget.document(kind), () async {
        // Only Aadhaar/PAN accept a PDF and land in the private documents
        // bucket — every other kind picks/uploads exactly as it always has.
        final private = ProfileMediaService.acceptsPdf(kind);
        final file = await _mediaService.pickDocument(allowPdf: private);
        if (file == null) return null;
        final url = await _mediaService.uploadDocument(
          userId: _userId!,
          kind: kind,
          file: file,
          private: private,
        );
        if (kind == ProfileDocumentKind.companyLogo) {
          _companyLogoUrl = url;
        } else {
          _documentUrls[kind] = url;
          // Re-uploading a document an admin flagged clears the flag
          // locally — the admin sees "resubmitted" once Save Changes
          // persists this, rather than the field silently staying stuck on
          // "needs re-upload". Mirrors EditProfile.tsx:429-437.
          if (reviewFor(kind)?.isReuploadRequested ?? false) {
            final existing = _documentReviewsRaw[kind.slug];
            _documentReviewsRaw[kind.slug] = {
              if (existing is Map) ...existing,
              'status': 'resubmitted',
              'resubmitted_at': DateTime.now().toIso8601String(),
            };
          }
        }
        return null;
      });

  Future<String?> _runUpload(
    ProfileMediaTarget target,
    Future<String?> Function() action,
  ) async {
    if (_userId == null) return 'Profile not loaded.';
    if (_uploading != null) return null;

    _uploading = target;
    notifyListeners();
    try {
      return await action();
    } catch (e) {
      debugPrint('EditProfileProvider upload failed: $e');
      if (e is ProfileMediaValidationError) return e.message;
      return 'Upload failed. Please try again.';
    } finally {
      _uploading = null;
      notifyListeners();
    }
  }

  // ── Multi-select state ────────────────────────────────────────────────────
  //
  // Stored lists, not filtered sets. A value absent from the canonical options is
  // still a member here, which is what keeps a wizard-written selection alive
  // (decision 5.1).
  final List<String> _areasOfExpertise = [];
  final List<String> _languagesKnown = [];
  final List<String> _contentTypes = [];
  final List<String> _promotionTypes = [];
  final List<String> _propertyTypes = [];

  List<String> get areasOfExpertise => List.unmodifiable(_areasOfExpertise);
  List<String> get languagesKnown => List.unmodifiable(_languagesKnown);
  List<String> get contentTypes => List.unmodifiable(_contentTypes);
  List<String> get promotionTypes => List.unmodifiable(_promotionTypes);
  List<String> get propertyTypes => List.unmodifiable(_propertyTypes);

  /// Which stored list a chip group edits.
  List<String> _listFor(ProfileChipGroup group) {
    switch (group) {
      case ProfileChipGroup.areasOfExpertise:
        return _areasOfExpertise;
      case ProfileChipGroup.languagesKnown:
        return _languagesKnown;
      case ProfileChipGroup.contentTypes:
        return _contentTypes;
      case ProfileChipGroup.promotionTypes:
        return _promotionTypes;
      case ProfileChipGroup.propertyTypes:
        return _propertyTypes;
    }
  }

  bool isSelected(ProfileChipGroup group, String value) =>
      _listFor(group).contains(value);

  /// Adds or removes [value]. Removal works for legacy values too — that is the
  /// deliberate user action decision 5.1 permits.
  void toggleChip(ProfileChipGroup group, String value) {
    final list = _listFor(group);
    if (list.contains(value)) {
      list.remove(value);
    } else {
      list.add(value);
    }
    notifyListeners();
  }

  /// Adds a free-typed value to [group]'s selection — the "add custom" input
  /// next to the canonical chip options. Unlike [toggleChip], this never
  /// removes: a blank or already-selected value is a no-op, matching
  /// `influencer_registration_screen.dart`'s `_addCustomLanguage`, the
  /// existing verified pattern this mirrors. The value then renders and
  /// removes exactly like any other selected chip — `_ChipGroup` already
  /// shows any selected value outside the canonical list (decision 5.1's
  /// legacy-value handling), so there is nothing else to wire up.
  void addCustomChip(ProfileChipGroup group, String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    final list = _listFor(group);
    if (list.contains(v)) return;
    list.add(v);
    notifyListeners();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load(String userId) async {
    _userId = userId;
    _loading = true;
    _loadFailed = false;
    notifyListeners();

    try {
      final profile = await _profileService.fetchOwn(userId);
      if (profile == null) {
        _loadFailed = true;
      } else {
        _profile = profile;
        _hydrate(profile);
      }
    } catch (e) {
      debugPrint('EditProfileProvider.load failed: $e');
      _loadFailed = true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Fills the form from the row, reproducing EditProfile.tsx's read fallbacks.
  void _hydrate(UserProfile p) {
    final sm = p.socialMedia;

    // A display name containing "@" is an auth artefact, not a name — the portal
    // blanks it rather than showing it (EditProfile.tsx:140).
    final name = p.displayName;
    fullName.text = (name != null && !name.contains('@')) ? name : '';

    // Split the stored E.164-ish value into code + local part.
    _countryCode = '+91';
    phone.text = '';
    final stored = p.phone;
    if (stored != null) {
      final match = _knownCodes.firstWhere(stored.startsWith, orElse: () => '');
      if (match.isEmpty) {
        phone.text = stored;
      } else {
        _countryCode = match;
        phone.text = stored.substring(match.length);
      }
    }

    username.text =
        p.username ??
        (fullName.text.isEmpty
            ? ''
            : fullName.text.toLowerCase().replaceAll(RegExp(r'\s+'), '.'));

    companyName.text = p.companyName ?? '';
    reraNumber.text = p.effectiveRera ?? '';
    city.text = p.effectiveCity ?? '';
    website.text = p.effectiveWebsite ?? '';
    // The edit form's read order is company_description first, unlike the public
    // profile's bio-first display order (EditProfile.tsx:148).
    bio.text = p.companyDescription ?? p.bio ?? '';
    officeAddress.text = p.officeAddress ?? '';
    state.text = p.state ?? '';
    pincode.text = p.pincode ?? '';
    email.text = p.email ?? '';

    final years =
        p.yearsOfExperience ?? p.yearsExperience ?? sm.yearsOfExperience;
    yearsExperience.text = years == null || years == 0 ? '' : '$years';

    landmark.text = sm.landmark ?? '';
    alternateMobile.text = sm.alternateMobile ?? '';
    gstNumber.text = sm.gstNumber ?? '';
    panNumber.text = sm.panNumber ?? '';

    facebook.text = sm.facebook ?? '';
    instagram.text = sm.instagram ?? '';
    linkedin.text = sm.linkedin ?? '';
    youtube.text = sm.youtube ?? '';
    whatsapp.text = sm.whatsapp ?? '';
    telegram.text = sm.telegram ?? '';
    twitter.text = sm.twitter ?? '';

    instagramFollowers.text = sm.instagramFollowers?.toString() ?? '';
    youtubeSubscribers.text = sm.youtubeSubscribers?.toString() ?? '';
    audienceType.text = sm.audienceType ?? '';
    commissionDetails.text = sm.commissionDetails ?? '';
    priceRangeMin.text = sm.priceRangeMin?.toString() ?? '';
    priceRangeMax.text = sm.priceRangeMax?.toString() ?? '';

    // Decision 5.2 — stored as arrays by the influencer wizard.
    portfolioLinks.text = _joinLines(sm.raw['portfolio_links']);
    previousCollaborations.text = _joinLines(
      sm.raw['previous_brand_collaborations'],
    );

    _gender = sm.gender;
    _dob = sm.dob;
    _companyType = sm.companyType;
    _brokerType = sm.brokerType;
    _category = sm.category;
    _primaryPlatform = sm.primaryPlatform;

    // Stored lists copied verbatim — never intersected with the canonical
    // options, which is what preserves legacy values.
    _replace(_areasOfExpertise, sm.areasOfExpertise);
    _replace(_languagesKnown, sm.languagesKnown);
    _replace(_contentTypes, sm.contentTypes);
    _replace(_promotionTypes, sm.preferredPromotionTypes);
    _replace(_propertyTypes, p.propertyTypes);

    // Media (Phase 4).
    _avatarUrl = p.avatarUrl;
    _backgroundImageUrl = p.backgroundImageUrl;
    _companyLogoUrl = p.companyLogoUrl;
    _documentUrls.clear();
    for (final kind in ProfileDocumentKind.values) {
      if (kind == ProfileDocumentKind.companyLogo) continue;
      final url = _storedDocumentUrl(sm, kind);
      if (url != null) _documentUrls[kind] = url;
    }

    final storedReviews = sm.raw['document_reviews'];
    _documentReviewsRaw = storedReviews is Map
        ? Map<String, dynamic>.from(storedReviews)
        : {};
  }

  /// The stored URL for [kind], from the `social_media` key the portal uses.
  static String? _storedDocumentUrl(
    ProfileSocialMedia sm,
    ProfileDocumentKind kind,
  ) {
    switch (kind) {
      case ProfileDocumentKind.rera:
        return sm.reraCertificateUrl;
      case ProfileDocumentKind.gst:
        return sm.gstCertificateUrl;
      case ProfileDocumentKind.pan:
        return sm.panCardUrl;
      case ProfileDocumentKind.registrationProof:
        return sm.registrationProofUrl;
      case ProfileDocumentKind.aadhaar:
        return sm.aadhaarCardUrl;
      case ProfileDocumentKind.aadhaarBack:
        return sm.aadhaarCardBackUrl;
      case ProfileDocumentKind.companyLogo:
        return null;
    }
  }

  static const List<String> _knownCodes = ['+91', '+1', '+44', '+61', '+971'];

  static void _replace(List<String> target, Iterable<String> source) {
    target
      ..clear()
      ..addAll(source);
  }

  static String _joinLines(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .join('\n');
    }
    if (value is String) return value;
    return '';
  }

  static List<String> _splitLines(String value) => value
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  // ── Validation ────────────────────────────────────────────────────────────

  /// First error message, or null when the form is valid.
  ///
  /// Ordered as EditProfile.tsx checks them, so the same input surfaces the same
  /// complaint first on both platforms.
  String? validate() {
    final nameError = ProfileValidators.fullName(fullName.text);
    if (nameError != null) return 'Please enter your full name.';

    final phoneError = ProfileValidators.phoneAtLeast10(phone.text);
    if (phoneError != null) return phoneError;

    final emailError = Validators.email(email.text);
    if (emailError != null)
      return 'Please enter a valid business email address.';

    final altError = ProfileValidators.optionalMobile(alternateMobile.text);
    if (altError != null) return altError;

    final pincodeError = Validators.pincode(pincode.text);
    if (pincodeError != null) return 'Pincode must be exactly 6 digits.';

    final gstError = ProfileValidators.gstNumber(gstNumber.text);
    if (gstError != null) return gstError;

    final panError = ProfileValidators.panNumber(panNumber.text);
    if (panError != null) return panError;

    final yearsError = ProfileValidators.optionalYears(yearsExperience.text);
    if (yearsError != null) return yearsError;

    for (final c in [instagramFollowers, youtubeSubscribers]) {
      final countError = ProfileValidators.optionalCount(c.text);
      if (countError != null) return countError;
    }

    // About broker: at least 50 words.
    if (isBroker) {
      final words = aboutWordCount;
      if (words < kMinAboutBrokerWords) {
        return 'About your agency must be at least $kMinAboutBrokerWords '
            'words (currently $words).';
      }
    }

    // Same 18+ rule the broker/builder registration applies to DOB
    // (broker_registration_screen.dart `_isAtLeast18`). Only checked when a
    // DOB is set — Edit Profile doesn't make it mandatory.
    if (isBusinessRole && _dob != null && _dob!.trim().isNotEmpty) {
      final dob = DateTime.tryParse(_dob!.trim());
      final now = DateTime.now();
      if (dob == null ||
          DateTime(dob.year + 18, dob.month, dob.day).isAfter(now)) {
        return 'You must be at least 18 years old.';
      }
    }

    return null;
  }

  /// Minimum words for a broker's About text.
  static const int kMinAboutBrokerWords = 50;

  /// Words currently in the About/bio field.
  int get aboutWordCount => bio.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  // ── Save ──────────────────────────────────────────────────────────────────

  /// Builds the `profiles` column payload.
  ///
  /// [verifiedIdentity] is the current server-verified email/phone status
  /// (from `IdentityVerificationProvider`), if the caller has it. A verified
  /// channel is managed exclusively through identifier linking from here on
  /// — this generic save must never silently overwrite it with whatever
  /// this screen's own phone/email field currently shows, which could
  /// diverge from (or simply lag) the authenticated value.
  ///
  /// `null` (the default, used by every existing caller/test) preserves the
  /// prior behaviour exactly — always writing `phone` and (for business
  /// roles) `email` — since the caller has no verified-identity data to
  /// reconcile against.
  ///
  /// Visible for testing so the role branches and paired columns can be asserted
  /// without a database.
  @visibleForTesting
  Map<String, dynamic> buildColumnPayload({IdentityStatus? verifiedIdentity}) {
    final cleanPhone = phone.text.replaceAll(RegExp(r'\D'), '');

    final columns = <String, dynamic>{
      'display_name': fullName.text.trim(),
      'username': username.text.trim(),
    };
    if (verifiedIdentity?.phoneVerified != true) {
      columns['phone'] = '$_countryCode$cleanPhone';
    }

    // EditProfile.tsx:426 — the business block is written for the three business
    // roles only. An individual saves the basics and nothing else.
    if (isBusinessRole) {
      final rera = reraNumber.text.trim();
      final site = website.text.trim();
      final about = bio.text.trim();
      final cityValue = city.text.trim();
      final years = int.tryParse(yearsExperience.text.trim());

      columns.addAll(<String, dynamic>{
        'company_name': companyName.text.trim(),
        // Paired columns — both halves, always.
        'rera_number': rera,
        'license_number': rera,
        'website': site,
        'website_url': site,
        'bio': about,
        'company_description': about,
        'years_of_experience': years,
        'years_experience': years,
        'city': cityValue,
        'work_city': cityValue,
        'office_address': officeAddress.text.trim(),
        'state': state.text.trim(),
        'pincode': pincode.text.trim(),
      });
      if (verifiedIdentity?.emailVerified != true) {
        columns['email'] = email.text.trim();
      }

      // Phase 4 — its own column, not a social_media key.
      if (_companyLogoUrl != null) {
        columns['company_logo_url'] = _companyLogoUrl;
      }
    }

    // Decision 5.2 — brokers can now change what they deal in. A column, not a
    // social_media key, because that is where registration already writes it.
    if (isBroker) {
      columns['property_types'] = List<String>.from(_propertyTypes);
    }

    return columns;
  }

  /// Builds the `social_media` changes to merge over the stored map.
  ///
  /// Only keys this screen owns. Everything else in the column survives because
  /// `ProfileWriteService.mergeSocialMedia` spreads the original first.
  @visibleForTesting
  Map<String, dynamic> buildSocialMediaChanges() {
    String? orNull(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    // Always written, for every role — EditProfile.tsx:356-357.
    final changes = <String, dynamic>{'gender': _gender, 'dob': _dob};

    if (isBuilder) {
      changes.addAll(<String, dynamic>{
        'company_type': _companyType,
        'gst_number': orNull(gstNumber),
        'pan_number': orNull(panNumber),
        'landmark': orNull(landmark),
        'alternate_mobile': orNull(alternateMobile),
        'facebook': orNull(facebook),
        'instagram': orNull(instagram),
        'linkedin': orNull(linkedin),
        'youtube': orNull(youtube),
        'whatsapp': orNull(whatsapp),
        'telegram': orNull(telegram),
        'areas_of_expertise': List<String>.from(_areasOfExpertise),
        'languages_known': List<String>.from(_languagesKnown),
      });
    } else if (isBroker) {
      changes.addAll(<String, dynamic>{
        'broker_type': _brokerType,
        'landmark': orNull(landmark),
        // Broker writes `alt_mobile_number`; builder and influencer write
        // `alternate_mobile`. EditProfile.tsx:381 — kept as-is so the portal reads
        // back what it wrote.
        'alt_mobile_number': orNull(alternateMobile),
        'commission_details': orNull(commissionDetails),
        'price_range_min': _numberOrNull(priceRangeMin),
        'price_range_max': _numberOrNull(priceRangeMax),
        'facebook': orNull(facebook),
        'instagram': orNull(instagram),
        'linkedin': orNull(linkedin),
        'youtube': orNull(youtube),
        'whatsapp': orNull(whatsapp),
        'telegram': orNull(telegram),
        'areas_of_expertise': List<String>.from(_areasOfExpertise),
        'languages_known': List<String>.from(_languagesKnown),
      });
    } else if (isInfluencer) {
      changes.addAll(<String, dynamic>{
        'creator_name': orNull(fullName),
        'landmark': orNull(landmark),
        'alternate_mobile': orNull(alternateMobile),
        'category': _category,
        'languages_known': List<String>.from(_languagesKnown),
        'years_of_experience': int.tryParse(yearsExperience.text.trim()),
        'audience_type': orNull(audienceType),
        'primary_content_platform': _primaryPlatform,
        'instagram_username': orNull(instagram),
        'instagram_followers': int.tryParse(instagramFollowers.text.trim()),
        'youtube_channel_link': orNull(youtube),
        'youtube_subscribers': int.tryParse(youtubeSubscribers.text.trim()),
        'facebook_page_link': orNull(facebook),
        'linkedin_profile_url': orNull(linkedin),
        'twitter_profile_url': orNull(twitter),
        'telegram_channel_link': orNull(telegram),
        'whatsapp_number': orNull(whatsapp),
        'content_types': List<String>.from(_contentTypes),
        'preferred_promotion_types': List<String>.from(_promotionTypes),
        // Decision 5.2 — arrays, matching what the wizard writes.
        'portfolio_links': _splitLines(portfolioLinks.text),
        'previous_brand_collaborations': _splitLines(
          previousCollaborations.text,
        ),
      });
    }

    // Phase 4 — document URLs, added only when one exists so a role that never
    // uploaded anything does not write nulls over the portal's values.
    for (final entry in _documentUrls.entries) {
      final key = _socialMediaKeyFor(entry.key);
      if (key != null) changes[key] = entry.value;
    }

    // Always included, mirroring EditProfile.tsx:573 — round-trips unchanged
    // unless a flagged re-upload just flipped one entry to "resubmitted"
    // above.
    changes['document_reviews'] = _documentReviewsRaw;

    return changes;
  }

  /// The `social_media` key each document kind occupies, per EditProfile.tsx.
  static String? _socialMediaKeyFor(ProfileDocumentKind kind) {
    switch (kind) {
      case ProfileDocumentKind.rera:
        return 'rera_certificate_url';
      case ProfileDocumentKind.gst:
        return 'gst_certificate_url';
      case ProfileDocumentKind.pan:
        return 'pan_card_url';
      case ProfileDocumentKind.registrationProof:
        return 'registration_proof_url';
      case ProfileDocumentKind.aadhaar:
        return 'aadhaar_card_url';
      case ProfileDocumentKind.aadhaarBack:
        return 'aadhaar_card_back_url';
      case ProfileDocumentKind.companyLogo:
        // A column, handled in buildColumnPayload.
        return null;
    }
  }

  static num? _numberOrNull(TextEditingController c) {
    final v = c.text.trim().replaceAll(',', '');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }

  /// Validates and saves. Returns null on success, or a user-facing error.
  ///
  /// [verifiedIdentity] is passed through to [buildColumnPayload] — see its
  /// doc comment. Omit it (the default) to preserve prior behaviour exactly.
  Future<String?> save({IdentityStatus? verifiedIdentity}) async {
    final userId = _userId;
    final current = _profile;
    if (userId == null || current == null) return 'Profile not loaded.';

    final error = validate();
    if (error != null) return error;

    _saving = true;
    notifyListeners();

    try {
      await _writeService.saveProfile(
        userId: userId,
        columns: buildColumnPayload(verifiedIdentity: verifiedIdentity),
        // The stored map, so unmodelled keys survive the write.
        socialMediaExisting: current.socialMedia.raw,
        socialMediaChanges: buildSocialMediaChanges(),
      );

      // Builders and brokers only — EditProfile.tsx:452.
      if (isBuilder || isBroker) {
        await _writeService.syncCityPreference(
          userId: userId,
          city: city.text.trim(),
        );
      }

      return null;
    } catch (e) {
      debugPrint('EditProfileProvider.save failed: $e');
      return 'Could not save your profile. Please try again.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Which media row an upload belongs to, so only that row shows a spinner.
@immutable
class ProfileMediaTarget {
  const ProfileMediaTarget._(this.kind, this.isAvatar, this.isCover);

  const ProfileMediaTarget.avatarTarget() : this._(null, true, false);
  const ProfileMediaTarget.coverTarget() : this._(null, false, true);
  const ProfileMediaTarget.document(ProfileDocumentKind kind)
    : this._(kind, false, false);

  static const ProfileMediaTarget avatar = ProfileMediaTarget.avatarTarget();
  static const ProfileMediaTarget cover = ProfileMediaTarget.coverTarget();

  final ProfileDocumentKind? kind;
  final bool isAvatar;
  final bool isCover;

  @override
  bool operator ==(Object other) =>
      other is ProfileMediaTarget &&
      other.kind == kind &&
      other.isAvatar == isAvatar &&
      other.isCover == isCover;

  @override
  int get hashCode => Object.hash(kind, isAvatar, isCover);
}

/// The five multi-select groups on the form.
enum ProfileChipGroup {
  areasOfExpertise,
  languagesKnown,
  contentTypes,
  promotionTypes,
  propertyTypes,
}
