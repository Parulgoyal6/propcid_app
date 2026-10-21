// screens/dashboard/widgets/builder_offers_section.dart
//
// Marketed Offers on the builder dashboard's Content tab.
//
// The portal's counterpart is `FilteredOffersList role="builder"` rendered under a
// "Marketed Offers" heading (`BuilderDashboardManage.tsx:1235-1249`), with each row
// drawn by `ProjectOfferCard.tsx`.
//
// SPEC I CLOSED THIS SECTION'S TWO GAPS
// -------------------------------------
// Spec H shipped this as read-and-delete, reporting H-1 (no edit) and H-2 (no
// create) because `MarketToBrokersModal` looked like a network-marketing feature
// this app lacks. Spec I's precondition work settled what it actually is: an
// editor over `builder_project_offers`, the very table this section reads. So both
// gaps are closed here — Create sits in the header, Edit on each card, and both
// open `BuilderOfferEditorSheet`.
//
// A create needs a project to attach the offer to (`project_id`), so the button is
// only offered when the parent supplies at least one.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../services/builder_sections_service.dart';
import 'builder_offer_editor_sheet.dart';
import 'builder_section_kit.dart';

class BuilderOffersSection extends StatefulWidget {
  const BuilderOffersSection({
    super.key,
    required this.builderId,
    this.projects = const [],
    this.onCountChanged,
    this.service,
  });

  final String builderId;

  /// The builder's projects. An offer is always attached to one, so a create is
  /// only possible when there is at least one to attach to.
  ///
  /// Reuses the list the parent already loaded rather than re-querying.
  final List<ProjectModel> projects;

  /// Same contract as every other section: fires on a successful load and after a
  /// delete, never on failure.
  final ValueChanged<int>? onCountChanged;

  @visibleForTesting
  final BuilderOfferService? service;

  @override
  State<BuilderOffersSection> createState() => _BuilderOffersSectionState();
}

class _BuilderOffersSectionState extends State<BuilderOffersSection> {
  late final BuilderOfferService _offers =
      widget.service ?? BuilderOfferService();

  List<BuilderOffer>? _items;
  bool _failed = false;
  String? _busyOfferId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _reportCount() => widget.onCountChanged?.call(_items?.length ?? 0);

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _offers.listMine(widget.builderId);
      if (!mounted) return;
      setState(() => _items = rows);
      _reportCount();
    } catch (e) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _delete(BuilderOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Offer'),
        // A hard delete, and it says so: `builder_project_offers` has no
        // `deleted_at` column and is not one of soft_delete_content's three
        // whitelisted tables, so there is no recovery window to promise.
        content: Text(
          'Delete "${offer.title}"?\n\n'
          'Brokers you marketed it to will no longer see it. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyOfferId = offer.id);
    try {
      await _offers.delete(offer.id);
      if (!mounted) return;
      setState(() {
        _items = _items?.where((o) => o.id != offer.id).toList();
      });
      _reportCount();
      _toast('Offer deleted.');
    } catch (e) {
      _toast('Could not delete that offer. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  /// Picks a project when there is more than one, then opens the editor.
  Future<void> _create() async {
    final project = widget.projects.length == 1
        ? widget.projects.first
        : await _pickProject();
    if (project == null || !mounted) return;

    final draft = await showModalBottomSheet<BuilderOfferDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BuilderOfferEditorSheet(project: project),
    );
    if (draft == null || !mounted) return;

    setState(() => _busyOfferId = 'create');
    try {
      await _offers.create(
        builderId: widget.builderId,
        projectId: project.id,
        payload: draft.toPayload(isCreate: true),
      );
      if (!mounted) return;
      _toast('Offer marketed to your broker network.');
      await _load();
    } catch (e) {
      _toast('Could not create that offer. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  Future<ProjectModel?> _pickProject() {
    return showModalBottomSheet<ProjectModel>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Material(
        color: AppColors.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Which project?',
                  style: AppTextStyles.heading2.copyWith(fontSize: 17),
                ),
              ),
              for (final project in widget.projects)
                ListTile(
                  title: Text(
                    project.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body.copyWith(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    project.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                  onTap: () => Navigator.pop(context, project),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the editor for an existing offer.
  ///
  /// Needs the offer's project for the image picker. When that project is no longer
  /// in the parent's list — deleted since, which cascades the offer away too, so
  /// this is defensive — the edit is refused rather than opened against a stand-in.
  Future<void> _edit(BuilderOffer offer) async {
    final matches = widget.projects
        .where((p) => p.id == offer.projectId)
        .toList();
    if (matches.isEmpty) {
      _toast("That offer's project is no longer available.", isError: true);
      return;
    }

    final draft = await showModalBottomSheet<BuilderOfferDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          BuilderOfferEditorSheet(project: matches.first, editing: offer),
    );
    if (draft == null || !mounted) return;

    setState(() => _busyOfferId = offer.id);
    try {
      await _offers.update(
        offerId: offer.id,
        payload: draft.toPayload(isCreate: false),
      );
      if (!mounted) return;
      _toast('Offer updated.');
      await _load();
    } catch (e) {
      _toast('Could not update that offer. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyOfferId = null);
    }
  }

  void _openProject(BuilderOffer offer) {
    final projectId = offer.projectId;
    if (projectId == null) return;
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': projectId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    // Create sits OUTSIDE the shell, deliberately. The shell swaps its child for
    // `emptyMessage` when the list is empty — which is precisely when a builder
    // needs the button most. Inside, the message would have read "Use Create" with
    // no Create anywhere on screen.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.projects.isNotEmpty && !_failed)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busyOfferId == null ? _create : null,
              icon: const Icon(Icons.campaign_outlined, size: 16),
              label: const Text('Create'),
            ),
          ),
        if (_busyOfferId == 'create') const BuilderActionBusyRow(),
        _buildList(items),
      ],
    );
  }

  Widget _buildList(List<BuilderOffer>? items) {
    return BuilderSectionShell(
      failed: _failed,
      loaded: items != null,
      isEmpty: items?.isEmpty ?? false,
      onRetry: _load,
      errorTitle: "Couldn't load your offers",
      // Explained rather than collapsed, and now it names the button just above
      // rather than a flow on another platform.
      emptyMessage: widget.projects.isEmpty
          ? 'Publish a project first, then market an offer on it to your broker '
                'network.'
          : 'No active offers yet. Use Create to market one.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < (items?.length ?? 0); i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingM),
            _OfferCard(
              offer: items![i],
              busy: _busyOfferId == items[i].id,
              onTap: () => _openProject(items[i]),
              onDelete: () => _delete(items[i]),
              onEdit: () => _edit(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.busy,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  final BuilderOffer offer;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      // Tapping opens the project the offer is for — the portal's own primary
      // action on this card (`ProjectOfferCard.tsx:135`).
      onTap: busy || offer.projectId == null ? null : onTap,
      child: BuilderSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(url: offer.coverImage, hasVideo: offer.videoUrl != null),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(child: _Summary(offer: offer)),
              ],
            ),
            if (offer.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                offer.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(fontSize: 11.5),
              ),
            ],
            const SizedBox(height: AppConstants.spacingM),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 6),
            if (busy)
              const BuilderActionBusyRow()
            else
              Row(
                children: [
                  Expanded(
                    child: BuilderAction(
                      icon: Icons.open_in_new_rounded,
                      label: 'View',
                      onTap: offer.projectId == null ? null : onTap,
                    ),
                  ),
                  Expanded(
                    child: BuilderAction(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: onEdit,
                    ),
                  ),
                  Expanded(
                    child: BuilderAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      tint: AppColors.error,
                      onTap: onDelete,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.hasVideo});

  static const double _size = 74;

  final String? url;
  final bool hasVideo;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: _size,
      height: _size,
      color: AppColors.primaryLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.local_offer_rounded,
        size: 24,
        color: AppColors.primary,
      ),
    );

    // The portal falls back to a stock Unsplash photo here
    // (`ProjectOfferCard.tsx:42`). A placeholder the app owns is used instead —
    // loading a remote image to stand in for a missing one would be a network
    // request for nothing, and it reads as real content.
    final cover = url == null || url!.isEmpty
        ? placeholder()
        : CachedNetworkImage(
            imageUrl: url!,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            placeholder: (_, _) => placeholder(),
            errorWidget: (_, _, _) => placeholder(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.imageThumbnailRadius),
      child: hasVideo
          ? Stack(
              children: [
                cover,
                const Positioned(
                  right: 3,
                  bottom: 3,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ],
            )
          : cover,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.offer});

  final BuilderOffer offer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          offer.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (offer.projectTitle != null) ...[
          const SizedBox(height: 3),
          Text(
            offer.projectLocation == null
                ? offer.projectTitle!
                : '${offer.projectTitle} · ${offer.projectLocation}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 7),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              // Every listed offer is active — the query filters on it — so this
              // is a confirmation rather than a variable.
              const BuilderPill(label: 'Active', tint: AppColors.success),
              if (offer.createdAt != null) ...[
                const SizedBox(width: 6),
                BuilderPill(
                  label: _formatDate(offer.createdAt!),
                  tint: AppColors.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// `MMM d, yyyy` — the portal's `toLocaleDateString()` position on the card.
  static String _formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
