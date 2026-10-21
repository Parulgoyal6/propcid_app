import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/social_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/social_provider.dart';
import '../../services/builder_project_service.dart';
import '../../services/influencer_video_service.dart';
import '../../services/meta_error_helpers.dart';
import '../../services/property_service.dart';
import '../../services/social_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../../widgets/shared/content_picker_dialog.dart';
import '../shared/section_loader.dart';
import 'create_campaign_dialog.dart';
import 'widgets/social_screen_shell.dart';

/// Social ▸ Ad Campaigns — the design's `isSocialCampaigns` screen.
///
/// Lists `social_ad_campaigns` with their synced Meta metrics; "New campaign"
/// opens the same two-step flow the portal's `CampaignsPanel.tsx` does (a
/// role-aware content picker, then `CreateCampaignDialog`, ported as
/// [showCreateCampaignDialog]); "Refresh" pulls live status/spend/impressions/
/// clicks/leads from Meta via `meta-campaign-sync` before re-reading the row;
/// and each card's Launch/Pause/Archive drives `meta-campaign-update` through
/// [SocialService.updateCampaign], gated behind a confirmation dialog in every
/// case (the portal only confirms Launch — Pause and Archive confirm here too,
/// since either can end a campaign's delivery and Archive can't be undone).
class SocialCampaignsScreen extends StatelessWidget {
  const SocialCampaignsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialCampaignsSection(),
      child: const _CampaignsView(),
    );
  }
}

/// What each role can boost — a direct port of `CampaignsPanel.tsx`'s
/// `allowedKinds()`: broker → properties, builder → projects, influencer →
/// videos + properties, individual (default) → properties, admin/super_admin
/// → everything.
List<String> _allowedKinds(String? userType, String? userRole) {
  if (userRole == 'admin' || userRole == 'super_admin') {
    return const ['property', 'project', 'reel'];
  }
  switch (userType) {
    case 'builder':
      return const ['project'];
    case 'broker':
      return const ['property'];
    case 'influencer':
      return const ['reel', 'property'];
    default:
      return const ['property'];
  }
}

class _CampaignsView extends StatefulWidget {
  const _CampaignsView();

  @override
  State<_CampaignsView> createState() => _CampaignsViewState();
}

class _CampaignsViewState extends State<_CampaignsView>
    with DeferredSectionLoader<_CampaignsView> {
  final _service = SocialService();
  bool _pickerLoading = false;
  bool _syncing = false;
  String? _busyCampaignId;

  void _showError(Object error) => _showErrorWithAction('$error', null);

  /// Shows the error, and — when it's classifiable as a billing or
  /// Development-mode issue — an action that opens the fix in a browser, the
  /// same "fix it there" affordance `metaErrorAction` gives the portal's toast.
  void _showErrorWithAction(String message, String? adAccountId) {
    if (!mounted) return;
    final action = metaErrorAction(message, adAccountId: adAccountId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: action == null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 8),
        action: action == null
            ? null
            : SnackBarAction(
                label: action.label,
                onPressed: () => launchUrl(
                  Uri.parse(action.url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void loadSection(String userId) =>
      context.read<SocialCampaignsSection>().loadFor(userId);

  /// "Refresh" — pulls live status/spend/impressions/clicks/leads from Meta
  /// via `meta-campaign-sync`, then re-reads `social_ad_campaigns` so the list
  /// reflects what was just synced. A direct port of `CampaignsPanel.tsx`'s
  /// `handleSync`; never edits a row's fields locally.
  Future<void> _handleSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final synced = await _service.syncCampaigns();
      reloadSection();
      _showSuccess(
        synced > 0
            ? 'Refreshed $synced campaign${synced == 1 ? '' : 's'}.'
            : 'Nothing to refresh yet.',
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Launch/Pause/Archive — always confirms first (spend safety: a newly
  /// created campaign is never launched automatically, and every status
  /// change here is a deliberate, confirmed user action), then calls the
  /// existing `meta-campaign-update` through [SocialService.updateCampaign].
  /// The row is only re-read from the database after that call succeeds —
  /// a failed backend/Meta operation leaves the card showing its last known
  /// status, never a locally-guessed new one.
  Future<void> _handleAction(AdCampaign campaign, String action) async {
    if (_busyCampaignId != null) return;

    final bool confirmed;
    switch (action) {
      case 'resume':
        confirmed = await _confirm(
          title: 'Launch campaign?',
          message:
              'Launching "${campaign.name}" makes it active immediately '
              'and it may start spending up to '
              '${campaign.dailyBudgetDisplay}/day.',
          confirmLabel: 'Launch',
        );
        break;
      case 'pause':
        confirmed = await _confirm(
          title: 'Pause campaign?',
          message:
              'Pausing "${campaign.name}" stops it from spending '
              "further until you launch it again.",
          confirmLabel: 'Pause',
        );
        break;
      case 'archive':
        confirmed = await _confirm(
          title: 'Archive campaign?',
          message:
              'Archiving "${campaign.name}" stops it permanently. '
              "Archived campaigns can't be launched again.",
          confirmLabel: 'Archive',
          danger: true,
        );
        break;
      default:
        confirmed = false;
    }
    if (!confirmed || !mounted) return;

    setState(() => _busyCampaignId = campaign.id);
    try {
      await _service.updateCampaign(campaign.id, action: action);
      reloadSection();
      _showSuccess(switch (action) {
        'resume' => 'Campaign launched.',
        'pause' => 'Campaign paused.',
        'archive' => 'Campaign archived.',
        _ => 'Campaign updated.',
      });
    } catch (e) {
      _showErrorWithAction('$e', campaign.adAccountId);
    } finally {
      if (mounted) setState(() => _busyCampaignId = null);
    }
  }

  /// Loads this user's eligible content (per [_allowedKinds]) from the same
  /// three existing services the rest of the app already lists it with, then
  /// opens the shared content picker followed by [showCreateCampaignDialog] —
  /// exactly the `ContentPicker` → `CreateCampaignDialog` handoff
  /// `CampaignsPanel.tsx` does.
  Future<void> _openNewCampaign() async {
    final userId = loadedUserId;
    if (userId == null || _pickerLoading) return;
    final auth = context.read<AuthProvider>();
    final kinds = _allowedKinds(auth.userType, auth.userRole);

    setState(() => _pickerLoading = true);
    final items = <ContentPickerItem>[];
    final contentTypes = <ContentPickerItem, String>{};
    try {
      if (kinds.contains('property')) {
        final rows = await PropertyService().getPropertiesByUser(userId);
        for (final p in rows) {
          final item = ContentPickerItem(
            id: p.id,
            title: p.title.isEmpty ? 'Property' : p.title,
            typeLabel: 'Property',
            imageUrl: p.imageUrls.isNotEmpty
                ? p.imageUrls.first
                : (p.imageUrl.isNotEmpty ? p.imageUrl : null),
            fallbackIcon: Icons.apartment_rounded,
          );
          items.add(item);
          contentTypes[item] = 'property';
        }
      }
      if (kinds.contains('project')) {
        final rows = await BuilderProjectService().getProjects(userId);
        for (final p in rows) {
          final item = ContentPickerItem(
            id: p.id,
            title: p.title.isEmpty ? 'Project' : p.title,
            typeLabel: 'Project',
            imageUrl: p.image.isNotEmpty ? p.image : null,
            fallbackIcon: Icons.location_city_rounded,
          );
          items.add(item);
          contentTypes[item] = 'project';
        }
      }
      if (kinds.contains('reel')) {
        final rows = await InfluencerVideoService().listMine(userId);
        for (final v in rows) {
          final item = ContentPickerItem(
            id: v.id,
            title: v.title.isEmpty ? 'Video' : v.title,
            typeLabel: 'Video',
            imageUrl: v.thumbnailUrl,
            fallbackIcon: Icons.videocam_rounded,
          );
          items.add(item);
          contentTypes[item] = 'reel';
        }
      }
    } catch (e) {
      if (mounted) setState(() => _pickerLoading = false);
      _showError(e);
      return;
    }
    if (!mounted) return;
    setState(() => _pickerLoading = false);

    final picked = await showContentPickerSheet(
      context,
      items: items,
      title: 'Pick content to boost',
      searchHint: 'Search your content...',
      emptyTitle: 'Nothing to boost yet',
      emptyMessage: 'Create a listing first, then come back.',
    );
    if (picked == null || !mounted) return;

    await showCreateCampaignDialog(
      context,
      userId: userId,
      contentType: contentTypes[picked]!,
      contentId: picked.id,
      title: picked.title,
      mediaUrls: picked.imageUrl != null ? [picked.imageUrl!] : const [],
      onCreated: (_) => reloadSection(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialCampaignsSection>();

    return SocialCampaignsBody(
      campaigns: section.value,
      loading: section.loading,
      failed: section.failed,
      busy: _pickerLoading,
      syncing: _syncing,
      busyCampaignId: _busyCampaignId,
      onRefresh: _handleSync,
      onNewCampaign: _openNewCampaign,
      onAction: _handleAction,
    );
  }
}

class SocialCampaignsBody extends StatelessWidget {
  final List<AdCampaign> campaigns;
  final bool loading;
  final bool failed;
  final bool busy;
  final bool syncing;
  final String? busyCampaignId;
  final VoidCallback onRefresh;
  final VoidCallback onNewCampaign;
  final void Function(AdCampaign campaign, String action)? onAction;

  const SocialCampaignsBody({
    super.key,
    required this.campaigns,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    required this.onNewCampaign,
    this.busy = false,
    this.syncing = false,
    this.busyCampaignId,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SocialScreenShell(
      title: 'Ad Campaigns',
      subtitle: 'Boost your listings on Facebook & Instagram',
      children: [
        const SizedBox(height: AppConstants.spacingL),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                label: syncing ? 'Refreshing…' : 'Refresh',
                height: 40,
                fontSize: 12.5,
                icon: Icons.refresh,
                variant: AppActionButtonVariant.surface,
                onTap: syncing ? null : onRefresh,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppActionButton(
                label: busy ? 'Loading…' : 'New Campaign',
                height: 40,
                fontSize: 12.5,
                icon: Icons.add,
                onTap: busy ? null : onNewCampaign,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingL),
        if (loading)
          const DashboardCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (failed)
          DashboardCard(
            child: EmptyStateView(
              icon: Icons.error_outline,
              message: "Couldn't load your campaigns. Try refreshing.",
              iconCircleSize: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          )
        else if (campaigns.isEmpty)
          DashboardCard(
            child: EmptyStateView(
              icon: Icons.campaign_outlined,
              message:
                  'No campaigns yet. Boost a property, project, article '
                  'or reel — campaigns you create will show up here.',
              iconCircleSize: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              actionLabel: 'Create Your First Campaign',
              onAction: onNewCampaign,
            ),
          )
        else
          for (var i = 0; i < campaigns.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _CampaignCard(
              campaign: campaigns[i],
              busy: busyCampaignId == campaigns[i].id,
              onAction: onAction == null
                  ? null
                  : (action) => onAction!(campaigns[i], action),
            ),
          ],
      ],
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final AdCampaign campaign;
  final bool busy;
  final ValueChanged<String>? onAction;

  const _CampaignCard({
    required this.campaign,
    this.busy = false,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final status = campaign.status.toUpperCase();

    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  campaign.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              _StatusPill(campaign.displayStatus),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            campaign.objective,
            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(label: 'Spend', value: campaign.spendDisplay),
              _Metric(label: 'Impressions', value: '${campaign.impressions}'),
              _Metric(label: 'Clicks', value: '${campaign.clicks}'),
              _Metric(label: 'Leads', value: '${campaign.leadsCount}'),
            ],
          ),
          if (campaign.lastError?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    campaign.lastError!,
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.error,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (onAction != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'PAUSED')
                  AppActionButton(
                    label: 'Launch',
                    height: 34,
                    fontSize: 12,
                    icon: Icons.play_arrow_rounded,
                    onTap: busy ? null : () => onAction!('resume'),
                  ),
                if (status == 'ACTIVE')
                  AppActionButton(
                    label: 'Pause',
                    height: 34,
                    fontSize: 12,
                    icon: Icons.pause_rounded,
                    variant: AppActionButtonVariant.outline,
                    onTap: busy ? null : () => onAction!('pause'),
                  ),
                if (status != 'ARCHIVED')
                  AppActionButton(
                    label: 'Archive',
                    height: 34,
                    fontSize: 12,
                    icon: Icons.archive_outlined,
                    variant: AppActionButtonVariant.surface,
                    onTap: busy ? null : () => onAction!('archive'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTextStyles.heading3.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) {
    final active = status.toUpperCase() == 'ACTIVE';

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppColors.success : AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        status,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }
}
