// `ProjectCardVertical`'s type-label Text had no `maxLines`/`overflow`, unlike
// every other text in the card. A short label ("Office Spaces") fit on one
// line inside the card's tight 280px height (`AppConstants.propertyCardHeight`
// — a horizontal rail's `SizedBox` gives every card a fixed cross-axis
// constraint), but a longer one ("Gated Community with Plots/Villas") wrapped
// to two lines and overflowed the bottom of the card by a couple of pixels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/widgets/project_card_vertical.dart';

import 'support/overflow_detector.dart';

ProjectModel _project({required String projectType, required String title}) =>
    ProjectModel.fromSupabase({
      'id': 'p1',
      'builder_id': 'b1',
      'title': title,
      'project_type': projectType,
      'location': 'Pune',
      'status': 'active',
      'approval_status': 'approved',
      'total_units': 2,
      'available_units': 1,
    });

Future<void> _pumpCard(WidgetTester tester, ProjectModel project) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          // The exact constraint a horizontal rail gives every card —
          // `latest_projects_section.dart`'s `SizedBox(height:
          // AppConstants.propertyCardHeight)` around its `ListView.builder`.
          height: AppConstants.propertyCardHeight,
          child: ProjectCardVertical(project: project),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a long project type label does not overflow the fixed-height card',
    (tester) async {
      await _pumpCard(
        tester,
        _project(
          projectType: 'gated_community_plots_villas', // -> 34-char label
          title: 'Villa Available For Sale',
        ),
      );

      expect(overflowingBoxes(tester), isEmpty);
      // The label itself must still be findable, just truncated rather than
      // wrapped/clipped invisibly.
      expect(find.textContaining('Gated Community'), findsOneWidget);
    },
  );

  testWidgets('a short project type label still renders normally', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      _project(
        projectType: 'office_spaces', // -> 'Office Spaces'
        title: 'Office space Available',
      ),
    );

    expect(overflowingBoxes(tester), isEmpty);
    expect(find.text('Office Spaces'), findsOneWidget);
  });
}
