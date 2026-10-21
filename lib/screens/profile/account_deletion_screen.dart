// screens/profile/account_deletion_screen.dart
//
// Authenticated in-app account deletion — a port of
// features/profile/DeleteAccountDialog.tsx, reached from Settings ▸ Delete
// Account (this app has no logged-out entry point to account deletion, so
// the portal's separate public /account-deletion form — a different Edge
// Function, `account-deletion-public-request` — has no Flutter counterpart
// to port; every caller here already has a session).
//
// IT FILES A REQUEST; IT DOES NOT DELETE.
// `delete-account-request` (action: 'submit') inserts a row into
// `account_deletion_requests` with `status: 'pending'`. The account is only
// actually removed once the 14-day grace period has passed AND an admin
// approves it — the user can cancel any time before then (Settings ▸ the
// pending-request card), and `delete-user` enforces the same 14-day window
// server-side so it can't be skipped from the admin side either.
//
// RE-VERIFICATION, NOT JUST A FORM
// A phone-signup account (send-otp's `ensureUser` mints a synthetic
// `u<phone>@propcid.app` email and a password nobody knows) is re-verified
// with an SMS OTP; every other account is re-verified with its real
// password (matching the portal's own `isPhoneAccount` branch exactly).
// `delete-account-request` re-derives `user_id`/`email`/`phone` from the
// caller's verified JWT — nothing this screen sends is trusted for those.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/validation/validators.dart';
import '../../services/auth_service.dart';
import '../../services/edge_functions_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';

const int kAccountDeletionGracePeriodDays = 14;

/// Phone signups get a synthetic `u<10digits>@propcid.app` email and a
/// crypto-random password never disclosed to the user — they authenticate
/// purely by OTP, so "enter your password" is a dead end for them. Verbatim
/// port of `DeleteAccountDialog.tsx`'s `isPhoneAccount`.
bool isPhoneAccountEmail(String? email) =>
    RegExp(r'^u\d{10}@propcid\.app$', caseSensitive: false).hasMatch(email ?? '');

enum _Step { warn, verify, submitting, submitted }

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _edgeFunctions = EdgeFunctionsService();
  final _authService = AuthService();

  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  _Step _step = _Step.warn;
  bool _downloading = false;
  bool _verifying = false;
  String? _error;

  List<String> _knownPhones = const [];

  bool _resetSending = false;
  bool _resetSent = false;

  bool _otpSending = false;
  bool _otpSent = false;

  User? get _user => Supabase.instance.client.auth.currentUser;
  bool get _phoneAccount => isPhoneAccountEmail(_user?.email);

  /// Last 4 digits of the registered phone, or a placeholder if it's
  /// missing/too short to have any — matches the portal's
  /// `(user?.phone ?? '').slice(-4) || '····'`.
  String get _phoneLast4 {
    final phone = _user?.phone ?? '';
    if (phone.length < 4) return '····';
    return phone.substring(phone.length - 4);
  }

  @override
  void initState() {
    super.initState();
    if (!_phoneAccount) {
      // Best-effort, same as the portal's dialog — a failure here only
      // means the identifier field can't be pre-validated against a known
      // phone; the password check below still gates the actual request.
      _edgeFunctions.deleteAccountRequestPhones().then((phones) {
        if (mounted) setState(() => _knownPhones = phones);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _resetVerifyState() {
    _error = null;
    _verifying = false;
    _resetSending = false;
    _resetSent = false;
    _otpSending = false;
    _otpSent = false;
    _identifierCtrl.clear();
    _passwordCtrl.clear();
    _otpCtrl.clear();
  }

  bool _matchesAccount(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final email = _user?.email;
    if (email != null && v.toLowerCase() == email.toLowerCase()) return true;

    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return false;
    final last10 = digits.substring(digits.length - 10);
    return _knownPhones.any(
      (p) => p.replaceAll(RegExp(r'\D'), '').endsWith(last10),
    );
  }

  Future<void> _handleDownloadData() async {
    setState(() => _downloading = true);
    try {
      final url = await _edgeFunctions.exportUserData();
      if (!mounted) return;
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showSnack("Couldn't open the download link.", isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        "Couldn't prepare your data right now. Please try again.",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _user?.email;
    if (email == null) return;
    setState(() {
      _error = null;
      _resetSending = true;
    });
    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() => _resetSent = true);
      _showSnack('Check $email for a link to set a new password.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send reset email. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _resetSending = false);
    }
  }

  Future<void> _handleSendOtp() async {
    final phone = _user?.phone;
    if (phone == null || phone.isEmpty) return;
    setState(() {
      _error = null;
      _otpSending = true;
    });
    try {
      await _edgeFunctions.sendOtp(Validators.toE164(phone));
      if (!mounted) return;
      setState(() => _otpSent = true);
      _showSnack('Check the SMS on your registered number.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send OTP. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _otpSending = false);
    }
  }

  Future<void> _handleVerifyOtpAndSubmit() async {
    final phone = _user?.phone;
    if (phone == null || phone.isEmpty) return;

    final code = _otpCtrl.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code sent to your phone.');
      return;
    }

    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      final result = await _edgeFunctions.verifyOtp(
        phoneNumber: Validators.toE164(phone),
        otp: code,
      );
      if (result['success'] != true) {
        if (!mounted) return;
        setState(() {
          _error = result['error']?.toString() ?? 'Incorrect or expired code.';
          _verifying = false;
        });
        return;
      }
      await _submitRequest();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong verifying your code. Please try again.';
        _verifying = false;
      });
    }
  }

  Future<void> _handleVerifyPasswordAndSubmit() async {
    final email = _user?.email;
    if (email == null) return;

    if (!_matchesAccount(_identifierCtrl.text)) {
      setState(
        () => _error = "That doesn't match the email or phone number on this account.",
      );
      return;
    }
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password to continue.');
      return;
    }

    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      await _authService.login(email, password);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Incorrect password.';
        _verifying = false;
      });
      return;
    }
    await _submitRequest();
  }

  Future<void> _submitRequest() async {
    if (!mounted) return;
    setState(() => _step = _Step.submitting);
    try {
      await _edgeFunctions.deleteAccountRequestSubmit();
      if (!mounted) return;
      setState(() => _step = _Step.submitted);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong submitting your request. Please try again.';
        _step = _Step.verify;
        _verifying = false;
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Account deletion',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: switch (_step) {
          _Step.warn => _warnStep(),
          _Step.verify => _phoneAccount ? _verifyOtpStep() : _verifyPasswordStep(),
          _Step.submitting => _submittingStep(),
          _Step.submitted => _submittedStep(),
        },
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTextStyles.caption.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
  );

  Widget _errorText() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppConstants.spacingS),
      child: Text(
        _error!,
        style: AppTextStyles.caption.copyWith(color: AppColors.error, fontSize: 12.5),
      ),
    );
  }

  Widget _warnStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DashboardCard(
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
                  'This action is permanent',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),
            const DashboardCardTitle('Delete Account'),
            const SizedBox(height: 6),
            Text(
              'This permanently deletes your profile, listings, videos, posts '
              'and saved items. Your account will be deleted '
              '$kAccountDeletionGracePeriodDays days after you apply — you can '
              'cancel any time before then and nothing will be removed.',
              style: AppTextStyles.caption.copyWith(fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spacingL),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('Before you go'),
            const SizedBox(height: AppConstants.spacingS),
            Text(
              'You can download a copy of your account data first. This is '
              'optional.',
              style: AppTextStyles.caption.copyWith(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: AppConstants.spacingM),
            AppActionButton(
              label: _downloading ? 'Preparing…' : 'Download my data',
              variant: AppActionButtonVariant.outline,
              height: 40,
              icon: Icons.download_outlined,
              onTap: _downloading ? null : _handleDownloadData,
            ),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spacingL),
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardSectionLabel('What happens next'),
            const SizedBox(height: AppConstants.spacingS),
            for (final line in const [
              'Your request is reviewed by our team.',
              'You can cancel any time in the next '
                  '$kAccountDeletionGracePeriodDays days.',
              'You will receive a confirmation once it is done.',
              'Some data may be retained where the law requires it.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: AppTextStyles.caption.copyWith(fontSize: 12.5)),
                    Expanded(
                      child: Text(
                        line,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spacingL),
      Row(
        children: [
          Expanded(
            child: AppActionButton(
              label: 'Cancel',
              variant: AppActionButtonVariant.outline,
              height: 46,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppActionButton(
              label: 'Continue',
              variant: AppActionButtonVariant.danger,
              height: 46,
              onTap: () => setState(() {
                _resetVerifyState();
                _step = _Step.verify;
              }),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _verifyOtpStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardCardTitle('Verify your phone number'),
            const SizedBox(height: 6),
            Text(
              "This account signed up with a phone number, so we'll verify "
              "it's you with an SMS code to your registered number ending in "
              '$_phoneLast4.',
              style: AppTextStyles.caption.copyWith(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: AppConstants.spacingL),
            if (!_otpSent)
              AppActionButton(
                label: _otpSending ? 'Sending…' : 'Send OTP',
                variant: AppActionButtonVariant.outline,
                height: 44,
                onTap: _otpSending ? null : _handleSendOtp,
              )
            else ...[
              _label('Enter OTP'),
              const SizedBox(height: 6),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: AppTextStyles.body.copyWith(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '6-digit code',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _otpSending ? null : _handleSendOtp,
                child: Text(
                  _otpSending ? 'Sending…' : 'Resend OTP',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
            _errorText(),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spacingL),
      Row(
        children: [
          Expanded(
            child: AppActionButton(
              label: 'Back',
              variant: AppActionButtonVariant.outline,
              height: 46,
              onTap: _verifying ? null : () => setState(() => _step = _Step.warn),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppActionButton(
              label: _verifying ? 'Verifying…' : 'Verify & Submit',
              variant: AppActionButtonVariant.danger,
              height: 46,
              onTap: (_verifying || !_otpSent) ? null : _handleVerifyOtpAndSubmit,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _verifyPasswordStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DashboardCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DashboardCardTitle('Confirm it\'s you'),
            const SizedBox(height: AppConstants.spacingL),
            _label('Registered email or phone number'),
            const SizedBox(height: 6),
            TextField(
              controller: _identifierCtrl,
              style: AppTextStyles.body.copyWith(fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'you@example.com or 9876543210',
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Password'),
                GestureDetector(
                  onTap: _resetSending ? null : _handleForgotPassword,
                  child: Text(
                    _resetSending ? 'Sending…' : 'Forgot password?',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11.5,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              style: AppTextStyles.body.copyWith(fontSize: 14),
              decoration: const InputDecoration(hintText: 'Your account password'),
            ),
            if (_resetSent)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "We've sent a password reset link to ${_user?.email}. Set a "
                  'new password, then enter it above to continue.',
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
              ),
            _errorText(),
          ],
        ),
      ),
      const SizedBox(height: AppConstants.spacingL),
      Row(
        children: [
          Expanded(
            child: AppActionButton(
              label: 'Back',
              variant: AppActionButtonVariant.outline,
              height: 46,
              onTap: _verifying ? null : () => setState(() => _step = _Step.warn),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppActionButton(
              label: _verifying ? 'Verifying…' : 'Submit Request',
              variant: AppActionButtonVariant.danger,
              height: 46,
              onTap: _verifying ? null : _handleVerifyPasswordAndSubmit,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _submittingStep() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        SizedBox(height: 16),
        Text('Submitting your request…'),
      ],
    ),
  );

  Widget _submittedStep() => DashboardCard(
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 26, color: AppColors.success),
        ),
        const SizedBox(height: AppConstants.spacingL),
        Text(
          'Request submitted',
          style: AppTextStyles.heading3.copyWith(fontSize: 15),
        ),
        const SizedBox(height: AppConstants.spacingS),
        Text(
          'Your account will be deleted $kAccountDeletionGracePeriodDays days '
          'from now. You can cancel this request any time before then from '
          'Settings — after that, an admin can carry it out and it becomes '
          'permanent.',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: AppConstants.spacingL),
        AppActionButton(
          label: 'Done',
          height: 44,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}
