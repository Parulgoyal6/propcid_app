// screens/dashboard/widgets/outgoing_site_visits_section.dart
//
// The Manage Dashboard's "Site Visits" tab content, shared by all four role
// dashboards (Builder/Broker/Individual/Influencer) — requests the SIGNED-IN
// USER made on OTHER people's properties/projects/profiles. The opposite
// direction (incoming requests on the user's OWN listings) is the Leads
// tab, backed by `SiteVisitService.listForProjects`/`UnifiedLeadsService` —
// deliberately untouched by this widget.
//
// Backed by `MyVisitRequestsService`, which calls the existing
// `my-visit-requests`/`my-visit-booking-manage` Edge Functions rather than
// a locally-scoped table query — see that service's own header comment for
// why. This widget owns only presentation, loading/empty/error/retry state
// and the stale-account/stale-response guards; no query logic lives here.
//
// No Scaffold, no AppBar, no bottom nav — this is embedded directly inside
// a dashboard tab's existing scrollable body, the same way
// `BuilderSiteVisitsSection`/`BrokerVisitBookingsSection` are. The
// standalone `/visits` screen (property-only, reached from Home's quick
// actions) is untouched and keeps using its own `VisitBookingService`.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/outgoing_visit_request.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/my_visit_requests_service.dart';
import 'builder_section_kit.dart';

class OutgoingSiteVisitsSection extends StatefulWidget {
  const OutgoingSiteVisitsSection({
    super.key,
    this.service,
    this.enableRealtime = true,
    this.highlightBookingId,
    this.highlightSource,
    this.onCountChanged,
  });

  /// Injectable for tests — defaults to a real [MyVisitRequestsService]
  /// backed by the live Supabase client.
  @visibleForTesting
  final MyVisitRequestsService? service;

  /// Disabled in widget tests: a live `postgres_changes` subscription has no
  /// backend to talk to and would just hang.
  final bool enableRealtime;

  /// `data.bookingId`/`data.source` (as resolved by
  /// `resolveNotificationDestination`'s `_visitHighlightArgs`) from a tapped
  /// visit-booking notification — when a loaded item matches, it is drawn
  /// with a highlighted border. Either or both may be null/non-matching; a
  /// missing match is silently a no-highlight, never an error — per spec,
  /// missing highlight metadata must not prevent opening this section at
  /// all, let alone fail once it is open.
  final String? highlightBookingId;
  final OutgoingVisitSource? highlightSource;

  /// Reported upward once a load completes, so a dashboard's own tab badge
  /// (if any) can reflect this count without a second read.
  final ValueChanged<int>? onCountChanged;

  @override
  State<OutgoingSiteVisitsSection> createState() =>
      _OutgoingSiteVisitsSectionState();
}

class _OutgoingSiteVisitsSectionState
    extends State<OutgoingSiteVisitsSection> {
  late final MyVisitRequestsService _service =
      widget.service ?? MyVisitRequestsService();

  List<OutgoingVisitRequest>? _items;
  bool _failed = false;

  /// The user id [_items]/[_failed] was loaded for — compared against
  /// `AuthProvider.userId` on every rebuild so an account switch reloads for
  /// the new identity instead of showing the previous person's requests.
  /// Same pattern `VisitsScreen._loadedForUserId` already uses.
  String? _loadedForUserId;

  /// Bumped on every [_load] call; a resolving future only applies its
  /// result if it is still the most recent one, so a stale response from a
  /// superseded load (e.g. rapid account switching) cannot overwrite newer
  /// state. Same pattern `VisitsScreen._loadGeneration` already uses.
  int _loadGeneration = 0;

  RealtimeChannel? _channel;

  /// The [OutgoingVisitRequest.identity] of the item a cancel/reschedule is
  /// currently in flight for, so only that one card shows a busy row.
  String? _busyIdentity;

  @override
  void initState() {
    super.initState();
    // Without this, a signed-out mount never calls `_syncForUser` at all:
    // `build()` only calls it when `AuthProvider.userId` CHANGES from
    // `_loadedForUserId`, and both start as `null` on first mount. Left
    // unhandled, `_items` stays `null` forever and `BuilderSectionShell`
    // shows its loading spinner indefinitely — whose implicit animation
    // ticker then makes `pumpAndSettle()` hang forever in a test. Same
    // "sync the initial value unconditionally on mount" pattern
    // `VisitsScreen.initState` already uses for this exact reason.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncForUser(context.read<AuthProvider>().userId);
    });
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _service.unsubscribe(channel);
    super.dispose();
  }

  void _syncForUser(String? userId) {
    if (userId == _loadedForUserId) return;
    _loadedForUserId = userId;

    final channel = _channel;
    if (channel != null) {
      _service.unsubscribe(channel);
      _channel = null;
    }

    if (userId == null) {
      setState(() {
        _items = const [];
        _failed = false;
      });
      widget.onCountChanged?.call(0);
      return;
    }

    _load();

    if (widget.enableRealtime) {
      _channel = _service.subscribeToMine(userId, () {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() => _failed = false);
    try {
      final items = await _service.listMine();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _items = items);
      widget.onCountChanged?.call(items.length);
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _failed = true);
    }
  }

  void _openTarget(OutgoingVisitRequest item) {
    if (item.targetId.isEmpty) {
      _toast('This listing is no longer available.', isError: true);
      return;
    }
    switch (item.source) {
      case OutgoingVisitSource.property:
        Navigator.pushNamed(
          context,
          AppConstants.propertyDetailScreen,
          arguments: {'propertyId': item.targetId},
        );
        break;
      case OutgoingVisitSource.project:
        Navigator.pushNamed(
          context,
          AppConstants.projectDetailScreen,
          arguments: {'projectId': item.targetId},
        );
        break;
      case OutgoingVisitSource.profile:
        Navigator.pushNamed(
          context,
          AppConstants.publicProfileScreen,
          arguments: {'userId': item.targetId},
        );
        break;
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

  Future<void> _cancel(OutgoingVisitRequest item) async {
    setState(() => _busyIdentity = item.identity);
    try {
      await _service.cancel(source: item.source, bookingId: item.id);
      _toast('Visit cancelled.');
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busyIdentity = null);
    }
  }

  Future<void> _reschedule(OutgoingVisitRequest item) async {
    final now = DateTime.now();
    final initial = item.preferredDate.isBefore(now) ? now : item.preferredDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    setState(() => _busyIdentity = item.identity);
    try {
      await _service.reschedule(
        source: item.source,
        bookingId: item.id,
        preferredDate: _dateOnly(date),
        preferredTime:
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}',
      );
      _toast('Reschedule requested.');
      await _load();
    } catch (e) {
      _toast(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _busyIdentity = null);
    }
  }

  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    // Reacts to sign-out/account switching without this widget needing to
    // be recreated — same pattern `VisitsScreen.build` already uses.
    final userId = context.select<AuthProvider, String?>((a) => a.userId);
    if (userId != _loadedForUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncForUser(userId);
      });
    }

    final items = _items;
    return BuilderSectionShell(
      failed: _failed,
      loaded: items != null,
      isEmpty: items?.isEmpty ?? false,
      onRetry: _load,
      errorTitle: "Couldn't load your visit requests",
      emptyMessage:
          'Visits you request on other properties, projects or profiles '
          'will show up here.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < (items ?? const []).length; i++) ...[
            if (i > 0) const SizedBox(height: AppConstants.spacingM),
            _OutgoingVisitCard(
              item: items![i],
              highlighted:
                  widget.highlightBookingId != null &&
                  widget.highlightSource != null &&
                  items[i].id == widget.highlightBookingId &&
                  items[i].source == widget.highlightSource,
              isBusy: _busyIdentity == items[i].identity,
              onTap: () => _openTarget(items[i]),
              onCancel: items[i].isChangeable
                  ? () => _cancel(items[i])
                  : null,
              onReschedule: items[i].isChangeable
                  ? () => _reschedule(items[i])
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _OutgoingVisitCard extends StatelessWidget {
  const _OutgoingVisitCard({
    required this.item,
    required this.highlighted,
    required this.isBusy,
    required this.onTap,
    required this.onCancel,
    required this.onReschedule,
  });

  final OutgoingVisitRequest item;
  final bool highlighted;
  final bool isBusy;
  final VoidCallback onTap;

  /// Null when the request is no longer changeable (not pending/confirmed,
  /// or the slot has already passed) — the action row is omitted entirely
  /// rather than shown disabled, matching this app's existing convention
  /// for an action that genuinely does not apply right now.
  final VoidCallback? onCancel;
  final VoidCallback? onReschedule;

  static Color _tint(String status) => switch (status) {
    'pending' => AppColors.warning,
    'confirmed' => AppColors.success,
    'completed' => AppColors.primary,
    'cancelled' => AppColors.error,
    'rescheduled' => AppColors.statusNewLaunch,
    _ => AppColors.textHint,
  };

  static String _sourceLabel(OutgoingVisitSource source) => switch (source) {
    OutgoingVisitSource.property => 'Property',
    OutgoingVisitSource.project => 'Project',
    OutgoingVisitSource.profile => 'Profile',
  };

  @override
  Widget build(BuildContext context) {
    final card = BuilderSectionCard(
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
                      item.title.isEmpty ? 'Untitled' : item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.location.isNotEmpty
                          ? item.location
                          : _sourceLabel(item.source),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BuilderPill(
                label: item.status.isEmpty
                    ? 'Pending'
                    : item.status[0].toUpperCase() + item.status.substring(1),
                tint: _tint(item.status),
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
                label: _formatDate(item.preferredDate),
              ),
              if (item.preferredTime != null)
                _Meta(icon: Icons.schedule_outlined, label: item.preferredTime!),
            ],
          ),
          if (isBusy) ...[
            const SizedBox(height: AppConstants.spacingM),
            const BuilderActionBusyRow(),
          ] else if (onCancel != null || onReschedule != null) ...[
            const SizedBox(height: AppConstants.spacingM),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 6),
            Row(
              children: [
                if (onReschedule != null)
                  Expanded(
                    child: BuilderAction(
                      icon: Icons.schedule_outlined,
                      label: 'Reschedule',
                      onTap: onReschedule,
                    ),
                  ),
                if (onCancel != null)
                  Expanded(
                    child: BuilderAction(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      tint: AppColors.error,
                      onTap: onCancel,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: highlighted
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: card,
            )
          : card,
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
