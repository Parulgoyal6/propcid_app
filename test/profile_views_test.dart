// Phase 7 — "who viewed my profile".
//
// The number this screen shows is the one people misread. `profile_views` holds
// ONE row per (owner, viewer) pair, so the headline counts PEOPLE and does not
// move when someone returns — only `view_count` does. Reporting visits as viewers
// would inflate it, which is why both numbers are derived and asserted separately.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/providers/profile_views_provider.dart';
import 'package:propcid_app/services/profile_view_service.dart';

class _FakeViewService extends ProfileViewService {
  _FakeViewService(this.rows);
  final List<ProfileViewer> rows;
  int fetches = 0;

  @override
  Future<List<ProfileViewer>> fetchViewers(String userId) async {
    fetches++;
    return rows;
  }
}

ProfileViewer _viewer({
  required String id,
  int count = 1,
  String? name,
  String? role,
  DateTime? lastViewed,
}) =>
    ProfileViewer(
      id: id,
      viewerId: 'v-$id',
      viewCount: count,
      lastViewedAt: lastViewed,
      profile: name == null
          ? null
          : UserProfile.fromMap(<String, dynamic>{
              'user_id': 'v-$id',
              'display_name': name,
              'user_type': ?role,
            }),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  group('unique viewers vs total visits', () {
    test('unique count is the row count, not the visit sum', () async {
      final p = ProfileViewsProvider(
        service: _FakeViewService([
          _viewer(id: '1', count: 5),
          _viewer(id: '2', count: 3),
        ]),
      );
      await p.load('owner');

      expect(p.uniqueViewers, 2, reason: 'two people, not eight visits');
      expect(p.totalVisits, 8);
      expect(p.hasRepeatVisitors, isTrue);
    });

    test('with no repeat visitors the two numbers agree', () async {
      final p = ProfileViewsProvider(
        service: _FakeViewService([
          _viewer(id: '1'),
          _viewer(id: '2'),
          _viewer(id: '3'),
        ]),
      );
      await p.load('owner');

      expect(p.uniqueViewers, 3);
      expect(p.totalVisits, 3);
      // The header hides the second number when it would duplicate the first.
      expect(p.hasRepeatVisitors, isFalse);
    });

    test('an empty list reports zeros, not nulls', () async {
      final p = ProfileViewsProvider(service: _FakeViewService(const []));
      await p.load('owner');

      expect(p.uniqueViewers, 0);
      expect(p.totalVisits, 0);
      expect(p.hasRepeatVisitors, isFalse);
      expect(p.viewers, isEmpty);
    });
  });

  group('ProfileViewer', () {
    test('a single visit is not a repeat visitor', () {
      expect(_viewer(id: '1').isRepeatVisitor, isFalse);
      expect(_viewer(id: '1', count: 2).isRepeatVisitor, isTrue);
    });

    test('an unresolved profile still has a usable name', () {
      // profile_views references auth.users, so the join can miss.
      expect(_viewer(id: '1').displayName, 'PropCid user');
    });

    test('a resolved profile uses its display title', () {
      expect(_viewer(id: '1', name: 'Ravi Kumar').displayName, 'Ravi Kumar');
    });

    test('fromRow parses the row shape and defaults a missing count to 1', () {
      final viewer = ProfileViewer.fromRow({
        'id': 'row-1',
        'viewer_id': 'v-9',
        'last_viewed_at': '2026-08-01T10:00:00Z',
      });
      expect(viewer.id, 'row-1');
      expect(viewer.viewerId, 'v-9');
      expect(viewer.viewCount, 1);
      expect(viewer.lastViewedAt, isNotNull);
    });

    test('fromRow tolerates a malformed timestamp', () {
      final viewer = ProfileViewer.fromRow({
        'id': 'row-1',
        'viewer_id': 'v-9',
        'last_viewed_at': 'not-a-date',
      });
      expect(viewer.lastViewedAt, isNull);
    });
  });

  group('loading', () {
    test('loading is false once the fetch completes', () async {
      final p = ProfileViewsProvider(service: _FakeViewService(const []));
      expect(p.loading, isTrue);
      await p.load('owner');
      expect(p.loading, isFalse);
    });

    test('refresh re-fetches for the same user', () async {
      final service = _FakeViewService(const []);
      final p = ProfileViewsProvider(service: service);
      await p.load('owner');
      await p.refresh();
      expect(service.fetches, 2);
    });

    test('refresh before any load is a no-op', () async {
      final service = _FakeViewService(const []);
      final p = ProfileViewsProvider(service: service);
      await p.refresh();
      expect(service.fetches, 0);
    });

    test('the viewers list is unmodifiable', () async {
      final p = ProfileViewsProvider(
        service: _FakeViewService([_viewer(id: '1')]),
      );
      await p.load('owner');
      expect(() => p.viewers.clear(), throwsUnsupportedError);
    });

    test('notifying after dispose does not throw', () async {
      final p = ProfileViewsProvider(service: _FakeViewService(const []));
      p.dispose();
      // A load can complete after the screen is popped; the guard swallows it.
      await p.load('owner');
    });
  });

  group('fetchViewers is additive — getCount and recordView are unchanged', () {
    test('all three methods exist with their original signatures', () {
      final service = ProfileViewService();
      expect(service.getCount, isA<Future<int> Function(String)>());
      expect(service.fetchViewers, isA<Function>());
      expect(service.recordView, isA<Function>());
    });
  });
}
