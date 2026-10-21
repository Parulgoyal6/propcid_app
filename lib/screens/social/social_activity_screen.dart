import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/scale_tap.dart';
import '../../models/social_models.dart';
import '../../providers/social_provider.dart';
import '../../services/social_service.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../shared/section_loader.dart';
import 'widgets/social_screen_shell.dart';

/// Social ▸ Publishing Activity — the design's `isSocialActivity` screen.
///
/// The caller's live publish queue from `social_share_queue`, newest first —
/// a direct port of `SocialActivityPanel.tsx`. This reads the queue rather
/// than `social_share_logs`: the queue is the only place a `queued` or
/// `canceled` job is ever visible, since `social_share_logs` only ever
/// carries `success`/`failed`/`processing` rows a worker attempt already
/// resolved to. Retry — `retryQueueItem` — clones a failed job into a fresh
/// queued row so the insert trigger dispatches it again.
class SocialActivityScreen extends StatelessWidget {
  const SocialActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialActivitySection(),
      child: const _ActivityView(),
    );
  }
}

class _ActivityView extends StatefulWidget {
  const _ActivityView();

  @override
  State<_ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<_ActivityView>
    with DeferredSectionLoader<_ActivityView> {
  final _service = SocialService();
  bool _busy = false;

  @override
  void loadSection(String userId) =>
      context.read<SocialActivitySection>().loadFor(userId);

  Future<void> _retry(ShareQueueItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.retryQueueItem(item);
      reloadSection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialActivitySection>();

    return SocialActivityBody(
      items: section.value,
      loading: section.loading,
      failed: section.failed,
      busy: _busy,
      onRefresh: reloadSection,
      onRetry: _retry,
    );
  }
}

class SocialActivityBody extends StatelessWidget {
  final List<ShareQueueItem> items;
  final bool loading;
  final bool failed;
  final bool busy;
  final VoidCallback onRefresh;
  final ValueChanged<ShareQueueItem> onRetry;

  const SocialActivityBody({
    super.key,
    required this.items,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    required this.onRetry,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return SocialScreenShell(
      title: 'Publishing Activity',
      subtitle: 'Your publish timeline',
      children: [
        const SizedBox(height: 18),
        DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: SocialCardTitle('Publishing activity')),
                  Semantics(
                    label: 'Refresh',
                    button: true,
                    child: ScaleTap(
                      onTap: onRefresh,
                      child: ColoredBox(
                        color: AppColors.cardBackground,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh,
                              size: 16,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Refresh',
                              style: AppTextStyles.body.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingXL),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (failed)
                const EmptyStateView(
                  icon: Icons.error_outline,
                  message: "Couldn't load your publishing activity.",
                  iconCircleSize: 52,
                  padding: EdgeInsets.symmetric(vertical: 4),
                )
              else if (items.isEmpty)
                const EmptyStateView(
                  icon: Icons.schedule,
                  message:
                      'Nothing published yet. Create a property or '
                      'project and use "Publish Everywhere".',
                  iconCircleSize: 52,
                  padding: EdgeInsets.symmetric(vertical: 4),
                )
              else
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _LogRow(
                    item: items[i],
                    busy: busy,
                    onRetry: () => onRetry(items[i]),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `STATUS_META` — a direct port of `SocialActivityPanel.tsx`'s per-status
/// label/color/icon map. Every one of the queue's five statuses gets its own
/// word and color, not the raw enum value.
class _StatusMeta {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _StatusMeta(this.label, this.background, this.foreground, this.icon);
}

const Map<String, _StatusMeta> _statusMeta = {
  'queued': _StatusMeta(
    'Queued',
    Color(0xFFDCEAFE),
    Color(0xFF1D4ED8),
    Icons.schedule,
  ),
  'processing': _StatusMeta(
    'Processing',
    Color(0xFFFEF3C7),
    Color(0xFFB45309),
    Icons.autorenew,
  ),
  'success': _StatusMeta(
    'Published',
    AppColors.success,
    Colors.white,
    Icons.check_circle,
  ),
  'failed': _StatusMeta('Failed', AppColors.error, Colors.white, Icons.cancel),
  'canceled': _StatusMeta(
    'Canceled',
    AppColors.background,
    AppColors.textSecondary,
    Icons.block,
  ),
};

class _LogRow extends StatelessWidget {
  final ShareQueueItem item;
  final bool busy;
  final VoidCallback onRetry;

  const _LogRow({required this.item, required this.onRetry, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final failed = item.status == 'failed';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LogRowContent(item: item),
          if (failed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy ? null : onRetry,
                icon: const Icon(Icons.replay, size: 15),
                label: const Text('Retry', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogRowContent extends StatelessWidget {
  final ShareQueueItem item;

  const _LogRowContent({required this.item});

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta[item.status] ?? _statusMeta['queued']!;
    final subtitle =
        [
          item.relativeTime,
          if (item.error?.isNotEmpty ?? false) item.error!,
        ].join(
          item.relativeTime.isNotEmpty && (item.error?.isNotEmpty ?? false)
              ? ' — '
              : '',
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          item.platform == 'instagram'
              ? Icons.camera_alt_outlined
              : Icons.facebook,
          size: 18,
          color: item.platform == 'instagram'
              ? const Color(0xFFE4405F)
              : const Color(0xFF1877F2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.contentType.isEmpty
                    ? 'Post'
                    : (item.targets.isNotEmpty
                          ? '${item.contentType} · ${item.targets.join(', ')}'
                          : item.contentType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11,
                    color: (item.error?.isNotEmpty ?? false)
                        ? AppColors.error
                        : null,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppConstants.spacingS),
        Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: meta.background,
            borderRadius: BorderRadius.circular(AppConstants.pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon, size: 12, color: meta.foreground),
              const SizedBox(width: 4),
              Text(
                meta.label,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: meta.foreground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
