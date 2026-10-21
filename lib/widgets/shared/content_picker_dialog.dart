import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/scale_tap.dart';

/// One selectable row in a [showContentPickerSheet].
///
/// Deliberately backend-agnostic: Phase 5 builds no providers or services, and
/// the same picker has to serve properties, projects, articles and reels. The
/// caller maps its own model into this shape.
class ContentPickerItem {
  final String id;
  final String title;

  /// Secondary line — price, location, publish date, whatever the caller has.
  final String? subtitle;

  /// Short type label rendered as a tint chip, e.g. "Property", "Article".
  final String? typeLabel;

  final String? imageUrl;

  /// Fallback glyph when [imageUrl] is null or fails to load.
  final IconData fallbackIcon;

  const ContentPickerItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.typeLabel,
    this.imageUrl,
    this.fallbackIcon = Icons.apartment_rounded,
  });
}

/// "Pick content to boost" — the reusable content chooser.
///
/// Ports the flow `CampaignsPanel.tsx` opens before `CreateCampaignDialog`, and
/// is equally usable by any future "pick one of my listings" surface.
///
/// Presented as a modal bottom sheet rather than a centred dialog: every other
/// picker in this app is a sheet, and the design system's mobile adaptation
/// notes favour sheets over dialogs for list selection.
///
/// Returns the chosen item, or null if dismissed.
Future<ContentPickerItem?> showContentPickerSheet(
  BuildContext context, {
  required List<ContentPickerItem> items,
  String title = 'Pick content to boost',
  String searchHint = 'Search your content...',
  String emptyTitle = 'Nothing to pick yet',
  String emptyMessage = 'Create a property, project or article first.',
  bool loading = false,
}) {
  return showModalBottomSheet<ContentPickerItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ContentPickerSheet(
      items: items,
      title: title,
      searchHint: searchHint,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      loading: loading,
    ),
  );
}

class _ContentPickerSheet extends StatefulWidget {
  final List<ContentPickerItem> items;
  final String title;
  final String searchHint;
  final String emptyTitle;
  final String emptyMessage;
  final bool loading;

  const _ContentPickerSheet({
    required this.items,
    required this.title,
    required this.searchHint,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.loading,
  });

  @override
  State<_ContentPickerSheet> createState() => _ContentPickerSheetState();
}

class _ContentPickerSheetState extends State<_ContentPickerSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ContentPickerItem> get _visible {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items
        .where(
          (i) =>
              i.title.toLowerCase().contains(q) ||
              (i.subtitle ?? '').toLowerCase().contains(q) ||
              (i.typeLabel ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.82),
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
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(
                      AppConstants.pillRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingL),
              Text(
                widget.title,
                style: AppTextStyles.heading3.copyWith(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (widget.items.length > 5) ...[
                _SearchField(
                  controller: _controller,
                  hint: widget.searchHint,
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: AppConstants.spacingM),
              ],
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (widget.items.isEmpty) {
      return EmptyStateView(
        icon: Icons.inbox_outlined,
        title: widget.emptyTitle,
        message: widget.emptyMessage,
        iconCircleSize: 56,
        titleFontSize: 14.5,
      );
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Nothing matches "$_query".',
        iconCircleSize: 56,
        titleFontSize: 14.5,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _PickerRow(
        item: visible[index],
        onTap: () => Navigator.of(context).pop(visible[index]),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final ContentPickerItem item;
  final VoidCallback onTap;

  const _PickerRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: item.typeLabel == null
          ? item.title
          : '${item.title}, ${item.typeLabel}',
      button: true,
      child: ScaleTap(
        onTap: onTap,
        child: ColoredBox(
          color: AppColors.cardBackground,
          child: Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            ),
            child: Row(
              children: [
                _Thumb(item: item),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.typeLabel != null) ...[
                  const SizedBox(width: AppConstants.spacingS),
                  _TypeChip(label: item.typeLabel!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final ContentPickerItem item;

  const _Thumb({required this.item});

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: AppColors.primaryLight,
      child: Icon(item.fallbackIcon, size: 20, color: AppColors.primary),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.imageThumbnailRadius),
      child: SizedBox(
        width: 48,
        height: 48,
        child: item.imageUrl == null || item.imageUrl!.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: item.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppConstants.chipRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.chip.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
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
        ],
      ),
    );
  }
}
