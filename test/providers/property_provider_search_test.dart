// PropertyProvider — budget filtering, price sorting, price-aware pagination
// and stale-search protection.
//
// Uses a fake PropertyService (a minimal test seam — see PropertyProvider's
// constructor) that serves a fixed in-memory row set the way `.range()`
// pagination would, so these tests never touch a live backend.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/search_query_params.dart';
import 'package:propcid_app/providers/property_provider.dart';
import 'package:propcid_app/services/property_service.dart';

/// Serves [allRows] the way real `.range()`/`.limit()` Supabase pagination
/// would — a page for a given offset/limit, and the full row count via
/// `totalCount`, always. Records every call so tests can assert on how many
/// were made and with what shape.
class _FakePropertyService extends PropertyService {
  _FakePropertyService(this.allRows);

  final List<Map<String, dynamic>> allRows;
  final List<({int offset, int limit, bool includeRange})> calls = [];

  /// When set, the call at this zero-based index (across this instance's
  /// lifetime) awaits [_gate] before returning — used to simulate an
  /// in-flight request that resolves after a later one.
  int? delayedCallIndex;
  final Completer<void> _gate = Completer<void>();

  void releaseDelayedCall() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<PropertySearchPage> searchProperties({
    required SearchQueryParams params,
    required int offset,
    required int limit,
    bool includeRange = true,
  }) async {
    final callIndex = calls.length;
    calls.add((offset: offset, limit: limit, includeRange: includeRange));

    if (delayedCallIndex == callIndex) {
      await _gate.future;
    }

    if (!includeRange) {
      final page = allRows.take(limit).toList();
      return PropertySearchPage(rows: page, totalCount: allRows.length);
    }
    if (offset >= allRows.length) {
      return PropertySearchPage(rows: const [], totalCount: allRows.length);
    }
    final end = (offset + limit).clamp(0, allRows.length);
    return PropertySearchPage(
      rows: allRows.sublist(offset, end),
      totalCount: allRows.length,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getProperties() async => const [];
}

Map<String, dynamic> _row({
  required String id,
  required dynamic price,
  String category = 'residential',
  String propertyType = 'sell',
  DateTime? createdAt,
  int likes = 0,
}) {
  return {
    'id': id,
    'title': 'Property $id',
    'location': 'Test City',
    'price': price,
    'category': category,
    'property_type': propertyType,
    'status': 'active',
    'approval_status': 'approved',
    'created_at': (createdAt ?? DateTime(2024, 1, 1)).toIso8601String(),
    'likes': likes,
    'views': 0,
    'media_urls': <String>[],
    'hashtags': <String>[],
    'amenities': <String>[],
  };
}

SearchQueryParams _params({
  double budgetMin = AppConstants.priceMin,
  double budgetMax = AppConstants.priceMax,
  PropertySortOption sort = PropertySortOption.newest,
}) {
  return SearchQueryParams(
    budgetMin: budgetMin,
    budgetMax: budgetMax,
    sort: sort,
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // PropertyService's constructor resolves Supabase.instance.client, and
    // the fake subclasses it (see people_search_test.dart for the same
    // pattern). Loopback URL, no refresh — nothing here ever touches the
    // network, since every request goes through the fake's overridden
    // methods instead.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // Fixtures from the task spec.
  final propertyA = _row(id: 'A', price: '45,00,000'); // ₹45,00,000
  final propertyB = _row(id: 'B', price: '75,00,000'); // ₹75,00,000
  final propertyC = _row(id: 'C', price: '1.2 Cr'); // ₹1.2 Cr
  final propertyD = _row(id: 'D', price: 'Contact for price'); // unknown

  group('budget semantics', () {
    late PropertyProvider provider;

    setUp(() {
      final service = _FakePropertyService([
        propertyA,
        propertyB,
        propertyC,
        propertyD,
      ]);
      provider = PropertyProvider(propertyService: service);
    });

    test('₹50L–₹1Cr includes only the in-range property', () async {
      await provider.runSearch(
        _params(budgetMin: 5000000, budgetMax: 10000000),
      );

      final ids = provider.searchResults.map((p) => p.id).toSet();
      expect(ids, {'B'});
      expect(provider.totalResultCount, 1);
    });

    test('exact minimum and maximum boundary values are inclusive', () async {
      await provider.runSearch(
        // B is exactly ₹75,00,000 — set both bounds to that value.
        _params(budgetMin: 7500000, budgetMax: 7500000),
      );

      expect(provider.searchResults.map((p) => p.id), ['B']);
    });

    test(
      'unknown-price listings are excluded once ANY budget filter is active',
      () async {
        // A wide-but-non-default range (min still 0, max short of the ceiling)
        // is enough to activate filtering — D must disappear even though it
        // would satisfy no numeric comparison either way.
        await provider.runSearch(_params(budgetMin: 0, budgetMax: 20000000));

        final ids = provider.searchResults.map((p) => p.id).toSet();
        expect(ids, {'A', 'B', 'C'});
        expect(ids.contains('D'), isFalse);
      },
    );

    test(
      'unknown-price listings remain visible with no budget filter',
      () async {
        await provider.runSearch(_params()); // default range == inactive

        final ids = provider.searchResults.map((p) => p.id).toSet();
        expect(ids, {'A', 'B', 'C', 'D'});
      },
    );
  });

  group('price sorting', () {
    late PropertyProvider provider;

    setUp(() {
      final service = _FakePropertyService([
        propertyA,
        propertyB,
        propertyC,
        propertyD,
      ]);
      provider = PropertyProvider(propertyService: service);
    });

    test('ascending: A, B, C, D (unknown last)', () async {
      await provider.runSearch(_params(sort: PropertySortOption.priceAsc));
      expect(provider.searchResults.map((p) => p.id), ['A', 'B', 'C', 'D']);
    });

    test('descending: C, B, A, D (unknown last)', () async {
      await provider.runSearch(_params(sort: PropertySortOption.priceDesc));
      expect(provider.searchResults.map((p) => p.id), ['C', 'B', 'A', 'D']);
    });

    test('equal prices break ties deterministically by id', () async {
      final service = _FakePropertyService([
        _row(id: 'Z', price: 5000000),
        _row(id: 'Y', price: 5000000),
        _row(id: 'X', price: 5000000),
      ]);
      final p = PropertyProvider(propertyService: service);

      await p.runSearch(_params(sort: PropertySortOption.priceAsc));
      final first = p.searchResults.map((m) => m.id).toList();

      await p.runSearch(_params(sort: PropertySortOption.priceAsc));
      final second = p.searchResults.map((m) => m.id).toList();

      expect(first, ['X', 'Y', 'Z']); // lexicographic id tiebreak
      expect(
        second,
        first,
        reason: 'identical input must sort identically every time',
      );
    });
  });

  group('price-aware pagination over the complete matching set', () {
    test(
      'a valid budget match beyond the old 300-row cap is included',
      () async {
        // 320 rows: the first 319 are out of budget, the very last one matches.
        final rows = [
          for (int i = 0; i < 319; i++) _row(id: 'r$i', price: 100000000),
          _row(id: 'the-match', price: 6000000),
        ];
        final service = _FakePropertyService(rows);
        final provider = PropertyProvider(propertyService: service);

        await provider.runSearch(
          _params(budgetMin: 5000000, budgetMax: 7000000),
        );

        expect(provider.searchResults.map((p) => p.id), contains('the-match'));
        expect(provider.totalResultCount, 1);
        // Proves the fetch actually walked past the old 300-row cap in pages,
        // rather than a single capped batch.
        expect(
          service.calls.where((c) => c.includeRange).length,
          greaterThan(1),
        );
      },
    );

    test(
      'final result count is the post-budget count, not the DB total',
      () async {
        final rows = [
          for (int i = 0; i < 50; i++) _row(id: 'in$i', price: 6000000),
          for (int i = 0; i < 50; i++) _row(id: 'out$i', price: 100000000),
        ];
        final provider = PropertyProvider(
          propertyService: _FakePropertyService(rows),
        );

        await provider.runSearch(
          _params(budgetMin: 5000000, budgetMax: 7000000),
        );

        expect(provider.totalResultCount, 50);
      },
    );

    test('load-more does not duplicate or skip properties', () async {
      final rows = [
        for (int i = 0; i < 45; i++)
          _row(id: 'p${i.toString().padLeft(2, '0')}', price: 6000000),
      ];
      final provider = PropertyProvider(
        propertyService: _FakePropertyService(rows),
      );
      final params = _params(budgetMin: 5000000, budgetMax: 7000000);

      await provider.runSearch(params);
      expect(provider.searchResults.length, AppConstants.searchPageSize);
      expect(provider.hasMoreResults, isTrue);

      await provider.loadMoreResults(params);
      await provider.loadMoreResults(params);

      expect(provider.searchResults.length, 45);
      final ids = provider.searchResults.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'no duplicates');
      expect(provider.hasMoreResults, isFalse);
    });

    test('changing the sort resets the client buffer', () async {
      final provider = PropertyProvider(
        propertyService: _FakePropertyService([
          propertyA,
          propertyB,
          propertyC,
        ]),
      );

      await provider.runSearch(_params(sort: PropertySortOption.priceAsc));
      expect(provider.searchResults.map((p) => p.id), ['A', 'B', 'C']);

      await provider.runSearch(_params(sort: PropertySortOption.priceDesc));
      expect(provider.searchResults.map((p) => p.id), ['C', 'B', 'A']);
    });

    test(
      'newest/popular without budget keeps using the normal paginated path',
      () async {
        final rows = [
          for (int i = 0; i < 5; i++) _row(id: 'p$i', price: 5000000),
        ];
        final service = _FakePropertyService(rows);
        final provider = PropertyProvider(propertyService: service);

        await provider.runSearch(_params(sort: PropertySortOption.newest));

        expect(service.calls, hasLength(1));
        expect(service.calls.single.limit, AppConstants.searchPageSize);
        expect(service.calls.single.includeRange, isTrue);
      },
    );
  });

  group('stale-request protection', () {
    test('an older in-flight search cannot overwrite a newer one', () async {
      final service = _FakePropertyService([propertyA, propertyB, propertyC]);
      // Delay the very first request this service ever serves — the one
      // issued by the first (soon-to-be-stale) runSearch call below.
      service.delayedCallIndex = 0;
      final provider = PropertyProvider(propertyService: service);

      final staleSearch = provider.runSearch(
        _params(sort: PropertySortOption.priceAsc),
      );
      // Let the stale search actually start (and block on the gate) before
      // issuing the newer one.
      await Future<void>.delayed(Duration.zero);

      final freshSearch = provider.runSearch(
        _params(sort: PropertySortOption.priceDesc),
      );
      await freshSearch;

      expect(
        provider.searchResults.map((p) => p.id),
        ['C', 'B', 'A'],
        reason: 'the newer (descending) search must be what is on screen',
      );

      // Now let the stale request finish; it must not clobber the result
      // the newer search already committed.
      service.releaseDelayedCall();
      await staleSearch;

      expect(provider.searchResults.map((p) => p.id), ['C', 'B', 'A']);
    });
  });
}
