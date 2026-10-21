// screens/dashboard/widgets/builder_site_visits_section.dart
//
// Site Visits on the builder dashboard's Content tab.
//
// THE ONE INFERENCE IN SPEC H
// ---------------------------
// `SiteVisitBookingsManager` (the incoming-bookings manager this section is
// transcribed from) is mounted on `TeamMemberDashboard` only, for members
// holding the `site_visits` module. The builder's own dashboard's real
// "Visits" tab renders something else entirely — `MyVisitRequests`
// (`BuilderDashboardManage.tsx:809-815`), a read-only list of visit requests
// the builder made *as a visitor* to other people's listings, with no
// confirm/reschedule/cancel action at all. It is not a management screen and
// has nothing in common with this one beyond the word "visits" — this
// section does not port it and is not meant to.
//
// This section is therefore an extension, not a port of anything the
// builder's own dashboard shows today. It is a sound one: 20260304164434:30-49
// already grants a builder SELECT **and** UPDATE on bookings for their own
// projects, so the permission exists and only the screen was missing. A
// builder could grant a team member the power to confirm their site visits
// while having no way to confirm one themselves, which is not a rule anyone
// chose.
//
// Everything it does is transcribed from `SiteVisitBookingsManager.tsx`: the
// same query scope, the same five statuses, the same update payload, the
// same project + status filters, and the same rule about which status
// changes notify the visitor (now including the project id that notification
// deep-links to, matching the portal's current edge-function-backed
// behaviour rather than the client-side helper this was first written
// against).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../models/project_model.dart';
import '../../../services/builder_sections_service.dart';
import 'builder_section_kit.dart';

class BuilderSiteVisitsSection extends StatefulWidget {
  const BuilderSiteVisitsSection({
    super.key,
    required this.projectIds,
    required this.projectTitles,
    this.projects = const [],
    this.onCountChanged,
    this.service,
  });

  /// The builder's project ids — the scope of the query.
  ///
  /// `project_visit_bookings` has no builder column, so the project list *is* the
  /// filter. Supplied by the parent, which already loaded the projects for the
  /// Inventory section: fetching them twice would be a second identical query.
  final List<String> projectIds;

  /// Project id → title, for the card subtitle and the notification copy.
  ///
  /// The portal resolves the same way (`getProjectTitle`) from a list it already
  /// holds.
  final Map<String, String> projectTitles;

  /// The same project rows, for the project filter dropdown —
  /// `SiteVisitBookingsManager.tsx:198-209`'s project filter, which this
  /// section was previously missing even though `TeamSiteVisitsTab`'s own
  /// copy of this screen already has it. Optional/defaults to empty so every
  /// existing caller keeps compiling unchanged; `_ProjectFilterRow` hides
  /// itself for 0 or 1 project regardless, so an empty default never
  /// regresses the common one-project case.
  final List<ProjectModel> projects;

  final ValueChanged<int>? onCountChanged;

  @visibleForTesting
  final SiteVisitService? service;

  @override
  State<BuilderSiteVisitsSection> createState() =>
      _BuilderSiteVisitsSectionState();
}

class _BuilderSiteVisitsSectionState extends State<BuilderSiteVisitsSection> {
  late final SiteVisitService _visits = widget.service ?? SiteVisitService();

  List<SiteVisitBooking>? _items;
  bool _failed = false;
  String? _busyBookingId;

  /// `null` means "All"; otherwise one of the five statuses.
  ///
  /// `SiteVisitBookingsManager.tsx:203` filters client-side over the already
  /// fetched list, which is what this does — a filter change costs no query.
  String? _statusFilter;

  /// `null` means "All Projects" (`SiteVisitBookingsManager.tsx:72`,
  /// `filterProject`) — same client-side-filter approach as [_statusFilter].
  String? _projectFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BuilderSiteVisitsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent discovers project ids asynchronously, so this widget is first
    // built with an empty list and then rebuilt with the real one. Without this
    // the section would stay permanently empty.
    if (!_sameIds(oldWidget.projectIds, widget.projectIds)) _load();
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reportCount() => widget.onCountChanged?.call(_items?.length ?? 0);

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _visits.listForProjects(widget.projectIds);
      if (!mounted) return;
      setState(() => _items = rows);
      _reportCount();
    } catch (e) {
      if (!mounted) return;
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

  String _titleFor(String projectId) =>
      widget.projectTitles[projectId] ?? 'Unknown Project';

  Future<void> _call(SiteVisitBooking booking) async {
    final uri = Uri(scheme: 'tel', path: booking.visitorPhone);
    if (!await launchUrl(uri)) {
      _toast('Could not open the dialler.', isError: true);
    }
  }

  /// Opens the edit sheet, then writes whatever came back.
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
        _items = _items
            ?.map(
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
            // Worth saying: the builder should know the visitor was told.
            ? 'Booking updated. The visitor has been notified.'
            : 'Booking updated.',
      );
    } catch (e) {
      _toast('Could not update that booking. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyBookingId = null);
    }
  }

  List<SiteVisitBooking> get _visible {
    var result = _items ?? const <SiteVisitBooking>[];
    final project = _projectFilter;
    if (project != null) {
      result = result.where((b) => b.projectId == project).toList();
    }
    final status = _statusFilter;
    if (status != null) {
      result = result.where((b) => b.status == status).toList();
    }
    return result;
  }

  /// Names whichever filter(s) actually narrowed the list to nothing, rather
  /// than always blaming the status filter — reachable now that a project
  /// filter alone can also produce an empty result.
  String _emptyFilterMessage() {
    final status = _statusFilter;
    final project = _projectFilter;
    if (project != null) {
      final title = _titleFor(project);
      return status != null
          ? 'No ${siteVisitStatusLabel(status).toLowerCase()} bookings for '
                '$title.'
          : 'No bookings for $title.';
    }
    return 'No ${siteVisitStatusLabel(status).toLowerCase()} bookings.';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final visible = _visible;

    return BuilderSectionShell(
      failed: _failed,
      loaded: items != null,
      isEmpty: items?.isEmpty ?? false,
      onRetry: _load,
      errorTitle: "Couldn't load site visits",
      // No create action exists for bookings — a visitor makes them — so an empty
      // section has to explain itself rather than vanish.
      emptyMessage: widget.projectIds.isEmpty
          ? 'Site visit bookings appear here once you publish a project.'
          : 'No site visits booked yet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProjectFilterRow(
            projects: widget.projects,
            selected: _projectFilter,
            onChanged: (value) => setState(() => _projectFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingS),
          _StatusFilterRow(
            selected: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingM),
          // A filter that hides everything is not an empty section — the bookings
          // are still there, so the shell's collapse must not apply.
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(_emptyFilterMessage(), style: AppTextStyles.caption),
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingM),
              _VisitCard(
                booking: visible[i],
                projectTitle: _titleFor(visible[i].projectId),
                busy: _busyBookingId == visible[i].id,
                onCall: () => _call(visible[i]),
                onEdit: () => _edit(visible[i]),
              ),
            ],
        ],
      ),
    );
  }
}

/// "All Projects" plus one entry per project actually in scope. Mirrors
/// `TeamSiteVisitsTab`'s own `_ProjectFilterRow`
/// (`SiteVisitBookingsManager.tsx:198-209`'s project filter) — duplicated
/// rather than shared, same as `_StatusFilterRow` already is between the two
/// files.
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

/// Horizontally scrollable status chips, with "All" first.
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

class _VisitCard extends StatelessWidget {
  const _VisitCard({
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
    return BuilderSectionCard(
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
              BuilderPill(
                label: siteVisitStatusLabel(booking.status),
                tint: _tint(booking.status),
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
              if (booking.preferredTime != null)
                _Meta(
                  icon: Icons.schedule_outlined,
                  label: booking.preferredTime!,
                ),
              // Only when it matters: every past booking would otherwise carry a
              // warning chip, including ones already completed.
              if (booking.isPast && booking.status == 'pending')
                const BuilderPill(label: 'Date passed', tint: AppColors.error),
            ],
          ),
          if (booking.message != null) ...[
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
            const BuilderActionBusyRow()
          else
            Row(
              children: [
                Expanded(
                  child: BuilderAction(
                    icon: Icons.call_outlined,
                    label: 'Call',
                    onTap: onCall,
                  ),
                ),
                Expanded(
                  child: BuilderAction(
                    icon: Icons.edit_calendar_outlined,
                    label: 'Update',
                    onTap: onEdit,
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
      // A booking can legitimately be rescheduled into the past — marking a visit
      // that already happened as completed is the common case — so the range is
      // wide in both directions rather than future-only.
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
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
              'Update Booking',
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
              // Free text, because the column is: `preferred_time TEXT`, and the
              // portal's own input is a plain text field. A time picker would
              // impose a format the existing rows do not follow.
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
                  GestureDetector(
                    onTap: () => setState(() => _status = option.value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _status == option.value
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          AppConstants.pillRadius,
                        ),
                      ),
                      child: Text(
                        option.label,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _status == option.value
                              ? Colors.white
                              : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (kNotifyingSiteVisitStatuses.contains(_status)) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The visitor will be notified of this change.',
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _VisitEdit(
                        date: _date,
                        time: _time.text.trim().isEmpty
                            ? null
                            : _time.text.trim(),
                        status: _status,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
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
