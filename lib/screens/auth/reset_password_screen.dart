import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_button.dart';
import '../../providers/auth_provider.dart';

/// Reached from the `propcid://reset-password` deep link. Named route
/// `/reset-password`, optional arg `{'tokenHash': String}`.
///
/// By the time this screen builds, `supabase_flutter`'s own deep-link
/// handling has usually already exchanged the recovery token and established
/// a session — `tokenHash` is only used as a fallback if that hasn't happened.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.tokenHash});

  final String? tokenHash;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _isLoading = false;
  bool _done = false;

  bool _verifying = true;
  String? _tokenError;

  @override
  void initState() {
    super.initState();
    _verifyToken();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    if (Supabase.instance.client.auth.currentSession != null) {
      setState(() => _verifying = false);
      return;
    }

    final token = widget.tokenHash;
    if (token == null || token.isEmpty) {
      setState(() {
        _verifying = false;
        _tokenError = 'This reset link is incomplete. Request a new one.';
      });
      return;
    }

    final error = await context.read<AuthProvider>().verifyRecoveryToken(token);
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _tokenError = error;
    });
  }

  String? _validate() {
    if (_passwordCtrl.text.isEmpty) return 'Password is required.';
    if (_passwordCtrl.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_confirmCtrl.text != _passwordCtrl.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      _showSnackBar(validationError, isError: true);
      return;
    }
    setState(() => _isLoading = true);
    final error = await context.read<AuthProvider>().updatePassword(
      _passwordCtrl.text,
    );
    setState(() => _isLoading = false);
    if (error != null) {
      if (mounted) _showSnackBar(error, isError: true);
      return;
    }
    if (mounted) setState(() => _done = true);
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError
            ? Colors.red.shade700
            : AppColors.verifiedBadge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF0EEFF), Color(0xFFF4F4F8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_verifying) {
      return const Padding(
        padding: EdgeInsets.only(top: 120),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_tokenError != null) {
      return _buildMessageState(
        icon: Icons.link_off_rounded,
        title: 'That link no longer works',
        message: _tokenError!,
        actionLabel: 'Back to sign in',
        onAction: () => Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/auth', (route) => false),
      );
    }

    if (_done) {
      return _buildMessageState(
        icon: Icons.lock_reset_rounded,
        title: 'Password updated',
        message: 'You are signed in with your new password.',
        actionLabel: 'Continue',
        // Matches the portal (AuthContext.tsx's password-reset flow): sign
        // out and return to Auth rather than staying on the session that was
        // just used to set the new password. The message above is true at
        // the moment it's shown — the sign-out only happens once the person
        // taps through, by which point they're leaving this screen anyway.
        onAction: () async {
          await context.read<AuthProvider>().logout();
          if (!mounted) return;
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/auth', (route) => false);
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.primaryGlow,
          ),
          child: const Icon(
            Icons.lock_reset_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Set a new password',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 32),
        _buildTextField(
          controller: _passwordCtrl,
          label: 'New password',
          hint: 'Min. 6 characters',
          passwordVisible: _passwordVisible,
          onTogglePassword: () =>
              setState(() => _passwordVisible = !_passwordVisible),
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _confirmCtrl,
          label: 'Confirm password',
          hint: 'Re-enter your password',
          passwordVisible: _confirmVisible,
          onTogglePassword: () =>
              setState(() => _confirmVisible = !_confirmVisible),
        ),
        const SizedBox(height: 24),
        PremiumButton(
          label: 'Update password',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          PremiumButton(label: actionLabel, onPressed: onAction),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool passwordVisible,
    required VoidCallback onTogglePassword,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            obscureText: !passwordVisible,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textHint,
                fontSize: 14,
              ),
              prefixIcon: const Icon(
                Icons.lock_outline,
                color: AppColors.textSecondary,
                size: 20,
              ),
              suffixIcon: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  passwordVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
