import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/network_models.dart';
import '../../../services/network_service.dart';
import 'team_tab_states.dart';

/// The Team Workspace's Leads tab.
///
/// Builder-level, never project-scoped — confirmed from three independent
/// places: the portal's own `TeamLeadsView.tsx` (queries `network_leads` by
/// `builder_id` only — no project filter, no project-scoping prop on the
/// component at all), that file's own doc comment ("not per-project"), and
/// `has_team_permission`'s SQL, which the `leads` RLS policies always call
/// with `_project_id = NULL`, so the permission check short-circuits to "every
/// lead of this builder's" regardless of what the membership's `project_ids`
/// contains. This is a deliberate design in the migration, not a gap — this
/// tab must NOT start filtering by [builderId]'s membership `project_ids`
/// just because every other tab does.
///
/// Status updates are supported, matching `TeamLeadsView.tsx:67-82` exactly —
/// that's the only write the portal's version makes (no delete, no note
/// editing, no reassignment), so that's the only write added here.
/// `NetworkService`/`NetworkLead` otherwise stay read-only for every other
/// caller (the broker-side "My Leads" screen); [NetworkService.updateLeadStatus]
/// is additive.
class TeamLeadsTab extends StatefulWidget {
  const TeamLeadsTab({super.key, required this.builderId});

  final String builderId;

  @override
  State<TeamLeadsTab> createState() => _TeamLeadsTabState();
}

class _TeamLeadsTabState extends State<TeamLeadsTab> {
  final NetworkService _network = NetworkService();

  bool _loading = true;
  String? _error;
  List<NetworkLead> _leads = const [];
  String? _updatingLeadId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _network.listLeads(widget.builderId, isBuilder: true);
      if (!mounted) return;
      setState(() {
        _leads = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load leads. Please try again.';
        _loading = false;
      });
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

  Future<void> _updateStatus(NetworkLead lead, String status) async {
    if (status == lead.status) return;

    setState(() => _updatingLeadId = lead.id);
    try {
      await _network.updateLeadStatus(lead.id, status);
      if (!mounted) return;
      setState(() {
        _leads = [
          for (final l in _leads)
            if (l.id == lead.id)
              NetworkLead(
                id: l.id,
                leadType: l.leadType,
                priority: l.priority,
                status: status,
                assignmentMethod: l.assignmentMethod,
                assignedMemberId: l.assignedMemberId,
                autoAssigned: l.autoAssigned,
                notes: l.notes,
                assignedAt: l.assignedAt,
                createdAt: l.createdAt,
                metadata: l.metadata,
              )
            else
              l,
        ];
      });
      _toast('Lead updated. Status set to $status.');
    } catch (_) {
      _toast('Could not update that lead. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _updatingLeadId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return TeamTabErrorState(message: _error!, onRetry: _load);
    }
    if (_leads.isEmpty) {
      return const TeamTabEmptyState(
        message: 'No leads assigned to this workspace yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        itemCount: _leads.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingM),
        itemBuilder: (context, index) {
          final lead = _leads[index];
          return _LeadCard(
            lead: lead,
            updating: _updatingLeadId == lead.id,
            onStatusChanged: (status) => _updateStatus(lead, status),
          );
        },
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.updating,
    required this.onStatusChanged,
  });

  final NetworkLead lead;
  final bool updating;
  final ValueChanged<String> onStatusChanged;

  /// `TeamLeadsView.tsx:27-35`'s `statusColor`, adapted to this app's tokens.
  Color _statusColor(String status) {
    switch (status) {
      case 'converted':
        return AppColors.success;
      case 'qualified':
        return AppColors.primary;
      case 'contacted':
        return AppColors.warning;
      case 'lost':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = lead.status.isEmpty ? 'new' : lead.status;
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(lead.displayName, style: AppTextStyles.heading3),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: AppTextStyles.chip.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (lead.displayPhone != null) ...[
            const SizedBox(height: AppConstants.spacingXS),
            Text(
              lead.displayPhone!,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacingXS),
          Wrap(
            spacing: AppConstants.spacingS,
            runSpacing: AppConstants.spacingXS,
            children: [
              if (lead.priority.isNotEmpty) _Pill(text: lead.priority),
              if (lead.leadType.isNotEmpty) _Pill(text: lead.leadType),
            ],
          ),
          if (lead.notes != null && lead.notes!.isNotEmpty) ...[
            const SizedBox(height: AppConstants.spacingM),
            Text(
              lead.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacingM),
          if (updating)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: kTeamLeadStatusOptions.any((o) => o.value == status)
                  ? status
                  : null,
              isDense: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: [
                for (final option in kTeamLeadStatusOptions)
                  DropdownMenuItem(
                    value: option.value,
                    child: Text(
                      option.label,
                      style: AppTextStyles.body.copyWith(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onStatusChanged(value);
              },
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
