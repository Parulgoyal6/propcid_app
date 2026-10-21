// screens/dashboard/widgets/builder_inventory_summary.dart
//
// The six summary cards above the portal's Inventory list
// (`BuilderInventoryManager.tsx:327-400`), which Flutter had none of.
//
// Portal → here, card for card:
//
//   Total Projects      projects.length
//   Active              status == 'active'
//   Under Construction  status == 'under_construction'
//   Completed           status == 'completed'
//   Total Units         Σ project_inventory rows
//   Units Sold          Σ rows with status == 'sold'
//
// All six are unconditional on the portal — `totalUnits`/`soldUnits` render as
// `0` in their own card exactly like the other four, never hidden. This used
// to hide the last two tiles below a `_totalUnits > 0` guard, so a builder who
// had not yet added any `project_inventory` rows for any project saw four
// cards instead of six, reading as though the feature were missing entirely.
// Matching the portal's own unconditional layout removed that guard.
//
// PRESENTATION ONLY
// -----------------
// Every figure is a fold over two collections the Builder dashboard already holds:
// `_projects` (from `ProjectService.listMine`) and `_unitCounts` (from
// `ProjectInventoryService.countsByProject`). No query, no service change, no new
// model.
//
// Rendered with the same [MetricCard]/[MetricCardGrid] every other dashboard's
// KPI grid uses (Analytics/Audience, blueprint §16.5), rather than a bespoke
// tinted-strip look — one shared card shape across the app instead of a
// one-off here.
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../widgets/shared/stat_kpi_card.dart';

class BuilderInventorySummary extends StatelessWidget {
  const BuilderInventorySummary({
    super.key,
    required this.projects,
    required this.unitCounts,
  });

  final List<ProjectModel> projects;
  final Map<String, InventoryCounts> unitCounts;

  int _withStatus(String status) =>
      projects.where((p) => p.status == status).length;

  int get _totalUnits =>
      unitCounts.values.fold<int>(0, (sum, c) => sum + c.total);

  int get _soldUnits =>
      unitCounts.values.fold<int>(0, (sum, c) => sum + c.sold);

  @override
  Widget build(BuildContext context) {
    // Nothing to summarise before the projects land. The list below shows its own
    // spinner, so a second one here would be two spinners for one load.
    if (projects.isEmpty) return const SizedBox.shrink();

    return MetricCardGrid(
      cards: [
        MetricCard(
          icon: Icons.apartment_rounded,
          value: '${projects.length}',
          label: 'Total Projects',
          accent: AppColors.primary,
        ),
        MetricCard(
          icon: Icons.check_circle_rounded,
          value: '${_withStatus('active')}',
          label: 'Active',
          accent: AppColors.success,
        ),
        MetricCard(
          icon: Icons.construction_rounded,
          value: '${_withStatus('under_construction')}',
          label: 'Under Construction',
          accent: AppColors.warning,
        ),
        MetricCard(
          icon: Icons.task_alt_rounded,
          value: '${_withStatus('completed')}',
          label: 'Completed',
          accent: AppColors.statusNewLaunch,
        ),
        // Unconditional, matching the portal — see the file header. `0` here
        // means "no inventory added yet", which is worth showing directly
        // rather than making the whole card disappear.
        MetricCard(
          icon: Icons.grid_view_rounded,
          value: '$_totalUnits',
          label: 'Total Units',
          accent: AppColors.statusLoanAvailableText,
        ),
        MetricCard(
          icon: Icons.sell_rounded,
          value: '$_soldUnits',
          label: 'Units Sold',
          accent: AppColors.statusSold,
        ),
      ],
    );
  }
}
