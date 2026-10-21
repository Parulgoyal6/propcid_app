// providers/profile_views_provider.dart
//
// State for "who viewed my profile".
//
// Screen-scoped, like every other provider in this feature. Realtime is
// deliberately not wired: the plan lists it as optional, and a `postgres_changes`
// subscription is the one thing here that can leak across a session if disposal
// ever goes wrong. Pull-to-refresh covers the same need at no risk.
import 'package:flutter/foundation.dart';

import '../services/profile_view_service.dart';

class ProfileViewsProvider extends ChangeNotifier {
  ProfileViewsProvider({ProfileViewService? service})
    : _service = service ?? ProfileViewService();

  final ProfileViewService _service;

  String? _userId;
  bool _disposed = false;

  List<ProfileViewer> _viewers = const [];
  bool _loading = true;

  List<ProfileViewer> get viewers => List.unmodifiable(_viewers);
  bool get loading => _loading;

  /// People, not visits — one row per viewer, so the row count IS the unique
  /// count. This is why a returning visitor never moves this number.
  int get uniqueViewers => _viewers.length;

  /// Total visits across everyone, which the header shows beside [uniqueViewers]
  /// so the smaller number is self-explanatory.
  int get totalVisits => _viewers.fold<int>(0, (sum, v) => sum + v.viewCount);

  bool get hasRepeatVisitors => totalVisits > uniqueViewers;

  Future<void> load(String userId) async {
    _userId = userId;
    _loading = true;
    _notify();

    _viewers = await _service.fetchViewers(userId);
    _loading = false;
    _notify();
  }

  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    await load(userId);
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
