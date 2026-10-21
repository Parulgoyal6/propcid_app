import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../services/builder_sections_service.dart';
import '../../../services/project_service.dart';
import 'team_tab_states.dart';

/// The Team Workspace's Site Visits tab.
///
/// Mirrors `SiteVisitBookingsManager.tsx` scoped to [allowedProjectIds] — null
/// means every one of [builderId]'s projects, the same convention every other
/// scoped tab uses. `project_visit_bookings` has no `builder_id` column, so —
/// exactly as the portal does (`:114-141`) — the allowed project id list is
/// resolved first, and bookings are fetched by that list.
///
/// Full parity with the portal's manager: project filter, status filter, and
/// an edit sheet carrying all three fields it edits — date, time and status
/// (`:160-172`) — not status alone. `SiteVisitService` already supports all
/// of this (`builder_sections_service.dart:533-536` — built with this screen
/// in mind); only the UI needed upgrading.
///
/// The one thing deliberately not ported: the portal's Supabase Realtime
/// subscription (`:87-105`) that silently refetches on any change to
/// `project_visit_bookings`. Pull-to-refresh covers the same need without a
/// persistent channel — a disclosed simplification, not a missing action a
/// team member can take.
class TeamSiteVisitsTab extends StatefulWidget {
  const TeamSiteVisitsTab({
    super.key,
    required this.builderId,
    required this.allowedProjectIds,
  });

  final String builderId;

  /// Null ⇒ unrestricted (every project of [builderId]'s).
  final List<String>? allowedProjectIds;

  @override
  State<TeamSiteVisitsTab> createState() => _TeamSiteVisitsTabState();
}

class _TeamSiteVisitsTabState extends State<TeamSiteVisitsTab> {
  final ProjectService _projects = ProjectService();
  final SiteVisitService _visits = SiteVisitService();

  bool _loading = true;
  String? _error;
  List<ProjectModel> _visibleProjects = const [];
  List<SiteVisitBooking> _bookings = const [];
  String? _busyBookingId;

  /// `null` ⇒ "All Projects" (`SiteVisitBookingsManager.tsx:72`, `filterProject`).
  String? _projectFilter;

  /// `null` ⇒ "All Statuses" (`:73`, `filterStatus`).
  String? _statusFilter;

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

      final bookings = await _visits.listForProjects(
        visible.map((p) => p.id).toList(),
      );

      if (!mounted) return;
      setState(() {
        _visibleProjects = visible;
        _bookings = bookings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load site visits. Please try again.';
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

  String _titleFor(String projectId) {
    for (final project in _visibleProjects) {
      if (project.id == projectId) return project.title;
    }
    return 'Unknown Project';
  }

  Future<void> _call(SiteVisitBooking booking) async {
    final uri = Uri(scheme: 'tel', path: booking.visitorPhone);
    if (!await launchUrl(uri)) {
      _toast('Could not open the dialler.', isError: true);
    }
  }

  Future<void> _edit(SiteVisitBooking booking) async {
    final result = await showModalBottomSheet<_VisitEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditVisitSheet(
        booking: booking,
        projectTitle: _titleFor(booking.projectId),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busyBookingId = booking.id);
    try {
      await _visits.updateBooking(
        booking: booking,
        preferredDate: result.date,
        preferredTime: result.time,
        status: result.status,
        projectTitle: _titleFor(booking.projectId),
      );
      if (!mounted) return;
      setState(() {
        _bookings = _bookings
            .map(
              (b) => b.id == booking.id
                  ? b.copyWith(
                      preferredDate: result.date,
                      preferredTime: result.time,
                      status: result.status,
                    )
                  : b,
            )
            .toList();
      });
      _toast(
        kNotifyingSiteVisitStatuses.contains(result.status)
            ? 'Booking updated. The visitor has been notified.'
            : 'Booking updated.',
      );
    } catch (_) {
      _toast('Could not update that booking. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyBookingId = null);
    }
  }

  List<SiteVisitBooking> get _filtered {
    return _bookings.where((b) {
      if (_projectFilter != null && b.projectId != _projectFilter) return false;
      if (_statusFilter != null && b.status != _statusFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return TeamTabErrorState(message: _error!, onRetry: _load);
    }

    final filtered = _filtered;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        children: [
          Text(
            '${filtered.length} booking${filtered.length != 1 ? 's' : ''}',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          _ProjectFilterRow(
            projects: _visibleProjects,
            selected: _projectFilter,
            onChanged: (value) => setState(() => _projectFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingS),
          _StatusFilterRow(
            selected: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingL),
          if (filtered.isEmpty)
            TeamTabEmptyState(
              message: _bookings.isEmpty
                  ? 'No site visit requests have been made yet.'
                  : 'No bookings match the selected filters.',
            )
          else
            for (final booking in filtered) ...[
              _BookingCard(
                booking: booking,
                projectTitle: _titleFor(booking.projectId),
                busy: _busyBookingId == booking.id,
                onCall: () => _call(booking),
                onEdit: () => _edit(booking),
              ),
              const SizedBox(height: AppConstants.spacingM),
            ],
        ],
      ),
    );
  }
}

/// "All Projects" plus one entry per project actually in scope.
class _ProjectFilterRow extends StatelessWidget {
  const _ProjectFilterRow({
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<ProjectModel> projects;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (projects.length <= 1) return const SizedBox.shrink();

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('All Projects')),
        for (final project in projects)
          DropdownMenuItem(value: project.id, child: Text(project.title)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Horizontally scrollable status chips, with "All" first — the same pattern
/// `BuilderSiteVisitsSection`'s own filter uses.
class _StatusFilterRow extends StatelessWidget {
  const _StatusFilterRow({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String? value) {
      final active = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            ),
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.primary,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Row(
        children: [
          chip('All', null),
          for (final option in kSiteVisitStatusOptions)
            chip(option.label, option.value),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.projectTitle,
    required this.busy,
    required this.onCall,
    required this.onEdit,
  });

  final SiteVisitBooking booking;
  final String projectTitle;
  final bool busy;
  final VoidCallback onCall;
  final VoidCallback onEdit;

  static Color _tint(String status) => switch (status) {
    'pending' => AppColors.warning,
    'confirmed' => AppColors.success,
    'completed' => AppColors.primary,
    'cancelled' => AppColors.error,
    'rescheduled' => AppColors.statusNewLaunch,
    _ => AppColors.textHint,
  };

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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.visitorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      projectTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _tint(booking.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  siteVisitStatusLabel(booking.status),
                  style: AppTextStyles.chip.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _tint(booking.status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Meta(
                icon: Icons.event_outlined,
                label: _formatDate(booking.preferredDate),
              ),
              if (booking.preferredTime != null &&
                  booking.preferredTime!.isNotEmpty)
                _Meta(
                  icon: Icons.schedule_outlined,
                  label: booking.preferredTime!,
                ),
              if (booking.isPast && booking.status == 'pending')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Date passed',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          if (booking.message != null && booking.message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              booking.message!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ],
          if (booking.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Requested on ${_formatDate(booking.createdAt!)}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ],
          const SizedBox(height: AppConstants.spacingM),
          const Divider(height: 1, color: AppColors.hairline),
          const SizedBox(height: 6),
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
                  child: TextButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 16),
                    label: const Text('Call'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                    label: const Text('Update'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textHint),
        const SizedBox(width: 4),
        Text(label, style: AppTextStyles.caption.copyWith(fontSize: 11.5)),
      ],
    );
  }
}

/// What the edit sheet hands back.
class _VisitEdit {
  const _VisitEdit({
    required this.date,
    required this.time,
    required this.status,
  });

  final DateTime date;
  final String? time;
  final String status;
}

/// Date, time and status — the three fields the portal's edit dialog carries
/// (`SiteVisitBookingsManager.tsx:160-172`), and no others.
class _EditVisitSheet extends StatefulWidget {
  const _EditVisitSheet({required this.booking, required this.projectTitle});

  final SiteVisitBooking booking;
  final String projectTitle;

  @override
  State<_EditVisitSheet> createState() => _EditVisitSheetState();
}

class _EditVisitSheetState extends State<_EditVisitSheet> {
  late DateTime _date = widget.booking.preferredDate;
  late final TextEditingController _time = TextEditingController(
    text: widget.booking.preferredTime ?? '',
  );
  late String _status = widget.booking.status;

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // A booking can legitimately be rescheduled into the past — marking a
      // visit that already happened as completed is the common case — so
      // the range is wide in both directions rather than future-only.
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    Navigator.of(context).pop(
      _VisitEdit(
        date: _date,
        time: _time.text.trim().isEmpty ? null : _time.text.trim(),
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Update Site Visit',
              style: AppTextStyles.heading2.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.booking.visitorName} · ${widget.projectTitle}',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 18),
            Text('Date', style: AppTextStyles.body.copyWith(fontSize: 12.5)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_date.year}-${_date.month.toString().padLeft(2, '0')}'
                      '-${_date.day.toString().padLeft(2, '0')}',
                      style: AppTextStyles.body.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Time', style: AppTextStyles.body.copyWith(fontSize: 12.5)),
            const SizedBox(height: 6),
            TextField(
              controller: _time,
              // Free text, because the column is `preferred_time TEXT` and
              // the portal's own input is a plain text field — a time picker
              // would impose a format existing rows do not follow.
              decoration: InputDecoration(
                hintText: 'e.g. 11:00 AM — optional',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.hairline),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Status', style: AppTextStyles.body.copyWith(fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in kSiteVisitStatusOptions)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _status == option.value,
                    onSelected: (_) => setState(() => _status = option.value),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
