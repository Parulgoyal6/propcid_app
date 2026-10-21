import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/conversation_summary.dart';
import '../../../services/messaging_service.dart';
import 'chat_avatar.dart';

/// "Start New Chat" recipient picker.
///
/// Mirrors features/messaging/NewChatModal.tsx: type at least two characters,
/// pick a person, and the caller opens the resulting conversation.
///
/// Returns the selected person, or null if dismissed. The web modal hands back
/// just a `userId` through `onSelectUser`; returning the whole participant lets
/// the caller open the thread with the correct name and avatar without waiting
/// on a list refresh.
Future<ConversationParticipant?> showNewChatSheet(
  BuildContext context,
  String currentUserId,
) {
  return showModalBottomSheet<ConversationParticipant>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NewChatSheet(currentUserId: currentUserId),
  );
}

class _NewChatSheet extends StatefulWidget {
  final String currentUserId;

  const _NewChatSheet({required this.currentUserId});

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _service = MessagingService();
  final _controller = TextEditingController();

  Timer? _debounce;
  List<ConversationParticipant> _results = const [];
  bool _searching = false;
  bool _failed = false;

  /// Tracks the latest issued search so a slow earlier response cannot
  /// overwrite the results of a newer query.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String term) async {
    final trimmed = term.trim();

    if (trimmed.length < MessagingService.recipientSearchMinLength) {
      setState(() {
        _results = const [];
        _searching = false;
        _failed = false;
      });
      return;
    }

    final id = ++_requestId;
    setState(() {
      _searching = true;
      _failed = false;
    });

    try {
      final found = await _service.searchRecipients(
        term: trimmed,
        currentUserId: widget.currentUserId,
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = found;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Leaves room for the keyboard so the field stays visible while typing.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Same fix as share_property_sheet.dart: this used to be a flat 40% of
    // the *full* screen height, which ignored how much the keyboard had
    // already eaten into the available space — sizing off the keyboard-
    // adjusted height instead keeps the sheet from overflowing once it's up.
    final resultsMaxHeight = (screenHeight - bottomInset - 220).clamp(
      80.0,
      screenHeight * 0.4,
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
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: SafeArea(
          top: false,
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
                'Start New Chat',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              MessagesSearchField(
                controller: _controller,
                hint: 'Search people by name...',
                autofocus: true,
                onChanged: _onChanged,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: resultsMaxHeight),
                child: _buildResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_failed) {
      return _message("Couldn't search right now. Please try again.");
    }

    final term = _controller.text.trim();
    if (term.length < MessagingService.recipientSearchMinLength) {
      return _message('Type at least 2 characters to search');
    }

    if (_results.isEmpty) return _message('No people found');

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final person = _results[index];
        return ScaleTap(
          onTap: () => Navigator.of(context).pop(person),
          child: ColoredBox(
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ChatAvatar(
                    avatarUrl: person.avatarUrl,
                    initials: person.initial,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      person.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 18,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _message(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.caption.copyWith(fontSize: 12.5),
        ),
      ),
    );
  }
}

/// Pill-shaped search input, shared by this sheet and the Messages list's
/// inline filter.
class MessagesSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  const MessagesSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.autofocus = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.textHint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: AppTextStyles.body.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: hint,
                hintStyle: AppTextStyles.body.copyWith(
                  fontSize: 13.5,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          if (onClear != null && controller.text.isNotEmpty)
            Semantics(
              label: 'Clear search',
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 16, color: AppColors.textHint),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
