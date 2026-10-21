import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/chat_message.dart';

/// Plain white circle (soft shadow, no border) for the attach / image buttons.
const BoxDecoration _kComposerCircle = BoxDecoration(
  color: Colors.white,
  shape: BoxShape.circle,
  boxShadow: [
    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
  ],
);

/// The message input bar (blueprint §16.7).
///
/// Prototype spec: a 38 dp attach button, a pill text field on the app canvas
/// colour, and a 40 dp primary send button carrying
/// `0 4px 12px rgba(91,80,232,0.28)`.
class MessageComposer extends StatefulWidget {
  /// Returns an error string to surface, or null on success.
  final Future<String?> Function(String text) onSend;

  final bool sending;

  /// The message currently being replied to, if any — rendered as a
  /// dismissible quoted strip above the input, matching the portal's
  /// `replyingTo` UI in Chat.tsx/ChannelChat.tsx.
  final ChatMessage? replyingTo;
  final String? replyingToSenderName;
  final VoidCallback? onCancelReply;

  /// Fired on every keystroke — the caller throttles this into a typing
  /// broadcast (see ChatThreadProvider.notifyTyping).
  final VoidCallback? onTyping;

  /// Opens an image picker for a photo message. Null hides the attach button.
  final VoidCallback? onAttach;

  /// Starts/stops voice-note recording. Null hides the mic button.
  final VoidCallback? onRecordVoice;
  final bool isRecordingVoice;

  const MessageComposer({
    super.key,
    required this.onSend,
    this.sending = false,
    this.replyingTo,
    this.replyingToSenderName,
    this.onCancelReply,
    this.onTyping,
    this.onAttach,
    this.onRecordVoice,
    this.isRecordingVoice = false,
  });

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      widget.onTyping?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.sending) return;

    // Cleared up front so a fast second message is not blocked; restored below
    // if the send fails, so the user never loses what they typed.
    _controller.clear();
    final error = await widget.onSend(text);

    if (!mounted) return;
    if (error != null) {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _hasText && !widget.sending;

    return Container(
      // No bar surface of its own — the controls sit directly on the page.
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyingTo != null) _buildReplyStrip(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.onAttach != null) ...[
                    Semantics(
                      label: 'Attach',
                      button: true,
                      child: ScaleTap(
                        onTap: widget.onAttach,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: _kComposerCircle,
                          child: const Icon(
                            Icons.attach_file_rounded,
                            size: 19,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Same image picker as the "+" button above — a second,
                    // more specific entry point to it, matching the
                    // reference's separate gallery icon rather than a second
                    // action.
                    Semantics(
                      label: 'Attach image',
                      button: true,
                      child: ScaleTap(
                        onTap: widget.onAttach,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: _kComposerCircle,
                          child: const Icon(
                            Icons.image_outlined,
                            size: 19,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 42,
                        maxHeight: 100,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppConstants.pillRadius,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      // No `alignment` here: with one, the Container expands
                      // to its 100 dp maxHeight instead of hugging one line.
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          height: 1.3,
                        ),
                        // `isCollapsed` is the important bit: it's what tells
                        // Material's InputDecorator to skip the ambient
                        // InputDecorationTheme's own padding/border reservations
                        // (the ones the app's form screens rely on) entirely, so
                        // this pill's height comes only from the padding above —
                        // without it, the field was inheriting that theme's
                        // larger default sizing and rendering much taller than
                        // a WhatsApp/Telegram-style compact bar.
                        // `filled: false` + every border state set to none:
                        // the app theme's InputDecorationTheme is filled and
                        // defines its own enabled/focused borders, which
                        // otherwise draw a second box inside this pill.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          hintText: 'Type a message...',
                          hintMaxLines: 1,
                          hintStyle: AppTextStyles.body.copyWith(
                            fontSize: 13,
                            color: AppColors.textHint,
                          ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          suffixIcon: Semantics(
                            label: 'Emoji',
                            button: true,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Emoji picker isn't available yet.",
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.emoji_emotions_outlined,
                                size: 20,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.onRecordVoice != null && !_hasText) ...[
                    Semantics(
                      label: widget.isRecordingVoice
                          ? 'Stop recording'
                          : 'Record voice message',
                      button: true,
                      child: ScaleTap(
                        onTap: widget.onRecordVoice,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: widget.isRecordingVoice ? Colors.red : null,
                            gradient: widget.isRecordingVoice
                                ? null
                                : AppColors.primaryGradient,
                            shape: BoxShape.circle,
                            boxShadow: AppColors.primaryGlow,
                          ),
                          child: Icon(
                            widget.isRecordingVoice
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ] else
                    Semantics(
                      label: 'Send message',
                      button: true,
                      enabled: canSend,
                      child: ScaleTap(
                        onTap: canSend ? _submit : null,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: canSend
                                ? null
                                : AppColors.primary.withValues(alpha: 0.4),
                            gradient: canSend
                                ? AppColors.primaryGradient
                                : null,
                            shape: BoxShape.circle,
                            boxShadow: canSend ? AppColors.primaryGlow : null,
                          ),
                          child: widget.sending
                              ? const Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.send,
                                  size: 18,
                                  color: Colors.white,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyStrip(BuildContext context) {
    final reply = widget.replyingTo!;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 2.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${widget.replyingToSenderName ?? 'message'}',
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.displayContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onCancelReply,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }
}
