// Builder inventory management — the screen behind "Manage Inventory" on a
// builder's own project card (`my_projects_section_test.dart` covers the entry
// point) and behind "Manage Units" in the Team Workspace's Inventory tab.
//
// What is pinned:
//   * Total/Available/Sold tallies come from the loaded units, not a second query;
//   * "Pre-fill from Listing" generates draft rows up to total_units, defaulting
//     from the project's own type/area/price, and refuses once already full;
//   * a draft row is never written until its own checkmark or "Save All New" is
//     used — pre-filling alone writes nothing;
//   * "Save All New" only ever bulk-inserts the currently-savable drafts;
//   * a plot-type unit hides the floor field.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/screens/team/widgets/manage_units_screen.dart';
import 'package:propcid_app/services/builder_sections_service.dart';
import 'package:propcid_app/services/project_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

class _FakeInventoryService extends ProjectInventoryService {
  _FakeInventoryService({this.units = const [], this.shouldFail = false});

  List<InventoryUnit> units;
  bool shouldFail;

  final List<Map<String, dynamic>> created = [];
  final List<List<Map<String, dynamic>>> bulkCreated = [];

  int _nextId = 1;

  InventoryUnit _fromPayload(Map<String, dynamic> payload) => InventoryUnit(
        id: 'u-${_nextId++}',
        projectId: 'p-1',
        unitType: payload['unit_type']?.toString() ?? '',
        status: payload['status']?.toString() ?? 'available',
        unitNumber: payload['unit_number']?.toString(),
        floorNumber: payload['floor_number'] as int?,
        areaSqft: (payload['area_sqft'] as num?)?.toDouble() ?? 0,
        price: (payload['price'] as num?)?.toDouble() ?? 0,
        facingDirection: payload['facing_direction']?.toString(),
      );

  @override
  Future<List<InventoryUnit>> unitsForProject(String projectId) async {
    if (shouldFail) throw Exception('forced failure');
    return units;
  }

  @override
  Future<InventoryUnit> createUnit({
    required String projectId,
    required Map<String, dynamic> payload,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    created.add(payload);
    final unit = _fromPayload(payload);
    units = [...units, unit];
    return unit;
  }

  @override
  Future<List<InventoryUnit>> createUnits({
    required String projectId,
    required List<Map<String, dynamic>> payloads,
  }) async {
    if (shouldFail) throw Exception('forced failure');
    bulkCreated.add(payloads);
    final saved = payloads.map(_fromPayload).toList();
    units = [...units, ...saved];
    return saved;
  }

  @override
  Future<void> updateUnit({
    required String unitId,
    required Map<String, dynamic> payload,
  }) async {
    if (shouldFail) throw Exception('forced failure');
  }

  @override
  Future<void> deleteUnit(String unitId) async {
    if (shouldFail) throw Exception('forced failure');
    units = units.where((u) => u.id != unitId).toList();
  }
}

class _FakeProjectService extends ProjectService {
  final List<({String projectId, String builderId})> syncs = [];

  @override
  Future<void> syncTotalsFromInventory({
    required String projectId,
    required String builderId,
  }) async {
    syncs.add((projectId: projectId, builderId: builderId));
  }
}

ProjectModel _project({
  int totalUnits = 3,
  String projectType = 'group_housing',
  double areaMin = 800,
  double priceMin = 4500000,
}) =>
    ProjectModel.fromSupabase({
      'id': 'p-1',
      'builder_id': 'b-1',
      'title': 'Green Valley',
      'project_type': projectType,
      'location': 'Pune',
      'status': 'active',
      'approval_status': 'approved',
      'total_units': totalUnits,
      'available_units': 0,
      'area_sqft_min': areaMin,
      'price_range_min': priceMin,
    });

InventoryUnit _unit({
  String id = 'u-1',
  String status = 'available',
  String unitType = 'Studio',
}) =>
    InventoryUnit(
      id: id,
      projectId: 'p-1',
      unitType: unitType,
      status: status,
      areaSqft: 800,
      price: 4500000,
    );

Future<void> _pump(
  WidgetTester tester, {
  required ProjectModel project,
  required _FakeInventoryService service,
  Size size = kSmall,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: ManageUnitsScreen(project: project, service: service),
    ),
  );
  await tester.pumpAndSettle();
}

/// Pushes [ManageUnitsScreen] from a dummy host screen and hands back the
/// [Navigator.push] result future, so a test can pop the screen (by any
/// route) and assert what the caller actually receives.
Future<Future<bool?>> _pushOnStack(
  WidgetTester tester, {
  required ProjectModel project,
  required _FakeInventoryService service,
  ProjectService? projectService,
  Size size = kSmall,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late Future<bool?> result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            result = Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => ManageUnitsScreen(
                  project: project,
                  service: service,
                  projectService: projectService,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
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

  group('tallies', () {
    testWidgets('total, available and sold come from the loaded units',
        (tester) async {
      await _pump(
        tester,
        project: _project(),
        service: _FakeInventoryService(units: [
          _unit(id: 'u-1', status: 'available'),
          _unit(id: 'u-2', status: 'available'),
          _unit(id: 'u-3', status: 'sold'),
          _unit(id: 'u-4', status: 'booked'),
        ]),
      );

      expect(find.text('4'), findsOneWidget); // total
      expect(find.text('2'), findsOneWidget); // available
      expect(find.text('1'), findsOneWidget); // sold
      expect(overflowingBoxes(tester), isEmpty);
    });
  });

  group('pre-fill from listing', () {
    testWidgets('generates drafts up to the listing total, writing nothing',
        (tester) async {
      final service = _FakeInventoryService(units: [_unit(id: 'u-1')]);
      await _pump(tester, project: _project(totalUnits: 3), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();

      // 3 total - 1 existing = 2 drafts.
      expect(find.text('NEW'), findsNWidgets(2));
      expect(service.created, isEmpty);
      expect(service.bulkCreated, isEmpty);
      expect(find.text('Save All New (2)'), findsOneWidget);
    });

    testWidgets('refuses once inventory already matches the listing',
        (tester) async {
      final service = _FakeInventoryService(units: [_unit(id: 'u-1')]);
      await _pump(tester, project: _project(totalUnits: 1), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();

      expect(
        find.text("Inventory already matches the listing's unit count."),
        findsOneWidget,
      );
      expect(find.text('NEW'), findsNothing);
    });

    testWidgets('a listing with no total unit count says so', (tester) async {
      final service = _FakeInventoryService();
      await _pump(tester, project: _project(totalUnits: 0), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();

      expect(
        find.text("This project's listing has no total unit count set."),
        findsOneWidget,
      );
    });
  });

  group('draft rows', () {
    testWidgets('the checkmark saves just that one row', (tester) async {
      final service = _FakeInventoryService();
      await _pump(tester, project: _project(totalUnits: 2), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();
      expect(find.text('NEW'), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.check_circle_outline).first);
      await tester.pumpAndSettle();

      expect(service.created, hasLength(1));
      expect(find.text('NEW'), findsOneWidget); // one draft remains
    });

    testWidgets('the discard icon drops the row without writing anything',
        (tester) async {
      final service = _FakeInventoryService();
      await _pump(tester, project: _project(totalUnits: 1), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();
      expect(find.text('NEW'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.cancel_outlined));
      await tester.pumpAndSettle();

      expect(find.text('NEW'), findsNothing);
      expect(service.created, isEmpty);
      expect(service.bulkCreated, isEmpty);
    });

    testWidgets('Save All New bulk-inserts every savable draft in one call',
        (tester) async {
      final service = _FakeInventoryService();
      await _pump(tester, project: _project(totalUnits: 4), service: service);

      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save All New (4)'));
      await tester.pumpAndSettle();

      expect(service.bulkCreated, hasLength(1));
      expect(service.bulkCreated.single, hasLength(4));
      expect(service.created, isEmpty, reason: 'one bulk call, not four single ones');
      expect(find.text('NEW'), findsNothing);
      expect(find.text('4 units added.'), findsOneWidget);
    });

    testWidgets('a failed bulk save keeps the drafts and says so',
        (tester) async {
      final service = _FakeInventoryService(shouldFail: true);
      await _pump(tester, project: _project(totalUnits: 2), service: service);

      // Pre-fill itself is a client-side draft generation and does not call
      // the (failing) service at all — and must show up even though the
      // initial load already failed (the screen's error state must not hide
      // drafts once there are some).
      await tester.tap(find.text('Pre-fill from Listing'));
      await tester.pumpAndSettle();
      expect(find.text('NEW'), findsNWidgets(2));

      await tester.tap(find.text('Save All New (2)'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not save the new units. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('NEW'), findsNWidgets(2), reason: 'nothing was actually saved');
    });
  });

  group('unit form', () {
    testWidgets('a plot unit type hides the floor field', (tester) async {
      final service = _FakeInventoryService();
      await _pump(
        tester,
        project: _project(projectType: 'plotted_development'),
        service: service,
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit type'),
        'Residential Plot',
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Floor (optional)'), findsNothing);
    });

    testWidgets('a non-plot unit type shows the floor field', (tester) async {
      final service = _FakeInventoryService();
      await _pump(
        tester,
        project: _project(projectType: 'group_housing'),
        service: service,
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Floor (optional)'), findsOneWidget);
    });

    testWidgets('adding a unit sends facing_direction through', (tester) async {
      final service = _FakeInventoryService();
      await _pump(tester, project: _project(), service: service);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit type'),
        'Studio',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Area (sqft)'),
        '600',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Price'), '3000000');

      await tester.tap(find.widgetWithText(DropdownButtonFormField<String?>, 'Facing (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('North').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Add Unit'));
      await tester.pumpAndSettle();

      expect(service.created.single['facing_direction'], 'North');
    });
  });

  group('reports changes back on pop', () {
    testWidgets(
      'popping with no edits at all returns false, not null, and never syncs',
      (tester) async {
        final service = _FakeInventoryService(units: [_unit(id: 'u-1')]);
        final projectService = _FakeProjectService();
        final result = await _pushOnStack(
          tester,
          project: _project(),
          service: service,
          projectService: projectService,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(await result, isFalse);
        expect(projectService.syncs, isEmpty);
      },
    );

    testWidgets(
      'adding a unit then popping returns true and syncs the listing totals',
      (tester) async {
        final service = _FakeInventoryService();
        final projectService = _FakeProjectService();
        final result = await _pushOnStack(
          tester,
          project: _project(),
          service: service,
          projectService: projectService,
        );

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Unit type'),
          'Studio',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Area (sqft)'),
          '600',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Price'),
          '3000000',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Add Unit'));
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(await result, isTrue);
        expect(projectService.syncs.single.projectId, 'p-1');
        expect(projectService.syncs.single.builderId, 'b-1');
      },
    );

    testWidgets(
      'deleting a unit then popping returns true and syncs the listing totals',
      (tester) async {
        final service = _FakeInventoryService(units: [_unit(id: 'u-1')]);
        final projectService = _FakeProjectService();
        final result = await _pushOnStack(
          tester,
          project: _project(),
          service: service,
          projectService: projectService,
        );

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(await result, isTrue);
        expect(projectService.syncs, hasLength(1));
      },
    );
  });
}
