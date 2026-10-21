import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_button.dart';
import '../../providers/auth_provider.dart';
import '../../providers/identity_verification_provider.dart';
import '../../services/identity_verification_service.dart';
import '../../services/profile_media_service.dart';
import '../../widgets/verify_identifier_field.dart';
import 'individual_username_password_screen.dart';

/// Individual sign-up's completion step — the Flutter counterpart of the
/// portal's `ProfileCompletion.tsx` individual branch, field-for-field:
///
///   * Avatar — optional, via [ProfileMediaService], same upload path every
///     other registration screen already uses.
///   * Full Name — pre-filled from the current `display_name`, UNLESS it
///     looks like an email (the portal's `includes('@')` guard). That check
///     exists there specifically because a phone-first signup's
///     `display_name` falls back to the auto-generated `u<phone>@propcid.app`
///     placeholder (`send-otp/index.ts`'s `ensureUser` leaves `display_name`
///     unset when no name was collected at OTP time) — without the guard,
///     that placeholder would otherwise show up as a pre-filled "name".
///   * Phone Number — read-only once a real number is already on the
///     session (`auth.currentUser.phone`, set the moment phone-OTP sign-in
///     completes): "Phone number cannot be changed once set.", matching the
///     portal exactly. Only editable for a Google sign-in, which has no
///     phone on the auth user yet and still needs one collected.
///   * Location — a plain city text field, matching the portal.
///
/// No Username/Password here — the portal has those on its own separate
/// second step ("Set Username & Password"), reached via Continue below —
/// see [IndividualUsernamePasswordScreen], which is also where this
/// screen's fields actually get written.
///
/// Reached only from [AccountTypeScreen]'s "Individual" tile — Builder/
/// Broker/Influencer are untouched and still go straight to their existing
/// registration screens.
class IndividualProfileDetailsScreen extends StatefulWidget {
  const IndividualProfileDetailsScreen({required this.userId, super.key});

  final String userId;

  @override
  State<IndividualProfileDetailsScreen> createState() =>
      _IndividualProfileDetailsScreenState();
}

class _IndividualProfileDetailsScreenState
    extends State<IndividualProfileDetailsScreen> {
  // Letters, spaces, hyphens and apostrophes only — no digits or other symbols.
  static final RegExp _namePattern = RegExp(r"^[a-zA-Z\s'-]+$");

  final ProfileMediaService _mediaService = ProfileMediaService();

  late final TextEditingController _nameCtrl;
  final TextEditingController _cityCtrl = TextEditingController();

  String? _avatarUrl;
  bool _uploadingAvatar = false;

  String? _nameError;
  String? _cityError;
  String? _identityError;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final displayName = auth.userName;
    // `ProfileCompletion.tsx`'s exact guard: a name that "looks like an
    // email" is a placeholder, not a real name, so it isn't pre-filled.
    final prefill = displayName.contains('@') ? '' : displayName;
    _nameCtrl = TextEditingController(text: prefill);
    _avatarUrl = auth.avatarUrl;

    // Server-verified email/phone status drives the fields below — a
    // phone-OTP signup already shows up phone_verified from the backend
    // (see `_shared/identity.ts`'s `isOtpMintedAccount`), no separate
    // client-side "was there already a phone on the session" heuristic
    // needed anymore.
    context.read<IdentityVerificationProvider>().ensureLoaded();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final file = await _mediaService.pickAvatar();
      if (file == null) return;
      final url = await _mediaService.uploadAvatar(
        userId: widget.userId,
        file: file,
      );
      if (!mounted) return;
      setState(() => _avatarUrl = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not upload photo: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final identityStatus = context.read<IdentityVerificationProvider>().status;
    final phoneDigits = identityStatus?.phone;

    setState(() {
      _nameError = name.isEmpty
          ? 'Please enter your name.'
          : !_namePattern.hasMatch(name)
          ? 'Name can only contain letters, spaces and hyphens.'
          : null;
      _cityError = city.isEmpty ? 'Please enter your city.' : null;
      _identityError = (identityStatus?.bothVerified ?? false)
          ? null
          : 'Please verify your email and phone number to continue.';
    });
    if (_nameError != null ||
        _cityError != null ||
        _identityError != null ||
        phoneDigits == null) {
      return;
    }

    // Nothing is written yet — the portal's own second step ("Set Username &
    // Password") is a separate screen from this one, so the actual
    // `profiles` write (plus setting the real password) happens there. This
    // screen only validates and carries the collected fields forward.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IndividualUsernamePasswordScreen(
          userId: widget.userId,
          name: name,
          phoneDigits: phoneDigits,
          city: city,
          avatarUrl: _avatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Complete your profile',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Just a couple more details to get you started.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              Center(child: _avatarPicker()),
              const SizedBox(height: 28),
              const Text(
                'Full Name',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                // A name has no legitimate reason to contain digits.
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Your full name',
                  errorText: _nameError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              VerifyIdentifierField(
                channel: IdentityChannel.email,
                label: 'Email',
                hint: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
                normalizeTarget: (raw) => raw.trim(),
                fieldValidator: (raw) =>
                    raw.trim().contains('@') ? null : 'Enter a valid email address.',
                externalError: _identityError,
              ),
              const SizedBox(height: 20),
              VerifyIdentifierField(
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
                fieldValidator: (raw) => RegExp(r'^[6-9]\d{9}$').hasMatch(raw.trim())
                    ? null
                    : 'Enter a valid 10-digit mobile number.',
                externalError: _identityError,
              ),
              if (_identityError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _identityError!,
                  style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Location',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _cityCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Enter your city',
                  errorText: _cityError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PremiumButton(
                label: 'Continue',
                isLoading: false,
                onPressed: _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarPicker() {
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: AppColors.primaryLight,
          backgroundImage: _avatarUrl != null
              ? NetworkImage(_avatarUrl!)
              : null,
          child: _uploadingAvatar
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : (_avatarUrl == null
                    ? Icon(Icons.person, size: 40, color: AppColors.primary)
                    : null),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _uploadingAvatar ? null : _pickAndUploadAvatar,
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('Upload Photo'),
        ),
      ],
    );
  }
}
