import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../models/social_models.dart';
import '../../providers/social_provider.dart';
import '../../services/social_service.dart';
import '../../widgets/shared/app_action_button.dart';
import '../../widgets/shared/app_surface_card.dart';
import '../shared/section_loader.dart';
import 'widgets/social_screen_shell.dart';

/// Lead status values — a direct port of the portal's `AdLeadStatus`/
/// `STATUSES`. The status control offers all four regardless of the lead's
/// current status (all-to-all, no staged progression), matching the portal.
const List<String> kLeadStatuses = ['new', 'contacted', 'qualified', 'closed'];

/// Per-status color — a direct port of `AdLeadsPanel.tsx`'s `STATUS_STYLE`.
const Map<String, Color> _leadStatusColor = {
  'new': Color(0xFF2563EB),
  'contacted': Color(0xFFB45309),
  'qualified': Color(0xFF0D9488),
  'closed': Color(0xFF16A34A),
};

Color _statusColor(String status) =>
    _leadStatusColor[status] ?? AppColors.primary;

String _statusLabel(String status) => status.isEmpty
    ? status
    : '${status[0].toUpperCase()}${status.substring(1)}';

/// Builds the same CSV `exportLeadsCsv` builds — header row, then one row per
/// lead, every field quoted, `\r\n`-joined.
String buildLeadsCsv(
  List<AdLead> leads,
  String Function(String? campaignId) campaignName,
) {
  String escape(String v) => '"${v.replaceAll('"', '""')}"';

  final rows = <String>[
    [
      'Name',
      'Email',
      'Phone',
      'Campaign',
      'Status',
      'Received',
    ].map(escape).join(','),
    for (final l in leads)
      [
        l.fullName ?? '',
        l.email ?? '',
        l.phone ?? '',
        campaignName(l.campaignId),
        l.status,
        l.createdAt?.toIso8601String() ?? '',
      ].map(escape).join(','),
  ];
  return rows.join('\r\n');
}

/// Social ▸ Leads — the design's `isSocialLeads` screen.
///
/// A direct port of `AdLeadsPanel.tsx`: search over name/email/phone, an
/// all-statuses filter, per-lead status updates (`updateLeadStatus`),
/// "Refresh" that calls `meta-leads-sync` before re-reading `social_ad_leads`,
/// a realtime subscription to the same table, and a CSV export.
class SocialLeadsScreen extends StatelessWidget {
  const SocialLeadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SocialLeadsSection(),
      child: const _LeadsView(),
    );
  }
}

class _LeadsView extends StatefulWidget {
  const _LeadsView();

  @override
  State<_LeadsView> createState() => _LeadsViewState();
}

class _LeadsViewState extends State<_LeadsView>
    with DeferredSectionLoader<_LeadsView> {
  final _service = SocialService();
  bool _syncing = false;
  String? _busyLeadId;
  List<AdCampaign> _campaigns = const [];
  RealtimeChannel? _channel;

  @override
  void loadSection(String userId) {
    context.read<SocialLeadsSection>().loadFor(userId);
    _loadCampaigns(userId);
    // `reloadSection()` calls this directly (`section_loader.dart`'s
    // `_loadedUserId` guard only covers the first, `didChangeDependencies`-
    // triggered call), and the realtime callback below itself calls
    // `reloadSection()` — so without this guard, every incoming change would
    // open one more channel on top of the last, forever. `??=` makes the
    // subscribe genuinely once-per-screen-instance.
    _channel ??= _service.subscribeLeads(
      userId: userId,
      channelSuffix: identityHashCode(this).toRadixString(36),
      onChange: reloadSection,
    );
  }

  Future<void> _loadCampaigns(String userId) async {
    try {
      final campaigns = await _service.listCampaigns(userId);
      if (mounted) setState(() => _campaigns = campaigns);
    } catch (_) {
      // Campaign names are a display/export nicety — a failed fetch here
      // must not block the leads list itself.
    }
  }

  String _campaignName(String? id) {
    if (id == null) return '—';
    for (final c in _campaigns) {
      if (c.id == id) return c.name;
    }
    return '—';
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// "Refresh" — pulls new submissions from Meta via `meta-leads-sync`, then
  /// re-reads `social_ad_leads`. A direct port of `AdLeadsPanel`'s
  /// `handleSync`.
  Future<void> _handleSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final ingested = await _service.syncLeads();
      reloadSection();
      _showSuccess(
        ingested > 0
            ? '$ingested new lead${ingested == 1 ? '' : 's'}.'
            : 'No new leads.',
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Updates the lead's status, then re-reads the confirmed row rather than
  /// guessing the new value locally — the row is only ever shown as changed
  /// once the write has actually succeeded.
  Future<void> _handleStatusChange(AdLead lead, String status) async {
    if (_busyLeadId != null) return;
    setState(() => _busyLeadId = lead.id);
    try {
      await _service.updateLeadStatus(lead.id, status);
      reloadSection();
    } catch (e) {
      _showError('Could not update status.');
    } finally {
      if (mounted) setState(() => _busyLeadId = null);
    }
  }

  Future<void> _handleExport(List<AdLead> leads) async {
    if (leads.isEmpty) return;
    try {
      final csv = buildLeadsCsv(leads, _campaignName);
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/propcid-leads-$stamp.csv');
      await file.writeAsString(csv, flush: true);
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv'),
      ], subject: 'PropCid Leads');
    } catch (e) {
      _showError('Could not export leads.');
    }
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _service.unsubscribeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = context.watch<SocialLeadsSection>();

    return SocialLeadsBody(
      leads: section.value,
      loading: section.loading,
      failed: section.failed,
      syncing: _syncing,
      busyLeadId: _busyLeadId,
      onRefresh: _handleSync,
      onExport: _handleExport,
      onStatusChange: _handleStatusChange,
    );
  }
}

class SocialLeadsBody extends StatefulWidget {
  final List<AdLead> leads;
  final bool loading;
  final bool failed;
  final bool syncing;
  final String? busyLeadId;
  final VoidCallback onRefresh;
  final ValueChanged<List<AdLead>> onExport;
  final void Function(AdLead lead, String status)? onStatusChange;

  const SocialLeadsBody({
    super.key,
    required this.leads,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    required this.onExport,
    this.syncing = false,
    this.busyLeadId,
    this.onStatusChange,
  });

  @override
  State<SocialLeadsBody> createState() => _SocialLeadsBodyState();
}

class _SocialLeadsBodyState extends State<SocialLeadsBody> {
  final _controller = TextEditingController();
  String _query = '';
  String _statusFilter = 'all';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Client-side, over the already-loaded list — no extra query, and it
    // matches how the design describes the field.
    final visible = widget.leads
        .where(
          (lead) =>
              (_statusFilter == 'all' || lead.status == _statusFilter) &&
              lead.matches(_query),
        )
        .toList();

    return SocialScreenShell(
      title: 'Leads',
      subtitle: 'People who submitted your lead-ad forms',
      children: [
        const SizedBox(height: AppConstants.spacingL),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                label: widget.syncing ? 'Refreshing…' : 'Refresh',
                height: 40,
                fontSize: 12.5,
                icon: Icons.refresh,
                variant: AppActionButtonVariant.surface,
                onTap: widget.syncing ? null : widget.onRefresh,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppActionButton(
                label: 'Export CSV',
                height: 40,
                fontSize: 12.5,
                icon: Icons.download_outlined,
                variant: AppActionButtonVariant.surface,
                onTap: visible.isEmpty ? null : () => widget.onExport(visible),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingM),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(
                    AppConstants.buttonRadius,
                  ),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                        textInputAction: TextInputAction.search,
                        style: AppTextStyles.body.copyWith(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                          hintText: 'Search name, email or phone...',
                          hintStyle: AppTextStyles.body.copyWith(
                            fontSize: 13,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
                border: Border.all(color: AppColors.hairline),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _statusFilter,
                  isDense: true,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All statuses'),
                    ),
                    for (final s in kLeadStatuses)
                      DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingL),
        if (widget.loading)
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
        else if (widget.failed)
          DashboardCard(
            child: EmptyStateView(
              icon: Icons.error_outline,
              message: "Couldn't load your leads. Try refreshing.",
              iconCircleSize: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          )
        else if (widget.leads.isEmpty)
          DashboardCard(
            child: EmptyStateView(
              icon: Icons.people_outline,
              message:
                  'No leads yet. Run a Leads campaign and submissions '
                  'will appear here automatically.',
              iconCircleSize: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          )
        else if (visible.isEmpty)
          const DashboardCard(
            child: EmptyStateView(
              icon: Icons.search_off_rounded,
              message: 'No leads match your filters.',
              iconCircleSize: 56,
              padding: EdgeInsets.symmetric(vertical: 8),
            ),
          )
        else
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _LeadCard(
              lead: visible[i],
              busy: widget.busyLeadId == visible[i].id,
              onStatusChange: widget.onStatusChange == null
                  ? null
                  : (status) => widget.onStatusChange!(visible[i], status),
            ),
          ],
      ],
    );
  }
}

class _LeadCard extends StatelessWidget {
  final AdLead lead;
  final bool busy;
  final ValueChanged<String>? onStatusChange;

  const _LeadCard({required this.lead, this.busy = false, this.onStatusChange});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(lead.status);

    return DashboardCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lead.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (lead.email != null || lead.phone != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      lead.email,
                      lead.phone,
                    ].where((v) => v != null && v.isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppConstants.spacingS),
          Opacity(
            opacity: busy ? 0.5 : 1,
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppConstants.pillRadius),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: lead.status,
                  isDense: true,
                  icon: Icon(Icons.expand_more, size: 16, color: color),
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  onChanged: (busy || onStatusChange == null)
                      ? null
                      : (v) {
                          if (v != null) onStatusChange!(v);
                        },
                  items: [
                    for (final s in kLeadStatuses)
                      DropdownMenuItem(value: s, child: Text(_statusLabel(s))),
                    // A status the app doesn't otherwise offer (e.g. a value
                    // written some other way) still renders instead of
                    // crashing the dropdown.
                    if (!kLeadStatuses.contains(lead.status))
                      DropdownMenuItem(
                        value: lead.status,
                        child: Text(_statusLabel(lead.status)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
