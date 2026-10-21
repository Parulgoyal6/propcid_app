// providers/feed_provider.dart
import 'package:flutter/foundation.dart';

import '../models/feed_item.dart';
import '../services/feed_service.dart';

class FeedProvider extends ChangeNotifier {
  final FeedService _service = FeedService();

  List<FeedItem> _items = const [];
  bool _isLoading = true;
  String? _error;
  // The portal's default tab — it has no "All" (CombinedFeed.tsx:
  // `useState(... "broker")`).
  FeedRoleFilter _filter = FeedRoleFilter.broker;
  String? _currentUserId;

  // Exclusive tab (`builder_project_offers`) — fetched only when that tab is
  // opened, then kept until the next [load] (pull-to-refresh).
  List<FeedOffer>? _offers;
  bool _offersLoading = false;
  String? _offersError;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  FeedRoleFilter get filter => _filter;

  List<FeedOffer> get offers => _offers ?? const [];
  bool get offersLoading => _offersLoading || _offers == null;
  String? get offersError => _offersError;

  /// Items matching the active filter — recomputed on every read rather than
  /// cached, since the source list only changes on [load] and the filter
  /// only changes on [setFilter], both of which already call
  /// [notifyListeners].
  List<FeedItem> get visibleItems => _items
      .where((item) => item.matchesFilter(_filter, _currentUserId))
      .toList();

  Future<void> load(String? currentUserId) async {
    _currentUserId = currentUserId;
    _isLoading = true;
    _error = null;
    // Pull-to-refresh refreshes the offers too; otherwise they're refetched
    // the next time the Exclusive tab is opened.
    _offers = null;
    _safeNotify();

    try {
      _items = await _service.fetchFeed();
    } catch (e) {
      _error = 'Failed to load feed';
      _items = const [];
    }

    _isLoading = false;
    _safeNotify();

    if (_filter == FeedRoleFilter.exclusive) await _loadOffers();
  }

  void setFilter(FeedRoleFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    _safeNotify();
    if (filter == FeedRoleFilter.exclusive && _offers == null) _loadOffers();
  }

  Future<void> _loadOffers() async {
    if (_offersLoading) return;
    _offersLoading = true;
    _offersError = null;
    _safeNotify();
    try {
      _offers = await _service.fetchExclusiveOffers();
    } catch (e) {
      debugPrint('FeedProvider: exclusive offers failed: $e');
      _offersError = 'Failed to load exclusive offers';
      _offers = const [];
    }
    _offersLoading = false;
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
