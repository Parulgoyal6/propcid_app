// screens/network/widgets/network_invitations_section.dart
//
// Network Invitations + Collaboration Hub — Spec F's UI.
//
// ONE SECTION, TWO PORTAL COMPONENTS
// ----------------------------------
// The portal splits this in two by role:
//
//   * `BuilderNetworkInvitations.tsx` — a builder searches for a broker or
//     influencer, sends an invitation with a `member_type` and a note, and sees
//     what they have sent;
//   * `InfluencerCollaborationHub.tsx` — the recipient sees pending invitations and
//     accepts or rejects them.
//
// They are two ends of one `builder_network_invitations` row, so this renders both
// ends of it: a Received list with accept/decline (available to every role — anyone
// can be invited), and a Sent list with the invite form above it (builder-only).
//
// WHY THE INVITE BUTTON *IS* NOW ROLE-GATED
// ------------------------------------------
// An earlier version of this file deliberately did not gate the Invite button,
// reasoning that `builder_network_invitations`' RLS is not builder-only (any
// authenticated user can insert one naming themselves as `builder_id`), so a broker
// "can" send one too. That conflated "the database's RLS happens to allow it" with
// "the product intends it" — the very trap a later audit called out explicitly: this
// table's RLS was broadened for the generic peer-"Connect" flow, not to turn every
// role into a network owner who recruits members. A non-builder sending a formal
// network invitation would create a `builder_networks` row with *them* as
// `builder_id`, which every owned-network-member classification elsewhere in this
// module (`network_relationship.dart`) would then have to treat as if they run a
// real builder network. [isBuilder] gates the button on the intended product role
// instead of the accidental RLS permission; the Received list stays open to
// everyone, since anyone can legitimately be on the receiving end of an invitation.
//
// EXPIRY IS ENFORCED HERE
// ----------------------
// The contract requires an expired invitation not be actionable. `expires_at`
// defaults to `now() + 7 days` and nothing flips `status` to `'expired'`
// synchronously, so a row can read `pending` while being unusable.
// `NetworkInvitation.isActionable` is the single check, and the service re-checks it
// before writing — the UI hiding a button is not a guarantee.
//
// No realtime: neither portal component opens a `.channel(`, unlike the broker's
// visit bookings in Spec I.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../models/network_models.dart';
import '../../../services/profile_connection_service.dart';

class NetworkInvitationsSection extends StatefulWidget {
  const NetworkInvitationsSection({
    super.key,
    required this.userId,
    this.isBuilder = false,
    this.service,
    this.onChanged,
  });

  final String? userId;

  /// Gates the Invite button and the Sent list — see this file's header for
  /// why sending a formal network invitation is builder-only even though its
  /// RLS does not itself enforce that. Defaults to `false` so a caller that
  /// hasn't been updated yet degrades to "no invite controls" rather than
  /// accidentally granting them.
  final bool isBuilder;

  @visibleForTesting
  final ProfileConnectionService? service;

  /// Fired after any accept, decline or send, so the hub can refresh its counts —
  /// an accepted invitation becomes a `builder_networks` row, which is what the
  /// stats grid reads.
  final VoidCallback? onChanged;

  @override
  State<NetworkInvitationsSection> createState() =>
      _NetworkInvitationsSectionState();
}

class _NetworkInvitationsSectionState extends State<NetworkInvitationsSection> {
  late final ProfileConnectionService _connections =
      widget.service ?? ProfileConnectionService();

  NetworkInvitationInbox? _inbox;
  bool _failed = false;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final userId = widget.userId;
    if (userId == null) {
      setState(() => _inbox = NetworkInvitationInbox.empty);
      return;
    }

    setState(() => _failed = false);
    // `listInvitations` never throws — it degrades to an empty inbox — so the
    // failure state here is reached only by a null user, which the guard above
    // handles. Kept for symmetry with every other section and in case the service
    // ever propagates.
    final inbox = await _connections.listInvitations(userId);
    if (!mounted) return;
    setState(() => _inbox = inbox);
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

  /// Turns the service's error enum into something a person can read.
  String _messageFor(ConnectionWriteError error) => switch (error) {
    ConnectionWriteError.notAllowed => "You can't do that.",
    ConnectionWriteError.nothingToAccept =>
      'That invitation is no longer pending.',
    ConnectionWriteError.failed => 'Something went wrong. Please try again.',
  };

  Future<void> _accept(NetworkInvitation invitation) async {
    setState(() => _busyId = invitation.id);
    final error = await _connections.acceptInvitation(
      viewerId: widget.userId,
      invitation: invitation,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (error != null) {
      _toast(_messageFor(error), isError: true);
      // A stale row is exactly the case where a refresh is the right answer.
      if (error == ConnectionWriteError.nothingToAccept) await _load();
      return;
    }

    _toast('Invitation accepted.');
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _decline(NetworkInvitation invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Invitation'),
        // Says what happens rather than "are you sure": the row is marked, not
        // deleted, so the sender will see the outcome.
        content: Text(
          'Decline the invitation from ${invitation.recipientLabel}?\n\n'
          'They will see that it was declined.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = invitation.id);
    final error = await _connections.declineInvitation(
      viewerId: widget.userId,
      invitation: invitation,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (error != null) {
      _toast(_messageFor(error), isError: true);
      if (error == ConnectionWriteError.nothingToAccept) await _load();
      return;
    }

    _toast('Invitation declined.');
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _openInviteSheet() async {
    final draft = await showModalBottomSheet<_InviteDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InviteSheet(service: _connections),
    );
    if (draft == null || !mounted) return;

    setState(() => _busyId = 'invite');
    final error = await _connections.sendBuilderInvite(
      viewerId: widget.userId,
      memberType: draft.memberType,
      invitedUserId: draft.invitedUserId,
      email: draft.email,
      phone: draft.phone,
      message: draft.message,
    );
    if (!mounted) return;
    setState(() => _busyId = null);

    if (error != null) {
      _toast(_messageFor(error), isError: true);
      return;
    }

    _toast('Invitation sent to ${draft.recipientLabel}.');
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = _inbox;

    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load invitations",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }

    if (inbox == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final received = inbox.received;
    final sent = inbox.sent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                received.isEmpty
                    ? (widget.isBuilder
                          ? 'Invite a broker or influencer to your network.'
                          : 'Invitations you receive will appear here.')
                    : '${inbox.actionable.length} awaiting your reply',
                style: AppTextStyles.caption,
              ),
            ),
            if (widget.isBuilder)
              TextButton.icon(
                onPressed: _busyId == null && widget.userId != null
                    ? _openInviteSheet
                    : null,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                label: const Text('Invite'),
              ),
          ],
        ),

        if (_busyId == 'invite')
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),

        if (received.isEmpty && sent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No invitations yet.', style: AppTextStyles.caption),
          ),

        if (received.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GroupLabel('Received'),
          for (final invitation in received) ...[
            const SizedBox(height: AppConstants.spacingM),
            _InvitationCard(
              invitation: invitation,
              busy: _busyId == invitation.id,
              // Actions only on a live received invitation. An accepted, declined
              // or lapsed one still lists — a builder needs to see the outcome —
              // but cannot be acted on.
              onAccept: invitation.isActionable
                  ? () => _accept(invitation)
                  : null,
              onDecline: invitation.isActionable
                  ? () => _decline(invitation)
                  : null,
            ),
          ],
        ],

        if (sent.isNotEmpty) ...[
          const SizedBox(height: 18),
          _GroupLabel('Sent'),
          for (final invitation in sent) ...[
            const SizedBox(height: AppConstants.spacingM),
            _InvitationCard(
              invitation: invitation,
              busy: _busyId == invitation.id,
              // No actions on a sent invitation: the recipient decides. Withdrawing
              // is `cancelRequest`, which belongs to the profile screen where the
              // relationship is shown, not here.
              onAccept: null,
              onDecline: null,
            ),
          ],
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppTextStyles.caption.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  const _InvitationCard({
    required this.invitation,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final NetworkInvitation invitation;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// The status to show, which is not always the stored one.
  ///
  /// A lapsed `pending` row reads as Expired: telling a user it is pending when no
  /// button will work would be the wrong information.
  String get _statusLabel {
    if (invitation.hasLapsed && invitation.status == 'pending') {
      return 'Expired';
    }
    return switch (invitation.status) {
      'pending' => 'Pending',
      'accepted' => 'Accepted',
      'rejected' => 'Declined',
      'expired' => 'Expired',
      _ => invitation.status,
    };
  }

  Color get _statusTint {
    if (invitation.hasLapsed && invitation.status == 'pending') {
      return AppColors.textHint;
    }
    return switch (invitation.status) {
      'accepted' => AppColors.success,
      'rejected' => AppColors.error,
      'expired' => AppColors.textHint,
      _ => AppColors.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(
                url: invitation.counterpartAvatarUrl,
                name: invitation.recipientLabel,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.recipientLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      networkMemberTypeLabel(invitation.memberType),
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Pill(label: _statusLabel, tint: _statusTint),
            ],
          ),

          if (invitation.message != null) ...[
            const SizedBox(height: 8),
            Text(
              invitation.message!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ],

          // Only worth saying while it still matters.
          if (invitation.isActionable && invitation.expiresAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 13,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Expires ${_formatDate(invitation.expiresAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],

          // An off-platform invite cannot be accepted in-app: there is no
          // `invited_user_id` for a session to match, so saying so beats leaving
          // the builder wondering why nothing happened.
          if (invitation.isOffPlatform && invitation.status == 'pending') ...[
            const SizedBox(height: 6),
            Text(
              'Waiting for them to create an account.',
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ],

          if (onAccept != null || onDecline != null || busy) ...[
            const SizedBox(height: AppConstants.spacingM),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 6),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.check_rounded,
                      label: 'Accept',
                      tint: AppColors.success,
                      onTap: onAccept,
                    ),
                  ),
                  Expanded(
                    child: _Action(
                      icon: Icons.close_rounded,
                      label: 'Decline',
                      tint: AppColors.error,
                      onTap: onDecline,
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  static const double _size = 38;

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    Widget initials() => Container(
      width: _size,
      height: _size,
      color: AppColors.primaryLight,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );

    return ClipOval(
      child: url == null || url!.isEmpty
          ? initials()
          : CachedNetworkImage(
              imageUrl: url!,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              placeholder: (_, _) => initials(),
              errorWidget: (_, _, _) => initials(),
            ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.textHint : tint;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The invite sheet ────────────────────────────────────────────────────────

/// What the sheet hands back.
class _InviteDraft {
  const _InviteDraft({
    required this.memberType,
    this.invitedUserId,
    this.email,
    this.phone,
    this.message,
  });

  final String memberType;
  final String? invitedUserId;
  final String? email;
  final String? phone;
  final String? message;

  String get recipientLabel => email ?? phone ?? 'them';
}

/// The builder's invite form — `BuilderNetworkInvitations.tsx`'s two paths.
///
/// Search for someone with an account, or invite by email/phone. `member_type` is
/// required on both, which is the portal's own rule (`:179-181`) as well as a NOT
/// NULL CHECK column.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.service});

  final ProfileConnectionService service;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _search = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();

  String? _memberType;
  InviteeSuggestion? _selected;
  List<InviteeSuggestion> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _email.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String term) async {
    setState(() => _searching = true);
    final results = await widget.service.searchInvitees(term);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _submit() {
    if (_memberType == null) {
      setState(
        () => _error = 'Choose whether they are a broker or influencer.',
      );
      return;
    }

    final picked = _selected;
    final email = _email.text.trim();
    final phone = _phone.text.trim();

    if (picked == null && email.isEmpty && phone.isEmpty) {
      setState(
        () => _error = 'Pick someone, or enter an email or phone number.',
      );
      return;
    }

    Navigator.pop(
      context,
      _InviteDraft(
        memberType: _memberType!,
        invitedUserId: picked?.userId,
        // Only sent when there is no account to point at — the portal keeps the two
        // paths separate the same way.
        email: picked == null && email.isNotEmpty ? email : null,
        phone: picked == null && phone.isNotEmpty ? phone : null,
        message: _message.text.trim().isEmpty ? null : _message.text.trim(),
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
                'Invite to Your Network',
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

              Text(
                'They are a *',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final type in kNetworkMemberTypes)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _memberType = type.value;
                          _error = null;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _memberType == type.value
                                ? AppColors.primary
                                : AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              AppConstants.pillRadius,
                            ),
                          ),
                          child: Text(
                            type.label,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _memberType == type.value
                                  ? Colors.white
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Find someone',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _search,
                onChanged: (value) {
                  setState(() {
                    _selected = null;
                    _error = null;
                  });
                  if (value.trim().length >= 2) {
                    _runSearch(value);
                  } else {
                    setState(() => _results = const []);
                  }
                },
                decoration: _decoration('Search by name'),
              ),
              if (_searching)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              for (final result in _results)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: _Avatar(url: result.avatarUrl, name: result.name),
                  title: Text(
                    result.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(fontSize: 13),
                  ),
                  subtitle: Text(
                    networkMemberTypeLabel(result.userType),
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                  trailing: _selected?.userId == result.userId
                      ? const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () => setState(() {
                    _selected = result;
                    // Picking a person and typing an email are the two paths; one
                    // clears the other so the payload cannot carry both.
                    _email.clear();
                    _phone.clear();
                    _error = null;
                  }),
                ),
              const SizedBox(height: 14),

              Text(
                _selected == null
                    ? 'Or invite by email / phone'
                    : 'Inviting ${_selected!.name}',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              if (_selected == null) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: _decoration('name@example.com'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: _decoration('Phone number'),
                ),
                const SizedBox(height: 6),
                Text(
                  "They'll be able to accept once they create an account.",
                  style: AppTextStyles.caption.copyWith(fontSize: 11),
                ),
              ],
              const SizedBox(height: 14),

              Text(
                'Message',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _message,
                maxLines: 3,
                decoration: _decoration('Optional note'),
              ),
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
                      child: const Text('Send Invite'),
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

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.hairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.hairline),
    ),
  );
}
