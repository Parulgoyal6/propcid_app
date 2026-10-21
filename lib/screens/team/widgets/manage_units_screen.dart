import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/constants/project_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../services/builder_sections_service.dart';
import '../../../services/project_service.dart';
import 'team_tab_states.dart';

/// Mobile mirror of the portal's `ProjectInventoryManager.tsx` — opened from a
/// project's "Manage Units" action in `TeamInventoryTab`, and from a builder's
/// own "Manage Inventory" action on their My Projects card
/// (`my_projects_section.dart`).
///
/// Scoped entirely by [project]'s id, the same way the portal component is
/// (`projectId` is its only data prop) — a unit has no `builder_id` of its
/// own, so there is nothing else to scope by here; `project_inventory`'s RLS
/// (ownership through `builder_projects`, or "Team members can manage project
/// inventory" for a scoped member) is what actually restricts this to a
/// project the caller may act on.
///
/// Covers `unit_type`, `unit_number`, `floor_number`, `area_sqft`, `price`,
/// `status` and `facing_direction`, plus the portal's "Pre-fill from Listing"
/// / "Save All New" bulk-draft flow (`InventoryTableEditor.tsx`). Not
/// covered: `amenities`, `features`, `floor_plan_url` (per-unit, not
/// per-project — the portal's own table editor doesn't touch them either,
/// only its separate `AddInventoryItemModal`), and the project-level Master
/// Layout image — `builder_projects.master_layout_url` is derived from
/// `map_images.first` on every wizard save (`ProjectDraft.toPayload`), so a
/// standalone update here would be silently overwritten the next time the
/// project is edited through the wizard; fixing that conflict is its own
/// piece of work, not part of unit management.
class ManageUnitsScreen extends StatefulWidget {
  const ManageUnitsScreen({
    super.key,
    required this.project,
    this.service,
    this.projectService,
  });

  final ProjectModel project;

  /// Injected by tests.
  @visibleForTesting
  final ProjectInventoryService? service;

  /// Injected by tests. Used only for [ProjectService.syncTotalsFromInventory]
  /// on the way out — this screen's own unit CRUD stays entirely on
  /// [service].
  @visibleForTesting
  final ProjectService? projectService;

  @override
  State<ManageUnitsScreen> createState() => _ManageUnitsScreenState();
}

/// A generated-but-unsaved row from "Pre-fill from Listing", or a fresh one
/// started by "+ Add Row". Holds a plain payload map — the same shape
/// [ProjectInventoryService.createUnit] takes — so saving it is just handing
/// that map to the service, and editing it is just handing it to the same
/// [_UnitFormSheet] a saved unit uses.
class _DraftUnit {
  _DraftUnit({required this.tempId, required this.payload});

  final String tempId;
  Map<String, dynamic> payload;

  String get unitType => payload['unit_type']?.toString() ?? '';
  String? get unitNumber => payload['unit_number']?.toString();
  double get areaSqft => (payload['area_sqft'] as num?)?.toDouble() ?? 0;
  double get price => (payload['price'] as num?)?.toDouble() ?? 0;
  String get status => payload['status']?.toString() ?? 'available';

  /// Valid enough to bulk-save — `InventoryTableEditor.tsx`'s own
  /// `saveAllNewRows` filter: `unit_type && area_sqft && price`.
  bool get isSavable => unitType.trim().isNotEmpty && areaSqft > 0 && price > 0;

  /// A throwaway [InventoryUnit] so this draft can go through the exact same
  /// form sheet a saved unit edits, rather than a second form just for drafts.
  InventoryUnit asInventoryUnit(String projectId) => InventoryUnit(
    id: tempId,
    projectId: projectId,
    unitType: unitType,
    status: status,
    unitNumber: unitNumber,
    floorNumber: (payload['floor_number'] as num?)?.toInt(),
    areaSqft: areaSqft,
    price: price,
    facingDirection: payload['facing_direction']?.toString(),
  );
}

/// How many draft rows one "Pre-fill from Listing" tap may generate.
///
/// `InventoryTableEditor.tsx`'s own `PREFILL_CAP`.
const int _kPrefillCap = 200;

class _ManageUnitsScreenState extends State<ManageUnitsScreen> {
  late final ProjectInventoryService _inventory =
      widget.service ?? ProjectInventoryService();
  late final ProjectService _projects =
      widget.projectService ?? ProjectService();

  bool _loading = true;
  String? _error;
  List<InventoryUnit> _units = const [];
  final List<_DraftUnit> _drafts = [];
  String? _busyId;
  bool _savingAll = false;
  int _nextTempId = 0;

  /// Set on the first successful create/update/delete — reported back to
  /// the caller on pop (`PopScope` below) so a parent showing cached
  /// `project_inventory` tallies (e.g. a status change to "sold") knows to
  /// refetch them instead of going stale until its next full reload.
  bool _changed = false;

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
      final units = await _inventory.unitsForProject(widget.project.id);
      if (!mounted) return;
      setState(() {
        _units = units;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load units. Please try again.';
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

  Future<void> _addUnit() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _UnitFormSheet(projectType: widget.project.projectType),
    );
    if (payload == null || !mounted) return;

    try {
      await _inventory.createUnit(
        projectId: widget.project.id,
        payload: payload,
      );
      if (!mounted) return;
      _changed = true;
      _toast('Unit added.');
      await _load();
    } catch (_) {
      _toast('Could not add that unit. Please try again.', isError: true);
    }
  }

  Future<void> _editUnit(InventoryUnit unit) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UnitFormSheet(
        existing: unit,
        projectType: widget.project.projectType,
      ),
    );
    if (payload == null || !mounted) return;

    setState(() => _busyId = unit.id);
    try {
      await _inventory.updateUnit(unitId: unit.id, payload: payload);
      if (!mounted) return;
      _changed = true;
      _toast('Unit updated.');
      await _load();
    } catch (_) {
      _toast('Could not update that unit. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _deleteUnit(InventoryUnit unit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete unit'),
        content: Text(
          'Delete ${unit.unitNumber?.isNotEmpty == true ? 'unit ${unit.unitNumber}' : 'this unit'}? '
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

    setState(() => _busyId = unit.id);
    try {
      await _inventory.deleteUnit(unit.id);
      if (!mounted) return;
      _changed = true;
      setState(() {
        _units = _units.where((u) => u.id != unit.id).toList();
        _busyId = null;
      });
      _toast('Unit deleted.');
    } catch (_) {
      if (mounted) setState(() => _busyId = null);
      _toast('Could not delete that unit. Please try again.', isError: true);
    }
  }

  // ── Pre-fill from Listing ────────────────────────────────────────────────

  /// Generates draft rows up to the listing's declared `total_units`, the same
  /// rule `InventoryTableEditor.tsx:89-135` uses: target minus what already
  /// exists (saved rows and pending drafts alike), capped at [_kPrefillCap].
  void _prefillFromListing() {
    final total = widget.project.totalUnits;
    final remaining = total - _units.length - _drafts.length;

    if (total <= 0) {
      _toast("This project's listing has no total unit count set.");
      return;
    }
    if (remaining <= 0) {
      _toast("Inventory already matches the listing's unit count.");
      return;
    }

    final toGenerate = remaining > _kPrefillCap ? _kPrefillCap : remaining;
    final unitType = unitTypeOptionsFor(widget.project.projectType).first;
    final area = widget.project.areaSqftMin > 0
        ? widget.project.areaSqftMin
        : widget.project.areaSqftMax;
    final price = widget.project.priceRangeMin > 0
        ? widget.project.priceRangeMin
        : widget.project.priceRangeMax;
    final startNumber = _units.length + _drafts.length + 1;

    setState(() {
      for (var i = 0; i < toGenerate; i++) {
        _drafts.add(
          _DraftUnit(
            tempId: 'draft-${_nextTempId++}',
            payload: {
              'unit_type': unitType,
              'unit_number': '${startNumber + i}',
              'floor_number': null,
              'area_sqft': area,
              'price': price,
              'status': 'available',
              'facing_direction': null,
            },
          ),
        );
      }
    });
  }

  void _addBlankDraft() {
    setState(() {
      _drafts.add(
        _DraftUnit(
          tempId: 'draft-${_nextTempId++}',
          payload: {
            'unit_type': '',
            'unit_number': null,
            'floor_number': null,
            'area_sqft': 0.0,
            'price': 0.0,
            'status': 'available',
            'facing_direction': null,
          },
        ),
      );
    });
  }

  Future<void> _editDraft(_DraftUnit draft) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UnitFormSheet(
        existing: draft.asInventoryUnit(widget.project.id),
        projectType: widget.project.projectType,
      ),
    );
    if (payload == null || !mounted) return;
    setState(() => draft.payload = payload);
  }

  void _discardDraft(_DraftUnit draft) {
    setState(() => _drafts.remove(draft));
  }

  /// Commits one draft row — `InventoryTableEditor.tsx`'s per-row ✓ on an
  /// unsaved row (`saveNewRow`).
  Future<void> _saveDraft(_DraftUnit draft) async {
    if (!draft.isSavable) {
      _toast('Enter a unit type, area and price first.', isError: true);
      return;
    }

    setState(() => _busyId = draft.tempId);
    try {
      final saved = await _inventory.createUnit(
        projectId: widget.project.id,
        payload: draft.payload,
      );
      if (!mounted) return;
      _changed = true;
      setState(() {
        _units = [..._units, saved];
        _drafts.remove(draft);
        _busyId = null;
      });
    } catch (_) {
      if (mounted) setState(() => _busyId = null);
      _toast('Could not save that unit. Please try again.', isError: true);
    }
  }

  /// "Save All New (N)" — one bulk insert of every currently-savable draft.
  /// A draft still missing a required field is left in place rather than
  /// silently dropped, matching the portal's own filter-then-insert rule.
  Future<void> _saveAllDrafts() async {
    final savable = _drafts.where((d) => d.isSavable).toList();
    if (savable.isEmpty) return;

    setState(() => _savingAll = true);
    try {
      final saved = await _inventory.createUnits(
        projectId: widget.project.id,
        payloads: [for (final d in savable) d.payload],
      );
      if (!mounted) return;
      _changed = true;
      setState(() {
        _units = [..._units, ...saved];
        _drafts.removeWhere(savable.contains);
        _savingAll = false;
      });
      _toast('${saved.length} ${saved.length == 1 ? 'unit' : 'units'} added.');
    } catch (_) {
      if (mounted) setState(() => _savingAll = false);
      _toast('Could not save the new units. Please try again.', isError: true);
    }
  }

  /// Keeps the listing's own `total_units`/`available_units` truthful before
  /// handing control back — see [ProjectService.syncTotalsFromInventory]'s
  /// own doc comment for why this belongs here rather than being invisible
  /// until the next time someone happens to re-open Edit Project.
  Future<void> _popAndSync() async {
    if (_changed) {
      await _projects.syncTotalsFromInventory(
        projectId: widget.project.id,
        builderId: widget.project.builderId,
      );
    }
    if (mounted) Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    final savableDraftCount = _drafts.where((d) => d.isSavable).length;

    return PopScope(
      // Intercepts every dismissal path (AppBar back arrow, system back
      // gesture) so the caller reliably gets `_changed` back regardless of
      // which one the user used — see `_changed`'s own doc comment.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popAndSync();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(widget.project.title, style: AppTextStyles.heading3),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacingL,
                AppConstants.spacingM,
                AppConstants.spacingL,
                AppConstants.spacingS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TallyRow(units: _units),
                  const SizedBox(height: AppConstants.spacingM),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addBlankDraft,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Row'),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingM),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _prefillFromListing,
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 18,
                          ),
                          label: const Text('Pre-fill from Listing'),
                        ),
                      ),
                    ],
                  ),
                  if (widget.project.totalUnits > 0) ...[
                    const SizedBox(height: AppConstants.spacingS),
                    Text(
                      'Listing: ${_units.length}/${widget.project.totalUnits} units added',
                      style: AppTextStyles.caption,
                    ),
                  ],
                  if (savableDraftCount > 0) ...[
                    const SizedBox(height: AppConstants.spacingM),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _savingAll ? null : _saveAllDrafts,
                        child: _savingAll
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Save All New ($savableDraftCount)'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            Expanded(child: _buildList(context)),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addUnit,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Checked before `_error`, not after: a failed load must not hide drafts
    // the builder has since pre-filled or added by hand — those live only in
    // this screen's own state, not in whatever request failed, and a builder
    // who wants to add units from scratch should not be blocked by a listing
    // read that happened to fail first.
    if (_units.isEmpty && _drafts.isEmpty) {
      if (_error != null) {
        return TeamTabErrorState(message: _error!, onRetry: _load);
      }
      return const TeamTabEmptyState(message: 'No units yet.');
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingL,
          AppConstants.spacingM,
          AppConstants.spacingL,
          88,
        ),
        itemCount: _drafts.length + _units.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.spacingM),
        itemBuilder: (context, index) {
          if (index < _drafts.length) {
            final draft = _drafts[index];
            return _DraftCard(
              draft: draft,
              busy: _busyId == draft.tempId,
              onTap: () => _editDraft(draft),
              onSave: () => _saveDraft(draft),
              onDiscard: () => _discardDraft(draft),
            );
          }
          final unit = _units[index - _drafts.length];
          return _UnitCard(
            unit: unit,
            busy: _busyId == unit.id,
            onEdit: () => _editUnit(unit),
            onDelete: () => _deleteUnit(unit),
          );
        },
      ),
    );
  }
}

/// "Total | Available | Sold" — `ProjectInventoryManager.tsx`'s own tally
/// strip, computed from the same rows this screen already loaded rather than
/// a second query.
class _TallyRow extends StatelessWidget {
  const _TallyRow({required this.units});

  final List<InventoryUnit> units;

  @override
  Widget build(BuildContext context) {
    final total = units.length;
    final available = units.where((u) => u.status == 'available').length;
    final sold = units.where((u) => u.status == 'sold').length;

    Widget stat(String label, int value) => Expanded(
      child: Column(
        children: [
          Text('$value', style: AppTextStyles.heading2.copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Row(
        children: [
          stat('Total', total),
          const _TallyDivider(),
          stat('Available', available),
          const _TallyDivider(),
          stat('Sold', sold),
        ],
      ),
    );
  }
}

class _TallyDivider extends StatelessWidget {
  const _TallyDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 28,
    child: VerticalDivider(color: AppColors.hairline),
  );
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({
    required this.unit,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final InventoryUnit unit;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
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
                child: Text(
                  unit.unitNumber?.isNotEmpty == true
                      ? '${unit.unitType} · ${unit.unitNumber}'
                      : unit.unitType,
                  style: AppTextStyles.heading3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  inventoryUnitStatusLabel(unit.status),
                  style: AppTextStyles.chip.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingS),
          Text(
            '${unit.areaSqft.toStringAsFixed(0)} sqft'
            '${unit.floorNumber != null ? ' · Floor ${unit.floorNumber}' : ''}'
            ' · ₹${unit.price.toStringAsFixed(0)}'
            '${unit.facingDirection != null ? ' · ${unit.facingDirection} facing' : ''}',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (busy)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A not-yet-saved row from "+ Add Row" or "Pre-fill from Listing" —
/// `InventoryTableEditor.tsx`'s `newRows`. Tapping it opens the same form a
/// saved unit edits; the check/discard pair is this row's own ✓/✗.
class _DraftCard extends StatelessWidget {
  const _DraftCard({
    required this.draft,
    required this.busy,
    required this.onTap,
    required this.onSave,
    required this.onDiscard,
  });

  final _DraftUnit draft;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'NEW',
                          style: AppTextStyles.chip.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          draft.unitType.isEmpty
                              ? 'Tap to fill in this unit'
                              : (draft.unitNumber?.isNotEmpty == true
                                    ? '${draft.unitType} · ${draft.unitNumber}'
                                    : draft.unitType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (draft.areaSqft > 0 || draft.price > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${draft.areaSqft.toStringAsFixed(0)} sqft · ₹${draft.price.toStringAsFixed(0)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              IconButton(
                onPressed: onSave,
                icon: const Icon(Icons.check_circle_outline),
                color: AppColors.success,
                tooltip: 'Save this unit',
              ),
              IconButton(
                onPressed: onDiscard,
                icon: const Icon(Icons.cancel_outlined),
                color: AppColors.error,
                tooltip: 'Discard',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add/Edit form. Returns the payload to write, or `null` on cancel.
class _UnitFormSheet extends StatefulWidget {
  const _UnitFormSheet({this.existing, required this.projectType});

  final InventoryUnit? existing;

  /// `builder_projects.project_type` — selects which suggestion chips
  /// [unitTypeOptionsFor] offers above the unit type field.
  final String projectType;

  @override
  State<_UnitFormSheet> createState() => _UnitFormSheetState();
}

class _UnitFormSheetState extends State<_UnitFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unitType;
  late final TextEditingController _unitNumber;
  late final TextEditingController _floorNumber;
  late final TextEditingController _areaSqft;
  late final TextEditingController _price;
  late String _status;
  late String? _facing;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _unitType = TextEditingController(text: existing?.unitType ?? '');
    _unitNumber = TextEditingController(text: existing?.unitNumber ?? '');
    _floorNumber = TextEditingController(
      text: existing?.floorNumber?.toString() ?? '',
    );
    _areaSqft = TextEditingController(
      text: existing != null && existing.areaSqft > 0
          ? existing.areaSqft.toString()
          : '',
    );
    _price = TextEditingController(
      text: existing != null && existing.price > 0
          ? existing.price.toString()
          : '',
    );
    _status = existing?.status ?? 'available';
    _facing = existing?.facingDirection;
  }

  @override
  void dispose() {
    _unitType.dispose();
    _unitNumber.dispose();
    _floorNumber.dispose();
    _areaSqft.dispose();
    _price.dispose();
    super.dispose();
  }

  /// A plot has no floor — `isPlotUnitType` — so the field is hidden rather
  /// than shown for a value it can never meaningfully hold.
  bool get _showsFloor => !isPlotUnitType(_unitType.text.trim());

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(<String, dynamic>{
      'unit_type': _unitType.text.trim(),
      'unit_number': _unitNumber.text.trim().isEmpty
          ? null
          : _unitNumber.text.trim(),
      'floor_number': !_showsFloor || _floorNumber.text.trim().isEmpty
          ? null
          : int.tryParse(_floorNumber.text.trim()),
      'area_sqft': double.tryParse(_areaSqft.text.trim()) ?? 0,
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'status': _status,
      'facing_direction': _facing,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final suggestions = unitTypeOptionsFor(widget.projectType);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppConstants.spacingL,
          AppConstants.spacingM,
          AppConstants.spacingL,
          AppConstants.spacingXL,
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEdit ? 'Edit Unit' : 'Add Unit',
                    style: AppTextStyles.heading3,
                  ),
                  const SizedBox(height: AppConstants.spacingL),
                  TextFormField(
                    controller: _unitType,
                    decoration: const InputDecoration(labelText: 'Unit type'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  // A free VARCHAR column, not a fixed set — these are
                  // suggestions to tap into the field above, never a
                  // constraint on what it may hold.
                  const SizedBox(height: AppConstants.spacingS),
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: suggestions.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) => ActionChip(
                        label: Text(suggestions[i]),
                        labelStyle: AppTextStyles.chip.copyWith(fontSize: 11.5),
                        onPressed: () => setState(() {
                          _unitType.text = suggestions[i];
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  TextFormField(
                    controller: _unitNumber,
                    decoration: const InputDecoration(
                      labelText: 'Unit number (optional)',
                    ),
                  ),
                  if (_showsFloor) ...[
                    const SizedBox(height: AppConstants.spacingM),
                    TextFormField(
                      controller: _floorNumber,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Floor (optional)',
                      ),
                    ),
                  ],
                  const SizedBox(height: AppConstants.spacingM),
                  TextFormField(
                    controller: _areaSqft,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Area (sqft)'),
                    validator: (v) =>
                        (double.tryParse(v?.trim() ?? '') ?? 0) > 0
                        ? null
                        : 'Enter a valid area',
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Price'),
                    validator: (v) =>
                        (double.tryParse(v?.trim() ?? '') ?? 0) > 0
                        ? null
                        : 'Enter a valid price',
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final option in kInventoryUnitStatusOptions)
                        DropdownMenuItem(
                          value: option.value,
                          child: Text(option.label),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _status = value ?? _status),
                  ),
                  const SizedBox(height: AppConstants.spacingM),
                  DropdownButtonFormField<String?>(
                    initialValue: _facing,
                    decoration: const InputDecoration(
                      labelText: 'Facing (optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Not specified'),
                      ),
                      for (final option in kInventoryFacingOptions)
                        DropdownMenuItem<String?>(
                          value: option,
                          child: Text(option),
                        ),
                    ],
                    onChanged: (value) => setState(() => _facing = value),
                  ),
                  const SizedBox(height: AppConstants.spacingXL),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: Text(isEdit ? 'Save Changes' : 'Add Unit'),
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
