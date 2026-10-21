import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/network_models.dart';
import '../../../providers/network_communication_provider.dart';

/// Network ▸ Communication's Bulk Message compose sheet — reached from both
/// the header's "Bulk Message" button and the Messaging tab's
/// "Compose Message" CTA, matching the portal where both open the exact same
/// form (`NetworkCommunicationHub.tsx`'s `showBulkMessageForm`).
///
/// Recipient filtering, message type, priority and the write itself are all
/// portal-exact — see [filterBulkMessageRecipients] and
/// [NetworkCommunicationProvider.sendBulkMessage].
///
/// Returns the number of recipients the message was sent to, or `null` if
/// dismissed/not sent.
Future<int?> showBulkMessageSheet(BuildContext context) {
  final provider = context.read<NetworkCommunicationProvider>();
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NetworkCommunicationProvider>.value(
      value: provider,
      child: const _BulkMessageSheet(),
    ),
  );
}

class _BulkMessageSheet extends StatefulWidget {
  const _BulkMessageSheet();

  @override
  State<_BulkMessageSheet> createState() => _BulkMessageSheetState();
}

class _BulkMessageSheetState extends State<_BulkMessageSheet> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  String _recipientType = 'all';
  String _messageType = 'announcement';
  String _priority = 'medium';
  String? _validationError;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final provider = context.read<NetworkCommunicationProvider>();
    if (provider.sendingBulkMessage) return;

    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty) {
      setState(() => _validationError = 'Message title is required.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _validationError = 'Message is required.');
      return;
    }
    if (provider.recipientsFor(_recipientType).isEmpty) {
      setState(
        () => _validationError =
            'There are no eligible recipients for this filter.',
      );
      return;
    }

    setState(() => _validationError = null);

    final success = await provider.sendBulkMessage(
      recipientType: _recipientType,
      messageType: _messageType,
      priority: _priority,
      title: title,
      message: message,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(provider.lastBulkMessageRecipientCount);
      return;
    }

    setState(() {
      _validationError =
          provider.bulkMessageError ??
          "Couldn't send the message. Please try again.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NetworkCommunicationProvider>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final sending = provider.sendingBulkMessage;
    final recipientCount = provider.recipientsFor(_recipientType).length;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                  'Send Bulk Message',
                  style: AppTextStyles.heading3.copyWith(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Send a message to multiple network members',
                  style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 18),
                _label('Recipients*'),
                const SizedBox(height: 6),
                _dropdown(
                  value: _recipientType,
                  options: kBulkMessageRecipientTypes,
                  enabled: !sending,
                  onChanged: (v) => setState(() => _recipientType = v),
                ),
                const SizedBox(height: 14),
                _label('Message Type*'),
                const SizedBox(height: 6),
                _dropdown(
                  value: _messageType,
                  options: kBulkMessageTypes,
                  enabled: !sending,
                  onChanged: (v) => setState(() => _messageType = v),
                ),
                const SizedBox(height: 14),
                _label('Priority*'),
                const SizedBox(height: 6),
                _dropdown(
                  value: _priority,
                  options: kBulkMessagePriorities,
                  enabled: !sending,
                  onChanged: (v) => setState(() => _priority = v),
                ),
                const SizedBox(height: 14),
                _label('Message Title*'),
                const SizedBox(height: 6),
                _field(
                  _titleController,
                  'Enter message title...',
                  enabled: !sending,
                ),
                const SizedBox(height: 14),
                _label('Message*'),
                const SizedBox(height: 6),
                _field(
                  _messageController,
                  'Enter your message...',
                  maxLines: 5,
                  enabled: !sending,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recipients count:',
                        style: AppTextStyles.body.copyWith(fontSize: 13),
                      ),
                      Text(
                        '$recipientCount members',
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_validationError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _validationError!,
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
                    key: const Key('sendBulkMessageSubmit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: (sending || recipientCount == 0)
                        ? null
                        : _submit,
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Send Message'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<BulkMessageOption> options,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: options
              .map(
                (o) => DropdownMenuItem(
                  value: o.value,
                  child: Text(
                    o.label,
                    style: AppTextStyles.body.copyWith(fontSize: 13.5),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled ? (v) => onChanged(v!) : null,
        ),
      ),
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
    bool enabled = true,
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
        enabled: enabled,
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
