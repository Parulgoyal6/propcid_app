// providers/recent_searches_provider.dart
//
// Owns the recent-search list for the Search Entry screen. List semantics
// (order, dedupe, cap) live here; persistence lives in RecentSearchesService,
// matching the app's existing Provider -> Service convention (no repository
// layer — see PropertyProvider/PropertyService).
import 'package:flutter/foundation.dart';

import '../models/recent_search.dart';
import '../services/recent_searches_service.dart';
import 'auth_provider.dart';

class RecentSearchesProvider extends ChangeNotifier {
  final RecentSearchesService _service = RecentSearchesService();

  List<RecentSearch> _items = const [];

  /// The signed-in user's id, or null when signed out. Also the key that
  /// decides which backend [_persist] writes to.
  String? _userId;

  /// Distinguishes "never loaded" from "loaded, and the user is signed out" —
  /// both of which have a null [_userId].
  bool _initialised = false;

  RecentSearchesProvider(AuthProvider auth) {
    updateAuth(auth);
  }

  List<RecentSearch> get items => List.unmodifiable(_items);

  /// Display-ready queries, newest first. The UI works in plain strings; the
  /// `{q, ts}` storage shape stays an implementation detail of this provider
  /// and the service.
  List<String> get queries => _items.map((e) => e.q).toList();

  bool get isEmpty => _items.isEmpty;

  /// Called by the ChangeNotifierProxyProvider on every AuthProvider
  /// notification.
  ///
  /// Guarded on identity change rather than reloading each time, because
  /// AuthProvider notifies on every auth event AND again after its async
  /// `_fetchUserProfile()` completes — reloading on all of them would fire
  /// redundant queries on every sign-in.
  ///
  /// Note `userId` arrives a beat after `isLoggedIn` flips true (it is
  /// populated by that same async profile fetch). The intermediate state reads
  /// as signed-out and loads the local list; the follow-up notification
  /// carrying the real id then swaps in the server list. Transient and
  /// self-correcting, so it needs no special casing.
  void updateAuth(AuthProvider auth) {
    final String? nextUserId = auth.isLoggedIn ? auth.userId : null;
    if (_initialised && nextUserId == _userId) return;
    _initialised = true;
    _userId = nextUserId;
    _reload();
  }

  Future<void> _reload() async {
    final String? requestedFor = _userId;
    final loaded = requestedFor == null
        ? await _service.loadLocal()
        : await _service.loadRemote(requestedFor);

    // A rapid sign-in/sign-out can land two reloads out of order; drop this
    // result if the identity moved on while the load was in flight, so a
    // previous user's list can never appear under the current one.
    if (requestedFor != _userId) return;

    _items = loaded;
    notifyListeners();
  }

  /// Records a committed search. Newest first, de-duplicated by exact query
  /// text, capped — see [RecentSearchesService.merge].
  ///
  /// Updates in memory and notifies immediately, then persists: the row is
  /// best-effort, and the list must never appear to lag behind the search the
  /// user just ran.
  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    _items = RecentSearchesService.merge(_items, RecentSearch.now(trimmed));
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String query) async {
    final next = _items.where((e) => e.q != query).toList();
    if (next.length == _items.length) return;

    _items = next;
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    if (_items.isEmpty) return;
    _items = const [];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final String? userId = _userId;
    if (userId == null) {
      await _service.saveLocal(_items);
    } else {
      await _service.saveRemote(userId, _items);
    }
  }
}
