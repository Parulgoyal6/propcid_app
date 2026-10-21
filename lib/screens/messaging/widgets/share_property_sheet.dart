import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/shared_property_preview.dart';
import '../../../services/messaging_service.dart';
import 'new_chat_sheet.dart' show MessagesSearchField;

/// "Share Property" picker — searches `properties_public` by title, same
/// contract as the portal's `SharePropertyModal.tsx`. Structurally mirrors
/// `new_chat_sheet.dart` (debounced search, request-id guard against a slow
/// stale response, loading/empty/error states).
///
/// Returns the selected property, or null if dismissed.
Future<SharedPropertyPreview?> showSharePropertySheet(BuildContext context) {
  return showModalBottomSheet<SharedPropertyPreview>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SharePropertySheet(),
  );
}

class _SharePropertySheet extends StatefulWidget {
  const _SharePropertySheet();

  @override
  State<_SharePropertySheet> createState() => _SharePropertySheetState();
}

class _SharePropertySheetState extends State<_SharePropertySheet> {
  final _service = MessagingService();
  final _controller = TextEditingController();

  Timer? _debounce;
  List<SharedPropertyPreview> _results = const [];
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
      final found = await _service.searchProperties(trimmed);
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
    // The results area used to claim a flat 50% of the *full* screen height,
    // ignoring the keyboard entirely — once the keyboard opened (the search
    // field autofocuses), the real remaining space was much smaller than
    // that, and the sheet's total content (handle + title + search field +
    // this) no longer fit, overflowing at the bottom. Sizing it off the
    // keyboard-adjusted height instead — minus a fixed allowance for that
    // fixed header content above it — keeps the whole sheet within whatever
    // room is actually left.
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
                'Share Property',
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              MessagesSearchField(
                controller: _controller,
                hint: 'Search properties by title...',
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

    if (_results.isEmpty) return _message('No properties found');

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final property = _results[index];
        return ScaleTap(
          onTap: () => Navigator.of(context).pop(property),
          child: ColoredBox(
            color: AppColors.cardBackground,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: property.imageUrl == null
                        ? Container(
                            width: 56,
                            height: 56,
                            color: AppColors.primaryLight,
                            child: const Icon(
                              Icons.home_work_outlined,
                              color: AppColors.primary,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: property.imageUrl!,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Container(
                              width: 56,
                              height: 56,
                              color: AppColors.primaryLight,
                              child: const Icon(
                                Icons.home_work_outlined,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          property.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (property.location != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            property.location!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        if (property.price != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            property.price!,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ],
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
