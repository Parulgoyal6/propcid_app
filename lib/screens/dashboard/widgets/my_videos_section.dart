// screens/dashboard/widgets/my_videos_section.dart
//
// The influencer's videos on the dashboard's Content tab, with the actions the
// portal's `InfluencerContentManager` offers — plus the one it stubbed out.
//
// WHAT THE PORTAL SHOWS HERE
// --------------------------
// A grid of cards, each with the thumbnail, an approval badge over it, the title,
// the video type, a status badge, view and like counts, the created date, and two
// buttons: Edit and Delete (InfluencerContentManager.tsx:161-235).
//
// Edit in that component is a "Coming Soon" toast (:203-211) — but only there. The
// same action is fully implemented via `InfluencerVideoModal(editingVideo:)`, wired
// from SellerWall.tsx:827, CreateContent.tsx:650 and ProfileDashboardShell.tsx:5449.
// So this ports the working version, not the stub.
//
// Delete uses `soft_delete_content`, following SellerWall.tsx:302 rather than this
// component's own un-migrated hard delete. The reasoning is in
// `InfluencerVideoService.softDelete`.
//
// Built in the shape of `my_projects_section.dart` — same card, same cover, same
// action row, same "empty means collapse" rule — so the two Content tabs read
// alike. `InfluencerRecentCampaignsWidget` and the
// `InfluencerCampaignService`/`InfluencerCampaignModel` pair it reads through are
// left untouched, exactly as D6 left the builder's equivalents.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/influencer_video_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/influencer_video_model.dart';
import '../../../services/influencer_video_service.dart';
import '../../influencer/influencer_video_form_screen.dart';

/// Cover thumbnail edge — the same 74 dp the projects section uses.
const double _kThumbSize = 74;

class MyVideosSection extends StatefulWidget {
  const MyVideosSection({
    super.key,
    required this.userId,
    this.onCountChanged,
    this.service,
  });

  final String userId;

  /// Reports how many videos this section is showing, after every change.
  ///
  /// Same contract as `MyListingsSection.onCountChanged`: fires on a successful
  /// load and after a delete, never on a failure — a failed fetch is not an empty
  /// list, and a parent that hid the section on error would swallow the retry.
  final ValueChanged<int>? onCountChanged;

  /// Injected by tests.
  @visibleForTesting
  final InfluencerVideoService? service;

  @override
  State<MyVideosSection> createState() => _MyVideosSectionState();
}

class _MyVideosSectionState extends State<MyVideosSection> {
  late final InfluencerVideoService _videos =
      widget.service ?? InfluencerVideoService();

  /// Null while loading — told apart from an empty list, which collapses.
  List<InfluencerVideoModel>? _items;
  bool _failed = false;
  String? _busyVideoId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _reportCount() => widget.onCountChanged?.call(_items?.length ?? 0);

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _videos.listMine(widget.userId);
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

  /// Opens the form for a new video, then reloads if one was created.
  Future<void> create() async {
    final result = await Navigator.push<InfluencerVideoFormResult>(
      context,
      MaterialPageRoute(builder: (_) => const InfluencerVideoFormScreen()),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _edit(InfluencerVideoModel video) async {
    final result = await Navigator.push<InfluencerVideoFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => InfluencerVideoFormScreen(editing: video),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _delete(InfluencerVideoModel video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Video'),
        // Deliberately says "removed", not "permanently deleted", because it is
        // not: `soft_delete_content` stamps `deleted_at`, a RESTRICTIVE policy
        // hides the row from every read, and `purge_soft_deleted()` hard-deletes
        // it 30 days later. Promising permanence here would be the one claim this
        // dialog cannot honour.
        content: Text(
          'Remove "${video.title}"?\n\n'
          'It will disappear from your profile and from Reels straight away. '
          'Its views and likes are kept until it is purged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyVideoId = video.id);
    try {
      final removed = await _videos.softDelete(video.id);
      if (!mounted) return;

      if (!removed) {
        // The RPC returns false when RLS matched nothing or the row was already
        // retired. Pruning the card here would hide a video that is still live.
        _toast("That video couldn't be removed.", isError: true);
        return;
      }

      setState(() {
        _items = _items?.where((v) => v.id != video.id).toList();
      });
      _reportCount();
      _toast('Video removed.');
    } catch (e) {
      _toast('Could not remove that video. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyVideoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your videos",
          message: 'Check your connection and try again.',
          actionLabel: 'Retry',
          onAction: _load,
        ),
      );
    }

    final items = _items;
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // The Content tab already offers "Upload Your First Video", so an empty state
    // here would be the second prompt in the same column.
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingM),
          _VideoCard(
            video: items[i],
            busy: _busyVideoId == items[i].id,
            onEdit: () => _edit(items[i]),
            onDelete: () => _delete(items[i]),
          ),
        ],
      ],
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final InfluencerVideoModel video;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      // Tapping the card opens the editor: there is no public video-detail route
      // in this app, and Reels is a feed rather than an addressable page. Sending
      // the owner to their own edit form is the only destination that exists.
      onTap: busy ? null : onEdit,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingM),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          boxShadow: AppColors.surfaceCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Cover(url: video.thumbnailUrl),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(child: _Summary(video: video)),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 6),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: onEdit,
                    ),
                  ),
                  Expanded(
                    child: _Action(
                      icon: Icons.delete_outline_rounded,
                      label: 'Remove',
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
  const _Cover({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: _kThumbSize,
      height: _kThumbSize,
      color: AppColors.primaryLight,
      alignment: Alignment.center,
      child: const Icon(
        Icons.videocam_rounded,
        size: 24,
        color: AppColors.primary,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.imageThumbnailRadius),
      child: url == null || url!.isEmpty
          ? placeholder()
          : CachedNetworkImage(
              imageUrl: url!,
              width: _kThumbSize,
              height: _kThumbSize,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder(),
              errorWidget: (_, _, _) => placeholder(),
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.video});

  final InfluencerVideoModel video;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          influencerVideoTypeLabel(video.videoType),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 7),
        // Horizontally scrollable for the same reason the projects card is: two
        // pills plus a date exceed a 320 dp card at a large text scale.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              InfluencerApprovalPill(approvalStatus: video.approvalStatus),
              // Only shown when it is not the default. `active` is the column
              // default and the state of nearly every row, so a pill saying so on
              // every card would carry no information.
              if (video.status != 'active') ...[
                const SizedBox(width: 6),
                _Pill(
                  label: influencerVideoStatusLabel(video.status),
                  tint: AppColors.textSecondary,
                ),
              ],
              if (video.hashtags.isNotEmpty) ...[
                const SizedBox(width: 6),
                _Pill(
                  label:
                      '#${video.hashtags.first}'
                      '${video.hashtags.length > 1 ? ' +${video.hashtags.length - 1}' : ''}',
                  tint: AppColors.textSecondary,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 5),
        // A Wrap, not a Row: the projects card carries two counters in this space
        // and fits, but the portal also shows the created date here
        // (InfluencerContentManager.tsx:196-206) and three items overflow a 210 dp
        // summary column. Wrapping lets the date drop to a second line on a narrow
        // phone instead of being clipped.
        Wrap(
          spacing: 10,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Metric(icon: Icons.visibility_outlined, label: '${video.views}'),
            _Metric(
              icon: Icons.favorite_outline_rounded,
              label: '${video.likes}',
            ),
            if (video.createdAt != null)
              Text(
                _formatDate(video.createdAt!),
                style: AppTextStyles.caption.copyWith(fontSize: 10.5),
              ),
          ],
        ),
      ],
    );
  }

  /// `MMM d, yyyy` — the portal's `format(new Date(created_at), 'MMM d, yyyy')`
  /// (InfluencerContentManager.tsx:205).
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

/// One icon-and-number pair from the stats row.
class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: AppColors.textHint),
        const SizedBox(width: 3),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 10.5)),
      ],
    );
  }
}

/// The video's `approval_status`, tinted by what it means for visibility.
///
/// The public read policy requires `approval_status = 'approved'`, so anything
/// else means nobody but the owner can see the video — worth a colour that says
/// so. Mirrors `getApprovalBadge` (InfluencerContentManager.tsx:118-127).
class InfluencerApprovalPill extends StatelessWidget {
  const InfluencerApprovalPill({super.key, required this.approvalStatus});

  final String approvalStatus;

  @override
  Widget build(BuildContext context) {
    final tint = switch (approvalStatus) {
      'approved' => AppColors.success,
      'rejected' => AppColors.error,
      _ => AppColors.warning,
    };
    return _Pill(label: influencerApprovalLabel(approvalStatus), tint: tint);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        // Two actions share the card here rather than three, so there is more
        // room than the projects card has — but a large text scale still needs
        // the same scale-down.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
