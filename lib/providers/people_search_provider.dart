// providers/people_search_provider.dart
//
// People Search's state. Screen-scoped: created by `PeopleSearchScreen` through
// `ChangeNotifierProvider(create:)`, like `PublicProfileProvider`, so it is not
// added to the global tree in `main.dart` and cannot affect any other screen.
//
// The accounting mirrors `PropertyProvider`: `runSearch(reset:)` doubles as the
// "next page" call, `loadMore` guards on `isLoadingMore`/`hasMore`, and
// `totalCount` comes from the query's exact count. Property search itself is not
// touched — this is the same shape, not the same object.
import 'package:flutter/foundation.dart';

import '../models/people_search_result.dart';
import '../models/profile_review.dart';
import '../services/people_search_service.dart';

class PeopleSearchProvider extends ChangeNotifier {
  PeopleSearchProvider({PeopleSearchService? service, int pageSize = 20})
    : _service = service ?? PeopleSearchService(),
      _pageSize = pageSize;

  final PeopleSearchService _service;
  final int _pageSize;

  String _query = '';
  PeopleRole _role = PeopleRole.all;

  List<PersonResult> _results = const [];
  int _offset = 0;
  int? _totalCount;
  bool _hasMore = false;

  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasError = false;

  /// True until the first search of this screen's life completes, so the idle
  /// prompt ("search for people") can be told apart from a genuine empty result.
  bool _hasSearched = false;

  /// Bumped on every reset. An in-flight page that belongs to an earlier query or
  /// role is discarded on arrival instead of overwriting newer results — the same
  /// hazard a debounced box always has, and the reason a plain `mounted` check is
  /// not enough here.
  int _generation = 0;

  bool _disposed = false;

  String get query => _query;
  PeopleRole get role => _role;
  List<PersonResult> get results => _results;
  int? get totalCount => _totalCount;
  bool get hasMore => _hasMore;
  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasError => _hasError;
  bool get hasSearched => _hasSearched;

  /// No query typed yet — show the prompt, not an empty state.
  bool get isIdle => _query.trim().isEmpty;

  /// A completed search that matched nobody.
  bool get isEmptyResult =>
      !isIdle &&
      _hasSearched &&
      !_isSearching &&
      !_hasError &&
      _results.isEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Runs [query] from the first page.
  ///
  /// An empty query clears everything without a round-trip — `SearchModal.tsx:69`
  /// does the same rather than searching for the empty string.
  Future<void> search(String query, {PeopleRole? role}) async {
    _query = query;
    if (role != null) _role = role;

    if (_query.trim().isEmpty) {
      _generation++;
      _results = const [];
      _offset = 0;
      _totalCount = 0;
      _hasMore = false;
      _hasError = false;
      _hasSearched = false;
      _isSearching = false;
      _notify();
      return;
    }

    await _load(reset: true);
  }

  /// Re-runs the current query under a different role chip.
  Future<void> selectRole(PeopleRole role) async {
    if (_role == role) return;
    _role = role;
    if (_query.trim().isEmpty) {
      _notify();
      return;
    }
    await _load(reset: true);
  }

  /// Appends the next page. Safe to call repeatedly from a scroll listener.
  Future<void> loadMore() async {
    if (_isLoadingMore || _isSearching || !_hasMore) return;
    await _load(reset: false);
  }

  /// Re-issues the identical search after a failure.
  Future<void> retry() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (reset) {
      _generation++;
      _isSearching = true;
      _results = const [];
      _offset = 0;
      _totalCount = null;
      _hasMore = false;
      // Cleared only on a reset. A failed "load more" must not blank the results
      // already on screen — PropertyProvider draws the same line.
      _hasError = false;
    } else {
      _isLoadingMore = true;
    }
    _notify();

    final int generation = _generation;

    try {
      final page = await _service.searchPeople(
        query: _query,
        role: _role,
        offset: _offset,
        limit: _pageSize,
      );

      if (generation != _generation) return;

      final incoming = page.rows
          .map((profile) => PersonResult(profile: profile))
          .toList(growable: false);

      _results = reset ? incoming : [..._results, ...incoming];
      _offset += page.rows.length;
      _totalCount = page.totalCount;
      // Trust the reported total when there is one, and fall back to "a short
      // page means the end" when the count is missing.
      _hasMore = page.totalCount != null
          ? _offset < page.totalCount!
          : page.rows.length == _pageSize;
      _hasSearched = true;
      _isSearching = false;
      _isLoadingMore = false;
      _notify();

      // Ratings are a second round-trip, deliberately after the page is already
      // painted: a card without stars is complete enough to tap, and blocking the
      // list on a decoration would make search feel slower than the portal's.
      await _attachRatings(incoming, generation);
    } catch (e) {
      debugPrint('PeopleSearchProvider._load failed: $e');
      if (generation != _generation) return;
      _isSearching = false;
      _isLoadingMore = false;
      if (reset) _hasError = true;
      _notify();
    }
  }

  Future<void> _attachRatings(
    List<PersonResult> forResults,
    int generation,
  ) async {
    if (forResults.isEmpty) return;

    final ratings = await _service.fetchRatings(
      forResults.map((r) => r.userId),
    );
    if (ratings.isEmpty || generation != _generation) return;

    _results = _results
        .map((result) {
          final RatingSummary? summary = ratings[result.userId];
          // Only rated users are in the map, so everyone else keeps whatever they
          // already had rather than being reset to null.
          return summary == null ? result : result.withRating(summary);
        })
        .toList(growable: false);
    _notify();
  }
}
