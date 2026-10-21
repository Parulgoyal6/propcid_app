import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/geo_utils.dart';
import '../core/utils/listing_price_parser.dart';
import '../models/property_model.dart';
import '../models/search_query_params.dart';
import '../services/property_service.dart';
import '../services/property_likes_service.dart';
import '../services/saved_properties_service.dart';

class PropertyProvider extends ChangeNotifier {
  List<PropertyModel> _properties = [];
  // Query-driven search state — replaces the old fetch-everything-then-
  // filter-in-Dart `_filteredProperties`/searchProperties()/applyFilters().
  List<PropertyModel> _searchResults = [];
  List<PropertyModel> _mapResults = [];

  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasMoreResults = true;
  int _totalResultCount = 0;
  int _searchOffset = 0;

  // Used whenever budget filtering or a price sort is active — see
  // runSearch/_needsClientSideBuffering. Holds the COMPLETE, budget-filtered,
  // client-sorted matching set so pagination can slice pages out of it in
  // memory, instead of trusting the DB to filter/sort/paginate on a column
  // (`price`, free text) or value (budget) it was never asked to handle
  // server-side.
  List<PropertyModel> _budgetBuffer = [];
  int _budgetBufferCursor = 0;

  bool _hasError = false;

  // Bumped on every `runSearch(reset: true)`/`loadMapResults` call. An
  // in-flight request whose generation has since been superseded discards
  // its result on arrival instead of overwriting a newer one — the same
  // hazard PeopleSearchProvider guards against, and for the same reason: two
  // rapid filter/sort changes (or a fast repeated search) can otherwise let
  // an older response land after a newer one and silently win.
  //
  // Two separate counters because the list search and the map are
  // independent surfaces that can each be mid-request at the same time
  // (e.g. changing budget while the map tab is open) — a stale list
  // response must not be judged against the map's generation or vice versa.
  int _generation = 0;
  int _mapGeneration = 0;

  final SavedPropertiesService _savedPropertiesService =
      SavedPropertiesService();

  // Authoritative, persisted "saved" ids — independent of whether the
  // property itself is cached in _properties/_searchResults/_mapResults, so
  // a deep-linked property's saved state is always correct. PropertyModel's
  // own `isShortlisted` field is kept in sync (see _syncShortlistFlags) so
  // existing card widgets that read that field directly stay correct too.
  Set<String> _shortlistedIds = {};

  final PropertyLikesService _propertyLikesService = PropertyLikesService();

  // "Like" is a separate, independently-toggleable action from Save/
  // Shortlist above — the reference backs them with two different tables
  // (`user_likes` vs `saved_properties`); this mirrors that split rather
  // than reusing the shortlist state for a second purpose.
  Set<String> _likedPropertyIds = {};

  List<PropertyModel> get properties => _properties;
  List<PropertyModel> get searchResults => _searchResults;
  List<PropertyModel> get mapResults => _mapResults;
  bool get isSearching => _isSearching;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMoreResults => _hasMoreResults;
  // NOTE: reflects the DB-level count (matching filters, before the
  // client-side budget filter below is applied) — see _applyBudgetFilter.
  int get totalResultCount => _totalResultCount;

  /// True when the most recent [runSearch] threw.
  ///
  /// Purely additive, and reported rather than acted on: this class still
  /// swallows the exception and still logs it exactly as before. What changes is
  /// that a caller can now tell a failed search from a search that legitimately
  /// matched nothing — until now both surfaced as "No properties found", which is
  /// a lie when the request never completed.
  ///
  /// Scoped to [runSearch] on purpose. [loadProperties] feeds the Home rails, and
  /// [loadMapResults] the map, so raising this flag from either would let an
  /// unrelated failure paint an error over a perfectly good result list — or, in
  /// the case where a search legitimately returns zero rows and the map then
  /// fails, replace a correct "nothing matched" message with a wrong one. Both
  /// keep their existing silent-failure behaviour.
  bool get hasError => _hasError;

  /// [propertyService] is an injectable test seam — every real call site
  /// keeps using the default `PropertyProvider()`, which behaves exactly as
  /// before. Tests can supply a fake to exercise runSearch's paging/sorting
  /// logic without a live Supabase round-trip.
  PropertyProvider({PropertyService? propertyService})
    : _propertyService = propertyService ?? PropertyService() {
    loadProperties();
    _loadShortlistedIds();
    _loadLikedPropertyIds();
  }

  final PropertyService _propertyService;

  Future<void> loadProperties() async {
    try {
      final data = await _propertyService.getProperties();
      _properties = data
          .map((item) => PropertyModel.fromSupabase(item))
          .toList();
      _syncShortlistFlags();
      notifyListeners();
    } catch (e) {
      debugPrint('[PropertyProvider] loadProperties failed: $e');
    }
  }

  /// Loads the current user's saved-property ids from the persisted
  /// `saved_properties` table. Silently does nothing when signed out —
  /// mirrors the reference portal redirecting anonymous saves to sign-in
  /// rather than surfacing an error here.
  Future<void> _loadShortlistedIds() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      _shortlistedIds = await _savedPropertiesService.fetchSavedPropertyIds(
        userId,
      );
      _syncShortlistFlags();
      notifyListeners();
    } catch (e) {
      debugPrint('[PropertyProvider] _loadShortlistedIds failed: $e');
    }
  }

  /// Loads the current user's liked-property ids from the persisted
  /// `user_likes` table. Silently does nothing when signed out, same as
  /// [_loadShortlistedIds].
  Future<void> _loadLikedPropertyIds() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      _likedPropertyIds = await _propertyLikesService.fetchLikedPropertyIds(
        userId,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[PropertyProvider] _loadLikedPropertyIds failed: $e');
    }
  }

  bool isLiked(String propertyId) => _likedPropertyIds.contains(propertyId);

  /// Every property id the user has liked, straight from `user_likes`. Read-
  /// only view of the same set [isLiked] checks — exposed so a caller that
  /// needs the whole set (rather than one id at a time), such as
  /// `MyActivitySection` reconciling a listing-video reel's like state, does
  /// not have to re-derive it.
  Set<String> get likedPropertyIds => Set.unmodifiable(_likedPropertyIds);

  /// Every property id the user has shortlisted, straight from
  /// `saved_properties`. Read-only view of the same set [isShortlisted]
  /// checks — see [likedPropertyIds]'s doc for why this is exposed.
  Set<String> get shortlistedPropertyIds => Set.unmodifiable(_shortlistedIds);

  /// Optimistically toggles, then persists to `user_likes`; rolls back on
  /// failure. No-ops when signed out.
  Future<void> toggleLike(String propertyId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final wasLiked = _likedPropertyIds.contains(propertyId);
    if (wasLiked) {
      _likedPropertyIds.remove(propertyId);
    } else {
      _likedPropertyIds.add(propertyId);
    }
    notifyListeners();

    try {
      if (wasLiked) {
        await _propertyLikesService.unlike(userId, propertyId);
      } else {
        await _propertyLikesService.like(userId, propertyId);
      }
    } catch (e) {
      debugPrint('[PropertyProvider] toggleLike persistence failed: $e');
      if (wasLiked) {
        _likedPropertyIds.add(propertyId);
      } else {
        _likedPropertyIds.remove(propertyId);
      }
      notifyListeners();
    }
  }

  /// Stamps `isShortlisted` on every cached PropertyModel from the
  /// authoritative [_shortlistedIds] set, so widgets reading the model field
  /// directly (card grids across Home/Search) reflect persisted state.
  void _syncShortlistFlags() {
    List<PropertyModel> sync(List<PropertyModel> list) => list
        .map(
          (p) => p.isShortlisted == _shortlistedIds.contains(p.id)
              ? p
              : p.copyWith(isShortlisted: _shortlistedIds.contains(p.id)),
        )
        .toList();

    _properties = sync(_properties);
    _searchResults = sync(_searchResults);
    _mapResults = sync(_mapResults);
  }

  /// Runs (or continues, when `reset: false`) a search against the live
  /// backend for the given filter/sort snapshot. Mirrors Search.tsx's own
  /// branch: normal search pages via `.range()`; near-me and any
  /// budget/price-sort search instead need the COMPLETE matching set in
  /// memory (see [_needsClientSideBuffering]/[_fetchCompleteMatchingRows])
  /// before filtering/sorting/pagination can be correct — a DB page can
  /// contain zero real matches even though real matches exist further down
  /// the full result set, and price sorting has no reliable DB-level column
  /// to order by (`price` is free text; `price_min` is sparsely populated).
  Future<void> runSearch(SearchQueryParams params, {bool reset = true}) async {
    if (reset) {
      _generation++;
      _searchOffset = 0;
      _searchResults = [];
      _budgetBuffer = [];
      _budgetBufferCursor = 0;
      _hasMoreResults = true;
      _isSearching = true;
      // Cleared before every new search, so a previous failure can never make a
      // fresh attempt look like it failed too. Deliberately inside the `reset`
      // branch: `reset: false` is loadMoreResults continuing an existing search,
      // not starting one.
      _hasError = false;
      notifyListeners();
    }
    // Snapshot once — `reset: false` (loadMoreResults) deliberately does NOT
    // bump `_generation`, so this is the generation of whichever `reset: true`
    // call most recently started the result set being continued.
    final int generation = _generation;
    bool isCurrent() => generation == _generation;

    try {
      if (params.nearMeEnabled &&
          params.nearMeLat != null &&
          params.nearMeLng != null) {
        // Near-me always shows its own capped, distance-sorted set in one
        // shot (unchanged) — but when budget is ALSO active, that capped
        // batch must be the complete matching set first, or a real
        // in-budget match outside the cap silently never gets the chance to
        // be distance-filtered at all.
        final rows = _isBudgetFilterActive(params)
            ? await _fetchCompleteMatchingRows(
                params,
                isStillCurrent: isCurrent,
              )
            : (await _propertyService.searchProperties(
                params: params,
                offset: 0,
                limit: AppConstants.mapResultsSafetyCap,
                includeRange: false,
              )).rows;
        if (!isCurrent()) return;

        _searchResults = _applyBudgetAndNearMeFilter(rows, params);
        _totalResultCount = _searchResults.length;
        _hasMoreResults = false; // near-me's capped set is fully in memory
      } else if (_needsClientSideBuffering(params)) {
        // Budget is never a DB filter, and price sorting has no reliable DB
        // column to order by — neither can be combined with `.range()`
        // DB-level pagination. Fetch the COMPLETE matching set once,
        // budget-filter it, apply the requested sort client-side, then page
        // through that buffer in memory.
        if (reset) {
          final rows = await _fetchCompleteMatchingRows(
            params,
            isStillCurrent: isCurrent,
          );
          if (!isCurrent()) return;
          final filtered = _applyBudgetAndNearMeFilter(rows, params);
          _budgetBuffer = _sortForClientSideBuffer(filtered, params.sort);
          _budgetBufferCursor = 0;
        }
        if (!isCurrent()) return;
        final nextCursor = (_budgetBufferCursor + AppConstants.searchPageSize)
            .clamp(0, _budgetBuffer.length);
        final pageModels = _budgetBuffer.sublist(
          _budgetBufferCursor,
          nextCursor,
        );
        _searchResults = reset
            ? pageModels
            : [..._searchResults, ...pageModels];
        _budgetBufferCursor = nextCursor;
        _totalResultCount = _budgetBuffer.length;
        _hasMoreResults = _budgetBufferCursor < _budgetBuffer.length;
      } else {
        // Neither budget nor a price sort is active — the DB's own
        // newest/popular ordering and `.range()` pagination are both
        // trustworthy, so this keeps the original, cheaper path.
        final page = await _propertyService.searchProperties(
          params: params,
          offset: _searchOffset,
          limit: AppConstants.searchPageSize,
        );
        if (!isCurrent()) return;
        // Budget is inactive on this branch (handled above), so this only
        // ever passes rows through unchanged.
        final models = _applyBudgetAndNearMeFilter(page.rows, params);

        _searchResults = reset ? models : [..._searchResults, ...models];
        _searchOffset += page.rows.length;
        _totalResultCount = page.totalCount ?? _searchOffset;
        _hasMoreResults = _searchOffset < (page.totalCount ?? _searchOffset);
      }
    } catch (e) {
      debugPrint('[PropertyProvider] runSearch failed: $e');
      if (!isCurrent()) return;
      // Added alongside the log, not in place of it. The `finally` below already
      // notifies, so no extra notification is needed here.
      _hasError = true;
    } finally {
      if (isCurrent()) {
        if (reset) {
          _isSearching = false;
        }
        _syncShortlistFlags();
        notifyListeners();
      }
    }
  }

  bool _isBudgetFilterActive(SearchQueryParams params) {
    return !(params.budgetMin <= AppConstants.priceMin &&
        params.budgetMax >= AppConstants.priceMax);
  }

  /// True whenever the DB can no longer be trusted to filter/sort/paginate
  /// on its own — a non-default budget (filtered client-side against the
  /// free-text `price` column) or a price sort (no reliable DB column to
  /// order by). Both require the complete matching set in memory; see
  /// [_fetchCompleteMatchingRows].
  bool _needsClientSideBuffering(SearchQueryParams params) {
    return _isBudgetFilterActive(params) ||
        params.sort == PropertySortOption.priceAsc ||
        params.sort == PropertySortOption.priceDesc;
  }

  /// Fetches every DB row matching [params]' non-price filters via repeated
  /// read-only `.range()` pages, so a real match is never dropped just
  /// because it landed past a single capped batch. Uses
  /// [PropertyService.searchProperties] exactly as the normal paginated path
  /// does — its own DB-level `.order()` only needs to be a stable, total
  /// order for `.range()` to page correctly; which column that is doesn't
  /// matter here, since the result is always re-sorted client-side
  /// afterward (see [_sortForClientSideBuffer]).
  ///
  /// [isStillCurrent] is checked after every await so an abandoned search
  /// (a newer one has since started) stops fetching instead of continuing
  /// to hammer the backend for a result nobody will ever see.
  Future<List<Map<String, dynamic>>> _fetchCompleteMatchingRows(
    SearchQueryParams params, {
    required bool Function() isStillCurrent,
  }) async {
    final rows = <Map<String, dynamic>>[];
    // Defensive de-dup only — `.range()` pages should already be
    // non-overlapping given a stable, total DB-level order, but an id-keyed
    // guard costs nothing and turns a hypothetical backend hiccup into a
    // skipped duplicate instead of a visibly repeated card.
    final seenIds = <Object>{};
    int offset = 0;
    int? reportedTotal;

    while (true) {
      final page = await _propertyService.searchProperties(
        params: params,
        offset: offset,
        limit: AppConstants.priceAwareFetchBatchSize,
        includeRange: true,
      );
      if (!isStillCurrent()) return rows;

      reportedTotal ??= page.totalCount;
      for (final row in page.rows) {
        final id = row['id'];
        if (id == null || seenIds.add(id)) {
          rows.add(row);
        }
      }

      offset += page.rows.length;
      final doneByCount = reportedTotal != null && rows.length >= reportedTotal;
      final shortPage =
          page.rows.length < AppConstants.priceAwareFetchBatchSize;
      if (page.rows.isEmpty || shortPage || doneByCount) break;
      if (rows.length >= AppConstants.priceAwareFetchSafetyCeiling) break;
    }
    return rows;
  }

  /// Reproduces the requested final sort entirely client-side over the
  /// complete (already budget-filtered) set. A deterministic `id`
  /// tiebreaker is always applied last, so slicing pages out of
  /// `_budgetBuffer` can never duplicate or reshuffle equal-key rows.
  List<PropertyModel> _sortForClientSideBuffer(
    List<PropertyModel> models,
    PropertySortOption sort,
  ) {
    int comparePrimary(PropertyModel a, PropertyModel b) {
      switch (sort) {
        case PropertySortOption.priceAsc:
        case PropertySortOption.priceDesc:
          // A genuine parse is always positive (see listing_price_parser.dart),
          // so `price <= 0` unambiguously means "unknown" here.
          final aUnknown = a.price <= 0;
          final bUnknown = b.price <= 0;
          if (aUnknown != bUnknown) return aUnknown ? 1 : -1;
          if (aUnknown) return 0;
          final cmp = a.price.compareTo(b.price);
          return sort == PropertySortOption.priceAsc ? cmp : -cmp;
        case PropertySortOption.popular:
          return (b.likes ?? 0).compareTo(a.likes ?? 0);
        case PropertySortOption.newest:
          final aDate = a.createdAt;
          final bDate = b.createdAt;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate);
      }
    }

    final sorted = List<PropertyModel>.of(models);
    sorted.sort((a, b) {
      final primary = comparePrimary(a, b);
      if (primary != 0) return primary;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  Future<void> loadMoreResults(SearchQueryParams params) async {
    if (_isLoadingMore || !_hasMoreResults || params.nearMeEnabled) return;
    final int generation = _generation;
    _isLoadingMore = true;
    notifyListeners();
    try {
      await runSearch(params, reset: false);
    } finally {
      // A stale load-more (a newer `reset: true` search started while this
      // one was in flight) must not touch a loading flag that no longer
      // belongs to it — runSearch's own generation guard already protected
      // the results/count/buffer; this protects the flag the same way.
      if (generation == _generation) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Always fetches the complete matching set in one shot, independent of
  /// the list's incremental pagination cursor, so the map can `fitBounds`
  /// over everything the way the website's map does while the list pages
  /// incrementally.
  ///
  /// Runs the SAME budget + near-me post-filtering as runSearch's near-me
  /// branch — this previously only applied the budget filter, so enabling
  /// "Near Me" while the map was open (or refreshing the map while near-me
  /// was active) showed properties from anywhere within the safety cap
  /// instead of just the ones within 15km. When budget is active, also uses
  /// the exhaustive fetch instead of a single capped batch, for the same
  /// reason the list search does — otherwise a real in-budget match past
  /// the cap would never reach the map either.
  ///
  /// Tracked by its own [_mapGeneration] — independent of the list search's
  /// [_generation] — so a stale map refresh can't be judged against (or
  /// overwrite results that belong to) an unrelated list search generation,
  /// and vice versa.
  Future<void> loadMapResults(SearchQueryParams params) async {
    _mapGeneration++;
    final int generation = _mapGeneration;
    bool isCurrent() => generation == _mapGeneration;

    try {
      final rows = _isBudgetFilterActive(params)
          ? await _fetchCompleteMatchingRows(params, isStillCurrent: isCurrent)
          : (await _propertyService.searchProperties(
              params: params,
              offset: 0,
              limit: AppConstants.mapResultsSafetyCap,
              includeRange: false,
            )).rows;
      if (!isCurrent()) return;

      _mapResults = _applyBudgetAndNearMeFilter(rows, params);
      _syncShortlistFlags();
      notifyListeners();
    } catch (e) {
      debugPrint('[PropertyProvider] loadMapResults failed: $e');
    }
  }

  /// Budget is never sent as a DB filter (see PropertyService.searchProperties
  /// for why) — this parses the free-text `price` column via the same
  /// canonical [resolveEffectivePrice] every price-interpreting call site
  /// uses (PropertyModel.fromSupabase included), so display, budget
  /// filtering and price sorting can never disagree about what a listing's
  /// price actually is. Bounds are inclusive; a listing whose price can't be
  /// resolved at all is excluded once a budget filter is active, exactly
  /// like a genuine out-of-range price would be.
  ///
  /// When near-me is active, also Haversine-filters to the website's
  /// hardcoded 15km radius, sorts ascending by distance, and caps to 100 —
  /// shared by both runSearch (near-me branch) and loadMapResults so the two
  /// can never drift apart.
  List<PropertyModel> _applyBudgetAndNearMeFilter(
    List<Map<String, dynamic>> rows,
    SearchQueryParams params,
  ) {
    final bool budgetActive = _isBudgetFilterActive(params);

    final filteredRows = !budgetActive
        ? rows
        : rows.where((row) {
            final price = resolveEffectivePrice(row);
            if (price == null) return false;
            if (price < params.budgetMin) return false;
            if (price > params.budgetMax) return false;
            return true;
          }).toList();

    final models = filteredRows
        .map((r) => PropertyModel.fromSupabase(r))
        .toList();

    if (!params.nearMeEnabled ||
        params.nearMeLat == null ||
        params.nearMeLng == null) {
      return models;
    }

    final withDistance = <MapEntry<PropertyModel, double>>[];
    for (final model in models) {
      if (model.latitude == null || model.longitude == null) continue;
      final distanceKm = haversineKm(
        params.nearMeLat!,
        params.nearMeLng!,
        model.latitude!,
        model.longitude!,
      );
      if (distanceKm <= AppConstants.nearMeRadiusKm) {
        withDistance.add(MapEntry(model, distanceKm));
      }
    }
    withDistance.sort((a, b) => a.value.compareTo(b.value));
    return withDistance
        .take(AppConstants.nearMeResultCap)
        .map((e) => e.key)
        .toList();
  }

  /// Checks the bulk list, current search results, and current map results
  /// for an already-loaded copy of a property — lets the detail screen
  /// instant-paint before its dedicated fetch resolves.
  PropertyModel? findCached(String id) {
    for (final list in [_properties, _searchResults, _mapResults]) {
      for (final p in list) {
        if (p.id == id) return p;
      }
    }
    return null;
  }

  /// Id-based check, independent of whether [propertyId] happens to be
  /// cached in _properties/_searchResults/_mapResults — safe to call for a
  /// deep-linked property that isn't in any of those lists yet.
  bool isShortlisted(String propertyId) => _shortlistedIds.contains(propertyId);

  /// Optimistically toggles, then persists to `saved_properties`; rolls
  /// back on failure. No-ops when signed out, mirroring the reference
  /// portal's sign-in-required gate.
  Future<void> toggleShortlist(String propertyId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final wasShortlisted = _shortlistedIds.contains(propertyId);
    if (wasShortlisted) {
      _shortlistedIds.remove(propertyId);
    } else {
      _shortlistedIds.add(propertyId);
    }
    _syncShortlistFlags();
    notifyListeners();

    try {
      if (wasShortlisted) {
        await _savedPropertiesService.unsave(userId, propertyId);
      } else {
        await _savedPropertiesService.save(userId, propertyId);
      }
    } catch (e) {
      debugPrint('[PropertyProvider] toggleShortlist persistence failed: $e');
      if (wasShortlisted) {
        _shortlistedIds.add(propertyId);
      } else {
        _shortlistedIds.remove(propertyId);
      }
      _syncShortlistFlags();
      notifyListeners();
    }
  }

  List<PropertyModel> getShortlistedProperties() {
    return _properties.where((p) => p.isShortlisted).toList();
  }

  /// Cached properties the user has liked — same "filter what's already
  /// cached" approach as [getShortlistedProperties], backing the "Liked"
  /// tab of My Activity.
  List<PropertyModel> getLikedProperties() {
    return _properties.where((p) => _likedPropertyIds.contains(p.id)).toList();
  }

  List<PropertyModel> getFeaturedProperties() {
    return _properties.where((p) => p.isFeatured).toList();
  }
}
