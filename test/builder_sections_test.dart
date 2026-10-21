// Spec H — Inventory, Marketed Offers, Team and Site Visits.
//
// What is pinned:
//
//   * the vocabularies, each of which is a CHECK constraint or a portal picker —
//     project status (all four values, unlike listings where the portal exposes
//     two of four), unit status, booking status, team modules;
//   * `project_inventory`'s fold, including the detail that `booked` and `blocked`
//     land in neither counter, so sold + available can be less than total;
//   * NULL `project_ids` meaning **all projects**, which an empty list would lose;
//   * which booking statuses notify the visitor, and that a cancellation omits the
//     new slot from the message;
//   * the empty-id guard on every `inFilter`, because PostgREST answers an empty
//     `in` with every visible row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/builder_section_options.dart';
import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/screens/dashboard/widgets/builder_offers_section.dart';
import 'package:propcid_app/screens/dashboard/widgets/builder_site_visits_section.dart';
import 'package:propcid_app/screens/dashboard/widgets/builder_team_section.dart';
import 'package:propcid_app/services/builder_sections_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

/// Wide enough that every status filter chip is on screen.
const Size kFilterViewport = Size(700, 1200);

/// Yesterday as `yyyy-MM-dd`.
String _isoYesterday() {
  final d = DateTime.now().subtract(const Duration(days: 1));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';
}

// ── Fixtures ────────────────────────────────────────────────────────────────

BuilderOffer _offer({
  String id = 'o-1',
  String title = 'Festive 5% off on all 3BHKs',
  String? projectId = 'p-1',
  String? videoUrl,
  List<String> media = const ['https://cdn.test/o.jpg'],
}) =>
    BuilderOffer.fromSupabase({
      'id': id,
      'project_id': projectId,
      'builder_id': 'b-1',
      'offer_title': title,
      'offer_description': 'Limited to bookings before 31 March.',
      'offer_media_urls': media,
      'offer_video_url': videoUrl,
      'status': 'active',
      'created_at': '2026-05-01T10:00:00Z',
      'project': {
        'title': 'Green Valley Heights',
        'location': 'Pune',
        'price_range_min': 4500000,
        'price_range_max': 9500000,
      },
    });

SiteVisitBooking _booking({
  String id = 'v-1',
  String status = 'pending',
  String date = '2026-09-12',
  String? time = '11:00 AM',
  String projectId = 'p-1',
}) =>
    SiteVisitBooking.fromSupabase({
      'id': id,
      'project_id': projectId,
      'user_id': 'u-9',
      'visitor_name': 'Rahul Sharma',
      'visitor_phone': '9876543210',
      'preferred_date': date,
      'preferred_time': time,
      'message': 'Prefer a morning slot.',
      'status': status,
      'created_at': '2026-05-01T10:00:00Z',
    });

BuilderTeamMember _member({
  String id = 'm-1',
  String email = 'asha@example.com',
  List<String> modules = const ['inventory', 'site_visits'],
  Object? projectIds = const ['p-1'],
  String status = 'active',
}) =>
    BuilderTeamMember.fromSupabase({
      'id': id,
      'member_user_id': 'u-2',
      'email': email,
      'modules': modules,
      'project_ids': projectIds,
      'status': status,
      'created_at': '2026-05-01T10:00:00Z',
    });

BuilderTeamInvitation _invitation({
  String id = 'i-1',
  String email = 'new@example.com',
  String status = 'pending',
  String expires = '2099-01-01T00:00:00Z',
}) =>
    BuilderTeamInvitation.fromSupabase({
      'id': id,
      'email': email,
      'modules': ['offers'],
      'project_ids': null,
      'status': status,
      'expires_at': expires,
      'created_at': '2026-05-01T10:00:00Z',
    });

ProjectModel _project({String id = 'p-1', String title = 'Green Valley'}) =>
    ProjectModel.fromSupabase({
      'id': id,
      'builder_id': 'b-1',
      'title': title,
      'status': 'active',
    });

// ── Fakes ───────────────────────────────────────────────────────────────────

class _FakeOfferService extends BuilderOfferService {
  _FakeOfferService({this.rows = const []});

  final List<BuilderOffer> rows;
  bool shouldFail = false;
  final List<String> deletes = [];

  @override
  Future<List<BuilderOffer>> listMine(String builderId) async {
    if (shouldFail) throw Exception('forced failure');
    return rows;
  }

  @override
  Future<void> delete(String offerId) async => deletes.add(offerId);
}

class _FakeVisitService extends SiteVisitService {
  _FakeVisitService({this.rows = const []});

  final List<SiteVisitBooking> rows;
  bool shouldFail = false;

  final List<({String id, String status, String? time, String title})> updates =
      [];
  final List<String> scopes = [];

  @override
  Future<List<SiteVisitBooking>> listForProjects(
    List<String> projectIds,
  ) async {
    scopes.add(projectIds.join(','));
    if (shouldFail) throw Exception('forced failure');
    // The real service short-circuits an empty scope; the fake mirrors it so the
    // widget's behaviour is what is under test.
    if (projectIds.isEmpty) return const [];
    return rows;
  }

  @override
  Future<void> updateBooking({
    required SiteVisitBooking booking,
    required DateTime preferredDate,
    required String? preferredTime,
    required String status,
    required String projectTitle,
  }) async {
    updates.add((
      id: booking.id,
      status: status,
      time: preferredTime,
      title: projectTitle,
    ));
  }
}

class _FakeTeamService extends BuilderTeamService {
  _FakeTeamService({
    this.members = const [],
    this.invitations = const [],
    this.activity = const [],
  });

  List<BuilderTeamMember> members;
  List<BuilderTeamInvitation> invitations;
  List<BuilderTeamActivity> activity;
  bool shouldFail = false;

  final List<String> revokedMembers = [];
  final List<String> revokedInvitations = [];
  final List<({String? email, List<String> modules, List<String>? projects})>
      invites = [];

  BuilderTeamInviteResult inviteResult = const BuilderTeamInviteResult();
  Object? inviteError;

  @override
  Future<List<BuilderTeamMember>> listMembers(String builderId) async {
    if (shouldFail) throw Exception('forced failure');
    return members;
  }

  @override
  Future<List<BuilderTeamInvitation>> listInvitations(String builderId) async {
    if (shouldFail) throw Exception('forced failure');
    return invitations;
  }

  @override
  Future<List<BuilderTeamActivity>> listActivity(String builderId) async {
    if (shouldFail) throw Exception('forced failure');
    return activity;
  }

  @override
  Future<BuilderTeamInviteResult> invite({
    String? email,
    String? phone,
    required List<String> modules,
    required List<String>? projectIds,
    required String redirectOrigin,
  }) async {
    invites.add((email: email, modules: modules, projects: projectIds));
    final error = inviteError;
    if (error != null) {
      inviteError = null;
      throw error;
    }
    return inviteResult;
  }

  @override
  Future<void> revokeMember(String memberId) async =>
      revokedMembers.add(memberId);

  @override
  Future<void> revokeInvitation(String id) async =>
      revokedInvitations.add(id);
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

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

  // ── 1. Vocabularies ─────────────────────────────────────────────────────
  group('vocabularies', () {
    test('the project picker offers the whole CHECK constraint', () {
      // builder_projects.status CHECK is
      // ('active','inactive','completed','under_construction') and
      // BuilderInventoryManager.tsx:544-551 offers all four — unlike listings,
      // where the portal deliberately exposes two of four.
      expect(
        kProjectStatusPickerOptions.map((o) => o.value).toList(),
        ['active', 'under_construction', 'completed', 'inactive'],
      );
      for (final value in ['active', 'under_construction', 'completed',
                           'inactive']) {
        expect(isSettableProjectStatus(value), isTrue, reason: value);
      }
      expect(isSettableProjectStatus('sold'), isFalse);
    });

    test('unit statuses cover project_inventory\'s CHECK', () {
      expect(inventoryUnitStatusLabel('available'), 'Available');
      expect(inventoryUnitStatusLabel('booked'), 'Booked');
      expect(inventoryUnitStatusLabel('sold'), 'Sold');
      expect(inventoryUnitStatusLabel('blocked'), 'Blocked');
    });

    test('booking statuses match the portal picker', () {
      // project_visit_bookings.status has NO check constraint, so these five are
      // the portal's list, not a database rule.
      expect(
        kSiteVisitStatusOptions.map((o) => o.value).toList(),
        ['pending', 'confirmed', 'completed', 'cancelled', 'rescheduled'],
      );
    });

    test('an unknown booking status still reads', () {
      // The column is unconstrained, so a row may hold anything.
      expect(siteVisitStatusLabel('confirmed'), 'Confirmed');
      expect(siteVisitStatusLabel('no_show'), 'No_show');
      expect(siteVisitStatusLabel(null), 'Pending');
      expect(siteVisitStatusLabel(''), 'Pending');
    });

    test('only three statuses notify the visitor', () {
      // SiteVisitBookingsManager.tsx:177. `completed` deliberately does not,
      // even though notifyVisitBookingUpdate has copy for it.
      expect(kNotifyingSiteVisitStatuses,
          {'confirmed', 'cancelled', 'rescheduled'});
      expect(kNotifyingSiteVisitStatuses.contains('completed'), isFalse);
      expect(kNotifyingSiteVisitStatuses.contains('pending'), isFalse);
    });

    test('team modules match the CHECK constraint', () {
      // modules <@ ARRAY['inventory','offers','leads','site_visits']
      expect(
        kBuilderTeamModules.map((m) => m.value).toList(),
        ['inventory', 'offers', 'leads', 'site_visits'],
      );
      expect(areValidTeamModules(['inventory', 'leads']), isTrue);
      expect(areValidTeamModules(['inventory', 'billing']), isFalse);
      expect(areValidTeamModules(const []), isTrue,
          reason: 'vacuously true; emptiness is a separate rule');
    });

    test('the member cap is 10', () {
      // Enforced by enforce_team_member_cap(), a trigger.
      expect(kMaxBuilderTeamMembers, 10);
    });
  });

  // ── 2. Inventory counts ─────────────────────────────────────────────────
  group('InventoryCounts', () {
    test('booked and blocked units fall into neither counter', () {
      // The portal only increments `sold` and `available`
      // (BuilderInventoryManager.tsx:158-164), so the two other CHECK values are
      // counted in `total` alone. Reproduced, not corrected.
      const counts = InventoryCounts(total: 10, sold: 3, available: 5);
      expect(counts.otherStatuses, 2);
    });

    test('no rows is empty, all-booked is not', () {
      expect(const InventoryCounts().isEmpty, isTrue);
      expect(const InventoryCounts(total: 4).isEmpty, isFalse);
    });
  });

  // ── 3. Models ───────────────────────────────────────────────────────────
  group('BuilderOffer', () {
    test('reads the offer and its embedded project', () {
      final offer = _offer();
      expect(offer.title, 'Festive 5% off on all 3BHKs');
      expect(offer.projectTitle, 'Green Valley Heights');
      expect(offer.projectLocation, 'Pune');
      expect(offer.hasPriceRange, isTrue);
      expect(offer.coverImage, 'https://cdn.test/o.jpg');
    });

    test('no media means no cover, not a stock photo', () {
      // The portal substitutes an Unsplash URL; this returns null so the card can
      // draw a placeholder the app owns.
      expect(_offer(media: const []).coverImage, isNull);
    });

    test('a missing embedded project does not throw', () {
      final offer = BuilderOffer.fromSupabase({
        'id': 'o-1',
        'offer_title': 'Orphan',
        'project': null,
      });
      expect(offer.projectTitle, isNull);
      expect(offer.hasPriceRange, isFalse);
    });
  });

  group('BuilderTeamMember', () {
    test('null project_ids means all projects', () {
      // 20270201000000:49 — `NULL => all of the builder's projects`. An empty list
      // would mean the opposite, so the distinction has to survive parsing.
      expect(_member(projectIds: null).hasAllProjects, isTrue);
      expect(_member(projectIds: null).projectIds, isNull);
      expect(_member(projectIds: const ['p-1']).hasAllProjects, isFalse);
    });

    test('an empty array is scoped to nothing, not to everything', () {
      final scoped = _member(projectIds: const <String>[]);
      expect(scoped.hasAllProjects, isFalse);
      expect(scoped.projectIds, isEmpty);
    });
  });

  group('BuilderTeamInvitation', () {
    test('a lapsed invitation is not pending, whatever its status says', () {
      // Nothing sets status to 'expired' synchronously, so a row can read
      // 'pending' while already unusable.
      final lapsed = _invitation(expires: '2020-01-01T00:00:00Z');
      expect(lapsed.status, 'pending');
      expect(lapsed.hasLapsed, isTrue);
      expect(lapsed.isPending, isFalse);
    });

    test('a live pending invitation is pending', () {
      expect(_invitation().isPending, isTrue);
    });

    test('a revoked invitation is never pending', () {
      expect(_invitation(status: 'revoked').isPending, isFalse);
    });
  });

  group('SiteVisitBooking', () {
    test('a booking earlier today is not past', () {
      // Compared day-to-day: a visit at 09:00 is not overdue at 14:00.
      final today = DateTime.now();
      final booking = _booking(
        date: '${today.year}-${today.month.toString().padLeft(2, '0')}'
            '-${today.day.toString().padLeft(2, '0')}',
      );
      expect(booking.isPast, isFalse);
    });

    test('yesterday is past', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final booking = _booking(
        date: '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}'
            '-${yesterday.day.toString().padLeft(2, '0')}',
      );
      expect(booking.isPast, isTrue);
    });

    test('copyWith keeps the fields it is not given', () {
      final updated = _booking().copyWith(status: 'confirmed');
      expect(updated.status, 'confirmed');
      expect(updated.visitorName, 'Rahul Sharma');
      expect(updated.message, 'Prefer a morning slot.');
    });
  });

  // ── 4. Offers section ───────────────────────────────────────────────────
  group('BuilderOffersSection', () {
    testWidgets('renders an offer with its project and date', (tester) async {
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: _FakeOfferService(rows: [_offer()]),
        ),
      );

      expect(find.text('Festive 5% off on all 3BHKs'), findsOneWidget);
      expect(find.text('Green Valley Heights · Pune'), findsOneWidget);
      expect(find.text('May 1, 2026'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      // Spec I added Edit and shortened 'View Project' to 'View' so three
      // actions fit the row.
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('an empty list explains itself instead of collapsing',
        (tester) async {
      // Spec I gave the section a Create button, so the message now names it
      // instead of pointing at a flow on another platform. With no projects there
      // is nothing to attach an offer to, so it says that instead.
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: _FakeOfferService(),
        ),
      );
      expect(find.textContaining('Publish a project first'), findsOneWidget);
      expect(find.text('Create'), findsNothing);

      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          projects: [_project()],
          service: _FakeOfferService(),
        ),
      );
      expect(find.textContaining('Use Create to market one'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: _FakeOfferService()..shouldFail = true,
        ),
      );
      expect(find.text("Couldn't load your offers"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('delete confirms, says it cannot be undone, and prunes',
        (tester) async {
      final counts = <int>[];
      final service = _FakeOfferService(rows: [_offer()]);
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: service,
          onCountChanged: counts.add,
        ),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // There is no deleted_at on this table, so unlike videos the dialog must
      // not soften the wording.
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.deletes, ['o-1']);
      expect(find.text('Festive 5% off on all 3BHKs'), findsNothing);
      expect(counts, [1, 0]);
    });

    testWidgets('an offer whose project is gone cannot be tapped through',
        (tester) async {
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: _FakeOfferService(rows: [_offer(projectId: null)]),
        ),
      );
      // The action stays visible but disabled, rather than vanishing.
      expect(find.text('View'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        BuilderOffersSection(
          builderId: 'b-1',
          service: _FakeOfferService(rows: [
            _offer(
              title: 'Festive season five percent discount on every 3BHK unit',
              videoUrl: 'https://cdn.test/o.mp4',
            ),
          ]),
        ),
        textScale: 1.3,
      );
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 5. Site visits section ──────────────────────────────────────────────
  group('BuilderSiteVisitsSection', () {
    testWidgets('renders a booking with visitor, project, date and time',
        (tester) async {
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley Heights'},
          service: _FakeVisitService(rows: [_booking()]),
        ),
      );

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(find.text('Green Valley Heights'), findsOneWidget);
      expect(find.text('Sep 12, 2026'), findsOneWidget);
      expect(find.text('11:00 AM'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('no projects yields a different message than no bookings',
        (tester) async {
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const [],
          projectTitles: const {},
          service: _FakeVisitService(),
        ),
      );
      expect(find.textContaining('once you publish a project'), findsOneWidget);

      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: _FakeVisitService(),
        ),
      );
      expect(find.text('No site visits booked yet.'), findsOneWidget);
    });

    testWidgets('an empty project scope issues no unfiltered read',
        (tester) async {
      // PostgREST answers `in.()` with every visible row, so an empty scope must
      // short-circuit rather than become "every booking in the table".
      final service = _FakeVisitService(rows: [_booking()]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const [],
          projectTitles: const {},
          service: service,
        ),
      );
      expect(find.text('Rahul Sharma'), findsNothing);
      expect(service.scopes, ['']);
    });

    testWidgets('the filter narrows without re-querying', (tester) async {
      final service = _FakeVisitService(rows: [
        _booking(id: 'a', status: 'pending'),
        _booking(id: 'b', status: 'confirmed'),
      ]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: service,
        ),
        // Wide: the filter row is a horizontal scroller by design and its later
        // chips sit past 320 dp. Scrolling it is not what this test is about.
        size: kFilterViewport,
      );

      expect(find.text('Rahul Sharma'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(GestureDetector, 'Confirmed').first);
      await tester.pumpAndSettle();

      expect(find.text('Rahul Sharma'), findsOneWidget);
      expect(service.scopes, hasLength(1), reason: 'filtered client-side');
    });

    testWidgets(
      'the project filter is hidden with 0 or 1 project in scope',
      (tester) async {
        await _pump(
          tester,
          BuilderSiteVisitsSection(
            projectIds: const ['p-1'],
            projectTitles: const {'p-1': 'Green Valley'},
            projects: [_project()],
            service: _FakeVisitService(rows: [_booking()]),
          ),
          size: kFilterViewport,
        );
        expect(find.text('All Projects'), findsNothing);
      },
    );

    testWidgets(
      'the project filter narrows by project, client-side, once there are '
      'two or more',
      (tester) async {
        final service = _FakeVisitService(rows: [
          _booking(id: 'a', projectId: 'p-1'),
          _booking(id: 'b', projectId: 'p-2'),
        ]);
        await _pump(
          tester,
          BuilderSiteVisitsSection(
            projectIds: const ['p-1', 'p-2'],
            projectTitles: const {'p-1': 'Green Valley', 'p-2': 'Blue Ridge'},
            projects: [_project(), _project(id: 'p-2', title: 'Blue Ridge')],
            service: service,
          ),
          size: kFilterViewport,
        );

        expect(find.text('Rahul Sharma'), findsNWidgets(2));

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blue Ridge').last);
        await tester.pumpAndSettle();

        expect(find.text('Rahul Sharma'), findsOneWidget);
        expect(find.text('Blue Ridge'), findsWidgets);
        expect(find.text('Green Valley'), findsNothing);
        expect(service.scopes, hasLength(1), reason: 'filtered client-side');
      },
    );

    testWidgets('shows when the booking was requested', (tester) async {
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: _FakeVisitService(rows: [_booking()]),
        ),
      );
      // `_booking()`'s default `created_at` is 2026-05-01T10:00:00Z.
      expect(find.text('Requested on May 1, 2026'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing is not an empty section',
        (tester) async {
      // The bookings still exist, so the shell must not collapse.
      final service = _FakeVisitService(rows: [_booking(status: 'pending')]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: service,
        ),
        size: kFilterViewport,
      );

      await tester.tap(find.widgetWithText(GestureDetector, 'Cancelled').first);
      await tester.pumpAndSettle();

      expect(find.text('No cancelled bookings.'), findsOneWidget);
      expect(find.text('No site visits booked yet.'), findsNothing);
    });

    testWidgets('a past pending booking is flagged', (tester) async {
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: _FakeVisitService(
            rows: [_booking(date: _isoYesterday(), status: 'pending')],
          ),
        ),
      );
      expect(find.text('Date passed'), findsOneWidget);
    });

    testWidgets('a past completed booking is not flagged', (tester) async {
      // Its own test rather than a second pump: re-pumping the same widget type
      // without a key reuses the State, and didUpdateWidget sees identical
      // projectIds, so nothing reloads and the first fixture survives.
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: _FakeVisitService(
            rows: [_booking(date: _isoYesterday(), status: 'completed')],
          ),
        ),
      );
      expect(find.text('Date passed'), findsNothing);
    });

    testWidgets('updating writes the new status and names the project',
        (tester) async {
      final service = _FakeVisitService(rows: [_booking()]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley Heights'},
          service: service,
        ),
        size: const Size(320, 1400),
      );

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update Booking'), findsOneWidget);

      // `.last`: the filter row behind the sheet carries the same five labels, so
      // a bare finder is ambiguous. The sheet is pumped last, so it is last.
      await tester.tap(find.widgetWithText(GestureDetector, 'Confirmed').last);
      await tester.pumpAndSettle();
      // The sheet warns before saving, not after.
      expect(find.textContaining('visitor will be notified'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.updates.single.id, 'v-1');
      expect(service.updates.single.status, 'confirmed');
      expect(service.updates.single.title, 'Green Valley Heights');
      expect(find.textContaining('visitor has been notified'), findsOneWidget);
    });

    testWidgets('a non-notifying status does not claim the visitor was told',
        (tester) async {
      final service = _FakeVisitService(rows: [_booking()]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: service,
        ),
        size: const Size(320, 1400),
      );

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GestureDetector, 'Completed').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('visitor will be notified'), findsNothing);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(service.updates.single.status, 'completed');
      expect(find.text('Booking updated.'), findsOneWidget);
    });

    testWidgets('cancelling the sheet writes nothing', (tester) async {
      final service = _FakeVisitService(rows: [_booking()]);
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'Green Valley'},
          service: service,
        ),
        size: const Size(320, 1400),
      );

      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(service.updates, isEmpty);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        BuilderSiteVisitsSection(
          projectIds: const ['p-1'],
          projectTitles: const {'p-1': 'A rather long project name here'},
          service: _FakeVisitService(rows: [_booking()]),
        ),
        textScale: 1.3,
        size: const Size(320, 1200),
      );
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 6. Team section ─────────────────────────────────────────────────────
  group('BuilderTeamSection', () {
    testWidgets('renders a member with modules and project scope',
        (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: [_project(title: 'Green Valley')],
          service: _FakeTeamService(members: [_member()]),
        ),
      );

      expect(find.text('asha@example.com'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Site Visits'), findsOneWidget);
      // Titles, not ids — an id tells a builder nothing.
      expect(find.text('Green Valley'), findsOneWidget);
      expect(find.text('1 of 10 members'), findsOneWidget);
    });

    testWidgets('an all-projects grant says so', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: [_project()],
          service: _FakeTeamService(members: [_member(projectIds: null)]),
        ),
      );
      expect(find.text('All projects'), findsOneWidget);
    });

    testWidgets('a scoped project since deleted falls back to a count',
        (tester) async {
      // `project_ids` is a uuid[] with no FK, so it does not cascade.
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService(
            members: [_member(projectIds: const ['gone-1', 'gone-2'])],
          ),
        ),
      );
      expect(find.text('2 project(s)'), findsOneWidget);
    });

    testWidgets('an empty team still shows the invite button', (tester) async {
      // This section never collapses — the invite action is the point of it.
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService(),
        ),
      );
      expect(find.text('Invite'), findsOneWidget);
      expect(find.textContaining('No team members yet'), findsOneWidget);
    });

    testWidgets('revoked members are not listed or counted', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService(members: [
            _member(id: 'm-1', email: 'live@example.com'),
            _member(id: 'm-2', email: 'gone@example.com', status: 'revoked'),
          ]),
        ),
      );
      expect(find.text('live@example.com'), findsOneWidget);
      expect(find.text('gone@example.com'), findsNothing);
      expect(find.text('1 of 10 members'), findsOneWidget);
    });

    testWidgets('a lapsed invitation is not shown as pending', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService(invitations: [
            _invitation(id: 'i-1', email: 'live@example.com'),
            _invitation(
              id: 'i-2',
              email: 'stale@example.com',
              expires: '2020-01-01T00:00:00Z',
            ),
          ]),
        ),
      );
      expect(find.text('live@example.com'), findsOneWidget);
      expect(find.text('stale@example.com'), findsNothing);
    });

    testWidgets('the cap blocks the invite and says why', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService(
            members: List.generate(10, (i) => _member(id: 'm-$i')),
          ),
        ),
        size: const Size(320, 4000),
      );

      expect(find.text('10 of 10 members'), findsOneWidget);
      expect(find.textContaining('Limit reached'), findsOneWidget);
    });

    testWidgets('revoking a member confirms first', (tester) async {
      final service = _FakeTeamService(members: [_member()]);
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: service,
        ),
      );

      await tester.tap(find.text('Revoke Access'));
      await tester.pumpAndSettle();
      expect(find.text('Revoke Access'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, 'Keep'));
      await tester.pumpAndSettle();
      expect(service.revokedMembers, isEmpty);

      await tester.tap(find.text('Revoke Access').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(service.revokedMembers, ['m-1']);
      expect(find.text('asha@example.com'), findsNothing);
    });

    testWidgets('cancelling an invitation removes it', (tester) async {
      final service = _FakeTeamService(invitations: [_invitation()]);
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: service,
        ),
      );

      await tester.tap(find.text('Cancel Invitation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(service.revokedInvitations, ['i-1']);
      expect(find.text('new@example.com'), findsNothing);
    });

    testWidgets('a failure offers a retry', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: _FakeTeamService()..shouldFail = true,
        ),
      );
      expect(find.text("Couldn't load your team"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: [_project(title: 'A rather long project title indeed')],
          service: _FakeTeamService(
            members: [
              _member(
                modules: const ['inventory', 'offers', 'leads', 'site_visits'],
              ),
            ],
            invitations: [_invitation()],
          ),
        ),
        textScale: 1.3,
        size: const Size(320, 1600),
      );
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  // ── 7. The invite form's refusals ───────────────────────────────────────
  group('invite form', () {
    Future<_FakeTeamService> openSheet(
      WidgetTester tester, {
      Size size = const Size(320, 2400),
    }) async {
      final service = _FakeTeamService();
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: [_project()],
          service: service,
        ),
        size: size,
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('no email is refused', (tester) async {
      final service = await openSheet(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(find.text("Enter the person's email address."), findsOneWidget);
      expect(service.invites, isEmpty);
    });

    testWidgets('no module is refused', (tester) async {
      // Also a database rule: builder_team_invitations CHECKs
      // array_length(modules,1) >= 1.
      final service = await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(find.text('Grant at least one module.'), findsOneWidget);
      expect(service.invites, isEmpty);
    });

    testWidgets('a full grant sends null for all projects', (tester) async {
      // Null, never []: the column documents NULL as "all projects", so an empty
      // list would grant access to nothing.
      final service = await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(service.invites.single.email, 'new@example.com');
      expect(service.invites.single.modules, ['inventory']);
      expect(service.invites.single.projects, isNull);
    });

    testWidgets('picking projects without ticking one is refused',
        (tester) async {
      final service = await openSheet(tester);
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Only the projects I pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(
        find.text('Choose at least one project, or grant all.'),
        findsOneWidget,
      );
      expect(service.invites, isEmpty);
    });

    testWidgets('a scoped grant sends the ticked ids', (tester) async {
      // The tallest path through the sheet: four module rows, two scope rows and
      // the project list all have to be laid out before they can be tapped.
      final service = await openSheet(tester, size: const Size(360, 3200));
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.text('Marketed Offers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Only the projects I pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green Valley'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(service.invites.single.projects, ['p-1']);
    });

    testWidgets('a builder with no projects cannot choose per-project scope',
        (tester) async {
      final service = _FakeTeamService();
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: service,
        ),
        size: const Size(320, 2400),
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();

      expect(find.text('You have no projects to pick yet.'), findsOneWidget);

      // The row is inert, so the scope stays on "all".
      await tester.tap(find.text('Only the projects I pick'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'new@example.com');
      await tester.tap(find.text('Leads'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(service.invites.single.projects, isNull);
    });

    testWidgets('a function refusal is surfaced verbatim', (tester) async {
      final service = _FakeTeamService()
        ..inviteError =
            const BuilderSectionException('That person is already a member.');
      await _pump(
        tester,
        BuilderTeamSection(
          builderId: 'b-1',
          projects: const [],
          service: service,
        ),
        size: const Size(320, 2400),
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'dupe@example.com');
      await tester.tap(find.text('Leads'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Invite'));
      await tester.pumpAndSettle();

      expect(find.text('That person is already a member.'), findsOneWidget);
    });
  });

  // ── 8. Service-level guards ─────────────────────────────────────────────
  group('service guards', () {
    test('an empty id list never becomes an unfiltered read', () async {
      // The one that matters most: `inFilter('x', [])` is answered by PostgREST
      // with every row the caller can see.
      expect(await ProjectInventoryService().countsByProject(const []), isEmpty);
      expect(await SiteVisitService().listForProjects(const []), isEmpty);
    });

    test('an invite with no modules is refused before the round trip', () {
      expect(
        () => BuilderTeamService().invite(
          email: 'a@b.com',
          modules: const [],
          projectIds: null,
          redirectOrigin: 'https://x.test',
        ),
        throwsA(isA<BuilderSectionException>()),
      );
    });

    test('an invite with an unknown module is refused', () {
      expect(
        () => BuilderTeamService().invite(
          email: 'a@b.com',
          modules: const ['billing'],
          projectIds: null,
          redirectOrigin: 'https://x.test',
        ),
        throwsA(isA<BuilderSectionException>()),
      );
    });

    test('an empty project scope is refused, since null means all', () {
      expect(
        () => BuilderTeamService().invite(
          email: 'a@b.com',
          modules: const ['leads'],
          projectIds: const [],
          redirectOrigin: 'https://x.test',
        ),
        throwsA(isA<BuilderSectionException>()),
      );
    });

    test('the notification type is one the enum already carries', () {
      // Added by 20260315190000_fix_missing_notification_types.sql:5, so no
      // schema change is implied by using it.
      expect(SiteVisitService.notificationType, 'visit_booking_update');
    });

    test('the invite function name matches the deployed one', () {
      expect(BuilderTeamService.inviteFunction, 'invite-team-member');
    });
  });
}
