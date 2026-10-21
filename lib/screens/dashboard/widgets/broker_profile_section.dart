// screens/dashboard/widgets/broker_profile_section.dart
//
// Broker Profile on the broker dashboard's Content tab — the port of
// `BrokerProfileManager.tsx`.
//
// WHAT IS EDITABLE, AND WHAT IS NOT
// ---------------------------------
// The portal's form edits fourteen columns across three cards (Professional,
// Location, Contact) and then renders a fourth, **read-only** card for
// Specialization — `property_types` and `operating_cities` are shown as badges with
// no editor (`:461-490`), because the broker registration flow owns them. Its
// `handleSave` sends them back unchanged (`:147-148`).
//
// This does the same: fourteen fields editable, two arrays displayed and preserved
// byte for byte. Inventing checkbox lists for them would add controls the portal
// lacks and risk dropping a stored value — the hazard decision 5.1 was written for.
//
// `approval_status` is read and never written. It is a reviewer's column; sending
// `'pending'` on every save would silently un-approve an approved broker.
//
// This section is NOT the profile-completion registration screen, which is under a
// standing instruction not to be modified and is untouched.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/broker_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/broker_section_models.dart';
import '../../../services/broker_sections_service.dart';
import 'builder_section_kit.dart';

class BrokerProfileSection extends StatefulWidget {
  const BrokerProfileSection({super.key, required this.userId, this.service});

  final String userId;

  @visibleForTesting
  final BrokerProfileService? service;

  @override
  State<BrokerProfileSection> createState() => _BrokerProfileSectionState();
}

class _BrokerProfileSectionState extends State<BrokerProfileSection> {
  late final BrokerProfileService _profiles =
      widget.service ?? BrokerProfileService();

  BrokerProfile? _profile;
  bool _loaded = false;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final row = await _profiles.fetchMine(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = row;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
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

  Future<void> _openEditor() async {
    final draft = await showModalBottomSheet<BrokerProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileSheet(profile: _profile),
    );
    if (draft == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final saved = await _profiles.save(userId: widget.userId, profile: draft);
      if (!mounted) return;
      setState(() => _profile = saved);
      _toast('Profile saved.');
    } catch (e) {
      _toast(
        e is BrokerSectionException
            ? e.message
            : 'Could not save your profile. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return BuilderSectionShell(
      failed: _failed,
      loaded: _loaded,
      // Never collapses: a broker with no profile row is precisely the person who
      // needs the Complete Profile button.
      isEmpty: false,
      onRetry: _load,
      errorTitle: "Couldn't load your profile",
      child: BuilderSectionCard(
        child: _saving
            ? const BuilderActionBusyRow()
            : profile == null
            ? _EmptyProfile(onCreate: _openEditor)
            : _ProfileSummary(profile: profile, onEdit: _openEditor),
      ),
    );
  }
}

class _EmptyProfile extends StatelessWidget {
  const _EmptyProfile({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No broker profile yet',
          style: AppTextStyles.body.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Add your RERA number, agency and contact details so buyers know who '
          'they are dealing with.',
          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: AppConstants.spacingM),
        const Divider(height: 1, color: AppColors.hairline),
        const SizedBox(height: 6),
        BuilderAction(
          icon: Icons.person_add_alt_1_outlined,
          label: 'Complete Profile',
          onTap: onCreate,
        ),
      ],
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile, required this.onEdit});

  final BrokerProfile profile;
  final VoidCallback onEdit;

  static Color _approvalTint(String status) => switch (status) {
    'approved' => AppColors.success,
    'rejected' => AppColors.error,
    _ => AppColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (profile.agencyName != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      profile.agencyName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            BuilderPill(
              label: brokerProfileApprovalLabel(profile.approvalStatus),
              tint: _approvalTint(profile.approvalStatus),
            ),
          ],
        ),

        // Only when there is one — an approved profile has no reason to show a
        // reason, and a pending one has none yet.
        if (profile.isRejected && profile.rejectionReason != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              profile.rejectionReason!,
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
        ],

        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            if (profile.reraNumber != null)
              _Field(label: 'RERA', value: profile.reraNumber!),
            if (profile.licenseNumber != null)
              _Field(label: 'Licence', value: profile.licenseNumber!),
            if (profile.yearsOfExperience > 0)
              _Field(
                label: 'Experience',
                value:
                    '${profile.yearsOfExperience} yr'
                    '${profile.yearsOfExperience == 1 ? '' : 's'}',
              ),
            if (profile.city != null)
              _Field(label: 'City', value: profile.city!),
            if (profile.mobileNumber != null)
              _Field(label: 'Mobile', value: profile.mobileNumber!),
          ],
        ),

        // The read-only Specialization card, as badges — the portal's own
        // treatment. Absent entirely when the registration flow set neither.
        if (profile.propertyTypes.isNotEmpty ||
            profile.operatingCities.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final type in profile.propertyTypes)
                BuilderPill(label: type, tint: AppColors.primary),
              for (final city in profile.operatingCities)
                BuilderPill(label: city, tint: AppColors.textSecondary),
            ],
          ),
        ],

        const SizedBox(height: AppConstants.spacingM),
        const Divider(height: 1, color: AppColors.hairline),
        const SizedBox(height: 6),
        BuilderAction(
          icon: Icons.edit_outlined,
          label: 'Edit Profile',
          onTap: onEdit,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.caption.copyWith(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.textHint,
          ),
        ),
        Text(value, style: AppTextStyles.body.copyWith(fontSize: 12.5)),
      ],
    );
  }
}

/// The portal's three editable cards, as one scrollable sheet.
class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.profile});

  /// Null when creating the row for the first time.
  final BrokerProfile? profile;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  // Letters, spaces, hyphens and apostrophes only — no digits or other symbols.
  static final RegExp _namePattern = RegExp(r"^[a-zA-Z\s'-]+$");

  late final _fullName = _controller(widget.profile?.fullName);
  late final _rera = _controller(widget.profile?.reraNumber);
  late final _licence = _controller(widget.profile?.licenseNumber);
  late final _agency = _controller(widget.profile?.agencyName);
  late final _experience = _controller(
    widget.profile?.yearsOfExperience.toString(),
  );
  late final _description = _controller(widget.profile?.companyDescription);
  late final _office = _controller(widget.profile?.officeAddress);
  late final _city = _controller(widget.profile?.city);
  late final _state = _controller(widget.profile?.state);
  late final _pincode = _controller(widget.profile?.pincode);
  late final _mobile = _controller(widget.profile?.mobileNumber);
  late final _email = _controller(widget.profile?.email);
  late final _website = _controller(widget.profile?.website);

  String? _error;

  static TextEditingController _controller(String? value) =>
      TextEditingController(text: value ?? '');

  List<TextEditingController> get _all => [
    _fullName,
    _rera,
    _licence,
    _agency,
    _experience,
    _description,
    _office,
    _city,
    _state,
    _pincode,
    _mobile,
    _email,
    _website,
  ];

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  /// Trimmed, or null when blank — so a cleared optional field becomes NULL rather
  /// than an empty string. Every one of these columns is nullable.
  String? _optional(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  void _submit() {
    if (_fullName.text.trim().isEmpty) {
      setState(() => _error = 'A full name is required.');
      return;
    }
    if (!_namePattern.hasMatch(_fullName.text.trim())) {
      setState(
        () => _error = 'Name can only contain letters, spaces and hyphens.',
      );
      return;
    }

    Navigator.pop(
      context,
      BrokerProfile(
        // Carried through: null means insert, present means update.
        id: widget.profile?.id,
        fullName: _fullName.text.trim(),
        reraNumber: _optional(_rera),
        licenseNumber: _optional(_licence),
        agencyName: _optional(_agency),
        // The column is `INTEGER DEFAULT 0` and NOT NULL-safe, so an unparseable
        // entry becomes 0 rather than failing the save.
        yearsOfExperience: int.tryParse(_experience.text.trim()) ?? 0,
        companyDescription: _optional(_description),
        officeAddress: _optional(_office),
        city: _optional(_city),
        state: _optional(_state),
        pincode: _optional(_pincode),
        mobileNumber: _optional(_mobile),
        email: _optional(_email),
        website: _optional(_website),
        // Round-tripped untouched. There is no editor for these, here or on the
        // portal.
        propertyTypes: widget.profile?.propertyTypes ?? const [],
        operatingCities: widget.profile?.operatingCities ?? const [],
        approvalStatus: widget.profile?.approvalStatus ?? 'pending',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.profile == null
                    ? 'Complete Your Profile'
                    : 'Edit Profile',
                style: AppTextStyles.heading2.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 18),

              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              _Group(label: 'Professional Details'),
              _Input(
                label: 'Full Name',
                controller: _fullName,
                required: true,
                // A name has no legitimate reason to contain digits.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
                onChanged: () {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              _Input(label: 'RERA Number', controller: _rera),
              _Input(label: 'Licence Number', controller: _licence),
              _Input(label: 'Agency Name', controller: _agency),
              _Input(
                label: 'Years of Experience',
                controller: _experience,
                keyboardType: TextInputType.number,
              ),
              _Input(
                label: 'Company Description',
                controller: _description,
                maxLines: 3,
              ),

              const SizedBox(height: 6),
              _Group(label: 'Location'),
              _Input(label: 'Office Address', controller: _office, maxLines: 2),
              _Input(label: 'City', controller: _city),
              _Input(label: 'State', controller: _state),
              _Input(
                label: 'Pincode',
                controller: _pincode,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 6),
              _Group(label: 'Contact'),
              _Input(
                label: 'Mobile Number',
                controller: _mobile,
                keyboardType: TextInputType.phone,
              ),
              _Input(
                label: 'Email',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
              ),
              _Input(label: 'Website', controller: _website),

              // Shown, not editable — the portal's Specialization card.
              if ((widget.profile?.propertyTypes.isNotEmpty ?? false) ||
                  (widget.profile?.operatingCities.isNotEmpty ?? false)) ...[
                const SizedBox(height: 6),
                _Group(label: 'Specialisation'),
                Text(
                  'Set during registration. Saving here leaves it unchanged.',
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final type in widget.profile!.propertyTypes)
                      BuilderPill(label: type, tint: AppColors.primary),
                    for (final city in widget.profile!.operatingCities)
                      BuilderPill(label: city, tint: AppColors.textSecondary),
                  ],
                ),
              ],

              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save'),
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

class _Group extends StatelessWidget {
  const _Group({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({
    required this.label,
    required this.controller,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final VoidCallback? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.body.copyWith(fontSize: 12.5),
                ),
              ),
              if (required)
                Text(
                  ' *',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    color: AppColors.error,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged == null ? null : (_) => onChanged!(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
