import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/property_status_options.dart';
import '../../core/theme/app_colors.dart';
import '../../models/property_model.dart';
import '../../services/property_service.dart';
import '../post_property/post_property_screen.dart';

// ── Brand palette (mirrors every other dashboard screen) ──────────────────────
class _Brand {
  static const Color c2 = AppColors.primary;
  static const Color c4 = Color(0xFFC2410C);
}

/// A self-contained "My Listings" section for use inside any dashboard screen.
///
/// Fetches properties for [userId] from the `properties` table, renders them as
/// cards with View, Edit, Delete and an inline status picker. Does not require a
/// provider in the widget tree — state is managed locally via [PropertyService]
/// calls.
///
/// The website's counterpart is `BrokerContentManager.tsx`, which this matches
/// action for action: the same `.eq('user_id').order('created_at', desc)` fetch,
/// the same hard delete behind a confirm, edit via the wizard's edit mode, and a
/// status control offering `active` and `sold` only. The website has no share
/// action here, so neither does this.
class MyListingsSection extends StatefulWidget {
  final String userId;

  /// Reports how many listings this section is showing, after every change.
  ///
  /// Added so a parent can collapse the whole block — its heading included —
  /// when a user has no listings at all. The builder dashboard needs that: a
  /// builder publishes projects, not listings, so the section is empty for
  /// everyone except the few who have legacy rows.
  ///
  /// Optional, and nothing else here changed. Fires on a successful load and
  /// after a delete, never on a failure — a failed fetch is not an empty list,
  /// and a parent that hid the section on error would swallow the retry.
  final ValueChanged<int>? onCountChanged;

  /// Injected by tests so the fetch, the status write and the delete can be
  /// exercised without a database. Production always builds a real service, and
  /// nothing else about this widget changed to accommodate it.
  @visibleForTesting
  final PropertyService? serviceOverride;

  const MyListingsSection({
    required this.userId,
    this.onCountChanged,
    this.serviceOverride,
    super.key,
  });

  @override
  State<MyListingsSection> createState() => _MyListingsSectionState();
}

class _MyListingsSectionState extends State<MyListingsSection> {
  bool _loading = false;
  List<PropertyModel> _properties = [];
  String? _error;

  late final PropertyService _service =
      widget.serviceOverride ?? PropertyService();

  /// The listing whose status write is in flight, so its picker can be disabled
  /// (BrokerContentManager.tsx's `updatingStatus === property.id`).
  String? _updatingStatusFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Publishes the current count to [MyListingsSection.onCountChanged].
  ///
  /// Called after the state is committed, so a parent that collapses on zero
  /// reads the same number this widget is about to render.
  void _reportCount() => widget.onCountChanged?.call(_properties.length);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _service.getPropertiesByUser(widget.userId);
      if (mounted) {
        setState(() {
          _properties = results;
          _loading = false;
        });
        _reportCount();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditScreen(PropertyModel property) async {
    PropertyEditBundle bundle;
    try {
      bundle = await _service.fetchForEdit(property.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load property for editing: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    if (!mounted) return;
    final refreshNeeded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PostPropertyScreen(editPropertyId: property.id, editBundle: bundle),
      ),
    );

    if (refreshNeeded == true && mounted) await _load();
  }

  Future<void> _showDeleteDialog(PropertyModel property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Property'),
        content: const Text(
          'Are you sure you want to delete this property? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteProperty(property.id);
      if (mounted) {
        setState(() {
          _properties = _properties.where((p) => p.id != property.id).toList();
        });
        // This path prunes the list locally rather than re-fetching, so without
        // this the count would go stale and deleting the last listing would
        // leave an empty section on screen instead of collapsing it.
        _reportCount();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Property deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Writes one listing's new status, then reflects it locally.
  ///
  /// Mirrors BrokerContentManager.tsx:85-112: optimism is deliberately avoided —
  /// the row is only recoloured after the write returns, so a rejected update
  /// never leaves the card claiming a status the database does not hold. The list
  /// is patched in place rather than re-fetched for the same reason the delete
  /// path prunes locally: a re-fetch would reorder nothing but would blank the
  /// section for a frame.
  Future<void> _setStatus(PropertyModel property, String status) async {
    if (status == property.status) return;

    setState(() => _updatingStatusFor = property.id);
    try {
      await _service.setPropertyStatus(property.id, status);
      if (!mounted) return;
      setState(() {
        _properties = _properties
            .map((p) => p.id == property.id ? p.copyWith(status: status) : p)
            .toList();
        _updatingStatusFor = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Marked as ${propertyStatusLabel(status).toLowerCase()}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingStatusFor = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update status: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// Opens the public listing page — what the card's View button always implied.
  void _openDetail(PropertyModel property) {
    Navigator.pushNamed(
      context,
      AppConstants.propertyDetailScreen,
      arguments: {'propertyId': property.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(color: _Brand.c2),
        ),
      );
    }

    if (_error != null) {
      return _ErrorState(onRetry: _load, message: _error!);
    }

    if (_properties.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _properties.length,
      itemBuilder: (_, index) {
        final property = _properties[index];
        return _PropertyCard(
          property: property,
          onEdit: () => _openEditScreen(property),
          onDelete: () => _showDeleteDialog(property),
          onView: () => _openDetail(property),
          onStatusChanged: (status) => _setStatus(property, status),
          statusBusy: _updatingStatusFor == property.id,
        );
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _Brand.c2.withOpacity(0.12),
                  _Brand.c4.withOpacity(0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.home_work_outlined,
              size: 32,
              color: _Brand.c2.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No property listings yet.",
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1C1530),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the Post Property wizard to publish your first listing.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withOpacity(0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;

  const _ErrorState({required this.onRetry, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load listings.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.red.shade600),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Property Card ─────────────────────────────────────────────────────────────

class _PropertyCard extends StatelessWidget {
  final PropertyModel property;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final ValueChanged<String> onStatusChanged;
  final bool statusBusy;

  const _PropertyCard({
    required this.property,
    required this.onEdit,
    required this.onDelete,
    required this.onView,
    required this.onStatusChanged,
    required this.statusBusy,
  });

  static String _formatDate(DateTime? dt) {
    if (dt == null) return '';
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

  // `rented` was missing here and fell through to the amber "Pending" case, so a
  // rented listing read as unreviewed. The label now comes from
  // propertyStatusLabel, which covers all four CHECK values.
  Color _statusColor(String? status) => switch (status) {
    'active' => Colors.green,
    'sold' => Colors.blue,
    'rented' => Colors.teal,
    'inactive' => Colors.grey,
    _ => Colors.amber,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final coverUrl = property.resolvedImageUrls.isNotEmpty
        ? property.resolvedImageUrls.first
        : null;
    final statusColor = _statusColor(property.status);
    final statusLabel = propertyStatusLabel(property.status);
    final category = (property.category ?? 'Property')
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withOpacity(0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover image ────────────────────────────────────────────────────
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: coverUrl != null
                  ? Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Category + Status ──────────────────────────────────────
                //
                // The status half is a control, not a label, whenever the owner
                // is allowed to change it — the website puts an inline Select in
                // the same cell (BrokerContentManager.tsx:334-347). Statuses the
                // owner did not set (`inactive`, `rented`) stay a plain badge:
                // offering a two-item picker there would make Active the only way
                // out of a state the owner never chose.
                Row(
                  children: [
                    // Flexible so the pair cannot overflow whatever the column
                    // holds: `category` is rendered verbatim after underscore
                    // expansion, and the picker beside it grows with the text
                    // scale.
                    Flexible(
                      child: _badge(
                        textTheme,
                        label: category,
                        bg: _Brand.c2.withOpacity(0.1),
                        fg: _Brand.c2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isOwnerSettableStatus(property.status))
                      Flexible(
                        child: _StatusPicker(
                          value: property.status ?? 'active',
                          color: statusColor,
                          busy: statusBusy,
                          onChanged: onStatusChanged,
                        ),
                      )
                    else
                      _badge(
                        textTheme,
                        label: statusLabel,
                        bg: statusColor.withOpacity(0.12),
                        fg: statusColor,
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── Title ──────────────────────────────────────────────────
                Text(
                  property.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1530),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Price ──────────────────────────────────────────────────
                Text(
                  property.priceDisplay,
                  style: textTheme.titleSmall?.copyWith(
                    color: _Brand.c2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Location ───────────────────────────────────────────────
                if (property.location.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: scheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          property.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),

                // ── Created date ───────────────────────────────────────────
                if (property.createdAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: scheme.onSurface.withOpacity(0.4),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(property.createdAt),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withOpacity(0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // ── Action buttons ─────────────────────────────────────────
                Row(
                  children: [
                    _ActionButton(
                      label: 'View',
                      icon: Icons.open_in_new_rounded,
                      color: _Brand.c2,
                      onTap: onView,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      color: Colors.orange,
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      label: 'Delete',
                      icon: Icons.delete_outline_rounded,
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(
    TextTheme textTheme, {
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFEEECF8),
      child: const Center(
        child: Icon(
          Icons.home_work_outlined,
          size: 48,
          color: Color(0xFFBBB6E0),
        ),
      ),
    );
  }
}

// ── Status picker ─────────────────────────────────────────────────────────────

/// The status badge, made tappable.
///
/// Shaped like the badge it replaces — same padding, radius, tint and type scale
/// — so the card's header row is unchanged at a glance and only gains a caret.
/// A [DropdownButton] was not used: its own chrome, minimum height and menu
/// alignment would all have to be fought back to badge size, and it asserts when
/// `value` is absent from `items`, which is exactly the `inactive` / `rented` case
/// the caller already routes around.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({
    required this.value,
    required this.color,
    required this.busy,
    required this.onChanged,
  });

  final String value;
  final Color color;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = propertyStatusLabel(value);

    return Semantics(
      button: true,
      // Read out as a control rather than as a state, so the caret is not the
      // only cue that this can be changed.
      label: 'Listing status, $label. Tap to change.',
      child: PopupMenuButton<String>(
        // Nulling this is what disables the button while a write is in flight.
        enabled: !busy,
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final option in propertyStatusOptions)
            PopupMenuItem<String>(
              value: option.value,
              child: Row(
                children: [
                  Icon(
                    option.value == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: option.value == value ? _Brand.c2 : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Text(option.label),
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: busy ? 0.06 : 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: busy ? color.withValues(alpha: 0.45) : color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              if (busy)
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: color.withValues(alpha: 0.6),
                  ),
                )
              else
                Icon(Icons.expand_more_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final effectiveColor = disabled ? Colors.grey.shade400 : color;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: effectiveColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: effectiveColor.withOpacity(disabled ? 0.2 : 0.3),
            ),
          ),
          // Three of these share the card's width, so at 320 dp each gets about
          // 89 dp — 2.8 dp short of "Delete" at the default text scale, and much
          // shorter once the text is scaled up. Scaling down beats ellipsising an
          // action label to "Dele…", and matches how the sibling projects
          // section handles the identical row.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: effectiveColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
