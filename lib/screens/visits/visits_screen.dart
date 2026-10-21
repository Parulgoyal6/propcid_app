// screens/visits/visits_screen.dart
//
// "My Visits" — the buyer's own `property_visit_bookings` rows. Previously
// backed by a hardcoded, in-memory list on `PropertyProvider` (fake agent
// names/phones/dates, `addVisit`/`cancelVisit` never touching the database).
// Now owns its own real state via [VisitBookingService], matching
// `MyVisitRequests.tsx`'s list/realtime contract — see that service's doc
// comment for the exact query shapes and RLS evidence.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../models/broker_section_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../services/visit_booking_service.dart';
import '../../widgets/bottom_nav_bar.dart';

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, this.service, this.enableRealtime = true});

  /// Injectable for tests — defaults to a real [VisitBookingService] backed
  /// by the live Supabase client.
  final VisitBookingService? service;

  /// Disabled in widget tests: a live `postgres_changes` subscription has no
  /// backend to talk to and would just hang.
  final bool enableRealtime;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final VisitBookingService _service;

  List<PropertyVisitBooking> _bookings = <PropertyVisitBooking>[];
  bool _isLoading = true;
  String? _error;
  String? _cancellingId;
  String? _reschedulingId;

  /// The user id the current [_bookings]/[_isLoading] state was loaded for.
  /// Compared against [AuthProvider.userId] on every rebuild so a sign-out or
  /// account switch reloads for the new identity instead of showing the
  /// previous person's bookings — see [_syncForUser].
  String? _loadedForUserId;

  /// Bumped on every [_load] call; a resolving future only applies its
  /// result if it is still the most recent one, so a stale response from a
  /// superseded load (e.g. rapid account switching) cannot overwrite newer
  /// state.
  int _loadGeneration = 0;

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _service = widget.service ?? VisitBookingService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Provider.of<NavigationProvider>(context, listen: false).setIndex(3);
      _syncForUser(Provider.of<AuthProvider>(context, listen: false).userId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    final channel = _channel;
    if (channel != null) {
      _service.unsubscribe(channel);
    }
    super.dispose();
  }

  /// Called whenever the authenticated user id might have changed (initial
  /// load, sign-out, or a different account signing in). A no-op if it is
  /// unchanged from the last load this screen already did.
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
        _bookings = <PropertyVisitBooking>[];
        _isLoading = false;
        _error = null;
      });
      return;
    }

    _load(userId);

    if (widget.enableRealtime) {
      _channel = _service.subscribeToMine(userId, () {
        if (mounted) _load(userId);
      });
    }
  }

  Future<void> _load(String userId) async {
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final bookings = await _service.listMyBookings(userId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _bookings = bookings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = 'Could not load your visits. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _cancel(PropertyVisitBooking booking) async {
    if (_cancellingId != null) return; // guards against a double tap
    setState(() => _cancellingId = booking.id);

    try {
      final updated = await _service.cancelBooking(booking);
      if (!mounted) return;
      setState(() {
        _bookings = _bookings
            .map((b) => b.id == updated.id ? updated : b)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Visit cancelled.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is VisitManageException
                ? e.message
                : "Couldn't cancel this visit. Please contact the property "
                      'owner directly, or try again shortly.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancellingId = null);
    }
  }

  /// Date/time pickers, then [VisitBookingService.rescheduleBooking] — a
  /// successful reschedule always comes back `pending` (the server's own
  /// rule, since the owner must reconfirm the new slot), which this reflects
  /// immediately via the returned booking rather than a second fetch.
  Future<void> _reschedule(PropertyVisitBooking booking) async {
    if (_reschedulingId != null) return; // guards against a double tap

    final DateTime now = DateTime.now();
    final DateTime initialDate = booking.preferredDate.isBefore(now)
        ? now
        : booking.preferredDate;
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;

    // The function's own `TIME_RE` requires 24-hour `HH:mm` — not the
    // "h:mm AM/PM" shape the create-booking sheet's custom time picker
    // produces for the direct-insert path.
    final String preferredTime =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';

    setState(() => _reschedulingId = booking.id);
    try {
      final updated = await _service.rescheduleBooking(
        booking,
        preferredDate: date,
        preferredTime: preferredTime,
      );
      if (!mounted) return;
      setState(() {
        _bookings = _bookings
            .map((b) => b.id == updated.id ? updated : b)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reschedule requested — waiting for the owner to reconfirm.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is VisitManageException
                ? e.message
                : "Couldn't reschedule this visit. Please try again shortly.",
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reschedulingId = null);
    }
  }

  /// Everything except `completed` stays on the Upcoming tab — including
  /// `cancelled`, matching this screen's own prior convention (the removed
  /// hardcoded data kept a cancelled visit's `isUpcoming: true` and only
  /// hid its action buttons; nothing in the portal or schema says a
  /// cancelled visit is "completed").
  static bool _isUpcoming(String status) => status != 'completed';

  @override
  Widget build(BuildContext context) {
    // Reacts to sign-out / account switching without this screen needing to
    // be recreated.
    final userId = context.select<AuthProvider, String?>((a) => a.userId);
    if (userId != _loadedForUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncForUser(userId);
      });
    }

    final upcoming = _bookings.where((b) => _isUpcoming(b.status)).toList()
      ..sort(
        (a, b) => (b.createdAt ?? b.preferredDate).compareTo(
          a.createdAt ?? a.preferredDate,
        ),
      );
    final completed = _bookings.where((b) => !_isUpcoming(b.status)).toList()
      ..sort(
        (a, b) => (b.createdAt ?? b.preferredDate).compareTo(
          a.createdAt ?? a.preferredDate,
        ),
      );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(upcoming.length + completed.length),
            _buildTabBar(),
            Expanded(
              child: userId == null
                  ? _buildSignInRequired()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildList(upcoming, isUpcoming: true),
                        _buildList(completed, isUpcoming: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomNavBar(currentIndex: 3),
    );
  }

  Widget _buildAppBar(int totalVisits) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Semantics(
                label: 'Back',
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushNamed(context, AppConstants.homeScreen);
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppColors.surfaceCardShadow,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('My Visits', style: AppTextStyles.heading2),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$totalVisits Visits',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            AppColors.cardBackground.withOpacity(0.95),
            AppColors.cardBackground.withOpacity(0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.12),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(14),
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textSecondary.withOpacity(0.8),
        labelStyle: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        unselectedLabelStyle: AppTextStyles.body.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Upcoming'),
          Tab(text: 'Completed'),
        ],
      ),
    );
  }

  Widget _buildSignInRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 72,
              color: AppColors.textHint.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text('Sign in to see your visits', style: AppTextStyles.heading3),
            const SizedBox(height: 8),
            Text(
              'Your booked property visits will appear here once you sign in.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<PropertyVisitBooking> bookings, {
    required bool isUpcoming,
  }) {
    if (_isLoading && bookings.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null && bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.textHint.withOpacity(0.6),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: AppTextStyles.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final userId = _loadedForUserId;
                  if (userId != null) _load(userId);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (bookings.isEmpty) {
      return _buildEmptyState(
        isUpcoming ? 'No upcoming visits' : 'No completed visits',
        isUpcoming
            ? 'Schedule a visit to see properties'
            : 'Your completed visits will appear here',
      );
    }

    final userId = _loadedForUserId;
    return RefreshIndicator(
      onRefresh: () async {
        if (userId != null) await _load(userId);
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (context, index) =>
            _buildVisitCard(bookings[index], isUpcoming: isUpcoming),
      ),
    );
  }

  Widget _buildVisitCard(
    PropertyVisitBooking booking, {
    required bool isUpcoming,
  }) {
    final status = booking.status;
    final isCancelling = _cancellingId == booking.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.textHint.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: booking.propertyImageUrl != null
                    ? Image.network(
                        booking.propertyImageUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  booking.propertyTitle ?? 'Property',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildStatusChip(status),
            ],
          ),
          if ((booking.propertyLocation ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    booking.propertyLocation!,
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(
                Icons.calendar_today,
                _formatDate(booking.preferredDate),
              ),
              if ((booking.preferredTime ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                _buildInfoChip(Icons.access_time, booking.preferredTime!),
              ],
              if (isUpcoming &&
                  (status == 'pending' || status == 'confirmed')) ...[
                const Spacer(),
                TextButton.icon(
                  onPressed: _reschedulingId != null
                      ? null
                      : () => _reschedule(booking),
                  icon: _reschedulingId == booking.id
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_calendar_outlined, size: 16),
                  label: const Text('Reschedule'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ],
          ),
          if ((booking.ownerName ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.person,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(booking.ownerName!, style: AppTextStyles.caption),
                ),
                if ((booking.ownerPhone ?? '').isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.phone, size: 20),
                    color: AppColors.primary,
                    onPressed: () => _callOwner(booking.ownerPhone!),
                  ),
              ],
            ),
          ],
          if (isUpcoming && status != 'cancelled') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isCancelling
                        ? null
                        : () => _confirmCancel(booking),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isCancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : const Text(
                            'Cancel Visit',
                            style: TextStyle(color: Colors.red),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      AppConstants.propertyDetailScreen,
                      arguments: {'propertyId': booking.propertyId},
                    ),
                    child: const Text('View Property'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppConstants.propertyDetailScreen,
                  arguments: {'propertyId': booking.propertyId},
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('View Property'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _imagePlaceholder() => Container(
    width: 48,
    height: 48,
    color: AppColors.primaryLight.withOpacity(0.15),
    child: const Icon(Icons.home_outlined, size: 22, color: AppColors.primary),
  );

  Widget _buildStatusChip(String status) {
    final Color color = switch (status) {
      'confirmed' => AppColors.success,
      'completed' => AppColors.primary,
      'cancelled' => Colors.red,
      _ => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _capitalize(status),
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 80,
            color: AppColors.textHint.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.heading3),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                Navigator.pushNamed(context, AppConstants.searchScreen),
            icon: const Icon(Icons.search),
            label: const Text('Browse Properties'),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(PropertyVisitBooking booking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Visit'),
        content: const Text('Are you sure you want to cancel this visit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _cancel(booking);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void _callOwner(String phone) {
    // Intentionally not auto-dialing (no url_launcher `tel:` call here) —
    // showing the number is enough for Phase 1 of this flow; wiring an
    // actual dialer intent is unrelated to the booking/enquiry contract this
    // change covers.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(phone)));
  }

  String _formatDate(DateTime date) {
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

  String _capitalize(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
}
