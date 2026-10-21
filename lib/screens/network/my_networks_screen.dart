import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/network_relationship.dart';
import '../../providers/network_relationships_provider.dart';
import '../../widgets/shared/stat_kpi_card.dart';
import '../messaging/widgets/chat_avatar.dart';
import '../shared/section_loader.dart';
import 'widgets/network_screen_shell.dart';

/// Network ▸ My Networks — the design's `isMyNetworks` screen.
///
/// Lists the caller's `builder_networks` connections, from either side of the
/// relationship, classified via [NetworkRelationship] rather than the raw
/// row-direction check the previous version rendered directly: "Broker in
/// your network" / "Member of a builder network" told the viewer only which
/// column they happened to be in, never who the other person actually was —
/// and, because `builder_networks`' RLS is fully symmetric with the generic
/// profile "Connect" flow, direction alone can't even be trusted to mean
/// "genuine network membership" (see `network_relationship.dart`'s header).
///
/// Three sections, shown only when non-empty: Current Network Members (rows
/// this viewer owns, with a real broker/influencer counterpart), Networks
/// Joined (builder networks this viewer belongs to), and Peer Connections
/// (accepted, but not safely either of the above). Pending requests and
/// formal invitations keep living in `NetworkInvitationsSection` on the
/// Network hub — they are not a membership until accepted, and moving that
/// already-working Accept/Decline flow here was a UI relocation, not a
/// correctness fix, so it was left alone.
///
/// Above those sections, three stat cards mirror the portal's own My Network
/// tab (`NetworkMemberships.tsx`'s Total Connections / Requests Sent /
/// Requests Received): counted from the exact same classified
/// [relationships] list the sections below already filter, so there is
/// nothing new to fetch — Total Connections is every accepted kind
/// ([isActiveMembershipKind]), Requests Sent is
/// [NetworkRelationshipKind.outgoingPeerRequest], Requests Received is
/// [NetworkRelationshipKind.incomingPeerRequest].
class MyNetworksScreen extends StatelessWidget {
  const MyNetworksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkRelationshipsProvider(),
      child: const _MyNetworksView(),
    );
  }
}

class _MyNetworksView extends StatefulWidget {
  const _MyNetworksView();

  @override
  State<_MyNetworksView> createState() => _MyNetworksViewState();
}

class _MyNetworksViewState extends State<_MyNetworksView>
    with DeferredSectionLoader<_MyNetworksView> {
  // Classification depends only on each row's own direction and the
  // counterpart's real profile type — never on the viewer's own role — so,
  // unlike My Leads/My Referrals, this load has nothing to get wrong by
  // running before `AuthProvider.userType` resolves.
  @override
  void loadSection(String userId) =>
      context.read<NetworkRelationshipsProvider>().load(userId);

  /// Which of the three stat tiles is selected — mirrors the portal's
  /// `NetworkMemberships.tsx` `activeTile` state, which switches the list
  /// card below between Connections / Sent / Received instead of stacking
  /// all three. Local UI state: it doesn't need to survive a provider
  /// refresh or outlive this screen.
  MyNetworksTile _activeTile = MyNetworksTile.total;

  void _selectTile(MyNetworksTile tile) {
    if (tile == _activeTile) return;
    setState(() => _activeTile = tile);
  }

  Future<void> _confirmAndLeave(NetworkRelationship relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave network?'),
        content: Text(
          "You'll stop seeing ${relationship.counterpartDisplayLabel} in "
          'your networks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<NetworkRelationshipsProvider>();
    final ok = await provider.leaveNetwork(relationship.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.leaveError ??
                "Couldn't leave this network. Please try again.",
          ),
        ),
      );
    }
  }

  Future<void> _cancelSent(NetworkRelationship relationship) async {
    final provider = context.read<NetworkRelationshipsProvider>();
    final ok = await provider.cancelSentRequest(relationship);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(provider.actionError!)));
  }

  Future<void> _acceptReceived(NetworkRelationship relationship) async {
    final provider = context.read<NetworkRelationshipsProvider>();
    final ok = await provider.acceptReceivedRequest(relationship);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(provider.actionError!)));
  }

  Future<void> _declineReceived(NetworkRelationship relationship) async {
    final provider = context.read<NetworkRelationshipsProvider>();
    final ok = await provider.declineReceivedRequest(relationship);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(provider.actionError!)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NetworkRelationshipsProvider>();

    return MyNetworksBody(
      relationships: provider.relationships,
      loading: provider.loading,
      failed: provider.failed,
      leavingRelationshipId: provider.leavingId,
      onLeave: _confirmAndLeave,
      activeTile: _activeTile,
      onSelectTile: _selectTile,
      actingOnId: provider.actingId,
      onCancelSent: _cancelSent,
      onAcceptReceived: _acceptReceived,
      onDeclineReceived: _declineReceived,
    );
  }
}

/// Which stat tile's list is shown below the stats row.
enum MyNetworksTile { total, sent, received }

class MyNetworksBody extends StatelessWidget {
  final List<NetworkRelationship> relationships;
  final bool loading;
  final bool failed;

  /// The `builder_networks.id` currently being left, so its row can show a
  /// busy state and every row's button can be disabled while it's in flight.
  final String? leavingRelationshipId;

  /// Optional so every pre-existing test that constructs this body directly
  /// keeps compiling and keeps passing with no Leave button rendered.
  final ValueChanged<NetworkRelationship>? onLeave;

  /// Which stat tile's list is shown below the stats row. Defaults to the
  /// pre-existing behaviour (the owned/joined/peer sections) so every
  /// pre-existing test/call site that doesn't pass this keeps rendering
  /// exactly as it did before.
  final MyNetworksTile activeTile;
  final ValueChanged<MyNetworksTile>? onSelectTile;

  /// The `builder_networks.id` of a pending request currently being
  /// cancelled/accepted/declined — the Sent/Received tiles' equivalent of
  /// [leavingRelationshipId].
  final String? actingOnId;
  final ValueChanged<NetworkRelationship>? onCancelSent;
  final ValueChanged<NetworkRelationship>? onAcceptReceived;
  final ValueChanged<NetworkRelationship>? onDeclineReceived;

  const MyNetworksBody({
    super.key,
    required this.relationships,
    required this.loading,
    required this.failed,
    this.leavingRelationshipId,
    this.onLeave,
    this.activeTile = MyNetworksTile.total,
    this.onSelectTile,
    this.actingOnId,
    this.onCancelSent,
    this.onAcceptReceived,
    this.onDeclineReceived,
  });

  List<NetworkRelationship> _where(NetworkRelationshipKind kind) =>
      relationships.where((r) => r.kind == kind).toList(growable: false);

  int get _totalConnections =>
      relationships.where((r) => isActiveMembershipKind(r.kind)).length;
  int get _requestsSentCount =>
      _where(NetworkRelationshipKind.outgoingPeerRequest).length;
  int get _requestsReceivedCount =>
      _where(NetworkRelationshipKind.incomingPeerRequest).length;

  @override
  Widget build(BuildContext context) {
    return NetworkScreenShell(
      title: 'My Networks',
      subtitle: 'View and manage your network connections',
      children: [
        const SizedBox(height: 20),
        // Loading/failure are already communicated by `_buildBody()`'s own
        // spinner/error card below — showing stat counts alongside either
        // state would either flash "0" before the real numbers land or claim
        // a count the load never actually confirmed.
        if (!loading && !failed) ...[
          _NetworkStatsRow(
            total: _totalConnections,
            sent: _requestsSentCount,
            received: _requestsReceivedCount,
            activeTile: activeTile,
            onSelectTile: onSelectTile,
          ),
          const SizedBox(height: AppConstants.spacingL),
        ],
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const NetworkTitledCard(
        icon: Icons.people_outline,
        title: 'Current Networks',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (failed) {
      return const NetworkTitledCard(
        icon: Icons.people_outline,
        title: 'Current Networks',
        child: Padding(
          padding: EdgeInsets.only(top: AppConstants.spacingXXL),
          child: EmptyStateView(
            icon: Icons.error_outline,
            title: "Couldn't load your networks",
            message: 'Try again in a moment.',
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    return switch (activeTile) {
      MyNetworksTile.total => _buildConnections(),
      MyNetworksTile.sent => _buildSentRequests(),
      MyNetworksTile.received => _buildReceivedRequests(),
    };
  }

  Widget _buildConnections() {
    final owned = _where(NetworkRelationshipKind.ownedNetworkMember);
    final joined = _where(NetworkRelationshipKind.joinedBuilderNetwork);
    final peers = _where(NetworkRelationshipKind.peerConnection);

    if (owned.isEmpty && joined.isEmpty && peers.isEmpty) {
      return NetworkTitledCard(
        icon: Icons.people_outline,
        title: 'Current Networks',
        child: const Padding(
          padding: EdgeInsets.only(top: AppConstants.spacingXXL),
          child: EmptyStateView(
            icon: Icons.apartment_rounded,
            title: 'No Network Memberships',
            message:
                "You haven't joined any networks yet. Invitations you "
                'receive appear on the Network hub.',
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owned.isNotEmpty) ...[
          NetworkTitledCard(
            icon: Icons.groups_2_outlined,
            title: 'Current Network Members',
            child: _RelationshipList(
              relationships: owned,
              leavingRelationshipId: leavingRelationshipId,
              onLeave: onLeave,
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
        ],
        if (joined.isNotEmpty) ...[
          NetworkTitledCard(
            icon: Icons.apartment_outlined,
            title: 'Networks Joined',
            child: _RelationshipList(
              relationships: joined,
              leavingRelationshipId: leavingRelationshipId,
              onLeave: onLeave,
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
        ],
        if (peers.isNotEmpty)
          NetworkTitledCard(
            icon: Icons.link_outlined,
            title: 'Peer Connections',
            child: _RelationshipList(
              relationships: peers,
              leavingRelationshipId: leavingRelationshipId,
              onLeave: onLeave,
            ),
          ),
      ],
    );
  }

  Widget _buildSentRequests() {
    final sent = _where(NetworkRelationshipKind.outgoingPeerRequest);

    if (sent.isEmpty) {
      return const NetworkTitledCard(
        icon: Icons.send_outlined,
        title: 'Requests Sent',
        child: Padding(
          padding: EdgeInsets.only(top: AppConstants.spacingXXL),
          child: EmptyStateView(
            icon: Icons.send_outlined,
            title: 'No Pending Requests',
            message: "Connection requests you've sent will appear here.",
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    return NetworkTitledCard(
      icon: Icons.send_outlined,
      title: 'Requests Sent',
      child: _RelationshipList(
        relationships: sent,
        actingOnId: actingOnId,
        onCancel: onCancelSent,
      ),
    );
  }

  Widget _buildReceivedRequests() {
    final received = _where(NetworkRelationshipKind.incomingPeerRequest);

    if (received.isEmpty) {
      return const NetworkTitledCard(
        icon: Icons.move_to_inbox_outlined,
        title: 'Requests Received',
        child: Padding(
          padding: EdgeInsets.only(top: AppConstants.spacingXXL),
          child: EmptyStateView(
            icon: Icons.move_to_inbox_outlined,
            title: 'No Pending Requests',
            message: 'Connection requests waiting on your reply appear here.',
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      );
    }

    return NetworkTitledCard(
      icon: Icons.move_to_inbox_outlined,
      title: 'Requests Received',
      child: _RelationshipList(
        relationships: received,
        actingOnId: actingOnId,
        onAccept: onAcceptReceived,
        onDecline: onDeclineReceived,
      ),
    );
  }
}

/// The portal's three "My Network" stat cards, in one row rather than
/// [MetricCardGrid]'s fixed two-column layout — the design shows exactly
/// three, side by side, not a 2-and-1 wrap.
///
/// Each tile is a tab, not just a counter — matching `NetworkMemberships.tsx`
/// (`onClick={() => setActiveTile(...)}`), which switches the list card
/// below to whichever tile is selected instead of rendering all three lists
/// at once. [MetricCard] itself stays untouched (it backs several other,
/// purely-decorative grids elsewhere), so the tap target and selected
/// styling are added here as a wrapper instead.
class _NetworkStatsRow extends StatelessWidget {
  final int total;
  final int sent;
  final int received;
  final MyNetworksTile activeTile;
  final ValueChanged<MyNetworksTile>? onSelectTile;

  const _NetworkStatsRow({
    required this.total,
    required this.sent,
    required this.received,
    this.activeTile = MyNetworksTile.total,
    this.onSelectTile,
  });

  @override
  Widget build(BuildContext context) {
    // MetricCard's own Column ends in a Flexible, which needs a bounded
    // height to lay out in — MetricCardGrid normally supplies that via its
    // fixed-height grid cells. A plain Row has no such height of its own
    // (its parent Column is inside a scroll view, so the constraint coming
    // down is unbounded), so each card gets the same fixed height explicitly.
    const cardHeight = MetricCardGrid.cardHeight;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            height: cardHeight,
            selected: activeTile == MyNetworksTile.total,
            onTap: onSelectTile == null
                ? null
                : () => onSelectTile!(MyNetworksTile.total),
            child: MetricCard(
              icon: Icons.people_outline,
              value: '$total',
              label: 'Total Connections',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            height: cardHeight,
            selected: activeTile == MyNetworksTile.sent,
            onTap: onSelectTile == null
                ? null
                : () => onSelectTile!(MyNetworksTile.sent),
            child: MetricCard(
              icon: Icons.send_outlined,
              value: '$sent',
              label: 'Requests Sent',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            height: cardHeight,
            selected: activeTile == MyNetworksTile.received,
            onTap: onSelectTile == null
                ? null
                : () => onSelectTile!(MyNetworksTile.received),
            child: MetricCard(
              icon: Icons.move_to_inbox_outlined,
              value: '$received',
              label: 'Requests Received',
            ),
          ),
        ),
      ],
    );
  }
}

/// Tappable/selectable wrapper around one [MetricCard] — the ripple and
/// selected-border live here so [MetricCard] itself needs no `onTap`
/// parameter that its other (non-tab) callers would have to ignore.
class _StatTile extends StatelessWidget {
  final double height;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  const _StatTile({
    required this.height,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              border: Border.all(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _RelationshipList extends StatelessWidget {
  final List<NetworkRelationship> relationships;
  final String? leavingRelationshipId;
  final ValueChanged<NetworkRelationship>? onLeave;

  /// The `builder_networks.id` of a pending request currently being acted
  /// on — the Sent/Received lists' equivalent of [leavingRelationshipId].
  final String? actingOnId;
  final ValueChanged<NetworkRelationship>? onCancel;
  final ValueChanged<NetworkRelationship>? onAccept;
  final ValueChanged<NetworkRelationship>? onDecline;

  const _RelationshipList({
    required this.relationships,
    this.leavingRelationshipId,
    this.onLeave,
    this.actingOnId,
    this.onCancel,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < relationships.length; i++) ...[
          SizedBox(height: i == 0 ? AppConstants.spacingL : 10),
          _RelationshipRow(
            relationship: relationships[i],
            leaving: relationships[i].id == leavingRelationshipId,
            onLeave: onLeave == null ? null : () => onLeave!(relationships[i]),
            acting: relationships[i].id == actingOnId,
            onCancel: onCancel == null
                ? null
                : () => onCancel!(relationships[i]),
            onAccept: onAccept == null
                ? null
                : () => onAccept!(relationships[i]),
            onDecline: onDecline == null
                ? null
                : () => onDecline!(relationships[i]),
          ),
        ],
      ],
    );
  }
}

class _RelationshipRow extends StatelessWidget {
  final NetworkRelationship relationship;
  final bool leaving;
  final VoidCallback? onLeave;

  /// True while this row's Cancel/Accept/Decline write is in flight.
  final bool acting;
  final VoidCallback? onCancel;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _RelationshipRow({
    required this.relationship,
    this.leaving = false,
    this.onLeave,
    this.acting = false,
    this.onCancel,
    this.onAccept,
    this.onDecline,
  });

  /// Commission rate/auto-convert are meaningful only for an owned network
  /// member — a peer connection or a network the viewer joined has no
  /// commission arrangement running the other way.
  bool get _showsCommissionDetails =>
      relationship.kind == NetworkRelationshipKind.ownedNetworkMember;

  /// "Connected" only makes sense once a relationship is actually accepted;
  /// a still-pending row's `created_at` is when the request itself was made.
  String get _dateLabel => switch (relationship.kind) {
    NetworkRelationshipKind.outgoingPeerRequest => 'Sent',
    NetworkRelationshipKind.incomingPeerRequest => 'Received',
    _ => 'Connected',
  };

  /// Opens the counterpart's public profile; a row with no resolved user id
  /// has nothing to open.
  void _openProfile(BuildContext context) {
    final userId = relationship.counterpartUserId;
    if (userId == null || userId.isEmpty) return;
    Navigator.pushNamed(
      context,
      AppConstants.publicProfileScreen,
      arguments: {'userId': userId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final rate = relationship.commissionRateLabel;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Avatar + name open the member's public profile.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openProfile(context),
                child: ChatAvatar(
                  avatarUrl: relationship.counterpartAvatarUrl,
                  initials: relationship.counterpartInitial,
                  size: 36,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openProfile(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        relationship.counterpartDisplayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (relationship.counterpartSubtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          relationship.counterpartSubtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              NetworkStatusPill(
                relationship.status,
                positive: relationship.isAccepted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          NetworkDetailRow(label: 'Role', value: relationship.roleLabel),
          if (relationship.createdAt != null)
            NetworkDetailRow(
              label: _dateLabel,
              value: _formatConnectedDate(relationship.createdAt!),
            ),
          if (_showsCommissionDetails) ...[
            if (rate != null)
              NetworkDetailRow(label: 'Commission rate', value: rate),
            NetworkDetailRow(
              label: 'Verified',
              value: relationship.verified ? 'Yes' : 'No',
            ),
            NetworkDetailRow(
              label: 'Auto-convert leads',
              value: relationship.autoConvertLeads ? 'On' : 'Off',
            ),
          ],
          // Leaving is meaningful for any accepted relationship — owned,
          // joined or peer — so this isn't gated on `_showsCommissionDetails`.
          if (onLeave != null && relationship.isAccepted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
                onPressed: leaving ? null : onLeave,
                child: Text(leaving ? 'Leaving…' : 'Leave Network'),
              ),
            ),
          ],
          // Requests Sent: withdraw the request this viewer sent.
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            if (acting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  onPressed: onCancel,
                  child: const Text('Cancel Request'),
                ),
              ),
          ],
          // Requests Received: accept or decline the request this viewer got.
          if (onAccept != null || onDecline != null) ...[
            const SizedBox(height: 10),
            if (acting)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
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
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(color: AppColors.success),
                      ),
                      onPressed: onAccept,
                      child: const Text('Accept'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      onPressed: onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// Mirrors `NetworkInvitationsSection._formatDate` — no `intl` dependency,
  /// same "Jan 5, 2026" shape the portal's `toLocaleDateString()` produces.
  static String _formatConnectedDate(DateTime dt) {
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
