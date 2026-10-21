import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/conversation_summary.dart';
import '../../services/messaging_service.dart';
import 'widgets/chat_avatar.dart';

/// Lists everyone the current user has personally blocked (`user_blocks`
/// where `blocker_id = me`), with an unblock action per row. The mobile
/// equivalent of the portal's `BlockedUsersModal.tsx` — reuses the exact
/// same table/RLS, no new backend contract.
class BlockedUsersScreen extends StatefulWidget {
  final String currentUserId;

  const BlockedUsersScreen({super.key, required this.currentUserId});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _service = MessagingService();
  List<ConversationParticipant> _blocked = const [];
  bool _loading = true;
  bool _failed = false;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final list = await _service.fetchBlockedUsers(widget.currentUserId);
      if (!mounted) return;
      setState(() => _blocked = list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(ConversationParticipant person) async {
    setState(() => _unblocking.add(person.userId));
    try {
      await _service.unblockUser(person.userId);
      if (mounted) {
        setState(() {
          _blocked = _blocked.where((p) => p.userId != person.userId).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't unblock ${person.displayName}.")),
        );
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(person.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Blocked Users'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_failed) {
      return Center(
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load blocked users",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }

    if (_blocked.isEmpty) {
      return const Center(
        child: EmptyStateView(
          icon: Icons.block,
          title: 'No blocked users',
          message: "People you've blocked will appear here.",
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _blocked.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final person = _blocked[index];
        final busy = _unblocking.contains(person.userId);

        return ListTile(
          leading: ChatAvatar(
            avatarUrl: person.avatarUrl,
            initials: person.initial,
            size: 40,
          ),
          title: Text(
            person.displayName,
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          trailing: OutlinedButton(
            onPressed: busy ? null : () => _unblock(person),
            child: Text(busy ? 'Unblocking…' : 'Unblock'),
          ),
        );
      },
    );
  }
}
