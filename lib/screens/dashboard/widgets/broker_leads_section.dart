// screens/dashboard/widgets/broker_leads_section.dart
//
// Leads on the broker dashboard's Content tab — the port of
// `BrokerLeadsManager.tsx`.
//
// THE LEADS TABLE IS `property_inquiries`
// ---------------------------------------
// The contract flagged a standing `crm_leads` vs `property_inquiries` ambiguity and
// required it be resolved rather than guessed. It is resolved: `:102` reads
// `property_inquiries`, `:194` writes it, and `crm_leads` appears in none of the
// three broker components. See `BrokerLeadService`.
//
// ONE STATUS IS DELIBERATELY MISSING
// ----------------------------------
// The portal offers six statuses; five round-trip and "Lost" does not — the column
// enum has no `lost`, so `BrokerLeadsManager.tsx:188` maps it back to `pending` and
// the broker's answer is discarded. The picker here offers the five that survive.
// See `broker_section_options.dart` for the full mapping.
//
// The card, pill, action and shell primitives come from `builder_section_kit.dart`.
// Its filename says builder because Spec H introduced it, but it is presentation
// only — no queries, no state, no role — so it is imported rather than duplicated.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/broker_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/broker_section_models.dart';
import '../../../models/property_model.dart';
import '../../../services/broker_sections_service.dart'
    show BrokerSectionException;
import '../../../services/unified_leads_service.dart';
import '../../../widgets/shared/stat_kpi_card.dart';
import 'builder_section_kit.dart';

class BrokerLeadsSection extends StatefulWidget {
  const BrokerLeadsSection({
    super.key,
    required this.properties,
    this.onCountChanged,
    this.service,
  });

  /// The broker's listings — the scope of the query, and the source of each
  /// lead's property title.
  ///
  /// `property_inquiries` has no builder or broker column, so the listing set *is*
  /// the scope. Supplied by the parent, which already loaded them through
  /// `PropertyService`; the portal's three broker components each run their own
  /// identical `properties` fetch.
  final List<PropertyModel> properties;

  final ValueChanged<int>? onCountChanged;

  @visibleForTesting
  final UnifiedLeadsService? service;

  @override
  State<BrokerLeadsSection> createState() => _BrokerLeadsSectionState();
}

class _BrokerLeadsSectionState extends State<BrokerLeadsSection> {
  late final UnifiedLeadsService _leads =
      widget.service ?? UnifiedLeadsService();

  List<UnifiedLead>? _items;
  BrokerLeadStats _stats = BrokerLeadStats.empty;
  bool _failed = false;
  String? _busyLeadId;

  /// null means "All".
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(BrokerLeadsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent resolves listings asynchronously, so the first build sees an
    // empty list. Without this the section would stay permanently empty.
    if (oldWidget.properties.length != widget.properties.length) _load();
  }

  void _reportCount() => widget.onCountChanged?.call(_items?.length ?? 0);

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _leads.listForProperties(widget.properties);
      final stats = await _leads.statsFor(rows);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _stats = stats;
      });
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

  Future<void> _setStatus(UnifiedLead lead, String status) async {
    if (status == lead.status) return;

    setState(() => _busyLeadId = lead.id);
    try {
      final updatedLead = await _leads.setStatus(lead, status);
      if (!mounted) return;
      final updated = _items
          ?.map((l) => l.id == lead.id ? updatedLead : l)
          .toList();
      // Recomputed rather than adjusted by hand: conversion rate and closed value
      // both move when a single status changes, and adjusting four counters in
      // place is how they drift out of step with the list.
      final stats = await _leads.statsFor(updated ?? const []);
      if (!mounted) return;
      setState(() {
        _items = updated;
        _stats = stats;
      });
      _toast('Marked as ${brokerLeadStatusLabel(status).toLowerCase()}.');
    } catch (e) {
      _toast(
        e is BrokerSectionException
            ? e.message
            : 'Could not update that lead. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busyLeadId = null);
    }
  }

  Future<void> _call(UnifiedLead lead) async {
    final phone = lead.buyerPhone;
    if (phone == null) return;
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _toast('Could not open the dialler.', isError: true);
    }
  }

  Future<void> _email(UnifiedLead lead) async {
    final email = lead.buyerEmail;
    if (email == null) return;
    if (!await launchUrl(Uri(scheme: 'mailto', path: email))) {
      _toast('Could not open your mail app.', isError: true);
    }
  }

  List<UnifiedLead> get _visible {
    final all = _items ?? const <UnifiedLead>[];
    final filter = _statusFilter;
    if (filter == null) return all;
    return all.where((l) => l.status == filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final visible = _visible;

    // isEmpty is deliberately false: the portal keeps its KPI cards visible
    // even with zero leads (`IncomingLeadsManager.tsx:436-539`) and only the
    // list area below them goes empty. Handing `items?.isEmpty` to the shell
    // would collapse the stats strip and filter row along with the list,
    // which is not what the portal does.
    return BuilderSectionShell(
      failed: _failed,
      loaded: items != null,
      isEmpty: false,
      onRetry: _load,
      errorTitle: "Couldn't load your leads",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeadStatsStrip(stats: _stats),
          const SizedBox(height: AppConstants.spacingM),
          _LeadFilterRow(
            selected: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingM),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  (items?.isEmpty ?? true)
                      // No leads at all, unfiltered — the portal's
                      // `leads.length === 0` copy.
                      ? (widget.properties.isEmpty
                            ? 'Leads appear here once you publish a listing.'
                            : 'No leads yet.')
                      // Leads exist, but none match the selected filter.
                      : 'No ${brokerLeadStatusLabel(_statusFilter).toLowerCase()} '
                            'leads.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingM),
              _LeadCard(
                lead: visible[i],
                busy: _busyLeadId == visible[i].id,
                onCall: () => _call(visible[i]),
                onEmail: () => _email(visible[i]),
                onStatusChanged: (status) => _setStatus(visible[i], status),
              ),
            ],
        ],
      ),
    );
  }
}

/// The six KPI cards `BrokerLeadsManager.tsx:442-538` shows above the list —
/// Total Leads, New Leads, Active Deals, Closed Deals, Conversion Rate, Total
/// Deal Value — on the same `MetricCard`/`MetricCardGrid` every other
/// dashboard tab's Analytics and Audience grids use, rather than the bespoke
/// pill row this replaces.
///
/// The portal always shows all six, closed value included — it never hides
/// "₹0" behind a `deals.length === 0` check — so this doesn't either; with
/// the "Closed Deals" card sitting right next to it, a ₹0 deal value reads as
/// "nothing closed yet," not as a missing number.
class _LeadStatsStrip extends StatelessWidget {
  const _LeadStatsStrip({required this.stats});

  final BrokerLeadStats stats;

  @override
  Widget build(BuildContext context) {
    return MetricCardGrid(
      cards: [
        MetricCard(
          icon: Icons.forum_outlined,
          value: '${stats.total}',
          label: 'Total Leads',
          accent: AppColors.statusNewLaunch,
        ),
        MetricCard(
          icon: Icons.schedule_outlined,
          value: '${stats.newLeads}',
          label: 'New Leads',
          accent: AppColors.statusPending,
        ),
        MetricCard(
          icon: Icons.trending_up_rounded,
          value: '${stats.active}',
          label: 'Active Deals',
          accent: AppColors.warning,
        ),
        MetricCard(
          icon: Icons.check_circle_outline,
          value: '${stats.closed}',
          label: 'Closed Deals',
          accent: AppColors.success,
        ),
        MetricCard(
          icon: Icons.percent_rounded,
          value: '${stats.conversionRate.toStringAsFixed(1)}%',
          label: 'Conversion Rate',
          accent: AppColors.amenityIndigo,
        ),
        MetricCard(
          icon: Icons.payments_outlined,
          value: _compactRupees(stats.closedValue),
          label: 'Total Deal Value',
          accent: AppColors.success,
        ),
      ],
    );
  }

  /// Lakh/crore notation, as everywhere else in the app.
  static String _compactRupees(double value) {
    String trim(double v) {
      final t = v.toStringAsFixed(1);
      return t.endsWith('.0') ? t.substring(0, t.length - 2) : t;
    }

    if (value >= 10000000) return '₹${trim(value / 10000000)} Cr';
    if (value >= 100000) return '₹${trim(value / 100000)} L';
    return '₹${value.round()}';
  }
}

class _LeadFilterRow extends StatelessWidget {
  const _LeadFilterRow({required this.selected, required this.onChanged});

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
          for (final status in kBrokerLeadStatuses)
            chip(status.label, status.value),
        ],
      ),
    );
  }
}

class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.lead,
    required this.busy,
    required this.onCall,
    required this.onEmail,
    required this.onStatusChanged,
  });

  final UnifiedLead lead;
  final bool busy;
  final VoidCallback onCall;
  final VoidCallback onEmail;
  final ValueChanged<String> onStatusChanged;

  static Color _tint(String status) => switch (status) {
    'new' => AppColors.warning,
    'contacted' => AppColors.statusNewLaunch,
    'viewing_scheduled' => AppColors.primary,
    'negotiation' => AppColors.amenityIndigo,
    'closed' => AppColors.success,
    _ => AppColors.textHint,
  };

  /// `sourceBadge` — `IncomingLeadsManager.tsx:388-397` — collapsed to the
  /// two sources this app has (`visit`/`project_visit` share one label
  /// there; only `visit` is reachable here).
  static ({IconData icon, String label}) _source(UnifiedLeadSource source) =>
      switch (source) {
        UnifiedLeadSource.inquiry => (
          icon: Icons.forum_outlined,
          label: 'Inquiry',
        ),
        UnifiedLeadSource.visit => (
          icon: Icons.event_available_outlined,
          label: 'Visit Request',
        ),
      };

  @override
  Widget build(BuildContext context) {
    final source = _source(lead.source);
    return BuilderSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // `property_inquiries` has no name column, so an inquiry's
                  // name is the portal's own placeholder rather than data —
                  // a visit's is the visitor's real name they typed.
                  lead.buyerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(source.icon, size: 12, color: AppColors.textHint),
              const SizedBox(width: 3),
              Text(
                source.label,
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10.5,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            lead.propertyTitle ?? 'Unknown Property',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          // On its own line rather than beside the name: "Viewing Scheduled" plus
          // a caret does not fit next to a title on a 320 dp card, and the pill
          // cannot ellipsise without changing the shared kit widget that four
          // other sections already use.
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusPicker(
              status: lead.status,
              tint: _tint(lead.status),
              busy: busy,
              onChanged: onStatusChanged,
            ),
          ),
          if (lead.message != null) ...[
            const SizedBox(height: 8),
            Text(
              lead.message!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(fontSize: 11.5),
            ),
          ],
          if (lead.preferredContactTime != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.schedule_outlined,
                  size: 13,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Prefers ${lead.preferredContactTime}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
          if (lead.preferredVisitDate != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 13,
                  color: AppColors.textHint,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${_formatDate(lead.preferredVisitDate!)}'
                    '${(lead.preferredVisitTime?.isNotEmpty ?? false) ? ' at ${lead.preferredVisitTime}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                  ),
                ),
              ],
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
                    // Disabled rather than hidden when the enquirer left no
                    // number: the action exists, this lead just lacks the detail.
                    onTap: lead.buyerPhone == null ? null : onCall,
                  ),
                ),
                Expanded(
                  child: BuilderAction(
                    icon: Icons.mail_outline_rounded,
                    label: 'Email',
                    // Visit-sourced leads carry no email at all — visitors
                    // only give a name/phone (`property_visit_bookings` has
                    // no email column), so this stays disabled for every one
                    // of them, not just the rare inquiry with none.
                    onTap: lead.buyerEmail == null ? null : onEmail,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// The status pill, made tappable.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker({
    required this.status,
    required this.tint,
    required this.busy,
    required this.onChanged,
  });

  final String status;
  final Color tint;
  final bool busy;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Lead status, ${brokerLeadStatusLabel(status)}. Tap to change.',
      child: PopupMenuButton<String>(
        enabled: !busy,
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: onChanged,
        itemBuilder: (_) => [
          for (final option in kBrokerLeadStatuses)
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
                  // Flexible: "Viewing Scheduled" beside a radio does not fit the
                  // menu's width on a 320 dp screen.
                  Flexible(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BuilderPill(label: brokerLeadStatusLabel(status), tint: tint),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 14, color: tint),
          ],
        ),
      ),
    );
  }
}
