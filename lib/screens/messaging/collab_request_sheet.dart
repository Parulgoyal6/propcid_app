// screens/messaging/collab_request_sheet.dart
//
// The "Collaborate" request sheet, opened from a public profile's sticky
// action bar. Ports `UserProfile.tsx`'s collab dialog: an optional message,
// an optional multi-select reel picker (shown only when the *viewer* is the
// influencer — the portal's `myReels` query is gated on `viewerUserType ===
// 'influencer'`, not on the viewed profile), and a single
// `collab_create_request` RPC call. Deliberately never creates (or reuses) a
// normal DM — a request has no conversation until the recipient accepts it.
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/collaboration_exceptions.dart';
import '../../services/collaboration_service.dart';
import 'widgets/collab_tile.dart' show kCollabAccent;

/// Shows the sheet and sends the request. Returns true if a request was sent
/// (so the caller can show its own confirmation), false/null otherwise.
Future<bool?> showCollabRequestSheet(
  BuildContext context, {
  required String counterpartyId,
  required String counterpartyName,
  required bool viewerIsInfluencer,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CollabRequestSheet(
      counterpartyId: counterpartyId,
      counterpartyName: counterpartyName,
      viewerIsInfluencer: viewerIsInfluencer,
    ),
  );
}

class _CollabRequestSheet extends StatefulWidget {
  final String counterpartyId;
  final String counterpartyName;
  final bool viewerIsInfluencer;

  const _CollabRequestSheet({
    required this.counterpartyId,
    required this.counterpartyName,
    required this.viewerIsInfluencer,
  });

  @override
  State<_CollabRequestSheet> createState() => _CollabRequestSheetState();
}

class _CollabRequestSheetState extends State<_CollabRequestSheet> {
  final _service = CollaborationService();
  final _messageController = TextEditingController();
  final Set<String> _selectedReelIds = {};

  List<CollabReelPreview> _myReels = const [];
  bool _reelsLoading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.viewerIsInfluencer) _loadReels();
  }

  Future<void> _loadReels() async {
    setState(() => _reelsLoading = true);
    // `CollaborationService.listMyActiveReels` needs the viewer's own id —
    // resolved from Supabase auth directly rather than threading AuthProvider
    // through this sheet, matching this file's narrow scope.
    final userId = _service.currentUserIdOrNull;
    if (userId == null) {
      setState(() => _reelsLoading = false);
      return;
    }
    final reels = await _service.listMyActiveReels(userId);
    if (!mounted) return;
    setState(() {
      _myReels = reels;
      _reelsLoading = false;
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.createRequest(
        counterpartyId: widget.counterpartyId,
        message: _messageController.text,
        attachedReelIds: _selectedReelIds.toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is CollaborationException
            ? e.message
            : 'Could not send request. Please try again.';
      });
    }
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
                  const Icon(Icons.handshake_outlined, color: kCollabAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collaborate with ${widget.counterpartyName}',
                      style: AppTextStyles.heading2.copyWith(fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Send a collaboration request. You\'ll see it in the Collabs tab in Chats once they respond.',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add a message (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.viewerIsInfluencer) ...[
                const SizedBox(height: 14),
                Text(
                  'Attach reels (optional)',
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (_reelsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_myReels.isNotEmpty)
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _myReels.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final reel = _myReels[i];
                        final selected = _selectedReelIds.contains(reel.id);
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (selected) {
                              _selectedReelIds.remove(reel.id);
                            } else {
                              _selectedReelIds.add(reel.id);
                            }
                          }),
                          child: Container(
                            width: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  reel.thumbnailUrl != null
                                      ? Image.network(
                                          reel.thumbnailUrl!,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          color: AppColors.background,
                                          child: const Icon(
                                            Icons.play_circle_outline,
                                          ),
                                        ),
                                  if (selected)
                                    Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
