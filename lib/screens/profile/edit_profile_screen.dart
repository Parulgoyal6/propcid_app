// screens/profile/edit_profile_screen.dart
//
// The single Edit Profile experience (approved decision: Option A — this replaces
// the registration-wizard route for every role; there is no second editor).
//
// Section order, headings and field order follow features/profile/EditProfile.tsx.
// Presentation is this app's: `DashboardCard` surfaces, `DashboardSectionLabel`
// headings, `AppActionButton`, `AppConstants` spacing, ordinary `InputDecoration`
// so `AppTheme.inputDecorationTheme` applies unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/profile_options.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/scale_tap.dart';
import '../../providers/auth_provider.dart';
import '../../providers/edit_profile_provider.dart';
import '../../providers/identity_verification_provider.dart';
// `ProfileDocumentKind` is declared alongside the uploader that consumes it.
import '../../services/identity_verification_service.dart';
import '../../services/profile_media_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/verify_identifier_field.dart';

class EditProfileScreen extends StatelessWidget {
  const EditProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => EditProfileProvider(),
      child: const _EditProfileView(),
    );
  }
}

class _EditProfileView extends StatefulWidget {
  const _EditProfileView();

  @override
  State<_EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<_EditProfileView> {
  String? _loadedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadIfNeeded());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;

    final provider = context.read<EditProfileProvider>();
    context.read<IdentityVerificationProvider>().ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId);
    });
  }

  Future<void> _save() async {
    final provider = context.read<EditProfileProvider>();
    final auth = context.read<AuthProvider>();
    final identityProvider = context.read<IdentityVerificationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Guarantees identity status is actually loaded before the payload is
    // built, rather than racing it — `ensureLoaded` is a no-op if it's
    // already loaded. Without this, a Save tapped before the first load
    // resolves would pass `verifiedIdentity: null`, which still can't write
    // a *wrong* value (buildColumnPayload falls back to whatever was
    // already loaded from `profiles`, not an edited one — the fields are no
    // longer freely editable), but it could needlessly re-send an
    // already-verified value's un-reconciled form-field copy. Closing the
    // race outright is simpler than reasoning about why the fallback is
    // safe.
    await identityProvider.ensureLoaded();
    if (!mounted) return;

    final error = await provider.save(
      verifiedIdentity: identityProvider.status,
    );
    if (!mounted) return;

    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // Re-read so every screen holding AuthProvider's cached row sees the change.
    await auth.refreshProfile();
    if (!mounted) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Profile updated')));
    navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EditProfileProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Edit Profile',
          style: AppTextStyles.heading3.copyWith(fontSize: 16),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: ColoredBox(
            color: AppColors.hairline,
            child: SizedBox(height: 1),
          ),
        ),
      ),
      body: _buildBody(provider),
      bottomNavigationBar: provider.loading || provider.loadFailed
          ? null
          : _SaveBar(saving: provider.saving, onSave: _save),
    );
  }

  Widget _buildBody(EditProfileProvider p) {
    if (p.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (p.loadFailed) {
      return Center(
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your profile",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: () {
            final userId = context.read<AuthProvider>().userId;
            if (userId != null) p.load(userId);
          },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingL,
        AppConstants.spacingL,
        AppConstants.spacingL,
        AppConstants.spacingXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mediaSection(p),
          const SizedBox(height: AppConstants.spacingL),
          _basicSection(p),
          if (p.hasFlaggedDocuments) ...[
            const SizedBox(height: AppConstants.spacingL),
            _reuploadBanner(p),
          ],
          if (p.isBuilder) ...[
            const SizedBox(height: AppConstants.spacingL),
            _builderCompanySection(p),
            const SizedBox(height: AppConstants.spacingL),
            _addressSection(p, title: 'Office address & contacts'),
            const SizedBox(height: AppConstants.spacingL),
            _builderDetailsSection(p),
            const SizedBox(height: AppConstants.spacingL),
            _socialSection(p),
          ],
          if (p.isBroker) ...[
            const SizedBox(height: AppConstants.spacingL),
            _brokerProfessionalSection(p),
            const SizedBox(height: AppConstants.spacingL),
            _addressSection(p, title: 'Office address & contacts'),
            const SizedBox(height: AppConstants.spacingL),
            _brokerDealsSection(p),
            const SizedBox(height: AppConstants.spacingL),
            _socialSection(p),
          ],
          if (p.isInfluencer) ...[
            const SizedBox(height: AppConstants.spacingL),
            _influencerProfileSection(p),
            const SizedBox(height: AppConstants.spacingL),
            _addressSection(p, title: 'Work address & contacts'),
            const SizedBox(height: AppConstants.spacingL),
            _influencerSocialSection(p),
            const SizedBox(height: AppConstants.spacingL),
            _influencerContentSection(p),
          ],
          // EditProfile.tsx:2205 — "No additional details for individual role".
          if (!p.isBusinessRole) ...[
            const SizedBox(height: AppConstants.spacingL),
            _individualNote(),
          ],
          if (_documentKindsFor(p).isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingL),
            _documentsSection(p),
          ],
        ],
      ),
    );
  }

  /// Which verification documents this role uploads.
  ///
  /// EditProfile.tsx: builder 912-1013, broker 1532-1599, influencer 2153-2199.
  /// Individuals upload none.
  List<ProfileDocumentKind> _documentKindsFor(EditProfileProvider p) {
    if (p.isBuilder) {
      // No RERA row for builders — EditProfile.tsx's builder section (912-
      // 1013) only ever shows a "RERA / License Number" text field (see
      // `p.reraNumber` below), never a document/upload status row; the
      // portal's registration never collects a builder RERA certificate
      // either, so a permanent "Not uploaded" row here had nothing it could
      // ever reflect as uploaded.
      return const [
        ProfileDocumentKind.gst,
        ProfileDocumentKind.pan,
        ProfileDocumentKind.registrationProof,
        ProfileDocumentKind.companyLogo,
      ];
    }
    if (p.isBroker) {
      return const [
        ProfileDocumentKind.rera,
        ProfileDocumentKind.pan,
        ProfileDocumentKind.aadhaar,
      ];
    }
    if (p.isInfluencer) {
      return const [ProfileDocumentKind.aadhaar, ProfileDocumentKind.pan];
    }
    return const [];
  }

  static String _documentLabel(ProfileDocumentKind kind) => switch (kind) {
    ProfileDocumentKind.rera => 'RERA certificate',
    ProfileDocumentKind.gst => 'GST certificate',
    ProfileDocumentKind.pan => 'PAN card',
    ProfileDocumentKind.registrationProof => 'Registration proof',
    ProfileDocumentKind.aadhaar => 'Aadhaar card',
    // Not currently reachable: _documentKindsFor never includes this kind,
    // matching the portal's own EditProfile.tsx, which has no Aadhaar-back
    // row either (see _documentKindsFor's doc comment). Exhaustiveness only.
    ProfileDocumentKind.aadhaarBack => 'Aadhaar card (back)',
    ProfileDocumentKind.companyLogo => 'Company logo',
  };

  Future<void> _runUpload(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (!mounted || error == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error)));
  }

  Widget _mediaSection(EditProfileProvider p) => _Section(
    title: 'Photos',
    children: [
      _AvatarRow(
        url: p.avatarUrl,
        busy: p.uploading == ProfileMediaTarget.avatar,
        onChange: () => _runUpload(p.pickAndUploadAvatar),
      ),
      _MediaRow(
        label: 'Cover photo',
        url: p.backgroundImageUrl,
        busy: p.uploading == ProfileMediaTarget.cover,
        onChange: () => _runUpload(p.pickAndUploadCover),
      ),
    ],
  );

  Widget _documentsSection(EditProfileProvider p) => _Section(
    title: 'Verification documents',
    children: [
      for (final kind in _documentKindsFor(p))
        _MediaRow(
          label: _documentLabel(kind),
          url: kind == ProfileDocumentKind.companyLogo
              ? p.companyLogoUrl
              : p.documentUrl(kind),
          isPdfCapable: ProfileMediaService.acceptsPdf(kind),
          busy: p.uploading == ProfileMediaTarget.document(kind),
          // KYC documents (everything but the company logo) can only be
          // re-uploaded once an admin explicitly flags one — see
          // `_reuploadBanner`. EditProfile.tsx has no upload input for these
          // at all outside that flagged state; matching that here is what
          // actually stops a user from freely changing an already-submitted
          // PAN/Aadhaar.
          onChange: kind == ProfileDocumentKind.companyLogo
              ? () => _runUpload(() => p.pickAndUploadDocument(kind))
              : null,
        ),
      Text(
        _documentsCaption(p),
        style: AppTextStyles.caption.copyWith(
          fontSize: 11.5,
          color: AppColors.textHint,
        ),
      ),
    ],
  );

  /// Aadhaar/PAN accept image or PDF now; every other document kind is still
  /// image-only, so the caption states whichever is actually true for this
  /// role's document set instead of one blanket line.
  String _documentsCaption(EditProfileProvider p) {
    final kinds = _documentKindsFor(p);
    if (kinds.isEmpty) return '';
    final pdfCapable = kinds.where(ProfileMediaService.acceptsPdf).toList();
    if (pdfCapable.isEmpty) return 'Images only.';
    if (pdfCapable.length == kinds.length) return 'Images or PDF, up to 20MB.';
    return 'Aadhaar and PAN accept images or PDF (max 20MB). '
        'Other documents: images only.';
  }

  /// "Action Needed: Re-upload Documents" — EditProfile.tsx:969-1002. Shown
  /// only while at least one of this role's documents carries a
  /// `document_reviews[kind].status == 'reupload_requested'` entry, and
  /// lists only those flagged fields, never the whole document set.
  Widget _reuploadBanner(EditProfileProvider p) {
    final flagged = _documentKindsFor(
      p,
    ).where((k) => p.reviewFor(k)?.isReuploadRequested ?? false).toList();
    if (flagged.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                'Action Needed: Re-upload Documents',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingM),
          for (var i = 0; i < flagged.length; i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingM),
            _ReuploadRow(
              label: _documentLabel(flagged[i]),
              reason: p.reviewFor(flagged[i])?.reason,
              busy: p.uploading == ProfileMediaTarget.document(flagged[i]),
              onUpload: () =>
                  _runUpload(() => p.pickAndUploadDocument(flagged[i])),
            ),
          ],
        ],
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _basicSection(EditProfileProvider p) => _Section(
    title: 'Basic information',
    children: [
      _Field(
        label: 'Full name',
        controller: p.fullName,
        required: true,
        hint: 'Enter your full name',
        // A name has no legitimate reason to contain digits — see
        // ProfileValidators.fullName, the save-time check this mirrors.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
        ],
      ),
      _PhoneField(provider: p),
      // Shown for every role, including Individual — this is the login
      // identifier, not the business-contact "email" column the old
      // `_addressSection` field used to double as. Individual profiles have
      // no `email` column write at all (see buildColumnPayload), so this is
      // purely about letting them link/verify their email identity via
      // verify-identifier; it never touches `profiles`.
      VerifyIdentifierField(
        channel: IdentityChannel.email,
        label: 'Email',
        hint: 'you@example.com',
        keyboardType: TextInputType.emailAddress,
        normalizeTarget: (raw) => raw.trim(),
        fieldValidator: (raw) =>
            raw.trim().contains('@') ? null : 'Enter a valid email address.',
      ),
      _ReadOnlyField(
        label: 'User type',
        value: p.userType?.isNotEmpty == true ? p.userType! : 'Not set',
        note: p.roleLocked ? 'Role cannot be changed once set.' : null,
      ),
      _Field(
        label: 'Username',
        controller: p.username,
        hint: 'Choose username',
      ),
      // EditProfile.tsx:634 hides these two for individuals.
      if (p.isBusinessRole) ...[
        _Dropdown(
          label: 'Gender',
          value: p.gender,
          options: mergeSingle(kGenderOptions, p.gender),
          onChanged: p.setGender,
        ),
        _DateField(label: 'Date of birth', value: p.dob, onChanged: p.setDob),
      ],
    ],
  );

  Widget _builderCompanySection(EditProfileProvider p) => _Section(
    title: 'Company details',
    children: [
      _Field(
        label: 'Company / agency name',
        controller: p.companyName,
        hint: 'e.g. Prestige Builders Ltd.',
      ),
      _Field(
        label: 'RERA / license number',
        controller: p.reraNumber,
        hint: 'e.g. MH12345678',
      ),
      _Dropdown(
        label: 'Company structure',
        value: p.companyType,
        options: mergeSingle(kCompanyTypeOptions, p.companyType),
        legacyOptions: kCompanyTypeOptions,
        onChanged: p.setCompanyType,
      ),
      _Field(label: 'Base city', controller: p.city, hint: 'e.g. Mumbai'),
      _Field(
        label: 'Years of experience',
        controller: p.yearsExperience,
        keyboardType: TextInputType.number,
        hint: 'e.g. 10',
      ),
      _Field(
        label: 'Website URL',
        controller: p.website,
        hint: 'e.g. www.yourcompany.com',
      ),
      _Field(
        label: 'GST number',
        controller: p.gstNumber,
        hint: '15-digit GSTIN',
      ),
      _Field(
        label: 'PAN number',
        controller: p.panNumber,
        hint: '10-digit PAN',
      ),
      _Field(
        label: 'About company',
        controller: p.bio,
        maxLines: 4,
        hint: 'Describe your company, expertise, or property offerings…',
      ),
    ],
  );

  Widget _brokerProfessionalSection(EditProfileProvider p) => _Section(
    title: 'Professional details',
    children: [
      _Field(
        label: 'Company name',
        controller: p.companyName,
        hint: 'e.g. Dream Realty Services',
      ),
      _Dropdown(
        label: 'Broker type',
        value: p.brokerType,
        options: mergeSingle(kBrokerTypeOptions, p.brokerType),
        legacyOptions: kBrokerTypeOptions,
        onChanged: p.setBrokerType,
      ),
      _Field(
        label: 'RERA / license number',
        controller: p.reraNumber,
        hint: 'e.g. MH12345678',
      ),
      _Field(label: 'City', controller: p.city, hint: 'e.g. Mumbai'),
      _Field(
        label: 'Years of experience',
        controller: p.yearsExperience,
        keyboardType: TextInputType.number,
        hint: 'e.g. 5',
      ),
      _Field(
        label: 'Website URL',
        controller: p.website,
        hint: 'e.g. www.youragency.com',
      ),
      _Field(
        label: 'About your agency',
        controller: p.bio,
        required: true,
        maxLines: 4,
        hint: 'Years in the market, specialisations…',
      ),
      // Live count toward the 50-word minimum enforced on save
      // (EditProfileProvider.validate).
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: p.bio,
        builder: (context, _, _) {
          final words = p.aboutWordCount;
          const min = EditProfileProvider.kMinAboutBrokerWords;
          return Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$words words ($min minimum)',
              style: AppTextStyles.caption.copyWith(
                fontSize: 11,
                color: words >= min ? AppColors.success : AppColors.textHint,
              ),
            ),
          );
        },
      ),
    ],
  );

  Widget _brokerDealsSection(EditProfileProvider p) => _Section(
    title: 'Deals & expertise',
    children: [
      // Decision 5.2 — previously write-once at registration.
      _ChipGroup(
        label: 'Property types you deal in',
        group: ProfileChipGroup.propertyTypes,
        canonical: kPropertyTypeOptions,
        provider: p,
      ),
      _ChipGroup(
        label: 'Areas of expertise',
        group: ProfileChipGroup.areasOfExpertise,
        canonical: kExpertiseOptions,
        provider: p,
        // Portal parity (EditProfile.tsx's custom area box): a value outside
        // the fixed list can be added and saved.
        allowCustom: true,
        customHint: 'Add an area of expertise…',
      ),
      _ChipGroup(
        label: 'Languages known',
        group: ProfileChipGroup.languagesKnown,
        canonical: kLanguageOptions,
        provider: p,
        // Same custom-language box the influencer section already has.
        allowCustom: true,
        customHint: 'Add a language…',
      ),
      // Commission details / price range min-max are not on the portal's
      // Edit Profile, so they aren't shown here either. Their saved values
      // still round-trip untouched (EditProfileProvider loads and re-sends
      // them), so hiding the fields never blanks existing data.
    ],
  );

  Widget _builderDetailsSection(EditProfileProvider p) => _Section(
    title: 'Builder details',
    children: [
      _ChipGroup(
        label: 'Areas of expertise',
        group: ProfileChipGroup.areasOfExpertise,
        canonical: kExpertiseOptions,
        provider: p,
        // Portal parity (EditProfile.tsx's custom area box): a value outside
        // the fixed list can be added and saved.
        allowCustom: true,
        customHint: 'Add an area of expertise…',
      ),
      _ChipGroup(
        label: 'Languages known',
        group: ProfileChipGroup.languagesKnown,
        canonical: kLanguageOptions,
        provider: p,
        // Same custom-language box the influencer section already has.
        allowCustom: true,
        customHint: 'Add a language…',
      ),
    ],
  );

  Widget _influencerProfileSection(EditProfileProvider p) => _Section(
    title: 'Influencer profile',
    children: [
      _Dropdown(
        label: 'Category',
        value: p.category,
        options: mergeSingle(kInfluencerCategoryOptions, p.category),
        legacyOptions: kInfluencerCategoryOptions,
        onChanged: p.setCategory,
      ),
      _Dropdown(
        label: 'Primary platform',
        value: p.primaryPlatform,
        options: mergeSingle(kPrimaryPlatformOptions, p.primaryPlatform),
        legacyOptions: kPrimaryPlatformOptions,
        onChanged: p.setPrimaryPlatform,
      ),
      _Field(
        label: 'Years of experience',
        controller: p.yearsExperience,
        keyboardType: TextInputType.number,
        hint: 'e.g. 3',
      ),
      // Free text on the portal, a dropdown in the wizard. The portal wins.
      _Field(
        label: 'Audience type',
        controller: p.audienceType,
        hint: 'e.g. Luxury Seekers, First-time Buyers',
      ),
      _Field(
        label: 'Website / portfolio',
        controller: p.website,
        hint: 'e.g. www.yourportfolio.com',
      ),
      _ChipGroup(
        label: 'Languages known',
        group: ProfileChipGroup.languagesKnown,
        canonical: kLanguageOptions,
        provider: p,
        // The one group Edit Profile previously had no way to extend beyond
        // the fixed canonical list — `languages_known` is a plain, unchecked
        // string array server-side (see `_shared/registration.ts`'s
        // `dbArray`), so a free-typed value persists safely.
        allowCustom: true,
        customHint: 'Add a language…',
      ),
      _Field(
        label: 'Bio',
        controller: p.bio,
        maxLines: 4,
        hint: 'Your content niche, platform metrics, collaborating brands…',
      ),
    ],
  );

  Widget _influencerSocialSection(EditProfileProvider p) => _Section(
    title: 'Social media & metrics',
    children: [
      _Field(label: 'Instagram', controller: p.instagram),
      _Field(
        label: 'Instagram followers',
        controller: p.instagramFollowers,
        keyboardType: TextInputType.number,
      ),
      _Field(label: 'YouTube', controller: p.youtube),
      _Field(
        label: 'YouTube subscribers',
        controller: p.youtubeSubscribers,
        keyboardType: TextInputType.number,
      ),
      _Field(label: 'Facebook', controller: p.facebook),
      _Field(label: 'LinkedIn', controller: p.linkedin),
      _Field(label: 'WhatsApp', controller: p.whatsapp),
      _Field(label: 'Telegram', controller: p.telegram),
      _Field(label: 'Twitter / X', controller: p.twitter),
    ],
  );

  Widget _influencerContentSection(EditProfileProvider p) => _Section(
    title: 'Content & promotion',
    children: [
      _ChipGroup(
        label: 'Content types',
        group: ProfileChipGroup.contentTypes,
        canonical: kContentTypeOptions,
        provider: p,
      ),
      _ChipGroup(
        label: 'Preferred promotion types',
        group: ProfileChipGroup.promotionTypes,
        canonical: kPromotionTypeOptions,
        provider: p,
      ),
      // Portfolio links / previous brand collaborations deliberately not
      // shown here: they're write-once at registration
      // (`influencer-registration-submit`) and `edit-profile-save` never
      // reads or re-writes either key for any role, so editing them here
      // would silently no-op on save. The provider still hydrates and writes
      // `p.portfolioLinks`/`p.previousCollaborations` unchanged, in case a
      // future backend contract makes them editable again.
    ],
  );

  Widget _addressSection(EditProfileProvider p, {required String title}) =>
      _Section(
        title: title,
        children: [
          _Field(
            label: 'Address',
            controller: p.officeAddress,
            maxLines: 2,
            hint: 'Enter full address',
          ),
          _Field(
            label: 'Landmark',
            controller: p.landmark,
            hint: 'e.g. Near metro station',
          ),
          _Field(label: 'State', controller: p.state, hint: 'e.g. Maharashtra'),
          _Field(
            label: 'Pincode',
            controller: p.pincode,
            keyboardType: TextInputType.number,
            hint: '6-digit pincode',
          ),
          _Field(
            label: 'Alternate mobile',
            controller: p.alternateMobile,
            keyboardType: TextInputType.phone,
          ),
        ],
      );

  Widget _socialSection(EditProfileProvider p) => _Section(
    title: 'Social media',
    children: [
      _Field(label: 'Facebook', controller: p.facebook),
      _Field(label: 'Instagram', controller: p.instagram),
      _Field(label: 'LinkedIn', controller: p.linkedin),
      _Field(label: 'YouTube', controller: p.youtube),
      _Field(label: 'WhatsApp', controller: p.whatsapp),
      _Field(label: 'Telegram', controller: p.telegram),
    ],
  );

  Widget _individualNote() => DashboardCard(
    child: Text(
      'Individual profiles need only the basics above.',
      style: AppTextStyles.caption.copyWith(fontSize: 12.5),
    ),
  );
}

/// Avatar preview + change action.
class _AvatarRow extends StatelessWidget {
  final String? url;
  final bool busy;
  final VoidCallback onChange;

  const _AvatarRow({
    required this.url,
    required this.busy,
    required this.onChange,
  });

  /// A row whose stored value is the R1 placeholder is treated as having no photo.
  ///
  /// `ProfileService.saveBuilderProfile` writes the literal string
  /// `'placeholder_profile.jpg'` into `avatar_url` at registration (defect R1,
  /// out of scope). Rendering it would attempt to load a relative path as a URL
  /// and show a broken image; treating it as absent shows the placeholder circle
  /// and invites the user to upload — which also repairs the row.
  bool get _hasPhoto =>
      url != null &&
      url!.isNotEmpty &&
      !url!.endsWith('placeholder_profile.jpg') &&
      !url!.endsWith('placeholder_logo.jpg');

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: ClipOval(
            child: _hasPhoto
                ? Image.network(
                    url!,
                    fit: BoxFit.cover,
                    width: 64,
                    height: 64,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.primary,
                    ),
                  )
                : const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.primary,
                  ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingL),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile photo',
                style: AppTextStyles.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _hasPhoto ? 'Uploaded' : 'No photo yet',
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        _UploadButton(busy: busy, onTap: onChange),
      ],
    );
  }
}

/// A labelled upload row with an uploaded/not-yet state.
///
/// [onChange] is null for a KYC document locked against re-upload — see
/// `_documentsSection`. The row still shows its uploaded/not-uploaded status;
/// it just renders no "Change" control at all, matching EditProfile.tsx
/// having no upload input for these fields outside the flagged-for-reupload
/// banner.
class _MediaRow extends StatelessWidget {
  final String label;
  final String? url;
  final bool busy;
  final VoidCallback? onChange;

  /// Whether this row's document kind can be a PDF (Aadhaar/PAN). Used only
  /// to pick the uploaded-state icon below — the stored value (a private
  /// storage path or a legacy URL) is never fetched or rendered here, PDF or
  /// image alike, so a document's contents are never exposed on this screen.
  final bool isPdfCapable;

  const _MediaRow({
    required this.label,
    required this.url,
    required this.busy,
    required this.onChange,
    this.isPdfCapable = false,
  });

  bool get _has =>
      url != null &&
      url!.isNotEmpty &&
      !url!.endsWith('placeholder_logo.jpg') &&
      !url!.endsWith('placeholder_profile.jpg');

  bool get _isPdf => isPdfCapable && (url ?? '').toLowerCase().endsWith('.pdf');

  @override
  Widget build(BuildContext context) {
    final icon = !_has
        ? Icons.upload_file_outlined
        : _isPdf
        ? Icons.picture_as_pdf_outlined
        : Icons.check_rounded;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _has ? AppColors.primaryLight : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: _has ? AppColors.primary : AppColors.textHint,
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _has ? 'Uploaded' : 'Not uploaded',
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),
            ],
          ),
        ),
        if (onChange != null) _UploadButton(busy: busy, onTap: onChange!),
      ],
    );
  }
}

/// One row inside `_reuploadBanner` — label, admin's optional reason, and an
/// always-active upload control (unlike `_MediaRow`, this one is never
/// locked; being rendered here at all already means an admin flagged it).
class _ReuploadRow extends StatelessWidget {
  final String label;
  final String? reason;
  final bool busy;
  final VoidCallback onUpload;

  const _ReuploadRow({
    required this.label,
    required this.reason,
    required this.busy,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (reason != null && reason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    "Admin's note: $reason",
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.5,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingM),
          _UploadButton(busy: busy, onTap: onUpload),
        ],
      ),
    );
  }
}

class _UploadButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _UploadButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 44,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'Upload',
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            ),
            child: Center(
              child: Text(
                'Change',
                style: AppTextStyles.chip.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form primitives
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DashboardSectionLabel(title),
          const SizedBox(height: AppConstants.spacingM),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingM),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Ordinary `InputDecoration` so `AppTheme.inputDecorationTheme` applies — this
/// form deliberately does NOT use a custom container, which is what would require
/// the six-slot border override documented in `search_bar_widget.dart`.
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, required: required),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: AppTextStyles.body.copyWith(fontSize: 14),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;

  const _FieldLabel({required this.label, this.required = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      required ? '$label *' : label,
      style: AppTextStyles.caption.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final String? note;

  const _ReadOnlyField({required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
          ),
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(
            note!,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;

  /// The canonical set. Anything in [options] outside it is flagged as legacy.
  final List<String>? legacyOptions;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.legacyOptions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          style: AppTextStyles.body.copyWith(fontSize: 14),
          decoration: const InputDecoration(hintText: 'Select'),
          items: [
            for (final option in options)
              DropdownMenuItem(
                value: option,
                child: Text(
                  legacyOptions != null && isLegacyValue(legacyOptions!, option)
                      ? '$option  (existing)'
                      : option,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = value == null ? null : DateTime.tryParse(value!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label),
        const SizedBox(height: 6),
        ScaleTap(
          onTap: () async {
            final now = DateTime.now();
            // Same 18+ limit as registration's DOB picker. A stored date
            // later than that is clamped, since showDatePicker asserts when
            // initialDate falls after lastDate.
            final maxDob = DateTime(now.year - 18, now.month, now.day);
            final initial = parsed ?? DateTime(now.year - 30);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial.isAfter(maxDob) ? maxDob : initial,
              firstDate: DateTime(1940),
              lastDate: maxDob,
            );
            if (picked != null) {
              // ISO `yyyy-MM-dd`, matching what the portal's date input stores.
              onChanged(
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
              );
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null || value!.isEmpty ? 'Select date' : value!,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      color: value == null || value!.isEmpty
                          ? AppColors.textHint
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  final EditProfileProvider provider;

  const _PhoneField({required this.provider});

  @override
  Widget build(BuildContext context) {
    // Portal parity: the primary login phone is a verified identifier, not
    // a freely-editable text field — see VerifyIdentifierField. The old
    // dropdown+TextField pair let this drift from the authenticated phone;
    // this fixes that rather than only hiding the symptom.
    return VerifyIdentifierField(
      channel: IdentityChannel.phone,
      label: 'Phone number',
      hint: '10-digit mobile number',
      keyboardType: TextInputType.phone,
      prefixText: '+91  ',
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
      ],
      normalizeTarget: (raw) => raw.trim(),
      fieldValidator: (raw) => RegExp(r'^[6-9]\d{9}$').hasMatch(raw.trim())
          ? null
          : 'Enter a valid 10-digit mobile number.',
    );
  }
}

/// A wrap of selectable chips.
///
/// Renders `mergeSelection(canonical, stored)`, so a value written by the
/// registration wizard that is absent from the React vocabulary still appears and
/// stays selected (approved decision 5.1). Legacy chips are marked, and once
/// removed they cannot be re-added — which is the point: the canonical vocabulary
/// is where the profile should end up.
class _ChipGroup extends StatefulWidget {
  final String label;
  final ProfileChipGroup group;
  final List<String> canonical;
  final EditProfileProvider provider;

  /// Shows a free-text "add custom" input below the chips — enabled for the
  /// Languages known and Areas of expertise groups, so a value outside the
  /// fixed canonical list can be added (as on the portal). Off by default so
  /// every other `_ChipGroup` call site is unchanged.
  final bool allowCustom;
  final String customHint;

  const _ChipGroup({
    required this.label,
    required this.group,
    required this.canonical,
    required this.provider,
    this.allowCustom = false,
    this.customHint = 'Add custom…',
  });

  @override
  State<_ChipGroup> createState() => _ChipGroupState();
}

class _ChipGroupState extends State<_ChipGroup> {
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  List<String> _selectedFor() {
    switch (widget.group) {
      case ProfileChipGroup.areasOfExpertise:
        return widget.provider.areasOfExpertise;
      case ProfileChipGroup.languagesKnown:
        return widget.provider.languagesKnown;
      case ProfileChipGroup.contentTypes:
        return widget.provider.contentTypes;
      case ProfileChipGroup.promotionTypes:
        return widget.provider.promotionTypes;
      case ProfileChipGroup.propertyTypes:
        return widget.provider.propertyTypes;
    }
  }

  void _addCustom() {
    // Mirrors influencer_registration_screen.dart's `_addCustomLanguage`:
    // clear regardless, and a blank/duplicate entry is a silent no-op, not
    // an error — there's nothing wrong with pressing Add on an empty field.
    final value = _customCtrl.text;
    _customCtrl.clear();
    widget.provider.addCustomChip(widget.group, value);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedFor();
    final chips = mergeSelection(widget.canonical, selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: widget.label),
        const SizedBox(height: AppConstants.spacingS),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in chips)
              _SelectableChip(
                label: value,
                isSelected: selected.contains(value),
                isLegacy: isLegacyValue(widget.canonical, value),
                onTap: () => widget.provider.toggleChip(widget.group, value),
              ),
          ],
        ),
        if (widget.allowCustom) ...[
          const SizedBox(height: AppConstants.spacingS),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customCtrl,
                  style: AppTextStyles.body.copyWith(fontSize: 14),
                  decoration: InputDecoration(hintText: widget.customHint),
                  onSubmitted: (_) => _addCustom(),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              OutlinedButton(onPressed: _addCustom, child: const Text('Add')),
            ],
          ),
        ],
      ],
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isLegacy;
  final VoidCallback onTap;

  const _SelectableChip({
    required this.label,
    required this.isSelected,
    required this.isLegacy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? AppColors.primary : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: isLegacy ? '$label, existing value' : label,
      child: ExcludeSemantics(
        child: ScaleTap(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primaryLight
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              border: isLegacy
                  ? Border.all(color: AppColors.warning, width: 1)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check_rounded, size: 14, color: fg),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.chip.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
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

class _SaveBar extends StatelessWidget {
  final bool saving;
  final VoidCallback onSave;

  const _SaveBar({required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: AppConstants.spacingL,
        right: AppConstants.spacingL,
        top: 10,
        bottom: 10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(top: BorderSide(color: AppColors.textHint, width: 0.5)),
      ),
      child: AppActionButton(
        label: saving ? 'Saving…' : 'Update profile',
        variant: AppActionButtonVariant.solid,
        elevated: true,
        height: 46,
        onTap: saving ? null : onSave,
      ),
    );
  }
}
