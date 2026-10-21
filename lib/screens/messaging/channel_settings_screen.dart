import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/channel_summary.dart';
import '../../models/conversation_summary.dart';
import '../../services/messaging_exceptions.dart';
import '../../services/messaging_service.dart';
import 'widgets/chat_avatar.dart';
import 'widgets/new_chat_sheet.dart' show MessagesSearchField;

/// Channel settings & member management — mirrors the portal's
/// `ChannelSettingsModal.tsx`: a Settings tab (name/description/max
/// participants/who-can-message, creator-only) and a Members tab (add
/// members, personal block, channel-wide admin block, remove).
///
/// `isAdmin`/`isModerator` are derived here from the channel's own
/// `created_by` plus the caller's own participant row, fetched fresh on
/// load — not solely from the [isAdmin] constructor value, which only one of
/// this screen's two entry points (`ChatThreadScreen`, shared by the
/// Messages tab and the Network hub) threads through accurately for role
/// vs. moderator vs. creator. Every write below is re-verified server-side
/// by its own edge function regardless, matching the portal exactly, so a
/// stale client-side flag here can only ever hide a control a user doesn't
/// have — never grant one they shouldn't.
class ChannelSettingsScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String currentUserId;
  final bool isAdmin;

  const ChannelSettingsScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.currentUserId,
    required this.isAdmin,
  });

  @override
  State<ChannelSettingsScreen> createState() => _ChannelSettingsScreenState();
}

class _ChannelSettingsScreenState extends State<ChannelSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _service = MessagingService();
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _memberSearchController = TextEditingController();

  List<ChannelParticipantDetail> _participants = const [];
  Set<String> _blockedByMe = const {};
  String? _createdBy;
  String _messagingPermission = 'everyone';

  bool _loading = true;
  bool _failed = false;
  bool _savingSettings = false;
  bool _addingMembers = false;

  final List<ConversationParticipant> _selectedMembers = [];
  Timer? _debounce;
  List<ConversationParticipant> _searchResults = const [];
  bool _searching = false;
  int _searchRequestId = 0;

  bool get _isAdmin => widget.currentUserId == _createdBy || _myRole == 'admin';
  bool get _isModerator => _myRole == 'moderator' || _isAdmin;

  String? get _myRole {
    for (final p in _participants) {
      if (p.userId == widget.currentUserId) return p.role;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _maxParticipantsController.dispose();
    _memberSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _service.fetchChannelInfo(widget.channelId),
        _service.fetchChannelParticipantsDetailed(widget.channelId),
        _service.myBlockedUserIds(widget.currentUserId),
      ]);
      if (!mounted) return;

      final info = results[0] as Map<String, dynamic>;
      final participants = results[1] as List<ChannelParticipantDetail>;
      final blocked = results[2] as Set<String>;

      setState(() {
        _createdBy = info['created_by']?.toString();
        _messagingPermission =
            (info['messaging_permission'] as String?) ?? 'everyone';
        _nameController.text = (info['name'] as String?) ?? widget.channelName;
        _descriptionController.text = (info['description'] as String?) ?? '';
        _maxParticipantsController.text =
            ((info['max_participants'] as num?)?.toInt() ?? 100).toString();
        _participants = participants;
        _blockedByMe = blocked;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadParticipants() async {
    try {
      final participants = await _service.fetchChannelParticipantsDetailed(
        widget.channelId,
      );
      if (mounted) setState(() => _participants = participants);
    } catch (_) {
      // Keep showing the last-known list; the action itself already
      // reported success or failure to the user.
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveSettings() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Channel name is required.');
      return;
    }
    final maxParticipants = int.tryParse(
      _maxParticipantsController.text.trim(),
    );
    if (maxParticipants == null ||
        maxParticipants < 2 ||
        maxParticipants > 1000) {
      _snack('Maximum participants must be between 2 and 1000.');
      return;
    }

    setState(() => _savingSettings = true);
    try {
      await _service.updateChannelSettings(
        channelId: widget.channelId,
        name: name,
        description: _descriptionController.text.trim(),
        maxParticipants: maxParticipants,
        messagingPermission: _messagingPermission,
      );
      _snack('Channel settings updated successfully.');
    } on ChannelAdminError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't update channel settings.");
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  void _onMemberSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchMembers(value),
    );
  }

  Future<void> _searchMembers(String term) async {
    final trimmed = term.trim();
    if (trimmed.length < MessagingService.recipientSearchMinLength) {
      setState(() {
        _searchResults = const [];
        _searching = false;
      });
      return;
    }

    final id = ++_searchRequestId;
    setState(() => _searching = true);

    try {
      final found = await _service.searchRecipients(
        term: trimmed,
        currentUserId: widget.currentUserId,
      );
      if (!mounted || id != _searchRequestId) return;
      final existingIds = _participants.map((p) => p.userId).toSet();
      final selectedIds = _selectedMembers.map((m) => m.userId).toSet();
      setState(() {
        _searchResults = found
            .where(
              (p) =>
                  !selectedIds.contains(p.userId) &&
                  !existingIds.contains(p.userId),
            )
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted || id != _searchRequestId) return;
      setState(() => _searching = false);
    }
  }

  int get _remainingCapacity {
    final cap = int.tryParse(_maxParticipantsController.text.trim()) ?? 100;
    return (cap - _participants.length).clamp(0, cap);
  }

  void _addToSelection(ConversationParticipant person) {
    if (_selectedMembers.length >= _remainingCapacity) {
      _snack("This channel is at its member limit.");
      return;
    }
    setState(() {
      _selectedMembers.add(person);
      _searchResults = _searchResults
          .where((p) => p.userId != person.userId)
          .toList();
      _memberSearchController.clear();
    });
  }

  void _removeFromSelection(ConversationParticipant person) {
    setState(
      () => _selectedMembers.removeWhere((m) => m.userId == person.userId),
    );
  }

  Future<void> _addMembers() async {
    if (_selectedMembers.isEmpty) return;
    setState(() => _addingMembers = true);
    try {
      final added = await _service.addChannelMembers(
        channelId: widget.channelId,
        userIds: _selectedMembers.map((m) => m.userId).toList(),
      );
      _snack('Added $added member(s) to the channel.');
      setState(() => _selectedMembers.clear());
      await _reloadParticipants();
    } on ChannelAdminError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't add members.");
    } finally {
      if (mounted) setState(() => _addingMembers = false);
    }
  }

  Future<void> _togglePersonalBlock(
    ChannelParticipantDetail participant,
  ) async {
    final isBlocked = _blockedByMe.contains(participant.userId);
    if (isBlocked) {
      try {
        await _service.unblockUser(participant.userId);
        if (mounted) {
          setState(
            () => _blockedByMe = {..._blockedByMe}..remove(participant.userId),
          );
        }
        _snack('${participant.displayName} unblocked.');
      } catch (_) {
        _snack("Couldn't update block status.");
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block member?'),
        content: Text(
          "${participant.displayName}'s messages in this channel will be "
          "hidden from your view. They will not be notified and can still "
          "post for everyone else.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.blockUser(participant.userId);
      if (mounted) {
        setState(() => _blockedByMe = {..._blockedByMe, participant.userId});
      }
      _snack('${participant.displayName} blocked.');
    } catch (_) {
      _snack("Couldn't update block status.");
    }
  }

  Future<void> _toggleChannelBlock(ChannelParticipantDetail participant) async {
    if (participant.blockedAt != null) {
      await _setChannelBlock(participant, false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block this member channel-wide?'),
        content: Text(
          "${participant.displayName} will no longer be able to send "
          "messages here, and their past messages will be hidden from "
          "everyone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _setChannelBlock(participant, true);
  }

  Future<void> _setChannelBlock(
    ChannelParticipantDetail participant,
    bool blocked,
  ) async {
    try {
      await _service.setChannelParticipantBlocked(
        channelId: widget.channelId,
        participantRowId: participant.id,
        targetUserId: participant.userId,
        blocked: blocked,
      );
      _snack(
        blocked
            ? '${participant.displayName} blocked in this channel.'
            : '${participant.displayName} unblocked in this channel.',
      );
      await _reloadParticipants();
    } on ChannelAdminError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't update block status.");
    }
  }

  Future<void> _removeParticipant(ChannelParticipantDetail participant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          "${participant.displayName} will be removed from "
          "#${widget.channelName} and will need to be re-added to rejoin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.removeChannelParticipant(
        channelId: widget.channelId,
        participantRowId: participant.id,
        targetUserId: participant.userId,
      );
      _snack('Member removed from channel.');
      await _reloadParticipants();
    } on ChannelAdminError catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't remove member.");
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave channel?'),
        content: Text(
          "You'll stop receiving messages from ${widget.channelName}.",
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
    if (confirmed != true) return;

    try {
      await _service.leaveChannel(widget.channelId, widget.currentUserId);
      if (mounted) {
        // Pops both this settings screen and the thread behind it — the
        // thread's provider would otherwise keep polling a channel this
        // user is no longer a participant of.
        Navigator.of(context)
          ..pop()
          ..pop();
      }
    } on ChannelAdminError catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack("Couldn't leave the channel.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.channelName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        bottom: _loading || _failed
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                tabs: [
                  const Tab(text: 'Settings'),
                  Tab(text: 'Members (${_participants.length})'),
                ],
              ),
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _leave,
            child: const Text('Leave channel'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [_buildSettingsTab(), _buildMembersTab()],
    );
  }

  // ── Settings tab ─────────────────────────────────────────────────────

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Channel Name'),
          const SizedBox(height: 6),
          _textField(_nameController, enabled: _isAdmin),
          const SizedBox(height: 16),
          _label('Description'),
          const SizedBox(height: 6),
          _textField(_descriptionController, enabled: _isAdmin, maxLines: 3),
          const SizedBox(height: 16),
          _label('Maximum Participants'),
          const SizedBox(height: 6),
          _textField(
            _maxParticipantsController,
            enabled: _isAdmin,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _label('Who can send messages'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _permissionButton(label: 'Everyone', value: 'everyone'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _permissionButton(
                  label: 'Only admins',
                  value: 'admins_only',
                ),
              ),
            ],
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _savingSettings ? null : _saveSettings,
                icon: _savingSettings
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_savingSettings ? 'Saving...' : 'Save Changes'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionButton({required String label, required String value}) {
    final selected = _messagingPermission == value;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.primary : Colors.transparent,
        foregroundColor: selected ? Colors.white : AppColors.textPrimary,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.hairline,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _isAdmin
          ? () => setState(() => _messagingPermission = value)
          : null,
      child: Text(label, style: const TextStyle(fontSize: 13)),
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

  Widget _textField(
    TextEditingController controller, {
    required bool enabled,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: enabled ? AppColors.background : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: AppTextStyles.body.copyWith(fontSize: 13.5),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ── Members tab ──────────────────────────────────────────────────────

  Widget _buildMembersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isModerator) ...[
          _label('Add Members'),
          const SizedBox(height: 6),
          MessagesSearchField(
            controller: _memberSearchController,
            hint: 'Search users to add...',
            onChanged: _onMemberSearchChanged,
          ),
          if (_selectedMembers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedMembers.map(_selectedChip).toList(),
            ),
          ],
          if (_searching ||
              _memberSearchController.text.trim().length >=
                  MessagingService.recipientSearchMinLength) ...[
            const SizedBox(height: 8),
            _buildMemberResults(),
          ],
          if (_selectedMembers.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _addingMembers ? null : _addMembers,
                icon: _addingMembers
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.person_add_alt, size: 18),
                label: Text(
                  _addingMembers
                      ? 'Adding...'
                      : 'Add ${_selectedMembers.length} Member(s)',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
        ],
        _label('Current Members (${_participants.length})'),
        const SizedBox(height: 10),
        ..._participants.map(_participantTile),
      ],
    );
  }

  Widget _selectedChip(ConversationParticipant person) {
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatAvatar(
            avatarUrl: person.avatarUrl,
            initials: person.initial,
            size: 22,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _removeFromSelection(person),
            child: const Icon(Icons.close, size: 14, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'No people found',
            style: AppTextStyles.caption.copyWith(fontSize: 12.5),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final person = _searchResults[index];
          return InkWell(
            onTap: () => _addToSelection(person),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ChatAvatar(
                    avatarUrl: person.avatarUrl,
                    initials: person.initial,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(fontSize: 13.5),
                    ),
                  ),
                  const Icon(
                    Icons.add_circle_outline,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _participantTile(ChannelParticipantDetail participant) {
    final isSelf = participant.userId == widget.currentUserId;
    final isCreator = participant.userId == _createdBy;
    final iBlockThem = _blockedByMe.contains(participant.userId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ChatAvatar(
            avatarUrl: participant.avatarUrl,
            initials: participant.initial,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isSelf
                            ? '${participant.displayName} (you)'
                            : participant.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isCreator) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(Creator)',
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _roleBadge(participant.role),
                    if (participant.blockedAt != null) _blockedBadge(),
                  ],
                ),
              ],
            ),
          ),
          if (!isSelf) ...[
            IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: iBlockThem ? 'Unblock' : 'Block',
              color: iBlockThem ? Colors.red : AppColors.textHint,
              icon: const Icon(Icons.block),
              onPressed: () => _togglePersonalBlock(participant),
            ),
            if (_isModerator && !isCreator) ...[
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: participant.blockedAt != null
                    ? 'Unblock channel-wide'
                    : 'Block channel-wide',
                color: participant.blockedAt != null
                    ? Colors.red
                    : AppColors.textHint,
                icon: const Icon(Icons.remove_moderator_outlined),
                onPressed: () => _toggleChannelBlock(participant),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove from channel',
                color: Colors.red,
                icon: const Icon(Icons.person_remove_outlined),
                onPressed: () => _removeParticipant(participant),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _roleBadge(String role) {
    final colors = switch (role) {
      'admin' => (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E)),
      'moderator' => (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E40AF)),
      _ => (bg: AppColors.surfaceMuted, fg: AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.fg,
        ),
      ),
    );
  }

  Widget _blockedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Blocked',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF991B1B),
        ),
      ),
    );
  }
}
