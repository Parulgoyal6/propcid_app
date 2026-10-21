// screens/dashboard/widgets/my_projects_section.dart
//
// The builder's projects on the dashboard's Content tab, with the actions the
// portal's `BuilderProjectsManager` offers: Manage Inventory, Edit, Share and
// Delete. ("Mark to brokers" is `BuilderOfferService`'s own flow, reached
// from the Manage Dashboard's Offers tab, not a per-card action here.)
//
// Replaces the read-only `BuilderRecentProjectsWidget` in the tab's section list.
// That widget, and the `BuilderProjectService` / `BuilderProjectModel` pair it
// reads through, are left untouched and become idle — decision D6; retiring them
// is a B8 proposal.
//
// Edit reuses the wizard rather than duplicating a form: it pushes
// `/add-project` with the project as an argument, and `AddProjectRouteGate`'s
// edit branch passes it through un-gated. This is that branch's first live
// caller.
//
// SPEC H
// ------
// Three optional parameters were added so the Inventory section could be this
// widget rather than a second project list: `unitCounts` (a chip of real
// `project_inventory` tallies), `showStatusPicker` (the pill becomes a picker) and
// `onProjectsLoaded` (the parent needs the ids to scope its own queries). All
// three default to off, so every existing mount renders and behaves exactly as it
// did — verified by the B4 tests, which pass unchanged.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/constants/project_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/scale_tap.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../models/property_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/project_service.dart';
import '../../../services/project_share_service.dart';
import '../../project/widgets/share_project_sheet.dart';
import '../../team/widgets/manage_units_screen.dart';

/// Cover thumbnail edge.
const double _kThumbSize = 74;

class MyProjectsSection extends StatefulWidget {
  const MyProjectsSection({
    super.key,
    required this.userId,
    this.service,
    this.shareService,
    this.unitCounts,
    this.showStatusPicker = false,
    this.onProjectsLoaded,
  });

  final String userId;

  /// Injected by tests.
  @visibleForTesting
  final ProjectService? service;

  /// Injected by tests.
  @visibleForTesting
  final ProjectShareService? shareService;

  /// Per-project `project_inventory` tallies, keyed by project id.
  ///
  /// Added for Spec H's Inventory section. Null — the default — renders exactly
  /// what this section rendered before: no unit chip at all. A project absent from
  /// the map, or present with `total == 0`, likewise shows nothing, because a
  /// project with no inventory rows is the normal case and "0 units" would read as
  /// a problem.
  ///
  /// Passed in rather than fetched here so this widget keeps its single
  /// dependency on [ProjectService]; the Inventory section owns the second query.
  final Map<String, InventoryCounts>? unitCounts;

  /// Whether the status pill becomes a picker.
  ///
  /// False everywhere except the Inventory section, so the Content tab's existing
  /// project list is unchanged. `BuilderInventoryManager.tsx:544-551` is the only
  /// portal screen that offers this control.
  final bool showStatusPicker;

  /// Reports the loaded project ids, so a parent can run the queries that need
  /// them — inventory tallies and site-visit bookings are both scoped by project.
  ///
  /// Fires after a successful load only, never on failure, for the same reason
  /// `onCountChanged` does not: an empty id list and a failed fetch must not look
  /// alike to a parent.
  final ValueChanged<List<String>>? onProjectsLoaded;

  @override
  State<MyProjectsSection> createState() => _MyProjectsSectionState();
}

class _MyProjectsSectionState extends State<MyProjectsSection> {
  late final ProjectService _projects = widget.service ?? ProjectService();
  late final ProjectShareService _sharing =
      widget.shareService ?? ProjectShareService();

  List<ProjectModel>? _items;
  bool _failed = false;
  String? _busyProjectId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _projects.listMine(widget.userId);
      if (!mounted) return;
      setState(() => _items = rows);
      widget.onProjectsLoaded?.call(
        rows.map((p) => p.id).toList(growable: false),
      );
    } catch (e) {
      if (!mounted) return;
      // Distinct from an empty list: an empty list hides the section, a failure
      // offers a retry.
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

  void _openDetail(ProjectModel project) {
    Navigator.pushNamed(
      context,
      AppConstants.projectDetailScreen,
      arguments: {'projectId': project.id},
    );
  }

  /// The portal's per-card "Manage Inventory" (`BuilderProjectsManager.tsx`),
  /// which opens `ProjectInventoryManager` for that one project. Reuses the
  /// same screen the Team Workspace's Inventory tab already opens for the
  /// same purpose — a unit isn't scoped by who is managing it, only by
  /// `project_id`.
  ///
  /// Re-reports the (unchanged) project ids on a real change — e.g. a unit
  /// marked "sold" — so the parent dashboard refetches `unitCounts` the same
  /// way `_onProjectsLoaded` already does on first load; without this, the
  /// "sold / listed" chip below and `BuilderInventorySummary`'s "Units Sold"
  /// card stayed on whatever tally was fetched before Manage Inventory was
  /// even opened.
  Future<void> _manageInventory(ProjectModel project) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ManageUnitsScreen(project: project)),
    );
    final items = _items;
    if (changed == true && mounted && items != null) {
      widget.onProjectsLoaded?.call(items.map((p) => p.id).toList());
    }
  }

  /// Opens the wizard in edit mode through the route, so the gate's edit branch
  /// stays the single definition of "editing is never role-gated".
  Future<void> _edit(ProjectModel project) async {
    final saved = await Navigator.pushNamed(
      context,
      AppConstants.addProjectScreen,
      arguments: {'project': project},
    );
    // The wizard pops `true` after a successful update.
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(ProjectModel project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project'),
        // Every child table references builder_projects(id) ON DELETE CASCADE,
        // so this is not only the project. Visit bookings in particular are
        // other people's appointments, which is worth spelling out however long
        // it makes the dialog.
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
      await _projects.delete(projectId: project.id, builderId: widget.userId);
      if (!mounted) return;
      // Pruned locally rather than re-fetched, so the row disappears without a
      // spinner over the whole list.
      setState(() {
        _items = _items?.where((p) => p.id != project.id).toList();
      });
      _toast('Project deleted.');
    } catch (e) {
      _toast('Could not delete that project. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyProjectId = null);
    }
  }

  /// Writes a project's new status through the service that already owns that
  /// column, then reflects it locally.
  ///
  /// `BuilderInventoryManager.tsx:182-208`: non-optimistic — the row is only
  /// recoloured once the write returns — and the list is patched rather than
  /// re-fetched, matching what `_delete` below already does.
  Future<void> _setStatus(ProjectModel project, String status) async {
    if (status == project.status) return;

    setState(() => _busyProjectId = project.id);
    try {
      await _projects.setStatus(
        projectId: project.id,
        builderId: widget.userId,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _items = _items
            ?.map((p) => p.id == project.id ? p.withStatus(status) : p)
            .toList();
      });
      _toast('Status updated to ${projectStatusLabel(status).toLowerCase()}.');
    } catch (e) {
      _toast('Could not update that status. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyProjectId = null);
    }
  }

  Future<void> _share(ProjectModel project) async {
    // Opens the same share sheet as Project Detail / Feed — system share,
    // "Send to a user", copy link, socials — *in addition to* the automatic
    // network-connections notify below, which stays exactly as it was.
    showShareProjectSheet(
      context,
      projectId: project.id,
      title: project.title,
      description: project.description,
      location: project.location,
      priceRangeMin: project.priceRangeMin,
      currentUserId: widget.userId,
    );

    setState(() => _busyProjectId = project.id);
    try {
      final result = await _sharing.shareProject(
        builderId: widget.userId,
        projectId: project.id,
        projectTitle: project.title,
      );
      if (!mounted) return;

      if (result.isEmpty) {
        // The portal's refusal: nothing was sent, so it does not claim success.
        _toast(
          'You have no network connections to share with yet.',
          isError: true,
        );
        return;
      }

      final plural = result.notified == 1 ? 'connection' : 'connections';
      _toast(
        result.dropped > 0
            // Never present a partial fan-out as a complete one.
            ? 'Notified ${result.notified} $plural. '
                  '${result.dropped} more were not notified — '
                  'share again to reach them.'
            : 'Notified ${result.notified} $plural about '
                  '"${project.title}".',
      );
    } catch (e) {
      _toast('Could not share that project. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyProjectId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EmptyStateView(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your projects",
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

    // The Content tab already offers "Add Your First Project", so an empty
    // state here would be the second prompt in the same column.
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppConstants.spacingM),
          _ProjectCard(
            project: items[i],
            busy: _busyProjectId == items[i].id,
            onTap: () => _openDetail(items[i]),
            onEdit: () => _edit(items[i]),
            onDelete: () => _delete(items[i]),
            onShare: () => _share(items[i]),
            onManageInventory: () => _manageInventory(items[i]),
            units: widget.unitCounts?[items[i].id],
            onStatusChanged: widget.showStatusPicker
                ? (status) => _setStatus(items[i], status)
                : null,
          ),
        ],
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.busy,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onShare,
    required this.onManageInventory,
    this.units,
    this.onStatusChanged,
  });

  final ProjectModel project;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final VoidCallback onManageInventory;

  /// Spec H: unit tallies, when the parent supplied them.
  final InventoryCounts? units;

  /// Spec H: non-null turns the status pill into a picker.
  final ValueChanged<String>? onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return ScaleTap(
      onTap: busy ? null : onTap,
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
                _Cover(url: project.coverImage),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: _Summary(
                    project: project,
                    units: units,
                    onStatusChanged: onStatusChanged,
                  ),
                ),
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
                      icon: Icons.inventory_2_outlined,
                      label: 'Inventory',
                      onTap: onManageInventory,
                    ),
                  ),
                  Expanded(
                    child: _Action(
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                      onTap: onEdit,
                    ),
                  ),
                  Expanded(
                    child: _Action(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: onShare,
                    ),
                  ),
                  Expanded(
                    child: _Action(
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
        Icons.apartment_rounded,
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
  const _Summary({required this.project, this.units, this.onStatusChanged});

  final ProjectModel project;
  final InventoryCounts? units;
  final ValueChanged<String>? onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final isOwnerViewing =
        context.read<AuthProvider>().userId == project.builderId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          project.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${project.typeLabel} · ${project.location}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 7),
        // Horizontally scrollable: status, approval and units at a large text
        // scale exceed a 320 dp card.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: Row(
            children: [
              // A picker only where the parent asked for one; a read-only pill
              // everywhere else, exactly as before.
              if (onStatusChanged != null)
                ProjectStatusPicker(
                  status: project.status,
                  onChanged: onStatusChanged!,
                )
              else
                ProjectStatusPill(status: project.status),
              // Owner-only. Showing "pending verification" to a visitor would
              // advertise that the project has not been reviewed — and it is
              // publicly visible regardless, because the read policy checks
              // `status = 'active'` alone.
              if (isOwnerViewing && project.isPendingApproval) ...[
                const SizedBox(width: 6),
                const _Pill(
                  label: 'Pending verification',
                  tint: AppColors.warning,
                ),
              ],
              if (project.totalUnits > 0) ...[
                const SizedBox(width: 6),
                _Pill(
                  label:
                      '${project.availableUnits}/${project.totalUnits} units',
                  tint: AppColors.textSecondary,
                ),
              ],
              // Distinct from the chip above: that one reports the counts typed
              // into the wizard, this one counts real `project_inventory` rows.
              // A project can have 120 declared units and no inventory rows at
              // all, so conflating them would misreport both.
              if (units != null && !units!.isEmpty) ...[
                const SizedBox(width: 6),
                _Pill(
                  label: '${units!.sold} sold / ${units!.total} listed',
                  tint: AppColors.primary,
                ),
              ],
            ],
          ),
        ),
        if (project.hasPriceRange) ...[
          const SizedBox(height: 6),
          Text(
            projectPriceRangeLabel(project),
            style: AppTextStyles.body.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: 12,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 3),
            Text(
              '${project.views}',
              style: AppTextStyles.caption.copyWith(fontSize: 10.5),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.favorite_outline_rounded,
              size: 12,
              color: AppColors.textHint,
            ),
            const SizedBox(width: 3),
            Text(
              '${project.likes}',
              style: AppTextStyles.caption.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ],
    );
  }
}

/// The project's `status`, tinted by what it means for visibility.
///
/// Only `active` is exposed by the public read policy, so anything else is
/// effectively hidden from buyers — worth showing in a colour that says so.
class ProjectStatusPill extends StatelessWidget {
  const ProjectStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tint = switch (status) {
      'active' => AppColors.success,
      'under_construction' => AppColors.statusNewLaunch,
      'completed' => AppColors.primary,
      _ => AppColors.textHint,
    };
    return _Pill(label: projectStatusLabel(status), tint: tint);
  }
}

/// [ProjectStatusPill], made tappable.
///
/// Shaped like the pill it replaces so the summary row is unchanged at a glance.
/// A `PopupMenuButton` rather than a `DropdownButton` for the reason established
/// by the listing status picker in Spec D: a dropdown brings its own chrome and
/// minimum height, and asserts when `value` is absent from `items`.
///
/// Unlike that picker, every stored status here **is** offerable —
/// `kProjectStatusPickerOptions` is the whole CHECK constraint — so there is no
/// read-only fallback case to route around.
class ProjectStatusPicker extends StatelessWidget {
  const ProjectStatusPicker({
    super.key,
    required this.status,
    required this.onChanged,
  });

  final String status;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Project status, ${projectStatusLabel(status)}. Tap to change.',
      child: PopupMenuButton<String>(
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final option in kProjectStatusPickerOptions)
            PopupMenuItem<String>(
              value: option.value,
              child: Row(
                children: [
                  Icon(
                    option.value == status
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: option.value == status
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                  const SizedBox(width: 10),
                  Text(option.label),
                ],
              ),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProjectStatusPill(status: status),
            const SizedBox(width: 2),
            const Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
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
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.chip.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
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
    final color = tint ?? AppColors.textSecondary;

    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            // Three actions share the card's width, so at a large text scale
            // "Delete" plus its icon exceeds a third of a 320 dp card. Scaling
            // down keeps the whole word — ellipsising it to "Dele…" would read
            // worse than slightly smaller type.
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
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "₹45.0 L – ₹95.0 L", or a single figure when both ends match.
///
/// Uses the app's one price formatter so a project reads like every other price
/// in the app. Public so the detail screen shows the identical string.
String projectPriceRangeLabel(ProjectModel project) {
  final min = project.priceRangeMin;
  final max = project.priceRangeMax;
  String one(double v) => PropertyModel.formatIndianPrice(v);

  if (min > 0 && max > 0) {
    return min == max ? one(min) : '${one(min)} – ${one(max)}';
  }
  return one(min > 0 ? min : max);
}
