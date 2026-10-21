// screens/dashboard/widgets/broker_visit_bookings_section.dart
//
// Visit Bookings on the broker dashboard's Content tab — the port of
// `BrokerVisitBookingsManager.tsx`.
//
// REALTIME, FROM THE START
// ------------------------
// The contract records this as a **confirmed** realtime requirement rather than a
// verify-item, and says to build it with a subscription rather than retrofit one
// onto a polling screen. It is built that way: `_subscribe` opens the channel in
// `initState` and `dispose` removes it.
//
// The subscription is as coarse as the portal's — `event: '*'`, no filter, callback
// re-fetches (`:136-155`). A filter could not express this screen's scope anyway:
// "bookings on my listings" is a join, and realtime filters are single-column. So
// the channel says "something changed" and the *fetch* it triggers is what applies
// RLS and the listing scope.
//
// THIS IS NOT SPEC H's TABLE
// --------------------------
// `property_visit_bookings` hangs off `properties`; Spec H's
// `project_visit_bookings` hangs off `builder_projects`. Same column shape, two
// tables, two RLS policy sets. One difference worth knowing: this table has a
// `handle_updated_at` trigger, so its `updated_at` maintains itself.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/builder_section_options.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/broker_section_models.dart';
import '../../../models/property_model.dart';
import '../../../services/broker_sections_service.dart';
import 'builder_section_kit.dart';

class BrokerVisitBookingsSection extends StatefulWidget {
  const BrokerVisitBookingsSection({
    super.key,
    required this.properties,
    this.onCountChanged,
    this.service,
    this.enableRealtime = true,
  });

  /// The broker's listings — the query scope and the source of each booking's
  /// property title.
  final List<PropertyModel> properties;

  final ValueChanged<int>? onCountChanged;

  @visibleForTesting
  final PropertyVisitBookingService? service;

  /// Tests switch this off: a real channel needs a websocket, and what they are
  /// checking is the list and the edit flow. The realtime path itself is exercised
  /// by driving the callback directly.
  @visibleForTesting
  final bool enableRealtime;

  @override
  State<BrokerVisitBookingsSection> createState() =>
      _BrokerVisitBookingsSectionState();
}

class _BrokerVisitBookingsSectionState
    extends State<BrokerVisitBookingsSection> {
  late final PropertyVisitBookingService _bookings =
      widget.service ?? PropertyVisitBookingService();

  RealtimeChannel? _channel;

  List<PropertyVisitBooking>? _items;
  bool _failed = false;
  String? _busyBookingId;
  String? _statusFilter;

  /// Set briefly when a realtime event drives a refresh, so the broker can see
  /// that the list moved on its own rather than wondering whether it is stale.
  bool _liveUpdated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (widget.enableRealtime) _subscribe();
    });
  }

  @override
  void didUpdateWidget(BrokerVisitBookingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.properties.length != widget.properties.length) _load();
  }

  @override
  void dispose() {
    // Removed, not left open: a live channel would keep re-fetching for a screen
    // that no longer exists, and each re-fetch touches the database.
    final channel = _channel;
    _channel = null;
    if (channel != null) _bookings.unsubscribe(channel);
    super.dispose();
  }

  void _subscribe() {
    _channel = _bookings.subscribe(_onRealtimeChange);
  }

  /// Called by the channel on any insert, update or delete.
  ///
  /// Not annotated for testing: a test drives realtime by capturing the callback
  /// its fake service was handed in [subscribe] and invoking that, which exercises
  /// the same path without reaching into private state.
  Future<void> _onRealtimeChange() async {
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() => _liveUpdated = true);
  }

  void _reportCount() => widget.onCountChanged?.call(_items?.length ?? 0);

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await _bookings.listForProperties(widget.properties);
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

  String _titleFor(PropertyVisitBooking booking) =>
      booking.propertyTitle ?? 'Unknown Property';

  Future<void> _call(PropertyVisitBooking booking) async {
    if (!await launchUrl(Uri(scheme: 'tel', path: booking.visitorPhone))) {
      _toast('Could not open the dialler.', isError: true);
    }
  }

  Future<void> _edit(PropertyVisitBooking booking) async {
    final result = await showModalBottomSheet<_BookingEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditBookingSheet(
        booking: booking,
        propertyTitle: _titleFor(booking),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _busyBookingId = booking.id);
    try {
      await _bookings.updateBooking(
        booking: booking,
        preferredDate: result.date,
        preferredTime: result.time,
        status: result.status,
        propertyTitle: _titleFor(booking),
      );
      if (!mounted) return;
      // Patched locally even though the realtime channel will also fire: the
      // broker's own change should land immediately rather than after a round
      // trip, and the subsequent refresh is idempotent.
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
            ? 'Booking updated. The visitor has been notified.'
            : 'Booking updated.',
      );
    } catch (e) {
      _toast('Could not update that booking. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busyBookingId = null);
    }
  }

  List<PropertyVisitBooking> get _visible {
    final all = _items ?? const <PropertyVisitBooking>[];
    final filter = _statusFilter;
    if (filter == null) return all;
    return all.where((b) => b.status == filter).toList();
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
      errorTitle: "Couldn't load visit bookings",
      emptyMessage: widget.properties.isEmpty
          ? 'Visit bookings appear here once you publish a listing.'
          : 'No visits booked yet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_liveUpdated)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 13,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Updated live',
                    style: AppTextStyles.caption.copyWith(
                      fontSize: 11,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
          _StatusFilterRow(
            selected: _statusFilter,
            onChanged: (value) => setState(() => _statusFilter = value),
          ),
          const SizedBox(height: AppConstants.spacingM),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No ${siteVisitStatusLabel(_statusFilter).toLowerCase()} '
                  'bookings.',
                  style: AppTextStyles.caption,
                ),
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: AppConstants.spacingM),
              _BookingCard(
                booking: visible[i],
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

/// Reuses `kSiteVisitStatusOptions` — the five statuses are the same list on both
/// booking tables, because both managers were written from the same template.
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
    required this.busy,
    required this.onCall,
    required this.onEdit,
  });

  final PropertyVisitBooking booking;
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
                      booking.propertyTitle ?? 'Unknown Property',
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
              // Only where it is actionable: a completed visit in the past is not
              // a problem, an unconfirmed one is.
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

class _BookingEdit {
  const _BookingEdit({
    required this.date,
    required this.time,
    required this.status,
  });

  final DateTime date;
  final String? time;
  final String status;
}

/// Date, time and status — `BrokerVisitBookingsManager.tsx:166-177`'s three fields.
class _EditBookingSheet extends StatefulWidget {
  const _EditBookingSheet({required this.booking, required this.propertyTitle});

  final PropertyVisitBooking booking;
  final String propertyTitle;

  @override
  State<_EditBookingSheet> createState() => _EditBookingSheetState();
}

class _EditBookingSheetState extends State<_EditBookingSheet> {
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
      // Wide in both directions: marking a visit that already happened as
      // completed is the common case.
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
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
                '${widget.booking.visitorName} · ${widget.propertyTitle}',
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
                // Free text, because `preferred_time` is TEXT and the portal's own
                // input is a plain field. A picker would impose a format the
                // existing rows do not follow.
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

              Text(
                'Status',
                style: AppTextStyles.body.copyWith(fontSize: 12.5),
              ),
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
                        _BookingEdit(
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
      ),
    );
  }
}
