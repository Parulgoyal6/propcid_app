import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/animations/page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/segmented_tab_pill.dart';
import '../../models/network_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_thread_provider.dart';
import '../../providers/network_communication_provider.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/toggle_row.dart';
import '../messaging/chat_thread_screen.dart';
import 'widgets/bulk_message_sheet.dart';
import 'widgets/create_network_channel_sheet.dart';
import 'widgets/network_screen_shell.dart';

/// Network ▸ Communication — the design's `isCommunication` screen.
///
/// Three sub-tabs (Channels / Messaging / Settings) over `network_channels`,
/// `channels` and `channel_participants`. Builders can create channels
/// (auto-joining eligible accepted members) and send bulk messages to their
/// accepted network; members see and open only the channels they actually
/// participate in. Settings stays read-only — see the note rendered on that
/// tab — because neither switch has a column of its own to persist to.
class NetworkCommunicationScreen extends StatelessWidget {
  const NetworkCommunicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkCommunicationProvider(),
      child: const _CommunicationView(),
    );
  }
}

class _CommunicationView extends StatefulWidget {
  const _CommunicationView();

  @override
  State<_CommunicationView> createState() => _CommunicationViewState();
}

class _CommunicationViewState extends State<_CommunicationView> {
  String? _loadedUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  /// Mirrors [DeferredSectionLoader] but also needs `isBuilder`, which that
  /// mixin's `loadSection(String userId)` signature has no room for — a
  /// member and a builder read entirely different tables (see
  /// [NetworkCommunicationService.loadCommunicationData]), so the role has to
  /// travel with the load, not just the id.
  void _loadIfNeeded() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null || userId == _loadedUserId) return;
    _loadedUserId = userId;

    final isBuilder = auth.userType?.toLowerCase() == 'builder';
    final provider = context.read<NetworkCommunicationProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId, isBuilder: isBuilder);
    });
  }

  Future<void> _createChannel() async {
    await showCreateNetworkChannelSheet(context);
    // The provider already refreshed itself on success; nothing further to
    // do here — this screen watches the same instance the sheet mutated.
  }

  Future<void> _bulkMessage() async {
    final count = await showBulkMessageSheet(context);
    if (count == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bulk message sent to $count network members.')),
    );
  }

  Future<void> _openChannel(NetworkChannel channel) async {
    final provider = context.read<NetworkCommunicationProvider>();
    await Navigator.of(context).push(
      PremiumPageRoute(
        settings: const RouteSettings(name: AppConstants.channelChatScreen),
        builder: (_) => ChatThreadScreen(
          kind: ChatThreadKind.channel,
          threadId: channel.channelId,
          title: channel.displayName,
          subtitle: channel.participantCount == 1
              ? '1 member'
              : '${channel.participantCount} members',
          initials: channel.initials,
          isChannelAdmin: channel.isCurrentUserAdmin,
        ),
      ),
    );
    if (mounted) await provider.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NetworkCommunicationProvider>();

    return NetworkCommunicationBody(
      channels: provider.channels,
      loading: provider.loading,
      failed: provider.failed,
      isBuilder: provider.isBuilder,
      onCreateChannel: _createChannel,
      onBulkMessage: _bulkMessage,
      onOpenChannel: _openChannel,
    );
  }
}

class NetworkCommunicationBody extends StatefulWidget {
  final List<NetworkChannel> channels;
  final bool loading;
  final bool failed;
  final bool isBuilder;
  final VoidCallback onCreateChannel;
  final VoidCallback onBulkMessage;

  /// Optional so every pre-existing widget test that constructs this body
  /// directly (with no channel to tap) keeps compiling unchanged.
  final ValueChanged<NetworkChannel>? onOpenChannel;

  const NetworkCommunicationBody({
    super.key,
    required this.channels,
    required this.loading,
    required this.failed,
    required this.onCreateChannel,
    required this.onBulkMessage,
    this.isBuilder = false,
    this.onOpenChannel,
  });

  @override
  State<NetworkCommunicationBody> createState() =>
      _NetworkCommunicationBodyState();
}

class _NetworkCommunicationBodyState extends State<NetworkCommunicationBody> {
  int _tab = 0;

  static const List<String> _tabs = ['Channels', 'Messaging', 'Settings'];

  /// Below this, two side-by-side action buttons truncate their labels — the
  /// exact regression this rewrite fixes. Stack instead of shrinking further.
  static const double _stackedActionsBreakpoint = 360;

  @override
  Widget build(BuildContext context) {
    return NetworkScreenShell(
      title: 'Network Communication',
      subtitle: 'Channels, announcements & messages',
      children: [
        const SizedBox(height: 18),
        NetworkIntroBanner(
          title: 'Network Communication Hub',
          description:
              'Manage channels, send announcements, and stay '
              'connected with your network',
          // Not role-gated: the portal's `NetworkCommunicationHub.tsx` shows
          // Create Channel/Bulk Message to every signed-in user with no
          // `user_type` check at all — a broker, influencer or individual
          // can create their own channel and message their own accepted
          // network exactly like a builder can.
          action: _buildActions(),
        ),
        const SizedBox(height: AppConstants.spacingL),
        SegmentedTabPill(
          labels: _tabs,
          selectedIndex: _tab,
          onChanged: (index) => setState(() => _tab = index),
          labelFontSize: 12,
          itemVerticalPadding: 9,
        ),
        const SizedBox(height: AppConstants.spacingL),
        _buildTab(),
      ],
    );
  }

  /// A responsive `Wrap` rather than a fixed `Row`: on a narrow phone each
  /// button gets the full width on its own line; on a wider one they share a
  /// row, matching the design without ever truncating a label.
  Widget _buildActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < _stackedActionsBreakpoint;
        final createButton = AppActionButton(
          label: 'Create Channel',
          height: 40,
          fontSize: 12.5,
          icon: Icons.add,
          onTap: widget.onCreateChannel,
        );
        final bulkButton = AppActionButton(
          label: 'Bulk Message',
          height: 40,
          fontSize: 12.5,
          icon: Icons.send_outlined,
          variant: AppActionButtonVariant.outline,
          onTap: widget.onBulkMessage,
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [createButton, const SizedBox(height: 10), bulkButton],
          );
        }

        return Row(
          children: [
            Expanded(child: createButton),
            const SizedBox(width: 10),
            Expanded(child: bulkButton),
          ],
        );
      },
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 1:
        return _MessagingTab(onComposeMessage: widget.onBulkMessage);
      case 2:
        return _SettingsTab(channels: widget.channels, failed: widget.failed);
      default:
        return NetworkTitledCard(
          icon: Icons.tag,
          title: 'Network Channels',
          child: _buildChannels(),
        );
    }
  }

  Widget _buildChannels() {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (widget.failed) {
      return const Padding(
        padding: EdgeInsets.only(top: AppConstants.spacingXL),
        child: EmptyStateView(
          icon: Icons.error_outline,
          title: "Couldn't load channels",
          message: 'Try again in a moment.',
          iconCircleSize: 56,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      );
    }

    if (widget.channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppConstants.spacingXL),
        child: EmptyStateView(
          icon: Icons.chat_bubble_outline,
          title: 'No Channels Created',
          message:
              'Create channels to organize communication with your network.',
          iconCircleSize: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          // Not role-gated — see the create/bulk-message action row's own
          // note.
          actionLabel: 'Create First Channel',
          onAction: widget.onCreateChannel,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.channels.length; i++) ...[
          SizedBox(height: i == 0 ? AppConstants.spacingL : 10),
          _ChannelRow(
            channel: widget.channels[i],
            onOpen: widget.onOpenChannel == null
                ? null
                : () => widget.onOpenChannel!(widget.channels[i]),
          ),
        ],
      ],
    );
  }
}

/// Messaging tab — matches the portal's copy exactly: an explanation plus a
/// "Compose Message" CTA that opens the same Bulk Message sheet the header
/// button does, for every role — the portal renders this same static card
/// with no `user_type` check. There is no sent-message history: the backend
/// has no `network_broadcasts` table and sender-side notification history is
/// not readable back through current RLS, so this never fabricates one.
class _MessagingTab extends StatelessWidget {
  final VoidCallback onComposeMessage;

  const _MessagingTab({required this.onComposeMessage});

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: EmptyStateView(
        icon: Icons.send_outlined,
        title: 'Send Messages to Your Network',
        message:
            'Send announcements, lead alerts, and updates to all or '
            'specific network members.',
        iconCircleSize: 56,
        actionLabel: 'Compose Message',
        onAction: onComposeMessage,
      ),
    );
  }
}

/// The design's two switches, reported from the channels that exist.
class _SettingsTab extends StatelessWidget {
  final List<NetworkChannel> channels;
  final bool failed;

  const _SettingsTab({required this.channels, required this.failed});

  @override
  Widget build(BuildContext context) {
    // Derived, not invented: a network has channel notifications in play if any
    // channel exists, and member self-service joining if any channel is
    // auto-join. Neither is a stored preference, which is why both are inert.
    final hasChannels = channels.isNotEmpty;
    final anyAutoJoin = channels.any((c) => c.isAutoJoin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'These reflect your channel setup. Changing them becomes '
                  'available once channel management ships.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        DashboardCard(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToggleRow(
                label: 'Channel notifications',
                value: !failed && hasChannels,
                showDivider: true,
              ),
              ToggleRow(
                label: 'Allow member invites',
                value: !failed && anyAutoJoin,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final NetworkChannel channel;

  /// Null when there is nothing to open with (no callback wired) — renders
  /// the row without an action rather than a dead button. Also withheld by
  /// the caller when [NetworkChannel.isCurrentUserParticipant] is false, so a
  /// channel the viewer isn't actually in can never be tapped open.
  final VoidCallback? onOpen;

  const _ChannelRow({required this.channel, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final hasName = channel.name != null && channel.name!.trim().isNotEmpty;
    final hasDescription =
        channel.description != null && channel.description!.trim().isNotEmpty;
    final canOpen = onOpen != null && channel.isCurrentUserParticipant;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasName) ...[
            Text(
              channel.name!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (hasDescription) ...[
              const SizedBox(height: 3),
              Text(
                channel.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              const Icon(Icons.tag, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.purposeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (channel.isAutoJoin) ...[
                const SizedBox(width: AppConstants.spacingS),
                const NetworkStatusPill('Auto-join', positive: true),
              ],
            ],
          ),
          const SizedBox(height: 8),
          NetworkDetailRow(
            label: 'Participants',
            value: '${channel.participantCount}',
          ),
          if (channel.memberTypes.isNotEmpty) ...[
            const SizedBox(height: 4),
            NetworkDetailRow(
              label: 'Member types',
              value: channel.memberTypes.join(', '),
            ),
          ],
          if (onOpen != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: canOpen ? onOpen : null,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Open Channel'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
