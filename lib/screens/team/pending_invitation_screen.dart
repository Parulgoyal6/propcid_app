import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/builder_section_options.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/builder_section_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../services/builder_sections_service.dart';

/// Mobile equivalent of the portal's `AcceptInvite.tsx`.
///
/// Reached automatically by `PendingInvitationGate` (the mirror of
/// `TeamInviteGate.tsx`), or directly by `InviteDeepLinkHandler` with
/// [invitationId]/[token] when an already-signed-in user taps the invite
/// link itself. Reads its list from [AuthProvider.pendingTeamInvitations]
/// rather than querying `builder_team_invitations` itself, per that provider
/// already being the single source of truth for this person's own pending
/// rows — [invitationId] only ever adds one synthesized entry on top when
/// it names an invite that list doesn't already contain (see its own doc
/// comment).
///
/// Shows every pending invitation, not just the first — `AcceptInvite.tsx`'s
/// own detection always resolves to one (its email fallback query is
/// `.limit(1)`), but this app's provider does not truncate the list, so more
/// than one pending row is a real state this screen has to represent rather
/// than silently collapse.
///
/// Works unmodified for both populations `accept-team-invite` distinguishes
/// server-side (`index.ts:131-151`): a brand-new invitee, whose
/// `profiles.user_type` the function sets to `'team_member'`, and an existing
/// PropCid user, whose `user_type` it leaves untouched. This screen never
/// reads or writes `user_type` itself — it only ever calls the existing
/// Edge Function and re-reads `AuthProvider`'s cache afterward.
class PendingInvitationScreen extends StatelessWidget {
  const PendingInvitationScreen({super.key, this.invitationId, this.token});

  /// Present when reached via `InviteDeepLinkHandler`'s preserved
  /// `?invitation=&token=` link parameters — the ONLY reliable way to locate
  /// a phone-OTP invite that doesn't happen to match this signed-in
  /// account's own `profiles.email`/`profiles.phone`
  /// ([AuthProvider.pendingTeamInvitations]'s own lookup is email-only; see
  /// its doc comment). A matching entry already in that list is not
  /// duplicated — this only ever adds a synthesized minimal card when the id
  /// isn't already present.
  final String? invitationId;
  final String? token;

  @override
  Widget build(BuildContext context) {
    final discovered = context.watch<AuthProvider>().pendingTeamInvitations;
    final deepLinkId = invitationId;
    final alreadyListed =
        deepLinkId != null && discovered.any((i) => i.id == deepLinkId);
    final invitations = deepLinkId != null && !alreadyListed
        ? [
            // Minimal — this app has no way to fetch the full row for an
            // invitation not reachable by this account's own email/phone
            // (see the OTP step's own "builder name/modules unavailable
            // until verified" note); id+token are all `acceptInvite` and the
            // OTP functions actually need.
            BuilderTeamInvitation(
              id: deepLinkId,
              token: token,
              verificationMethod: 'phone_otp',
            ),
            ...discovered,
          ]
        : discovered;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          invitations.length > 1 ? 'Team Invitations' : 'Team Invitation',
          style: AppTextStyles.heading3,
        ),
      ),
      body: invitations.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(AppConstants.spacingL),
              itemCount: invitations.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppConstants.spacingL),
              itemBuilder: (context, index) =>
                  _InvitationCard(invitation: invitations[index]),
            ),
    );
  }
}

/// Reached if this screen is opened after every pending invitation on it has
/// already been resolved elsewhere (e.g. the person accepted on another
/// device) — [PendingInvitationGate] only ever pushes this screen when the
/// list was non-empty at that moment, but it can go stale while this screen
/// is open.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_email_read_outlined,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: AppConstants.spacingL),
            Text(
              'No pending invitations right now.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingXL),
            ElevatedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _CardStatus { idle, accepting, accepted, error }

class _InvitationCard extends StatefulWidget {
  const _InvitationCard({required this.invitation});

  final BuilderTeamInvitation invitation;

  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  final AuthService _authService = AuthService();
  final BuilderTeamService _teamService = BuilderTeamService();
  final TextEditingController _otpController = TextEditingController();

  bool _loadingBuilder = true;
  Map<String, dynamic>? _builderProfile;

  _CardStatus _status = _CardStatus.idle;
  String? _errorMessage;

  // ── Phone-OTP verification (`team-invite-otp`) ──────────────────────────
  // `accept-team-invite` refuses a phone-OTP invite until this signed-in
  // user has a fresh (<30 min) verification on file — see
  // `BuilderTeamService.acceptInvite`'s `OtpRequiredException`.
  bool _checkingOtpStatus = true;
  bool _otpVerified = false;
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  String? _maskedPhone;
  String? _otpErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadBuilderProfile();
    if (widget.invitation.isPhoneInvite) {
      _checkOtpStatus();
    } else {
      _checkingOtpStatus = false;
    }
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _checkOtpStatus() async {
    try {
      final status = await _teamService.inviteOtpStatus(
        invitationId: widget.invitation.id,
        token: widget.invitation.token,
      );
      if (!mounted) return;
      setState(() {
        _otpVerified = status.verified;
        _maskedPhone = status.maskedPhone;
        _checkingOtpStatus = false;
      });
    } catch (_) {
      // Non-fatal — worst case, the user taps "Send Code" directly and any
      // real problem surfaces there instead.
      if (mounted) setState(() => _checkingOtpStatus = false);
    }
  }

  Future<void> _sendOtp() async {
    setState(() {
      _sendingOtp = true;
      _otpErrorMessage = null;
    });
    try {
      final result = await _teamService.sendInviteOtp(
        invitationId: widget.invitation.id,
        token: widget.invitation.token,
      );
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _maskedPhone = result.maskedPhone ?? _maskedPhone;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otpErrorMessage = e is BuilderSectionException
            ? e.message
            : 'Could not send a code. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _otpErrorMessage = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifyingOtp = true;
      _otpErrorMessage = null;
    });
    try {
      await _teamService.verifyInviteOtp(
        invitationId: widget.invitation.id,
        token: widget.invitation.token,
        otp: otp,
      );
      if (!mounted) return;
      setState(() => _otpVerified = true);
      // Verified — proceed straight to acceptance, same as if this invite
      // had never needed a phone step at all.
      unawaited(_accept());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _otpErrorMessage = e is BuilderSectionException
            ? e.message
            : 'Could not verify that code. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _verifyingOtp = false);
    }
  }

  /// Resolves who invited this person for display. `builder_team_invitations`
  /// itself carries no display name — the portal only gets one back from
  /// `accept-team-invite`'s success response (`index.ts:160-165`), i.e. only
  /// after accepting — so this reads `profiles` directly by `builderId`,
  /// reusing [AuthService.getUserProfile] rather than adding a second way to
  /// fetch a profile row.
  Future<void> _loadBuilderProfile() async {
    final builderId = widget.invitation.builderId;
    if (builderId == null || builderId.isEmpty) {
      if (mounted) setState(() => _loadingBuilder = false);
      return;
    }

    try {
      final profile = await _authService.getUserProfile(builderId);
      if (!mounted) return;
      setState(() {
        _builderProfile = profile;
        _loadingBuilder = false;
      });
    } catch (_) {
      // Non-fatal: the card still works without a name, just less legibly.
      if (mounted) setState(() => _loadingBuilder = false);
    }
  }

  String get _builderLabel {
    final profile = _builderProfile;
    if (profile == null) return 'A builder';
    final company = profile['company_name']?.toString();
    if (company != null && company.isNotEmpty) return company;
    final name = profile['display_name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    return 'A builder';
  }

  Future<void> _accept() async {
    setState(() {
      _status = _CardStatus.accepting;
      _errorMessage = null;
    });

    try {
      final result = await _teamService.acceptInvite(
        invitationId: widget.invitation.id,
        token: widget.invitation.token,
      );

      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      await auth.refreshTeamStatus();

      // Confirmation, not blind trust in the function's response — the row
      // must actually be there before this is called complete.
      final confirmed = auth.activeTeamMemberships.any(
        (m) => m.builderId == result.builderId && m.status == 'active',
      );

      if (!mounted) return;
      setState(() {
        if (confirmed) {
          _status = _CardStatus.accepted;
        } else {
          _status = _CardStatus.error;
          _errorMessage =
              "Accepted, but we couldn't confirm your access "
              'yet. Pull to refresh and try again in a moment.';
        }
      });
    } on OtpRequiredException catch (_) {
      // A stale/skipped status check thought this was already verified —
      // fall back to the OTP step rather than a dead-end error.
      if (!mounted) return;
      setState(() {
        _status = _CardStatus.idle;
        _otpVerified = false;
      });
    } on BuilderSectionException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CardStatus.error;
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = _CardStatus.error;
        _errorMessage = 'Could not accept that invitation. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invitation = widget.invitation;
    final accepted = _status == _CardStatus.accepted;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _loadingBuilder
                    ? Text('Loading…', style: AppTextStyles.caption)
                    : Text(_builderLabel, style: AppTextStyles.heading3),
              ),
              _StatusChip(accepted: accepted),
            ],
          ),
          const SizedBox(height: AppConstants.spacingS),
          Text(
            'Invited you to help manage their workspace.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppConstants.spacingL),
          // A deep-link-only invitation (no builderId) has no row this app
          // can fetch to show real modules/projects — see this screen's own
          // `invitationId` doc comment. Confirmed details appear once this
          // phone is verified and the invite is actually accepted.
          if (invitation.builderId != null) ...[
            _sectionLabel('ACCESS'),
            const SizedBox(height: AppConstants.spacingS),
            Wrap(
              spacing: AppConstants.spacingS,
              runSpacing: AppConstants.spacingS,
              children: [
                for (final module in invitation.modules)
                  _Pill(label: builderTeamModuleLabel(module)),
              ],
            ),
            const SizedBox(height: AppConstants.spacingL),
            _sectionLabel('PROJECTS'),
            const SizedBox(height: AppConstants.spacingS),
            Text(_projectScopeLabel(invitation), style: AppTextStyles.body),
          ] else
            Text(
              "Access details appear once you've verified your phone number.",
              style: AppTextStyles.caption,
            ),
          const SizedBox(height: AppConstants.spacingXL),
          if (accepted)
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: Text(
                    'Invitation accepted successfully.',
                    style: AppTextStyles.body,
                  ),
                ),
              ],
            )
          else if (_checkingOtpStatus)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (invitation.isPhoneInvite && !_otpVerified) ...[
            // `accept-team-invite` refuses a phone-OTP invite outright until
            // this is done — see `BuilderTeamService.acceptInvite`'s
            // `OtpRequiredException`.
            if (!_otpSent) ...[
              Text(
                'Verify your phone number to accept this invitation.',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              if (_otpErrorMessage != null) ...[
                Text(
                  _otpErrorMessage!,
                  style: AppTextStyles.body.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: AppConstants.spacingS),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sendingOtp ? null : _sendOtp,
                  child: _sendingOtp
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send Code'),
                ),
              ),
            ] else ...[
              Text(
                'Enter the 6-digit code sent to '
                '${_maskedPhone ?? 'your phone'}.',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingS),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_otpErrorMessage != null) ...[
                const SizedBox(height: AppConstants.spacingS),
                Text(
                  _otpErrorMessage!,
                  style: AppTextStyles.body.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppConstants.spacingS),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _verifyingOtp ? null : _verifyOtp,
                  child: _verifyingOtp
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Accept'),
                ),
              ),
              TextButton(
                onPressed: _sendingOtp ? null : _sendOtp,
                child: const Text('Resend code'),
              ),
            ],
          ] else ...[
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: AppTextStyles.body.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppConstants.spacingS),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _status == _CardStatus.accepting ? null : _accept,
                child: _status == _CardStatus.accepting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Accept Invitation'),
              ),
            ),
          ],
          if (accepted) ...[
            const SizedBox(height: AppConstants.spacingM),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                // `AcceptInvite.tsx:113-121` — after acceptance the portal
                // navigates into `/team-workspace`, it never just returns
                // the person to wherever they were. `pushReplacement`
                // rather than `push`: this screen only ever got here via
                // `PendingInvitationGate`'s own auto-push, so leaving an
                // already-accepted card behind in the back stack would be a
                // dead end, not a screen worth returning to.
                onPressed: () => Navigator.of(
                  context,
                ).pushReplacementNamed(AppConstants.teamWorkspaceScreen),
                child: const Text('Continue'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.caption.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppColors.textHint,
        letterSpacing: 0.5,
      ),
    );
  }

  /// `null` ⇒ every one of the builder's projects — the same convention
  /// `BuilderTeamMember.hasAllProjects` documents on the membership side.
  String _projectScopeLabel(BuilderTeamInvitation invitation) {
    final projectIds = invitation.projectIds;
    if (projectIds == null) return 'All of their projects';
    if (projectIds.length == 1) return '1 project';
    return '${projectIds.length} projects';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.accepted});

  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final color = accepted ? AppColors.success : AppColors.statusPending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accepted ? 'Accepted' : 'Pending',
        style: AppTextStyles.chip.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTextStyles.chip.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}
