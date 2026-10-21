// The Projects & Inventory summary strip on the Builder dashboard's Inventory
// tab — six cards mirroring `BuilderInventoryManager.tsx:327-400` exactly.
//
// What is pinned: all six cards render unconditionally, including Total
// Units / Units Sold at `0` — the portal never hides any of them, and hiding
// the last two below a `_totalUnits > 0` guard (the previous behaviour) made
// the feature look entirely missing for a builder with no inventory rows yet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/builder_section_models.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/screens/dashboard/widgets/builder_inventory_summary.dart';

ProjectModel _project({String id = 'p-1', String status = 'active'}) =>
    ProjectModel.fromSupabase({
      'id': id,
      'builder_id': 'b-1',
      'title': 'Green Valley',
      'project_type': 'group_housing',
      'location': 'Pune',
      'status': status,
      'approval_status': 'approved',
    });

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectModel> projects,
  Map<String, InventoryCounts> unitCounts = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BuilderInventorySummary(projects: projects, unitCounts: unitCounts),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'shows all six cards, including Total Units and Units Sold at zero, '
    'when no project has inventory rows yet',
    (tester) async {
      await _pump(tester, projects: [_project()]);

      expect(find.text('Total Projects'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Under Construction'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Total Units'), findsOneWidget);
      expect(find.text('Units Sold'), findsOneWidget);

      // Total Units / Units Sold both read 0 rather than being absent —
      // alongside Under Construction and Completed, also 0 for this fixture.
      expect(find.text('0'), findsNWidgets(4));
    },
  );

  testWidgets('sums real inventory counts across every project', (tester) async {
    await _pump(
      tester,
      projects: [
        _project(id: 'p-1', status: 'active'),
        _project(id: 'p-2', status: 'under_construction'),
      ],
      unitCounts: const {
        'p-1': InventoryCounts(total: 10, sold: 4, available: 6),
        'p-2': InventoryCounts(total: 5, sold: 1, available: 4),
      },
    );

    expect(find.text('2'), findsOneWidget); // Total Projects
    expect(find.text('15'), findsOneWidget); // Total Units: 10 + 5
    expect(find.text('5'), findsOneWidget); // Units Sold: 4 + 1
  });

  testWidgets('renders nothing before any project has loaded', (tester) async {
    await _pump(tester, projects: const []);

    expect(find.text('Total Projects'), findsNothing);
    expect(find.byType(BuilderInventorySummary), findsOneWidget);
    expect(tester.getSize(find.byType(BuilderInventorySummary)).height, 0);
  });
}
