import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/premium_button.dart';
import '../../providers/auth_provider.dart';

/// Phone-OTP verification step, reached from the Phone tab on [AuthScreen].
/// Named route `/auth-otp`, args `{'phone': e164, 'name': String?}`.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, this.name});

  final String phone;
  final String? name;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const int _codeLength = 6;
  static const int _maxAttempts = 5;
  static const int _resendCooldownSeconds = 60;

  final TextEditingController _codeCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _ticker;
  int _secondsLeft = _resendCooldownSeconds;
  int _attempts = 0;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorText;

  bool get _lockedOut => _attempts >= _maxAttempts;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _secondsLeft = _resendCooldownSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != _codeLength || _lockedOut) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    final error = await context.read<AuthProvider>().verifyOtp(
      phone: widget.phone,
      otp: code,
      name: widget.name,
    );

    if (!mounted) return;

    if (error == null) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // `widget.name` already reaches the send-otp edge function's `verify`
        // action (AuthService.verifyOtp -> name:), but that action only uses
        // it for a "customers" lead-capture row — it never writes
        // profiles.display_name. Without this, everything reached after
        // sign-in (AccountTypeScreen, the individual/builder/broker/
        // influencer forms) sees an empty name and makes the person retype
        // what they just typed here.
        final name = widget.name;
        if (name != null && name.isNotEmpty) {
          try {
            // upsert, not update: this runs immediately after the edge
            // function creates a brand-new auth user for a first-time phone
            // sign-up, so there's a real window where the `handle_new_user`
            // trigger's profiles row hasn't landed yet — a plain `.update()`
            // would then silently affect zero rows and this name would be
            // lost. Still only ever touches this one column.
            await Supabase.instance.client.from('profiles').upsert({
              'user_id': userId,
              'display_name': name,
            }, onConflict: 'user_id');
          } catch (e) {
            debugPrint('OtpScreen: failed to persist display_name: $e');
          }
        }
      }
      // AuthProvider's own auth-stream listener resolves the destination and
      // navigates — this screen does not decide where to go.
      return;
    }

    setState(() {
      _isVerifying = false;
      _attempts += 1;
      _errorText = error;
      _codeCtrl.clear();
    });
    HapticFeedback.heavyImpact();
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    final error = await context.read<AuthProvider>().resendOtp(widget.phone);
    if (!mounted) return;
    setState(() => _isResending = false);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }
    _startCooldown();
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
                const SizedBox(height: 24),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppColors.primaryGlow,
                  ),
                  child: const Icon(
                    Icons.sms_outlined,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Verify your number',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      const TextSpan(text: 'Enter the 6-digit code sent to '),
                      TextSpan(
                        text: widget.phone,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                _CodeBoxes(
                  controller: _codeCtrl,
                  focusNode: _focusNode,
                  length: _codeLength,
                  enabled: !_isVerifying && !_lockedOut,
                  onCompleted: (_) => _verify(),
                ),
                const SizedBox(height: 16),
                if (_lockedOut)
                  _buildNotice(
                    'Too many incorrect attempts. Go back and request a new code.',
                  )
                else if (_errorText != null)
                  _buildNotice(_errorText!),
                if (_attempts > 0 && !_lockedOut) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_maxAttempts - _attempts} attempts left',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                PremiumButton(
                  label: 'Verify',
                  isLoading: _isVerifying,
                  onPressed: _lockedOut || _isVerifying ? null : _verify,
                ),
                const SizedBox(height: 20),
                Center(
                  child: _secondsLeft > 0
                      ? Text(
                          'Resend code in ${_secondsLeft}s',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        )
                      : TextButton(
                          onPressed: _isResending ? null : _resend,
                          child: Text(
                            _isResending ? 'Sending…' : 'Resend code',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotice(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Six boxes backed by one hidden field, so paste and SMS autofill work
/// without per-box focus juggling.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.enabled,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final ValueChanged<String> onCompleted;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: 0,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: length,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              if (value.length == length) onCompleted(value);
            },
          ),
        ),
        GestureDetector(
          onTap: enabled ? focusNode.requestFocus : null,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < length; i++)
                    _Box(
                      char: i < value.text.length ? value.text[i] : '',
                      active: i == value.text.length && focusNode.hasFocus,
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.char, required this.active});

  final String char;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final filled = char.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active || filled ? AppColors.primary : Colors.grey.shade200,
          width: active ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        char,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
