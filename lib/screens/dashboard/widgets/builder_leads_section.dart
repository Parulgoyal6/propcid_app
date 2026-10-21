// screens/dashboard/widgets/builder_leads_section.dart
//
// Leads on the builder dashboard's own new Leads tab.
//
// WHERE THIS DATA COMES FROM
// ---------------------------
// The portal's `IncomingLeadsManager` (mounted at `BuilderDashboardManage.tsx`'s
// `activeSection === 'leads'`) unifies four sources: `property_inquiries`,
// `property_visit_bookings`, `project_visit_bookings` and
// `profile_visit_requests`. A builder holds no rows in `properties`, so the
// first two always fetch empty for a builder, and `profile_visit_requests` (a
// direct "meet me" request with no listing attached) has no Flutter surface
// anywhere yet — building one would be a new feature, not this tab. What is
// left, and what actually populates a builder's leads in the live portal, is
// `project_visit_bookings` scoped to their own projects — exactly the rows
// `BuilderSiteVisitsSection` (the Visits tab) already reads via
// `SiteVisitService.listForProjects`.
//
// So this section reuses that same read, and is deliberately read-only: the
// Visits tab is where a lead's status/date/time is actually changed
// (`SiteVisitService.updateBooking`), matching the Broker dashboard's own
// split, where a visit booking is likewise readable from both its Leads tab
// and its Visits tab but only writable from the latter.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/builder_section_models.dart';
import '../../../services/builder_sections_service.dart';
import 'builder_section_kit.dart';

class BuilderLeadsSection extends StatefulWidget {
  const BuilderLeadsSection({
    super.key,
    required this.projectIds,
    required this.projectTitles,
    this.service,
  });

  /// The builder's project ids — the scope of the query. Same list the Visits
  /// tab is given, from the same parent-held source.
  final List<String> projectIds;

  /// Project id → title, for the card subtitle.
  final Map<String, String> projectTitles;

  @visibleForTesting
  final SiteVisitService? service;

  @override
  State<BuilderLeadsSection> createState() => _BuilderLeadsSectionState();
}

class _BuilderLeadsSectionState extends State<BuilderLeadsSection> {
  late final SiteVisitService _visits = widget.service ?? SiteVisitService();

  List<SiteVisitBooking>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BuilderLeadsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameIds(oldWidget.projectIds, widget.projectIds)) _load();
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _visits.listForProjects(widget.projectIds);
      if (!mounted) return;
      setState(() => _items = rows);
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

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return BuilderSectionShell(
      failed: _failed,
      loaded: items != null,
      isEmpty: items?.isEmpty ?? false,
      onRetry: _load,
      errorTitle: "Couldn't load leads",
      emptyMessage: widget.projectIds.isEmpty
          ? 'Leads appear here once you publish a project.'
          : 'No leads yet. When someone requests a site visit, they\'ll show up here.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeadStatsRow(items: items ?? const []),
          const SizedBox(height: AppConstants.spacingM),
          for (var i = 0; i < (items ?? const []).length; i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingM),
            _LeadCard(
              booking: items![i],
              projectTitle: _titleFor(items[i].projectId),
              onCall: () => _call(items[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// Total / Pending / Confirmed / Completed — the counts a builder actually has
/// over `project_visit_bookings`, read straight off the booking status rather
/// than forced through the inquiry-style new/contacted/negotiation vocabulary
/// the portal's unified `Lead["status"]` uses: that vocabulary's `closed`
/// value has no `project_visit` status that ever maps to it
/// (`visitStatusMap` in `IncomingLeadsManager.tsx` sends `completed` to
/// `negotiation`, never `closed`), so reusing it here would show a "Closed
/// Deals" stat that can never read anything but zero.
class _LeadStatsRow extends StatelessWidget {
  const _LeadStatsRow({required this.items});

  final List<SiteVisitBooking> items;

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final pending = items.where((b) => b.status == 'pending').length;
    final confirmed = items
        .where((b) => b.status == 'confirmed' || b.status == 'rescheduled')
        .length;
    final completed = items.where((b) => b.status == 'completed').length;

    return Row(
      children: [
        Expanded(
          child: _StatChip(label: 'Total', value: total),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Pending',
            value: pending,
            tint: AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Confirmed',
            value: confirmed,
            tint: AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: 'Completed',
            value: completed,
            tint: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.tint});

  final String label;
  final int value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: AppTextStyles.heading2.copyWith(fontSize: 18, color: color),
          ),
          const SizedBox(height: 2),
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

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.booking,
    required this.projectTitle,
    required this.onCall,
  });

  final SiteVisitBooking booking;
  final String projectTitle;
  final VoidCallback onCall;

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
              _Meta(icon: Icons.call_outlined, label: booking.visitorPhone),
              _Meta(
                icon: Icons.event_outlined,
                label: _formatDate(booking.preferredDate),
              ),
              if (booking.preferredTime != null)
                _Meta(
                  icon: Icons.schedule_outlined,
                  label: booking.preferredTime!,
                ),
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
          const SizedBox(height: AppConstants.spacingM),
          const Divider(height: 1, color: AppColors.hairline),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 120,
              child: BuilderAction(
                icon: Icons.call_outlined,
                label: 'Call',
                onTap: onCall,
              ),
            ),
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
