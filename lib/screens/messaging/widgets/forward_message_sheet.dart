import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/conversation_summary.dart';
import '../../../services/messaging_service.dart';
import 'chat_avatar.dart';

/// "Forward to…" picker — a plain list of the caller's own DM conversations,
/// matching the portal's `ForwardMessageModal.tsx` (no search there either,
/// just a tap-to-forward list). Fetches its own copy of the conversation
/// list rather than reading a `MessagingProvider` from context — this sheet
/// can be opened from any thread (DM or channel), and a page-scoped
/// `MessagingProvider` instance (created fresh per `MessagesListScreen`) is
/// not reliably an ancestor of wherever this is pushed from.
///
/// Returns the chosen conversation id, or null if dismissed.
Future<String?> showForwardMessageSheet(
  BuildContext context,
  String currentUserId,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ForwardMessageSheet(currentUserId: currentUserId),
  );
}

class _ForwardMessageSheet extends StatefulWidget {
  final String currentUserId;
  const _ForwardMessageSheet({required this.currentUserId});

  @override
  State<_ForwardMessageSheet> createState() => _ForwardMessageSheetState();
}

class _ForwardMessageSheetState extends State<_ForwardMessageSheet> {
  final _service = MessagingService();
  List<ConversationSummary> _conversations = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.listConversations(widget.currentUserId);
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
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
                'Forward to…',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            "Couldn't load your conversations.",
            style: AppTextStyles.caption.copyWith(fontSize: 12.5),
          ),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'No conversations yet',
            style: AppTextStyles.caption.copyWith(fontSize: 12.5),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        return ScaleTap(
          onTap: () => Navigator.of(context).pop(conversation.id),
          child: ColoredBox(
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  ChatAvatar(
                    avatarUrl: conversation.otherParticipant?.avatarUrl,
                    initials: conversation.otherParticipant?.initial ?? '?',
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
