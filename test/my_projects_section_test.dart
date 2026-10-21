// Builder flow — Phase B4: the Content tab's project list and its four actions.
//
// What is pinned:
//   * Manage Inventory opens `ManageUnitsScreen` for that project;
//   * Edit routes through `/add-project` with the project as an argument, so the
//     gate's un-gated edit branch stays the single definition of that rule;
//   * Delete confirms first, names **all three** cascades, and only then writes;
//   * Share reports a capped fan-out honestly and refuses on an empty network;
//   * an empty list hides the section, a failure offers a retry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/dashboard/widgets/my_projects_section.dart';
import 'package:propcid_app/screens/team/widgets/manage_units_screen.dart';
import 'package:propcid_app/services/project_service.dart';
import 'package:propcid_app/services/project_share_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

class _FakeAuth extends AuthProvider {
  // Every project fixture belongs to b-1, so the viewer is always the owner
  // here — the owner/visitor split is covered in project_detail_test.
  @override
  String? get userId => 'b-1';

  @override
  bool get isLoggedIn => true;
}

class _FakeProjectService extends ProjectService {
  _FakeProjectService({this.rows = const [], this.shouldFail = false});

  List<ProjectModel> rows;
  bool shouldFail;

  int listCalls = 0;
  final List<({String projectId, String builderId})> deleted = [];

  @override
  Future<List<ProjectModel>> listMine(String builderId) async {
    listCalls++;
    if (shouldFail) throw Exception('forced failure');
    return rows;
  }

  @override
  Future<void> delete({
    required String projectId,
    required String builderId,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    deleted.add((projectId: projectId, builderId: builderId));
  }
}

class _FakeShareService extends ProjectShareService {
  _FakeShareService({this.result, this.shouldFail = false});

  ProjectShareResult? result;
  bool shouldFail;

  final List<String> shared = [];

  @override
  Future<ProjectShareResult> shareProject({
    required String builderId,
    required String projectId,
    required String projectTitle,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    shared.add(projectId);
    return result ??
        const ProjectShareResult(notified: 3, dropped: 0, hasNetwork: true);
  }
}

ProjectModel _project({String id = 'p-1', String title = 'Green Valley'}) =>
    ProjectModel.fromSupabase({
      'id': id,
      'builder_id': 'b-1',
      'title': title,
      'project_type': 'group_housing',
      'location': 'Pune',
      'status': 'active',
      'approval_status': 'approved',
      'total_units': 120,
      'available_units': 45,
      'price_range_min': 4500000,
      'price_range_max': 9500000,
    });

Future<List<RouteSettings>> _pump(
  WidgetTester tester, {
  required _FakeProjectService service,
  _FakeShareService? share,
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuth(),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MyProjectsSection(
              userId: 'b-1',
              service: service,
              shareService: share ?? _FakeShareService(),
            ),
          ),
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
  await tester.pumpAndSettle();
  return pushed;
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

  // ── 1. Rendering ───────────────────────────────────────────────────────
  group('rendering', () {
    testWidgets('a project renders with its four actions', (tester) async {
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
      );

      expect(find.text('Green Valley'), findsOneWidget);
      expect(find.text('Group Housing · Pune'), findsOneWidget);
      expect(find.text('45/120 units'), findsOneWidget);
      expect(find.text('Inventory'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('an empty list hides the section entirely', (tester) async {
      // The Content tab already offers "Add Your First Project"; a second prompt
      // in the same column would be noise.
      await _pump(tester, service: _FakeProjectService(rows: []));

      expect(find.byType(MyProjectsSection), findsOneWidget);
      expect(tester.getSize(find.byType(MyProjectsSection)).height, 0);
    });

    testWidgets('a failed load offers a retry that re-queries', (tester) async {
      final service = _FakeProjectService(shouldFail: true);
      await _pump(tester, service: service);

      expect(find.text("Couldn't load your projects"), findsOneWidget);
      expect(service.listCalls, 1);

      service.shouldFail = false;
      service.rows = [_project()];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(service.listCalls, 2);
      expect(find.text('Green Valley'), findsOneWidget);
    });

    testWidgets('survives 130% text scale at 320 dp', (tester) async {
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        textScale: 1.3,
      );

      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  // ── 2. Manage Inventory ──────────────────────────────────────────────────
  group('manage inventory', () {
    testWidgets('opens ManageUnitsScreen for that project', (tester) async {
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project(id: 'p-5')]),
      );

      await tester.tap(find.text('Inventory'));
      // Not pumpAndSettle: the pushed screen's own initState kicks off a real
      // Supabase read that never resolves in this test's fake environment,
      // which pumpAndSettle would wait on indefinitely. Bounded pumps instead
      // just carry the push transition to completion.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byType(ManageUnitsScreen), findsOneWidget);
    });
  });

  // ── 3. Edit ────────────────────────────────────────────────────────────
  group('edit', () {
    testWidgets('routes to /add-project carrying the project', (tester) async {
      // Through the route, not a direct construction, so AddProjectRouteGate's
      // edit branch remains the one place that says editing is not role-gated.
      final pushed = await _pump(
        tester,
        service: _FakeProjectService(rows: [_project(id: 'p-9')]),
      );

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(pushed.single.name, AppConstants.addProjectScreen);
      final args = pushed.single.arguments as Map<String, dynamic>;
      expect((args['project'] as ProjectModel).id, 'p-9');
    });

    testWidgets('tapping the card opens the project detail', (tester) async {
      final pushed = await _pump(
        tester,
        service: _FakeProjectService(rows: [_project(id: 'p-7')]),
      );

      await tester.tap(find.text('Green Valley'));
      await tester.pumpAndSettle();

      expect(pushed.single.name, AppConstants.projectDetailScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['projectId'],
        'p-7',
      );
    });
  });

  // ── 4. Delete ──────────────────────────────────────────────────────────
  group('delete', () {
    testWidgets('confirms first and names all three cascades', (tester) async {
      final service = _FakeProjectService(rows: [_project()]);
      await _pump(tester, service: service);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Project'), findsOneWidget);
      // Every child table cascades; visit bookings are other people's
      // appointments, which is the consequence most worth stating.
      expect(find.textContaining('inventory units'), findsOneWidget);
      expect(find.textContaining('offers'), findsOneWidget);
      expect(find.textContaining('site-visit booking'), findsOneWidget);
      expect(service.deleted, isEmpty, reason: 'nothing written yet');
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final service = _FakeProjectService(rows: [_project()]);
      await _pump(tester, service: service);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(service.deleted, isEmpty);
      expect(find.text('Green Valley'), findsOneWidget);
    });

    testWidgets('confirming deletes and removes the row', (tester) async {
      final service = _FakeProjectService(rows: [_project(id: 'p-3')]);
      await _pump(tester, service: service);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(service.deleted.single.projectId, 'p-3');
      expect(service.deleted.single.builderId, 'b-1');
      expect(find.text('Green Valley'), findsNothing);
      expect(find.text('Project deleted.'), findsOneWidget);
    });

    testWidgets('a failed delete keeps the row and says so', (tester) async {
      final service = _FakeProjectService(rows: [_project()]);
      await _pump(tester, service: service);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      service.shouldFail = true;
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Green Valley'), findsOneWidget,
          reason: 'the row must not vanish on a failed write');
      expect(
        find.text('Could not delete that project. Please try again.'),
        findsOneWidget,
      );
    });
  });

  // ── 5. Share ───────────────────────────────────────────────────────────
  group('share', () {
    testWidgets('reports how many connections were notified', (tester) async {
      final share = _FakeShareService(
        result: const ProjectShareResult(
          notified: 4,
          dropped: 0,
          hasNetwork: true,
        ),
      );
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        share: share,
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(share.shared, ['p-1']);
      expect(find.textContaining('Notified 4 connections'), findsOneWidget);
    });

    testWidgets('one connection is singular', (tester) async {
      final share = _FakeShareService(
        result: const ProjectShareResult(
          notified: 1,
          dropped: 0,
          hasNetwork: true,
        ),
      );
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        share: share,
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Notified 1 connection about'), findsOneWidget);
    });

    testWidgets('a capped fan-out is never presented as complete',
        (tester) async {
      final share = _FakeShareService(
        result: const ProjectShareResult(
          notified: 500,
          dropped: 300,
          hasNetwork: true,
        ),
      );
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        share: share,
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.textContaining('300 more were not notified'), findsOneWidget);
    });

    testWidgets('an empty network refuses rather than claiming success',
        (tester) async {
      final share = _FakeShareService(
        result: const ProjectShareResult(
          notified: 0,
          dropped: 0,
          hasNetwork: false,
        ),
      );
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        share: share,
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(
        find.text('You have no network connections to share with yet.'),
        findsOneWidget,
      );
      expect(find.textContaining('Notified'), findsNothing);
    });

    testWidgets('a failed share says so', (tester) async {
      final share = _FakeShareService(shouldFail: true);
      await _pump(
        tester,
        service: _FakeProjectService(rows: [_project()]),
        share: share,
      );

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not share that project. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
