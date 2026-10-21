// People Search — portal parity, paging, card rendering and navigation.
//
// The portal reference for every assertion here is tabulated in
// docs/PEOPLE_SEARCH_PORTAL_COMPARISON.md. What is pinned:
//
//   * the `or=` filter string, which is the one part of the query built from user
//     text (SearchModal.tsx:115-117);
//   * the rating fold, which must produce the same number as
//     ExploreCity.tsx:217-235 and as the Public Profile screen;
//   * the role vocabulary, including the two values the portal filters on that
//     the `user_type` CHECK constraint forbids;
//   * pagination, which the portal does not have and which therefore has no
//     reference behaviour to copy — only correctness to hold to.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/global_search_suggestion.dart';
import 'package:propcid_app/models/people_search_result.dart';
import 'package:propcid_app/models/profile_review.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/filter_provider.dart';
import 'package:propcid_app/providers/navigation_provider.dart';
import 'package:propcid_app/providers/people_search_provider.dart';
import 'package:propcid_app/providers/recent_searches_provider.dart';
import 'package:propcid_app/screens/search/people_search_screen.dart';
import 'package:propcid_app/screens/search/search_screen.dart';
import 'package:propcid_app/screens/search/widgets/people_result_card.dart';
import 'package:propcid_app/services/people_search_service.dart';
import 'package:propcid_app/services/property_service.dart';

import 'support/overflow_detector.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

/// 320 dp — the narrowest phone the app supports, and where the meta strip is
/// tightest.
const Size kSmall = Size(320, 720);

UserProfile _person({
  required String id,
  String? name = 'Rahul Sharma',
  String? username,
  String? company,
  String? agency,
  String? city,
  String? workCity,
  String userType = 'broker',
  int? yearsExperience,
  int? yearsOfExperience,
  String? rera,
  String? licence,
  String? verificationStatus,
}) {
  return UserProfile.fromMap(<String, dynamic>{
    'user_id': id,
    'display_name': name,
    'username': username,
    'company_name': company,
    'agency_name': agency,
    'city': city,
    'work_city': workCity,
    'user_type': userType,
    'years_experience': yearsExperience,
    'years_of_experience': yearsOfExperience,
    'rera_number': rera,
    'license_number': licence,
    'verification_status': verificationStatus,
  });
}

List<UserProfile> _people(int count, {String prefix = 'u'}) => List.generate(
      count,
      (i) => _person(id: '$prefix-$i', name: 'Person $i'),
    );

/// Records every call and replays a scripted list of pages.
class _FakePeopleSearchService extends PeopleSearchService {
  _FakePeopleSearchService({
    List<PeopleSearchPage>? pages,
    this.ratings = const {},
  }) : _pages = pages ?? const [];

  final List<PeopleSearchPage> _pages;
  Map<String, RatingSummary> ratings;

  final List<({String query, PeopleRole role, int offset, int limit})> calls = [];
  int ratingFetches = 0;

  /// When set, the next `searchPeople` blocks on this instead of returning.
  Completer<PeopleSearchPage>? gate;

  /// When true, the next `searchPeople` throws.
  bool shouldFail = false;

  @override
  Future<PeopleSearchPage> searchPeople({
    required String query,
    PeopleRole role = PeopleRole.all,
    int offset = 0,
    int limit = 20,
  }) async {
    calls.add((query: query, role: role, offset: offset, limit: limit));

    if (shouldFail) {
      shouldFail = false;
      throw Exception('forced failure');
    }

    final pending = gate;
    if (pending != null) {
      gate = null;
      return pending.future;
    }

    final index = calls.length - 1;
    if (index < _pages.length) return _pages[index];
    return PeopleSearchPage.empty;
  }

  @override
  Future<Map<String, RatingSummary>> fetchRatings(Iterable<String> userIds) async {
    ratingFetches++;
    return ratings;
  }
}


/// Returns scripted `global_search` suggestions instead of calling the RPC.
class _FakeGlobalSearchService extends PropertyService {
  _FakeGlobalSearchService(this.suggestions);

  final List<GlobalSearchSuggestion> suggestions;

  @override
  Future<List<GlobalSearchSuggestion>> globalSearch(String term) async =>
      suggestions;
}

GlobalSearchSuggestion _suggestion({
  required String id,
  required String label,
  required String type,
  String? description,
}) =>
    GlobalSearchSuggestion.fromSupabase({
      'result_id': id,
      'label': label,
      'type': type,
      'description': description,
    });

Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// Pumps the screen with an injected provider, recording every named push so
/// navigation can be asserted without a real profile screen.
Future<List<RouteSettings>> _pumpScreen(
  WidgetTester tester, {
  required PeopleSearchProvider provider,
  String initialQuery = '',
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PeopleSearchScreen(
        initialQuery: initialQuery,
        providerOverride: provider,
      ),
      onGenerateRoute: (settings) {
        pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SizedBox.shrink(),
        );
      },
    ),
  );
  await tester.pump();
  return pushed;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // PeopleSearchService's constructor resolves Supabase.instance.client, and the
    // fake subclasses it. Loopback URL, no refresh — nothing touches the network.
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

  // ── 1. The or= filter string ────────────────────────────────────────────
  group('text filter', () {
    test('a plain term produces the portal\'s exact filter string', () {
      // SearchModal.tsx:115-117, byte for byte:
      //   `display_name.ilike.%q%,company_name.ilike.%q%,bio.ilike.%q%`
      expect(
        PeopleSearchService.buildTextFilter('rahul'),
        'display_name.ilike.%rahul%,'
        'company_name.ilike.%rahul%,'
        'bio.ilike.%rahul%',
      );
    });

    test('a term is trimmed before it is matched', () {
      expect(
        PeopleSearchService.buildTextFilter('  rahul  '),
        contains('display_name.ilike.%rahul%'),
      );
    });

    test('a period needs no quoting — it is not a PostgREST metacharacter', () {
      expect(PeopleSearchService.filterValue('n.k. builders'),
          '%n.k. builders%');
    });

    test('a comma is quoted instead of splitting the filter into four terms',
        () {
      // Unquoted, `Sharma, Rahul` would make PostgREST read `Rahul%` as a fourth
      // condition. This is portal defect D3.
      expect(PeopleSearchService.filterValue('Sharma, Rahul'),
          '"%Sharma, Rahul%"');
      expect(
        PeopleSearchService.buildTextFilter('Sharma, Rahul').split('.ilike.').length,
        4,
        reason: 'still exactly three conditions',
      );
    });

    test('parentheses are quoted', () {
      expect(PeopleSearchService.filterValue('ABC (India)'), '"%ABC (India)%"');
    });

    test('embedded quotes and backslashes are escaped inside the quoting', () {
      expect(PeopleSearchService.filterValue('a"b'), r'"%a\"b%"');
      expect(PeopleSearchService.filterValue(r'a\b,c'), r'"%a\\b,c%"');
    });
  });

  // ── 2. Role vocabulary ──────────────────────────────────────────────────
  group('roles', () {
    test('All sends no user_type predicate', () {
      // Reproduces SearchModal.tsx:112, Search.tsx:1264 and NewChatModal.tsx:49,
      // none of which filters by role.
      expect(PeopleRole.all.userType, isNull);
    });

    test('the four named roles are valid user_type values', () {
      // 20260326000000_fix_admin_user_types.sql:21.
      const allowed = {
        'builder',
        'broker',
        'influencer',
        'individual',
        'seller',
        'dealer',
      };
      for (final role in PeopleRole.values) {
        if (role.userType == null) continue;
        expect(allowed, contains(role.userType));
      }
    });

    test('the portal\'s two dead role values are not reproduced', () {
      // BrokersList.tsx:58 filters on `agent` and BuildersList.tsx:53 on
      // `developer`; neither is a legal user_type, so both match nothing.
      final values = PeopleRole.values.map((r) => r.userType).toSet();
      expect(values, isNot(contains('agent')));
      expect(values, isNot(contains('developer')));
    });
  });

  // ── 3. Rating fold — ExploreCity parity ─────────────────────────────────
  group('rating aggregation', () {
    test('averages to one decimal, exactly as the portal does', () {
      // ExploreCity.tsx:229: Number((sum / count).toFixed(1)). 13/3 = 4.333…
      final result = PeopleSearchService.aggregateRatings([
        {'rated_user_id': 'u-1', 'rating': 5},
        {'rated_user_id': 'u-1', 'rating': 4},
        {'rated_user_id': 'u-1', 'rating': 4},
      ]);
      expect(result['u-1']!.average, 4.3);
      expect(result['u-1']!.count, 3);
    });

    test('groups per user', () {
      final result = PeopleSearchService.aggregateRatings([
        {'rated_user_id': 'u-1', 'rating': 5},
        {'rated_user_id': 'u-2', 'rating': 2},
        {'rated_user_id': 'u-1', 'rating': 3},
      ]);
      expect(result['u-1']!.average, 4.0);
      expect(result['u-2']!.average, 2.0);
    });

    test('an unrated user is absent, not zero', () {
      // ExploreCity.tsx:228-230 leaves the average `undefined` and hides the
      // stars. A 0.0 would read as a bad rating rather than no rating.
      final result = PeopleSearchService.aggregateRatings([
        {'rated_user_id': 'u-1', 'rating': 5},
      ]);
      expect(result.containsKey('u-2'), isFalse);
    });

    test('malformed rows are skipped rather than counted as zero', () {
      final result = PeopleSearchService.aggregateRatings([
        {'rated_user_id': 'u-1', 'rating': 5},
        {'rated_user_id': 'u-1', 'rating': null},
        {'rated_user_id': 'u-1', 'rating': 'five'},
        {'rated_user_id': null, 'rating': 1},
      ]);
      expect(result['u-1']!.count, 1);
      expect(result['u-1']!.average, 5.0);
    });
  });

  // ── 4. Provider: search, paging, staleness, failure ─────────────────────
  group('provider', () {
    test('an empty query never reaches the network', () async {
      final service = _FakePeopleSearchService();
      final provider = PeopleSearchProvider(service: service);

      await provider.search('   ');

      expect(service.calls, isEmpty);
      expect(provider.isIdle, isTrue);
      expect(provider.results, isEmpty);
      expect(provider.isEmptyResult, isFalse,
          reason: 'no query is not the same as no matches');
    });

    test('the first page populates results, count and hasMore', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20), totalCount: 47),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');

      expect(provider.results.length, 20);
      expect(provider.totalCount, 47);
      expect(provider.hasMore, isTrue);
      expect(provider.hasSearched, isTrue);
      expect(provider.isEmptyResult, isFalse);
      expect(service.calls.single.offset, 0);
      expect(service.calls.single.limit, 20);
    });

    test('loadMore appends the next page and advances the offset', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20, prefix: 'a'), totalCount: 30),
        PeopleSearchPage(rows: _people(10, prefix: 'b'), totalCount: 30),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');
      await provider.loadMore();

      expect(provider.results.length, 30);
      expect(service.calls[1].offset, 20);
      expect(provider.hasMore, isFalse, reason: 'the reported total is reached');
    });

    test('loadMore is a no-op once there is no more', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(3), totalCount: 3),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');
      await provider.loadMore();

      expect(service.calls.length, 1);
    });

    test('a short page ends pagination when no count came back', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(7), totalCount: null),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');

      expect(provider.hasMore, isFalse);
    });

    test('a full page keeps pagination open when no count came back', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20), totalCount: null),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');

      expect(provider.hasMore, isTrue);
    });

    test('a role chip re-runs from the first page, carrying the role', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20), totalCount: 40),
        PeopleSearchPage(rows: _people(2, prefix: 'b'), totalCount: 2),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');
      await provider.selectRole(PeopleRole.builder);

      expect(service.calls[1].role, PeopleRole.builder);
      expect(service.calls[1].offset, 0, reason: 'a new filter is a new search');
      expect(provider.results.length, 2, reason: 'results replaced, not appended');
    });

    test('re-selecting the active role does not re-query', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(1), totalCount: 1),
      ]);
      final provider = PeopleSearchProvider(service: service);

      await provider.search('rahul');
      await provider.selectRole(PeopleRole.all);

      expect(service.calls.length, 1);
    });

    test('a superseded query is discarded when it finally lands', () async {
      final service = _FakePeopleSearchService(pages: [
        // Index 0 is gated below; index 1 is what the second search returns.
        PeopleSearchPage.empty,
        PeopleSearchPage(rows: _people(2, prefix: 'new'), totalCount: 2),
      ]);
      final provider = PeopleSearchProvider(service: service);

      final gate = Completer<PeopleSearchPage>();
      service.gate = gate;
      final stale = provider.search('ra');

      // The second search supersedes the first while it is still in flight.
      await provider.search('rahul');
      expect(provider.results.length, 2);

      gate.complete(
        PeopleSearchPage(rows: _people(9, prefix: 'stale'), totalCount: 9),
      );
      await stale;

      expect(provider.results.length, 2,
          reason: 'the stale page must not overwrite the newer one');
      expect(provider.totalCount, 2);
    });

    test('a failed search sets hasError and clears the list', () async {
      final service = _FakePeopleSearchService()..shouldFail = true;
      final provider = PeopleSearchProvider(service: service);

      await provider.search('rahul');

      expect(provider.hasError, isTrue);
      expect(provider.results, isEmpty);
      expect(provider.isSearching, isFalse);
      expect(provider.isEmptyResult, isFalse,
          reason: 'a failure is not an empty result');
    });

    test('a failed loadMore keeps the results already on screen', () async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20), totalCount: 40),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);

      await provider.search('rahul');
      service.shouldFail = true;
      await provider.loadMore();

      expect(provider.results.length, 20);
      expect(provider.hasError, isFalse);
      expect(provider.isLoadingMore, isFalse);
    });

    test('retry re-issues the identical search', () async {
      final service = _FakePeopleSearchService()..shouldFail = true;
      final provider = PeopleSearchProvider(service: service);

      await provider.search('rahul');
      await provider.retry();

      expect(service.calls.length, 2);
      expect(service.calls[1].query, 'rahul');
      expect(provider.hasError, isFalse);
    });

    test('ratings arrive after the page and attach to the right rows', () async {
      final service = _FakePeopleSearchService(
        pages: [
          PeopleSearchPage(rows: _people(3), totalCount: 3),
        ],
        ratings: {
          'u-1': const RatingSummary(average: 4.5, count: 2),
        },
      );
      final provider = PeopleSearchProvider(service: service);

      await provider.search('rahul');

      expect(service.ratingFetches, 1);
      expect(provider.results[1].rating!.average, 4.5);
      expect(provider.results[0].rating, isNull,
          reason: 'unrated people stay unrated');
    });

    test('an empty result is reported as empty, not as an error', () async {
      final service = _FakePeopleSearchService(pages: [
        const PeopleSearchPage(rows: [], totalCount: 0),
      ]);
      final provider = PeopleSearchProvider(service: service);

      await provider.search('zzzz');

      expect(provider.isEmptyResult, isTrue);
      expect(provider.hasError, isFalse);
      expect(service.ratingFetches, 0, reason: 'no ids to fetch ratings for');
    });
  });

  // ── 5. The result card ──────────────────────────────────────────────────
  group('result card', () {
    Widget card(PersonResult result, {VoidCallback? onTap}) => _host(
          Padding(
            padding: const EdgeInsets.all(16),
            child: PeopleResultCard(result: result, onTap: onTap ?? () {}),
          ),
        );

    testWidgets('shows every field the requirement lists', (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(card(PersonResult(
        profile: _person(
          id: 'u-1',
          name: 'Rahul Sharma',
          username: 'rahul',
          company: 'Prestige Realty',
          workCity: 'Pune',
          userType: 'broker',
          yearsExperience: 7,
          rera: 'A5200001234',
        ),
        rating: const RatingSummary(average: 4.6, count: 12),
      )));
      await tester.pump();

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('BROKER'), findsOneWidget);
      expect(find.text('Prestige Realty'), findsOneWidget);
      expect(find.text('@rahul'), findsOneWidget);
      expect(find.text('Pune'), findsOneWidget);
      expect(find.text('7 yrs exp'), findsOneWidget);
      expect(find.text('4.6 (12)'), findsOneWidget);
      expect(find.text('A5200001234'), findsOneWidget);
      expect(find.text('RERA'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('absent fields render nothing at all', (tester) async {
      await tester.pumpWidget(card(PersonResult(
        profile: _person(
          id: 'u-2',
          name: 'Anita Rao',
          userType: 'individual',
        ),
      )));
      await tester.pump();

      expect(find.text('Anita Rao'), findsOneWidget);
      expect(find.text('MEMBER'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('exp'), findsNothing);
      expect(find.text('RERA'), findsNothing);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
    });

    testWidgets('city falls back from city to work_city', (tester) async {
      // UserProfile.effectiveCity — `city || work_city`, UserProfile.tsx:1099.
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-3', city: '', workCity: 'Nagpur'),
      )));
      await tester.pump();
      expect(find.text('Nagpur'), findsOneWidget);
    });

    testWidgets('experience falls back to years_of_experience', (tester) async {
      // BrokersList.tsx:127 — `years_experience || years_of_experience`, where a
      // JavaScript 0 is falsy and loses to the next candidate.
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-4', yearsExperience: 0, yearsOfExperience: 9),
      )));
      await tester.pump();
      expect(find.text('9 yrs exp'), findsOneWidget);
    });

    testWidgets('one year is singular', (tester) async {
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-5', yearsExperience: 1),
      )));
      await tester.pump();
      expect(find.text('1 yr exp'), findsOneWidget);
    });

    testWidgets('the verified badge is data-driven, not always drawn',
        (tester) async {
      // The portal draws <ShieldCheck/> on every directory card regardless of
      // verification_status (defect D2). This must not.
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-6', verificationStatus: 'pending'),
      )));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsNothing);

      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-7', verificationStatus: 'verified'),
      )));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('a RERA number alone counts as verified', (tester) async {
      // UserProfile.isVerified, verbatim from UserProfile.tsx:1038.
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-8', rera: 'A5200009999'),
      )));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('the company name is not repeated when it is the heading',
        (tester) async {
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-9', name: null, company: 'Prestige Realty'),
      )));
      await tester.pump();
      expect(find.text('Prestige Realty'), findsOneWidget);
    });

    testWidgets('a nameless profile still renders something tappable',
        (tester) async {
      await tester.pumpWidget(card(PersonResult(
        profile: _person(id: 'u-10', name: null),
      )));
      await tester.pump();
      expect(find.text('PropCid Member'), findsOneWidget);
    });

    testWidgets('a long name and a long company do not overflow at 320 dp',
        (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(card(PersonResult(
        profile: _person(
          id: 'u-11',
          name: 'Venkatanarasimharajuvaripeta Subramanian Iyer',
          company: 'Prestige Estates Projects And Developers Limited',
          username: 'venkatanarasimharaju_subramanian',
          workCity: 'Thiruvananthapuram',
          yearsExperience: 18,
          rera: 'A52000012345678901234',
        ),
        rating: const RatingSummary(average: 4.9, count: 1234),
      )));
      await tester.pump();

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('survives 130% text scale at 320 dp', (tester) async {
      tester.view.physicalSize = kSmall;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(
        Padding(
          padding: const EdgeInsets.all(16),
          child: PeopleResultCard(
            result: PersonResult(
              profile: _person(
                id: 'u-12',
                name: 'Rahul Sharma',
                username: 'rahul',
                company: 'Prestige Realty',
                workCity: 'Pune',
                yearsExperience: 7,
                rera: 'A5200001234',
              ),
              rating: const RatingSummary(average: 4.6, count: 12),
            ),
            onTap: () {},
          ),
        ),
        textScale: 1.3,
      ));
      await tester.pump();

      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('tapping the card invokes its handler exactly once',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(card(
        PersonResult(profile: _person(id: 'u-13')),
        onTap: () => taps++,
      ));
      await tester.pump();

      await tester.tap(find.byType(PeopleResultCard));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });
  });

  // ── 6. The screen ───────────────────────────────────────────────────────
  group('screen', () {
    testWidgets('an untouched screen prompts instead of showing an empty state',
        (tester) async {
      final provider = PeopleSearchProvider(service: _FakePeopleSearchService());
      await _pumpScreen(tester, provider: provider);

      expect(find.text('Find people on PropCid'), findsOneWidget);
      expect(find.byType(PeopleResultSkeleton), findsNothing);
    });

    testWidgets('an initial query starts a search on open', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(2), totalCount: 2),
      ]);
      final provider = PeopleSearchProvider(service: service);

      await _pumpScreen(tester, provider: provider, initialQuery: 'rahul');
      await tester.pumpAndSettle();

      expect(service.calls.single.query, 'rahul');
      expect(find.byType(PeopleResultCard), findsNWidgets(2));
    });

    testWidgets('a first load shows skeletons, not a spinner', (tester) async {
      final service = _FakePeopleSearchService();
      final gate = Completer<PeopleSearchPage>();
      service.gate = gate;
      final provider = PeopleSearchProvider(service: service);

      await _pumpScreen(tester, provider: provider, initialQuery: 'rahul');
      await tester.pump();

      expect(find.byType(PeopleResultSkeleton), findsWidgets);

      gate.complete(const PeopleSearchPage(rows: [], totalCount: 0));
      await tester.pumpAndSettle();
    });

    testWidgets('no matches echoes the query back', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        const PeopleSearchPage(rows: [], totalCount: 0),
      ]);
      final provider = PeopleSearchProvider(service: service);
      await provider.search('zzzz');

      await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      expect(find.text('No matches found'), findsOneWidget);
      expect(find.textContaining('zzzz'), findsOneWidget);
      expect(find.text('Try another search'), findsOneWidget);
    });

    testWidgets('a failure offers a retry that re-queries', (tester) async {
      final service = _FakePeopleSearchService()..shouldFail = true;
      final provider = PeopleSearchProvider(service: service);
      await provider.search('rahul');

      await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load results"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(service.calls.length, 2);
    });

    testWidgets('the count line reads from the query\'s exact count',
        (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(20), totalCount: 47),
      ]);
      final provider = PeopleSearchProvider(service: service, pageSize: 20);
      await provider.search('rahul');

      await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      expect(find.text('47 people found'), findsOneWidget);
    });

    testWidgets('one match is singular', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(1), totalCount: 1),
      ]);
      final provider = PeopleSearchProvider(service: service);
      await provider.search('rahul');

      await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      expect(find.text('1 person found'), findsOneWidget);
    });

    testWidgets('tapping a result opens the public profile with its userId',
        (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: [_person(id: 'user-42')], totalCount: 1),
      ]);
      final provider = PeopleSearchProvider(service: service);
      await provider.search('rahul');

      final pushed = await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PeopleResultCard));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(pushed.single.name, AppConstants.publicProfileScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['userId'],
        'user-42',
      );
    });

    testWidgets('a role chip filters through the provider', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(3), totalCount: 3),
        PeopleSearchPage(rows: _people(1, prefix: 'b'), totalCount: 1),
      ]);
      final provider = PeopleSearchProvider(service: service);
      await provider.search('rahul');

      await _pumpScreen(tester, provider: provider);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Builders'));
      await tester.pumpAndSettle();

      expect(service.calls[1].role, PeopleRole.builder);
      expect(find.byType(PeopleResultCard), findsOneWidget);
    });

    testWidgets('all five role chips are offered', (tester) async {
      final provider = PeopleSearchProvider(service: _FakePeopleSearchService());
      await _pumpScreen(tester, provider: provider);

      for (final role in PeopleRole.values) {
        expect(find.text(role.label), findsOneWidget);
      }
    });

    testWidgets('the whole screen is laid out cleanly at 320 dp and 130%',
        (tester) async {
      final service = _FakePeopleSearchService(
        pages: [
          PeopleSearchPage(
            rows: [
              _person(
                id: 'u-1',
                name: 'Rahul Sharma',
                username: 'rahul',
                company: 'Prestige Realty',
                workCity: 'Pune',
                yearsExperience: 7,
                rera: 'A5200001234',
              ),
            ],
            totalCount: 1,
          ),
        ],
        ratings: {'u-1': const RatingSummary(average: 4.6, count: 12)},
      );
      final provider = PeopleSearchProvider(service: service);
      await provider.search('rahul');

      await _pumpScreen(tester, provider: provider, textScale: 1.3);
      await tester.pumpAndSettle();

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 7. The entry point on the existing Search screen ────────────────────
  //
  // This is the only pre-existing screen the feature modifies, so the property
  // paths it must NOT disturb are asserted alongside the people paths it adds.
  //
  // `global_search` is scripted through `propertyServiceOverride`. Tests that
  // pass no `places` leave it returning nothing, which also covers the isolation
  // case: people still render when the place fetch yields nothing.
  group('search entry point', () {
    Future<List<RouteSettings>> pumpSearch(
      WidgetTester tester,
      PeopleSearchService service, {
      List<GlobalSearchSuggestion> places = const [],
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pushed = <RouteSettings>[];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NavigationProvider()),
            ChangeNotifierProvider(create: (_) => FilterProvider()),
            // Takes an AuthProvider; a fresh one is signed out, which is the
            // "no recent searches" branch the dropdown wants here.
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProxyProvider<AuthProvider, RecentSearchesProvider>(
              create: (context) =>
                  RecentSearchesProvider(context.read<AuthProvider>()),
              update: (_, auth, previous) =>
                  previous ?? RecentSearchesProvider(auth),
            ),
          ],
          child: MaterialApp(
            home: SearchScreen(
              peopleSearchServiceOverride: service,
              propertyServiceOverride: _FakeGlobalSearchService(places),
            ),
            onGenerateRoute: (settings) {
              pushed.add(settings);
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const SizedBox.shrink(),
              );
            },
          ),
        ),
      );
      await tester.pump();
      return pushed;
    }

    /// Types [term], lets the 300 ms debounce fire, then settles the dropdown's
    /// own fade-in — which leaves a pending timer if it is not drained.
    Future<void> type(WidgetTester tester, String term) async {
      await tester.enterText(find.byType(TextField).first, term);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
    }

    testWidgets('a PEOPLE group appears once people match', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(
          rows: [
            _person(id: 'p-1', name: 'Rahul Sharma', company: 'Prestige Realty'),
          ],
          totalCount: 1,
        ),
      ]);

      await pumpSearch(tester, service);
      await type(tester, 'rahul');

      expect(find.text('PEOPLE'), findsOneWidget);
      expect(find.text('Rahul Sharma'), findsOneWidget);
      // SearchModal.tsx:494-501's subtitle composition.
      expect(find.text('Broker at Prestige Realty'), findsOneWidget);
    });

    testWidgets('the dropdown asks for exactly five people', (tester) async {
      // SearchModal.tsx:118 caps its People section at 5.
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(5), totalCount: 40),
      ]);

      await pumpSearch(tester, service);
      await type(tester, 'rahul');

      expect(service.calls.single.limit, 5);
      expect(service.calls.single.offset, 0);
    });

    testWidgets('no people means no heading at all', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        const PeopleSearchPage(rows: [], totalCount: 0),
      ]);

      await pumpSearch(tester, service);
      await type(tester, 'zzzz');

      expect(find.text('PEOPLE'), findsNothing);
      expect(find.textContaining('See all people'), findsNothing);
    });

    testWidgets('under three characters nothing is fetched', (tester) async {
      // The existing floor stays where it is; this asserts the people fetch does
      // not lower it.
      final service = _FakePeopleSearchService();

      await pumpSearch(tester, service);
      await type(tester, 'ra');

      expect(service.calls, isEmpty);
    });

    testWidgets('tapping a person opens their public profile', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(
          rows: [_person(id: 'p-99', name: 'Rahul Sharma')],
          totalCount: 1,
        ),
      ]);

      final pushed = await pumpSearch(tester, service);
      await type(tester, 'rahul');
      await tester.tap(find.text('Rahul Sharma'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.publicProfileScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['userId'],
        'p-99',
      );
    });

    testWidgets('"See all people" opens People Search with the query',
        (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(5), totalCount: 40),
      ]);

      final pushed = await pumpSearch(tester, service);
      await type(tester, 'rahul');
      await tester.tap(find.textContaining('See all people'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.peopleSearchScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['query'],
        'rahul',
      );
    });

    testWidgets('clearing the box clears the People group too', (tester) async {
      final service = _FakePeopleSearchService(pages: [
        PeopleSearchPage(rows: _people(2), totalCount: 2),
      ]);

      await pumpSearch(tester, service);
      await type(tester, 'rahul');
      expect(find.text('PEOPLE'), findsOneWidget);

      await type(tester, '');

      expect(find.text('PEOPLE'), findsNothing,
          reason: 'a stale People group must not outlive its query',
      );
    });

    // ── Spec J: project suggestions ────────────────────────────────────────
    //
    // `project` was dropped while no project detail screen existed. Its branch of
    // the RPC filters `status = 'active' AND approval_status = 'approved'`, so
    // surfacing it needs no extra client-side gate — and the payload carries no
    // status column one could filter on anyway.
    testWidgets('a PROJECTS group appears and opens the project detail',
        (tester) async {
      final pushed = await pumpSearch(
        tester,
        _FakePeopleSearchService(),
        places: [
          _suggestion(
            id: 'proj-1',
            label: 'Green Valley Heights',
            type: 'project',
            description: 'Pune',
          ),
        ],
      );
      await type(tester, 'green');

      expect(find.text('PROJECTS'), findsOneWidget);
      expect(find.text('Green Valley Heights'), findsOneWidget);

      await tester.tap(find.text('Green Valley Heights'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.projectDetailScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['projectId'],
        'proj-1',
      );
    });

    testWidgets('a property suggestion still opens the property detail',
        (tester) async {
      // The two types share the dropdown; adding one must not divert the other.
      final pushed = await pumpSearch(
        tester,
        _FakePeopleSearchService(),
        places: [
          _suggestion(id: 'prop-1', label: 'Sea View 3BHK', type: 'property'),
        ],
      );
      await type(tester, 'sea');

      expect(find.text('PROPERTIES'), findsOneWidget);
      await tester.tap(find.text('Sea View 3BHK'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.propertyDetailScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['propertyId'],
        'prop-1',
      );
    });

    testWidgets('builder rows from the RPC are still discarded', (tester) async {
      // Unlike the project branch, the profiles branch has no approval_status or
      // is_blocked predicate, so it can return pending and blocked profiles.
      // People come from PeopleSearchService instead.
      await pumpSearch(
        tester,
        _FakePeopleSearchService(),
        places: [
          _suggestion(id: 'b-1', label: 'Shady Builders', type: 'builder'),
        ],
      );
      await type(tester, 'shady');

      expect(find.text('Shady Builders'), findsNothing);
    });

    testWidgets('cities, properties and projects group in a fixed order',
        (tester) async {
      await pumpSearch(
        tester,
        _FakePeopleSearchService(),
        places: [
          _suggestion(id: 'p-1', label: 'A Property', type: 'property'),
          _suggestion(id: 'proj-1', label: 'A Project', type: 'project'),
          _suggestion(id: 'c-1', label: 'Pune', type: 'city'),
        ],
      );
      await type(tester, 'pune');

      final cities = tester.getRect(find.text('CITIES')).top;
      final properties = tester.getRect(find.text('PROPERTIES')).top;
      final projects = tester.getRect(find.text('PROJECTS')).top;
      expect(cities, lessThan(properties));
      expect(properties, lessThan(projects));
    });

    testWidgets('a people failure leaves the rest of the screen intact',
        (tester) async {
      final service = _FakePeopleSearchService()..shouldFail = true;

      await pumpSearch(tester, service);
      await type(tester, 'rahul');

      expect(tester.takeException(), isNull);
      expect(find.text('PEOPLE'), findsNothing);
      // The property side's own no-suggestions fallback still renders, which is
      // the isolation being checked: the people branch failed and the property
      // branch's code path is unaffected.
      expect(
        find.text('Press search to look for "rahul".'),
        findsOneWidget,
      );
    });
  });
}
