import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/constants/project_options.dart' show projectStatusLabel;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../screens/add_project/add_project_screen.dart';
import '../../../services/builder_sections_service.dart';
import '../../../services/project_service.dart';
import 'manage_units_screen.dart';
import 'team_tab_states.dart';

/// The Team Workspace's Inventory tab.
///
/// Mirrors `BuilderInventoryManager.tsx` scoped to [allowedProjectIds] — null
/// means every one of [builderId]'s projects (`TeamMemberDashboard.tsx:113-116`'s
/// convention, the same one `BuilderTeamMember.hasAllProjects` documents on the
/// membership side).
///
/// View, Edit, Delete, status-change and Manage Units are all available for
/// every project already in the (scope-filtered) list below, matching the
/// portal exactly — its own `readOnly` prop only ever hid "Add Project"
/// (`BuilderInventoryManager.tsx:312`), never these. Add Project is shown
/// only when [allowedProjectIds] is null: a scoped member's fixed
/// `project_ids` list can never contain a not-yet-created project's id, so
/// `builder_projects`'s own `WITH CHECK (has_team_permission(...))` would
/// refuse the insert regardless of what this screen offers — the same reason
/// the portal hides it there.
///
/// Every write below is scoped to `widget.builderId` (the membership's
/// owning builder), never the signed-in team member's own id — RLS
/// (`has_team_permission`) is what actually authorizes each call; nothing
/// here is a substitute for it.
class TeamInventoryTab extends StatefulWidget {
  const TeamInventoryTab({
    super.key,
    required this.builderId,
    required this.allowedProjectIds,
  });

  final String builderId;

  /// Null ⇒ unrestricted (every project of [builderId]'s).
  final List<String>? allowedProjectIds;

  @override
  State<TeamInventoryTab> createState() => _TeamInventoryTabState();
}

class _TeamInventoryTabState extends State<TeamInventoryTab> {
  final ProjectService _projects = ProjectService();
  final ProjectInventoryService _inventory = ProjectInventoryService();

  bool _loading = true;
  String? _error;
  List<ProjectModel> _visibleProjects = const [];
  Map<String, InventoryCounts> _counts = const {};
  String? _busyProjectId;

  bool get _canAddProject => widget.allowedProjectIds == null;

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
      final all = await _projects.listMine(widget.builderId);
      final allowed = widget.allowedProjectIds;
      final visible = allowed == null
          ? all
          : all.where((p) => allowed.contains(p.id)).toList();

      final counts = await _inventory.countsByProject(
        visible.map((p) => p.id).toList(),
      );

      if (!mounted) return;
      setState(() {
        _visibleProjects = visible;
        _counts = counts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load inventory. Please try again.';
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

  /// Pushes the existing builder project wizard directly, bypassing
  /// `/add-project`'s named route entirely — that route's own gate
  /// (`AddProjectRouteGate`) checks the *signed-in user's* role before
  /// allowing a create, which would refuse a team member outright even
  /// though their membership is what actually grants this. Edit and Add
  /// both go through here so both carry `builderIdOverride`.
  Future<void> _openWizard({ProjectModel? editingProject}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProjectScreen(
          editingProject: editingProject,
          builderIdOverride: widget.builderId,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(ProjectModel project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text(
          'Delete "${project.title}"?\n\n'
          'This also permanently deletes its inventory units, any marketed '
          'offers, and every site-visit booking customers have made for it. '
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

    setState(() => _busyProjectId = project.id);
    try {
      await _projects.delete(
        projectId: project.id,
        builderId: widget.builderId,
      );
      if (!mounted) return;
      setState(() {
        _visibleProjects = _visibleProjects
            .where((p) => p.id != project.id)
            .toList();
        _busyProjectId = null;
      });
      _toast('Project deleted.');
    } catch (_) {
      if (mounted) setState(() => _busyProjectId = null);
      _toast('Could not delete that project. Please try again.', isError: true);
    }
  }

  Future<void> _setStatus(ProjectModel project, String status) async {
    if (status == project.status) return;

    setState(() => _busyProjectId = project.id);
    try {
      await _projects.setStatus(
        projectId: project.id,
        builderId: widget.builderId,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _visibleProjects = _visibleProjects
            .map((p) => p.id == project.id ? p.withStatus(status) : p)
            .toList();
      });
      _toast('Status updated to ${projectStatusLabel(status).toLowerCase()}.');
    } catch (_) {
      _toast('Could not update that status. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyProjectId = null);
    }
  }

  Future<void> _manageUnits(ProjectModel project) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ManageUnitsScreen(project: project)),
    );
    // A unit status change (e.g. to "sold") is exactly what `_counts` is
    // meant to reflect — without this, the tally chips stayed on whatever
    // was fetched before Manage Units was even opened.
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return TeamTabErrorState(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        children: [
          if (_canAddProject)
            Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openWizard(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Project'),
                ),
              ),
            ),
          if (_visibleProjects.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppConstants.spacingXXL),
              child: TeamTabEmptyState(message: 'No projects to show yet.'),
            )
          else
            for (final project in _visibleProjects) ...[
              _ProjectInventoryCard(
                project: project,
                counts: _counts[project.id] ?? InventoryCounts.empty,
                busy: _busyProjectId == project.id,
                onEdit: () => _openWizard(editingProject: project),
                onDelete: () => _delete(project),
                onStatusChanged: (status) => _setStatus(project, status),
                onManageUnits: () => _manageUnits(project),
              ),
              const SizedBox(height: AppConstants.spacingM),
            ],
        ],
      ),
    );
  }
}

class _ProjectInventoryCard extends StatelessWidget {
  const _ProjectInventoryCard({
    required this.project,
    required this.counts,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onStatusChanged,
    required this.onManageUnits,
  });

  final ProjectModel project;
  final InventoryCounts counts;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onManageUnits;

  @override
  Widget build(BuildContext context) {
    // `BuilderInventoryManager.tsx:497-529`: when the granular
    // `project_inventory` fold is empty, the portal falls back to the
    // listing's own `total_units`/`available_units` fields rather than
    // showing zero — those are filled in on the project form directly and
    // can be non-zero even when nobody has ever added an individual unit
    // row. `counts` (the fold) takes priority whenever it has anything;
    // this only applies when it's genuinely empty.
    final bool usingListingFallback = counts.total == 0;
    final InventoryCounts displayCounts = usingListingFallback
        ? InventoryCounts(
            total: project.totalUnits,
            available: project.availableUnits > 0
                ? project.availableUnits
                : project.totalUnits,
            sold: 0,
          )
        : counts;

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
          Text(project.title, style: AppTextStyles.heading3),
          const SizedBox(height: AppConstants.spacingXS),
          Text(
            project.location,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Wrap(
            spacing: AppConstants.spacingS,
            runSpacing: AppConstants.spacingS,
            children: [
              _CountChip(label: 'Total', value: displayCounts.total),
              _CountChip(
                label: 'Available',
                value: displayCounts.available,
                color: AppColors.statusAvailable,
              ),
              _CountChip(
                label: 'Sold',
                value: displayCounts.sold,
                color: AppColors.statusSold,
              ),
            ],
          ),
          if (usingListingFallback && displayCounts.total > 0) ...[
            const SizedBox(height: AppConstants.spacingXS),
            Text(
              'from listing',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ],
          const SizedBox(height: AppConstants.spacingM),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: isSettableProjectStatus(project.status)
                        ? project.status
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
                      for (final option in kProjectStatusPickerOptions)
                        DropdownMenuItem(
                          value: option.value,
                          child: Text(
                            option.label,
                            style: AppTextStyles.body.copyWith(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: (status) {
                      if (status != null) onStatusChanged(status);
                    },
                  ),
                ),
                IconButton(
                  onPressed: onManageUnits,
                  icon: const Icon(Icons.inventory_2_outlined),
                  tooltip: 'Manage Units',
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  tooltip: 'Delete',
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$value $label',
        style: AppTextStyles.chip.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: chipColor,
        ),
      ),
    );
  }
}
