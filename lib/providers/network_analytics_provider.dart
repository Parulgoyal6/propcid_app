import 'package:flutter/foundation.dart';

import '../models/network_analytics.dart';
import '../services/network_analytics_service.dart';

/// Screen-scoped state for Network ▸ Analytics.
///
/// The performance leaderboard is loaded for the current calendar month —
/// `NetworkAnalyticsDashboard.tsx`'s own default period before a user picks
/// week/quarter/year from its selector, which this screen does not add (the
/// portal screenshot this was built from shows no period selector either).
class NetworkAnalyticsProvider extends ChangeNotifier {
  NetworkAnalyticsProvider({NetworkAnalyticsService? service})
    : _service = service ?? NetworkAnalyticsService();

  final NetworkAnalyticsService _service;

  String? _userId;
  bool _disposed = false;

  NetworkAnalyticsStats _stats = NetworkAnalyticsStats.empty;
  List<NetworkPerformanceEntry> _performance = const [];
  bool _loading = true;
  bool _failed = false;

  NetworkAnalyticsStats get stats => _stats;
  List<NetworkPerformanceEntry> get performance =>
      List.unmodifiable(_performance);
  bool get loading => _loading;
  bool get failed => _failed;

  Future<void> load(String userId) async {
    if (userId != _userId) {
      _stats = NetworkAnalyticsStats.empty;
      _performance = const [];
    }
    _userId = userId;
    _loading = true;
    _failed = false;
    _safeNotify();

    final now = DateTime.now();
    final periodStart = DateTime(now.year, now.month, 1);
    // Day 0 of next month = the last day of this month.
    final periodEnd = DateTime(now.year, now.month + 1, 0);

    try {
      final results = await Future.wait([
        _service.getStats(userId),
        _service.listPerformance(
          userId,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
      ]);
      if (_userId != userId) return;
      _stats = results[0] as NetworkAnalyticsStats;
      _performance = results[1] as List<NetworkPerformanceEntry>;
      _failed = false;
    } catch (e) {
      if (_userId != userId) return;
      debugPrint('NetworkAnalyticsProvider.load failed: $e');
      _failed = true;
      _stats = NetworkAnalyticsStats.empty;
      _performance = const [];
    } finally {
      if (_userId == userId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  Future<void> refresh() {
    final userId = _userId;
    if (userId == null) return Future.value();
    return load(userId);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
