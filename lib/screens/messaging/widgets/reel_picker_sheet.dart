import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/shared_reel_preview.dart';
import '../../../services/messaging_service.dart';
import 'new_chat_sheet.dart' show MessagesSearchField;

/// "Share Reel" picker for a chat - searches approved reels by title, the
/// same contract as the portal's `ShareReelModal.tsx` (which mirrors its
/// property picker). Structurally mirrors `showSharePropertySheet`
/// (debounced search, request-id guard against a slow stale response,
/// loading/empty/error states).
///
/// Returns the selected reel, or null if dismissed.
///
/// [service] defaults to a real [MessagingService]; the chat screen passes
/// its own so a test can swap in a fake.
Future<SharedReelPreview?> showReelPickerSheet(
  BuildContext context, {
  MessagingService? service,
}) {
  return showModalBottomSheet<SharedReelPreview>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReelPickerSheet(service: service),
  );
}

class _ReelPickerSheet extends StatefulWidget {
  final MessagingService? service;

  const _ReelPickerSheet({this.service});

  @override
  State<_ReelPickerSheet> createState() => _ReelPickerSheetState();
}

class _ReelPickerSheetState extends State<_ReelPickerSheet> {
  late final MessagingService _service =
      widget.service ?? MessagingService();
  final _controller = TextEditingController();

  Timer? _debounce;
  List<SharedReelPreview> _results = const [];
  bool _searching = false;
  bool _failed = false;
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

    if (trimmed.length < 2) {
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
      final found = await _service.searchReels(trimmed);
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    // Sized off the keyboard-adjusted height (see the property picker's note)
    // so the sheet never overflows once the search field's keyboard opens.
    final resultsMaxHeight = (screenHeight - bottomInset - 220).clamp(
      80.0,
      screenHeight * 0.5,
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
                'Share Reel',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              MessagesSearchField(
                controller: _controller,
                hint: 'Search reels by title...',
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

    if (_controller.text.trim().length < 2) {
      return _message('Type at least 2 characters to search');
    }

    if (_results.isEmpty) return _message('No reels found');

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final reel = _results[index];
        return ScaleTap(
          onTap: () => Navigator.of(context).pop(reel),
          child: ColoredBox(
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: reel.thumbnailUrl == null
                        ? _thumbFallback()
                        : CachedNetworkImage(
                            imageUrl: reel.thumbnailUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => _thumbFallback(),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reel.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (reel.ownerName?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            reel.ownerName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.play_circle_outline,
                    size: 20,
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

  Widget _thumbFallback() => Container(
    width: 56,
    height: 56,
    color: AppColors.primaryLight,
    child: const Icon(
      Icons.video_collection_outlined,
      color: AppColors.primary,
    ),
  );

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
