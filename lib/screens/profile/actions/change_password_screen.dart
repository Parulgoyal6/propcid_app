import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/auth_service.dart';

/// Mobile equivalent of the portal's `ChangePasswordSection.tsx` — reached
/// from the Settings sheet, which previously had no password capability at
/// all.
///
/// Two modes, exactly like the portal:
///   * "Change Password" — an email/password account. The current password
///     must be re-verified (a real [AuthService.login] call, not a client-
///     side guess) before [AuthService.updatePassword] is allowed to run,
///     so a device left signed in can't have its password silently swapped.
///   * "Set Password" — a social-only account (`currentUser.appMetadata
///     ['providers']` has no `'email'` entry, matching the portal's own
///     `hasEmailIdentity` check) has no current password to verify at all.
///
/// WHY RE-VERIFYING WITH `login()` IS SAFE HERE
/// ----------------------------------------------
/// `AuthProvider._handleAuthState` (`auth_provider.dart:406,444-461`)
/// explicitly branches on `isNewIdentity = _expectedUserId != currentUser.id`
/// — re-signing in as the SAME already-resolved user takes the "same user
/// re-firing" branch, which deliberately does not bump the auth generation
/// or reset `_destination`, so no navigation is triggered. Only a genuine
/// identity change forces a fresh resolution. This re-verification call
/// signs in with the account's own current session's email, so it can only
/// ever produce a same-identity event.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.authService});

  /// Typed against [AuthServiceBase] (not the concrete [AuthService]) so a
  /// test can inject the same `FakeAuthService` every other auth test uses.
  final AuthServiceBase? authService;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const int _minPasswordLength = 6;

  late final AuthServiceBase _authService = widget.authService ?? AuthService();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _saving = false;
  bool _sendingReset = false;
  String? _errorMessage;
  String? _successMessage;

  /// Mirrors the portal's `hasEmailIdentity`/`setMode`
  /// (`ChangePasswordSection.tsx:25-27`) exactly.
  bool get _hasEmailIdentity {
    final providers =
        _authService.currentUser?.appMetadata['providers'] as List? ?? const [];
    return providers.isEmpty || providers.contains('email');
  }

  bool get _setMode => !_hasEmailIdentity;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendForgotPasswordLink() async {
    final email = _authService.currentUser?.email;
    if (email == null || email.isEmpty) return;

    setState(() {
      _sendingReset = true;
      _errorMessage = null;
    });
    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(
        () => _successMessage = 'A password reset link was sent to $email.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = 'Could not send the reset link. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  Future<void> _submit() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if ((!_setMode && current.isEmpty) || next.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (next.length < _minPasswordLength) {
      setState(
        () => _errorMessage =
            'Password must be at least $_minPasswordLength characters.',
      );
      return;
    }
    if (next != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }
    if (!_setMode && next == current) {
      setState(
        () => _errorMessage =
            'New password must be different from the current one.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (!_setMode) {
        final email = _authService.currentUser?.email;
        if (email == null || email.isEmpty) {
          throw 'Could not verify your account email.';
        }
        try {
          await _authService.login(email, current);
        } catch (_) {
          // Matches the portal: a failed re-verification is always reported
          // as a wrong current password, not whatever generic auth message
          // `login()` mapped the failure to.
          throw 'Current password is incorrect.';
        }
      }

      await _authService.updatePassword(next);
      if (!mounted) return;
      setState(() {
        _successMessage = _setMode
            ? 'Password set successfully.'
            : 'Password updated successfully.';
        _currentCtrl.clear();
        _newCtrl.clear();
        _confirmCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _setMode ? 'Set Password' : 'Change Password';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _setMode
                  ? 'Set a password so you can also sign in with your email.'
                  : 'Enter your current password, then choose a new one.',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: AppTextStyles.body.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(
                _successMessage!,
                style: AppTextStyles.body.copyWith(color: AppColors.success),
              ),
              const SizedBox(height: 12),
            ],
            if (!_setMode) ...[
              TextField(
                controller: _currentCtrl,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _sendingReset ? null : _sendForgotPasswordLink,
                  child: Text(
                    _sendingReset ? 'Sending…' : 'Forgot current password?',
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _newCtrl,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(title),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
