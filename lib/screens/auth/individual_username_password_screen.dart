import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/registration_password_update.dart';
import '../../providers/auth_provider.dart';
import '../../services/registration_submit_service.dart';
import '../home/home_screen.dart';

/// Individual sign-up's final step — "Set Username & Password", reached
/// from [IndividualProfileDetailsScreen]'s Continue button. Matches the
/// live portal's own second step: Username + Password/Confirm Password, so
/// the person can sign in with a username/password later instead of always
/// needing phone OTP.
///
/// This is the screen that actually writes the `profiles` row — the
/// previous step only collects and validates name/phone/city/avatar and
/// hands them here unsaved, exactly the shape the portal's two-step flow
/// implies (a "Back" button that returns to an intact previous form only
/// makes sense if nothing was committed yet).
///
/// Password is set via Supabase's own `updateUser(password:)`, not a plain
/// `profiles` column — same mechanism already used to move password
/// collection off Builder/Broker/Influencer's sign-up form and onto their
/// registration screen's Account Setup step. A phone-OTP account already has
/// a real password on it (a random one nobody knows, minted by the shared
/// `send-otp` function's `ensureUser`, `send-otp/index.ts:201-207`) — this
/// simply overwrites it with the one chosen here. A Google-signed-in account
/// has no password at all yet; `updateUser` adds one, letting username/
/// password become a second way in alongside Google.
class IndividualUsernamePasswordScreen extends StatefulWidget {
  const IndividualUsernamePasswordScreen({
    required this.userId,
    required this.name,
    required this.phoneDigits,
    required this.city,
    this.avatarUrl,
    super.key,
  });

  final String userId;
  final String name;
  final String phoneDigits;
  final String city;
  final String? avatarUrl;

  @override
  State<IndividualUsernamePasswordScreen> createState() =>
      _IndividualUsernamePasswordScreenState();
}

class _IndividualUsernamePasswordScreenState
    extends State<IndividualUsernamePasswordScreen> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();

  Timer? _usernameDebounce;
  bool? _usernameAvailable;
  bool _usernameTaken = false;

  bool _passwordsVisible = false;
  bool _isSaving = false;

  String? _usernameError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  // ─── Username availability — mirrors builder_registration_screen.dart's
  // _onUsernameChanged/_checkUsername (itself ported from
  // BuilderRegistration.tsx:493-528) verbatim, so "unique username" means the
  // same thing for every account type. ───────────────────────────────────
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
      final taken = data != null && data['user_id'] != widget.userId;
      setState(() {
        _usernameTaken = taken;
        _usernameAvailable = !taken;
      });
    } catch (e) {
      debugPrint('Username availability check failed: $e');
    }
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    setState(() {
      if (username.length < 3) {
        _usernameError = 'Username must be at least 3 characters.';
      } else if (_usernameAvailable == null) {
        _usernameError = 'Checking username availability. Please wait.';
      } else if (_usernameTaken) {
        _usernameError = 'This username is already taken.';
      } else {
        _usernameError = null;
      }

      _passwordError = password.length < 6
          ? 'Password must be at least 6 characters.'
          : null;
      _confirmError = confirm.isEmpty
          ? 'Please confirm your password.'
          : (password != confirm ? 'Passwords do not match.' : null);
    });
    if (_usernameError != null ||
        _passwordError != null ||
        _confirmError != null) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      // `same_password` means a previous, partially-successful submit
      // already set this exact password — not a real failure, so
      // registration still proceeds; every other auth error still aborts
      // before anything is submitted.
      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: password),
        );
      } on AuthException catch (e) {
        if (!isHarmlessSamePasswordError(e)) rethrow;
      }

      // Phase 2: the portal's own backend validation (name format, phone
      // re-verified server-side against the identity the user already
      // proved via OTP, username availability) instead of a direct client
      // upsert the server never saw. The function derives the user id from
      // the session and writes profiles.phone from its OWN verified lookup,
      // never from widget.phoneDigits directly — that value is sent only so
      // the server can confirm it matches what it already has verified.
      await RegistrationSubmitService().individualFinalize(
        fullName: widget.name,
        avatarUrl: widget.avatarUrl,
        individualPhone: widget.phoneDigits,
        individualCity: widget.city,
        individualUsername: username,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_user_type');
      await prefs.remove('pending_user_type_uid');

      if (!mounted) return;
      await context.read<AuthProvider>().refreshProfile();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.grey.shade300),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Logout'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    side: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'propcid',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Set Username & Password',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use these to sign in instead of phone OTP, any time you like.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose Unique Username *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameCtrl,
                      onChanged: _onUsernameChanged,
                      decoration: InputDecoration(
                        hintText: 'Choose username',
                        errorText: _usernameError,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: _usernameCtrl.text.trim().length >= 3
                            ? (_usernameTaken
                                  ? const Icon(Icons.close, color: Colors.red)
                                  : (_usernameAvailable == true
                                        ? const Icon(
                                            Icons.check,
                                            color: Colors.green,
                                          )
                                        : null))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'You can sign in with this username instead of your phone number.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Set Password *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: !_passwordsVisible,
                      decoration: InputDecoration(
                        hintText: 'Min 6 characters',
                        errorText: _passwordError,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordsVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _passwordsVisible = !_passwordsVisible,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Confirm Password *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmPasswordCtrl,
                      obscureText: !_passwordsVisible,
                      decoration: InputDecoration(
                        hintText: 'Confirm your password',
                        errorText: _confirmError,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordsVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _passwordsVisible = !_passwordsVisible,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Shows/hides both password fields at once — a single
                    // combined toggle alongside the per-field eye icons.
                    OutlinedButton.icon(
                      onPressed: () => setState(
                        () => _passwordsVisible = !_passwordsVisible,
                      ),
                      icon: Icon(
                        _passwordsVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      label: Text(_passwordsVisible ? 'Hide' : 'Preview'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: AppColors.heroGradient.colors,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _isSaving ? null : _submit,
                          child: SizedBox(
                            height: 48,
                            child: Center(
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'Complete Profile',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('Back'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
