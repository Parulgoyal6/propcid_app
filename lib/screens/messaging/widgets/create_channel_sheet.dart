import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/conversation_summary.dart';
import '../../../services/messaging_service.dart';
import 'chat_avatar.dart';
import 'new_chat_sheet.dart' show MessagesSearchField;

/// "Create Channel" sheet — name, optional description, and a member picker.
/// Mirrors the portal's `CreateChannelModal.tsx`. Channel creation is
/// self-service for any authenticated user (`channels` INSERT RLS:
/// `created_by = auth.uid()`); the creator is added as `admin` in a second
/// insert right after, which the same RLS explicitly allows for the
/// channel's own creator.
///
/// Any people picked in the member search are added right after, via
/// [MessagingService.addChannelParticipant] — that method already existed
/// (used by `ChannelSettingsScreen`'s promote/demote flow's sibling insert
/// path) but nothing in the app ever called it to add someone new, so a
/// channel could only ever be created with just its creator in it.
///
/// Returns the new channel's id, or null if dismissed/failed.
Future<String?> showCreateChannelSheet(
  BuildContext context,
  String currentUserId,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CreateChannelSheet(currentUserId: currentUserId),
  );
}

class _CreateChannelSheet extends StatefulWidget {
  final String currentUserId;

  const _CreateChannelSheet({required this.currentUserId});

  @override
  State<_CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends State<_CreateChannelSheet> {
  final _service = MessagingService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _memberSearchController = TextEditingController();

  bool _creating = false;
  String? _error;

  final List<ConversationParticipant> _selectedMembers = [];
  Timer? _debounce;
  List<ConversationParticipant> _searchResults = const [];
  bool _searching = false;
  int _requestId = 0;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _memberSearchController.dispose();
    _debounce?.cancel();
    super.dispose();
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

    final id = ++_requestId;
    setState(() => _searching = true);

    try {
      final found = await _service.searchRecipients(
        term: trimmed,
        currentUserId: widget.currentUserId,
      );
      if (!mounted || id != _requestId) return;
      final selectedIds = _selectedMembers.map((m) => m.userId).toSet();
      setState(() {
        _searchResults = found
            .where((p) => !selectedIds.contains(p.userId))
            .toList();
        _searching = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() => _searching = false);
    }
  }

  void _addMember(ConversationParticipant person) {
    setState(() {
      _selectedMembers.add(person);
      _searchResults = _searchResults
          .where((p) => p.userId != person.userId)
          .toList();
      _memberSearchController.clear();
    });
  }

  void _removeMember(ConversationParticipant person) {
    setState(
      () => _selectedMembers.removeWhere((m) => m.userId == person.userId),
    );
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Channel name is required.');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final id = await _service.createChannel(
        name: name,
        description: _descriptionController.text,
      );

      // Best-effort: the channel itself was created successfully, so one
      // member failing to add shouldn't block the whole flow or roll back
      // the channel — each add is isolated the same way
      // MessagingService's other calls already log-and-rethrow internally.
      for (final member in _selectedMembers) {
        try {
          await _service.addChannelParticipant(
            channelId: id,
            userId: member.userId,
          );
        } catch (_) {
          // Swallowed per-member — see comment above.
        }
      }

      if (mounted) Navigator.of(context).pop(id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = "Couldn't create the channel. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final resultsMaxHeight = (screenHeight - bottomInset - 420).clamp(
      60.0,
      screenHeight * 0.3,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEDF2),
                      borderRadius: BorderRadius.circular(
                        AppConstants.pillRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Create Channel',
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _label('Name'),
                const SizedBox(height: 6),
                _field(_nameController, 'e.g. Downtown Buyers'),
                const SizedBox(height: 14),
                _label('Description (optional)'),
                const SizedBox(height: 6),
                _field(
                  _descriptionController,
                  'What is this channel about?',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _label('Add Members (optional)'),
                const SizedBox(height: 6),
                MessagesSearchField(
                  controller: _memberSearchController,
                  hint: 'Search people by name...',
                  onChanged: _onMemberSearchChanged,
                ),
                if (_selectedMembers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedMembers
                        .map((m) => _selectedChip(m))
                        .toList(),
                  ),
                ],
                if (_searching ||
                    _memberSearchController.text.trim().length >=
                        MessagingService.recipientSearchMinLength) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: resultsMaxHeight),
                    child: _buildMemberResults(),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _creating ? null : _create,
                    child: _creating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Create'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectedChip(ConversationParticipant person) {
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
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
            onTap: () => _removeMember(person),
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

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final person = _searchResults[index];
        return InkWell(
          onTap: () => _addMember(person),
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

  Widget _field(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: AppTextStyles.body.copyWith(fontSize: 13.5),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          hintText: hint,
          hintStyle: AppTextStyles.body.copyWith(
            fontSize: 13.5,
            color: AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
