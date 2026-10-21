// screens/messaging/widgets/collab_dispute_sheet.dart
//
// The "Raise a dispute" bottom sheet — ports `CollabActionPanel.tsx`'s
// dispute dialog. Reason is required (empty/whitespace-only blocked, same as
// the portal's disabled-button guard) and capped at 1000 characters —
// `collab-dispute`'s own server-side cap, enforced client-side too per the
// task's explicit instruction (the portal itself has no client-side cap).
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../services/collaboration_service.dart';

/// Returns the trimmed reason if the user submitted, or null if they
/// cancelled. Does not call the RPC itself — the caller (the action panel,
/// which already holds a [CollaborationThreadController]) does that so a
/// failure can be surfaced without this sheet needing its own controller
/// reference.
Future<String?> showCollabDisputeSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DisputeSheet(),
  );
}

class _DisputeSheet extends StatefulWidget {
  const _DisputeSheet();

  @override
  State<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<_DisputeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.report_gmailerrorred_outlined,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Raise a dispute',
                    style: AppTextStyles.heading2.copyWith(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'An admin will review this collaboration. Payout is frozen while a dispute is open.',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                maxLines: 4,
                maxLength: CollaborationService.maxDisputeReasonLength,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'What went wrong?',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _controller.text.trim().isEmpty
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(_controller.text.trim()),
                      child: const Text('Submit'),
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
}
