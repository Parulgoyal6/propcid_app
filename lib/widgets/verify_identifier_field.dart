import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/identity_verification_provider.dart';
import '../services/identity_verification_service.dart';

/// Reusable inline email/phone verification field: input → sent code →
/// verify → verified badge, backed by [IdentityVerificationProvider] (which
/// itself talks to the authenticated `verify-identifier` Edge Function).
///
/// Used wherever the portal shows an "Account verification" field —
/// registration's personal-information step, Individual profile details,
/// and Edit Profile's verification section — so the send/verify/resend/
/// target-change/locked-badge behavior is implemented exactly once.
///
/// This widget never creates an account, never establishes a session, and
/// never calls Supabase's own `verifyOTP` with its code — it only links a
/// second identifier to the CURRENT signed-in user via the provider.
class VerifyIdentifierField extends StatefulWidget {
  const VerifyIdentifierField({
    super.key,
    required this.channel,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.prefixText,
    this.inputFormatters = const [],
    required this.normalizeTarget,
    this.fieldValidator,
    this.externalError,
  });

  final IdentityChannel channel;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final String? prefixText;
  final List<TextInputFormatter> inputFormatters;

  /// A step-level validation error the PARENT wants shown on this field —
  /// e.g. "Email address is required.", computed when the wizard's
  /// Continue/Submit button is pressed without this field ever having been
  /// interacted with. Without this, a required-but-empty email/phone field
  /// had no way to be highlighted at all: this widget's own [_localError]
  /// only ever gets set from inside [_handleSend], so a user who never taps
  /// "Send OTP" and just presses Continue saw no red border on the box
  /// itself, only a separate summary line below both fields. Takes a back
  /// seat to [_localError] (a fresher, field-specific failure from an
  /// actual attempt) whenever both are set.
  final String? externalError;

  /// Converts the raw field text into the exact string sent to the server
  /// as `target` — e.g. stripping a `+91` prefix for phone, since the
  /// backend's primary-phone contract expects a validated ten-digit local
  /// number, not E.164. Returns `null` when the raw text is not even
  /// well-formed enough to attempt sending (shown as a local validation
  /// error without a network call).
  final String? Function(String raw) normalizeTarget;

  /// Optional extra client-side validation message shown before a send is
  /// attempted (e.g. "Enter a 10-digit mobile number"). The server's own
  /// `invalid_target` response is still the authority — this is only a
  /// faster, offline-capable first check.
  final String? Function(String raw)? fieldValidator;

  @override
  State<VerifyIdentifierField> createState() => _VerifyIdentifierFieldState();
}

class _VerifyIdentifierFieldState extends State<VerifyIdentifierField> {
  final _targetCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _localError;
  String? _codeError;
  Timer? _ticker;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    _targetCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  IdentityVerificationProvider get _provider =>
      context.read<IdentityVerificationProvider>();

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    setState(() => _secondsLeft = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  Future<void> _handleSend() async {
    final raw = _targetCtrl.text.trim();
    final fieldError = widget.fieldValidator?.call(raw);
    if (fieldError != null) {
      setState(() => _localError = fieldError);
      return;
    }
    final target = widget.normalizeTarget(raw);
    if (target == null || target.isEmpty) {
      setState(() => _localError = 'Enter a valid value.');
      return;
    }
    setState(() => _localError = null);
    try {
      await _provider.sendCode(channel: widget.channel, target: target);
      if (!mounted) return;
      _codeCtrl.clear();
      setState(() => _codeError = null);
      final sent = _provider.lastSend(widget.channel);
      _startCountdown(sent?.resendIn ?? 60);
    } on IdentityVerificationFailure catch (e) {
      if (!mounted) return;
      setState(() => _localError = e.userMessage);
      if (e.code == 'rate_limited' && e.retryAfter != null) {
        _startCountdown(e.retryAfter!);
      }
    }
  }

  Future<void> _handleVerify() async {
    final target = _provider.pendingTarget(widget.channel);
    final code = _codeCtrl.text.trim();
    if (target == null || code.length != 6) return;
    setState(() => _codeError = null);
    try {
      await _provider.verifyCode(
        channel: widget.channel,
        target: target,
        otp: code,
      );
      if (!mounted) return;
      _codeCtrl.clear();
    } on IdentityVerificationFailure catch (e) {
      if (!mounted) return;
      setState(() => _codeError = e.userMessage);
      if (e.code == 'invalid_or_expired') {
        _codeCtrl.clear();
      }
    }
  }

  void _onTargetChanged(String _) {
    // Changing the target after a code was sent must never let a stale code
    // apply to the new target.
    if (_provider.pendingTarget(widget.channel) != null) {
      _provider.clearPending(widget.channel);
      _codeCtrl.clear();
      setState(() => _codeError = null);
      _ticker?.cancel();
      setState(() => _secondsLeft = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IdentityVerificationProvider>();
    final status = provider.status;

    // Status hasn't resolved for the first time yet — show a neutral
    // loading placeholder rather than the "unverified, send a code" form,
    // which would otherwise flash misleadingly for an already-verified
    // channel on every screen open (and could prompt an unnecessary resend)
    // until the status fetch completes.
    if (status == null && provider.isLoading) {
      return _buildLoading();
    }

    final isEmail = widget.channel == IdentityChannel.email;
    final verifiedValue = isEmail ? status?.email : status?.phone;
    final isVerified = isEmail
        ? (status?.emailVerified ?? false)
        : (status?.phoneVerified ?? false);

    if (isVerified && verifiedValue != null && verifiedValue.isNotEmpty) {
      return _buildVerified(verifiedValue);
    }

    final pendingTarget = provider.pendingTarget(widget.channel);
    final sending = provider.isSending(widget.channel);
    final verifying = provider.isVerifying(widget.channel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _targetCtrl,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
                enabled: pendingTarget == null,
                onChanged: _onTargetChanged,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixText: widget.prefixText,
                  errorText: _localError ?? widget.externalError,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (pendingTarget == null)
              _SmallButton(
                label: 'Send OTP',
                isLoading: sending,
                onPressed: sending ? null : _handleSend,
              ),
          ],
        ),
        if (pendingTarget != null) ...[
          const SizedBox(height: 10),
          Text(
            'Code sent to $pendingTarget',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '6-digit code',
                    errorText: _codeError,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _SmallButton(
                label: 'Verify',
                isLoading: verifying,
                onPressed: verifying ? null : _handleVerify,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _secondsLeft > 0
              ? Text(
                  'Resend in ${_secondsLeft}s',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                )
              : GestureDetector(
                  onTap: sending ? null : _handleSend,
                  child: const Text(
                    'Resend code',
                    style: TextStyle(fontSize: 12, color: AppColors.primary),
                  ),
                ),
        ],
      ],
    );
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryLight),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text(
                'Checking verification status…',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerified(String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryLight),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.verified_rounded,
                size: 16,
                color: AppColors.verifiedBadge,
              ),
              const SizedBox(width: 4),
              const Text(
                'Verified',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.verifiedBadge,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
