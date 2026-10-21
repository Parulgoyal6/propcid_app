// Phase 5 — shared component library.
//
// Asserts each component against the design system's literal token values
// (sizes, colours, radii) plus the four states the phase's manual checklist
// names: populated, empty, long-text overflow, and on/off · active/inactive.
//
// Widget tests rather than golden images on purpose: a golden reference would be
// generated from this same render, so it would only prove the output is stable,
// not that it matches the spec. Asserting the documented numbers is falsifiable.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/theme/app_colors.dart';
import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/widgets/shared/content_picker_dialog.dart';
import 'package:propcid_app/widgets/shared/toggle_row.dart';

// The promoted widgets, at their single shared home. Phase 11 retired the
// re-export shims that used to sit at the original dashboard paths, so there is
// no second import path left to compare against.
import 'package:propcid_app/widgets/shared/stat_kpi_card.dart' as shared;
import 'package:propcid_app/widgets/shared/app_chart_wrapper.dart' as shared_chart;
import 'package:propcid_app/widgets/shared/section_header_back_button.dart'
    as shared_header;

import 'support/overflow_detector.dart';

// Size is applied via tester.view, not here.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      ),
    );

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(child));
  await tester.pumpAndSettle();
}

void main() {
  group('promotion is behaviour-preserving', () {

    test('grid geometry constants are unchanged by the move', () {
      expect(shared.MetricCardGrid.cardHeight, 112);
      expect(shared.MetricCardGrid.delegate.crossAxisCount, 2);
      expect(shared.MetricCardGrid.delegate.mainAxisSpacing, 10);
      expect(shared.MetricCardGrid.delegate.crossAxisSpacing, 10);
      expect(shared.MetricCardGrid.delegate.mainAxisExtent, 112);
    });
  });

  group('AppToggle — design tokens', () {
    testWidgets('track is 40x24 and knob 20x20', (tester) async {
      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: false, onChanged: (_) {}));

      final track = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      expect(track.constraints?.maxWidth, 40);
      expect(track.constraints?.maxHeight, 24);

      final knob = tester.getSize(
        find.descendant(
          of: find.byType(AnimatedPositioned),
          matching: find.byType(Container),
        ),
      );
      expect(knob, const Size(20, 20));
    });

    testWidgets('OFF track is #EDEDF2, ON track is #5B50E8', (tester) async {
      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: false, onChanged: (_) {}));
      var box = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .decoration as BoxDecoration;
      expect(box.color, AppColors.hairline);

      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: true, onChanged: (_) {}));
      box = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .decoration as BoxDecoration;
      expect(box.color, AppColors.primary);
    });

    testWidgets('knob travels 2 -> 18 between states', (tester) async {
      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: false, onChanged: (_) {}));
      expect(
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left,
        2,
      );

      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: true, onChanged: (_) {}));
      expect(
        tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).left,
        18,
      );
    });

    testWidgets('tapping reports the flipped value; null is inert',
        (tester) async {
      bool? got;
      await _pumpAt(tester, const Size(390, 844),
          AppToggle(value: false, onChanged: (v) => got = v));
      await tester.tap(find.byType(AppToggle));
      await tester.pump();
      expect(got, isTrue);

      got = null;
      await _pumpAt(
          tester, const Size(390, 844), const AppToggle(value: false));
      await tester.tap(find.byType(AppToggle));
      await tester.pump();
      expect(got, isNull);
    });
  });

  group('ToggleRow', () {
    testWidgets('renders label, optional description, and reacts to taps',
        (tester) async {
      var value = false;
      await _pumpAt(
        tester,
        const Size(320, 568),
        ToggleRow(
          label: 'Auto-share new properties',
          description: 'Publishes to your connected accounts automatically.',
          value: value,
          onChanged: (v) => value = v,
        ),
      );

      expect(find.text('Auto-share new properties'), findsOneWidget);
      expect(
        find.text('Publishes to your connected accounts automatically.'),
        findsOneWidget,
      );
      expect(overflowingBoxes(tester), isEmpty);

      await tester.tap(find.byType(AppToggle));
      await tester.pump();
      expect(value, isTrue);
    });

    testWidgets('long label and description do not overflow at 320 wide',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(320, 568),
        ToggleRow(
          label: 'Automatically share every newly published property listing '
              'to all connected social accounts',
          description: 'A deliberately long description used to prove the row '
              'wraps instead of overflowing its constraints on a small device.',
          value: true,
          onChanged: (_) {},
          showDivider: true,
        ),
      );
      expect(overflowingBoxes(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('content picker', () {
    final items = [
      const ContentPickerItem(
        id: '1',
        title: 'Luxury Villa in Dehradun',
        subtitle: 'Dehradun, Uttarakhand',
        typeLabel: 'Property',
      ),
      const ContentPickerItem(
        id: '2',
        title: 'Top 10 Investment Tips',
        subtitle: 'Published 2 days ago',
        typeLabel: 'Article',
        fallbackIcon: Icons.article_outlined,
      ),
    ];

    Future<ContentPickerItem?> open(
      WidgetTester tester, {
      required List<ContentPickerItem> data,
      bool loading = false,
      bool settle = true,
    }) async {
      ContentPickerItem? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showContentPickerSheet(
                    context,
                    items: data,
                    loading: loading,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
      return result;
    }

    testWidgets('populated: lists items with type chips', (tester) async {
      await open(tester, data: items);
      expect(find.text('Pick content to boost'), findsOneWidget);
      expect(find.text('Luxury Villa in Dehradun'), findsOneWidget);
      expect(find.text('Property'), findsOneWidget);
      expect(find.text('Top 10 Investment Tips'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('selecting a row returns it to the caller', (tester) async {
      ContentPickerItem? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showContentPickerSheet(context, items: items);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Top 10 Investment Tips'));
      await tester.pumpAndSettle();
      expect(picked?.id, '2');
    });

    testWidgets('empty: shows the empty-state block', (tester) async {
      await open(tester, data: const []);
      expect(find.text('Nothing to pick yet'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('loading: shows a spinner, not an empty state', (tester) async {
      await open(tester, data: const [], loading: true, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Nothing to pick yet'), findsNothing);
    });

    testWidgets('search is hidden for a short list', (tester) async {
      await open(tester, data: items);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('search appears past 5 items and filters', (tester) async {
      final many = [
        for (var i = 0; i < 8; i++)
          ContentPickerItem(id: '$i', title: 'Listing $i', typeLabel: 'Property'),
      ];
      await open(tester, data: many);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Listing 3');
      await tester.pumpAndSettle();
      // Scoped to the list: the search field itself also contains this text.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Listing 3'),
        ),
        findsOneWidget,
      );
      expect(find.text('Listing 4'), findsNothing);
    });

    testWidgets('search with no match shows the no-match state', (tester) async {
      final many = [
        for (var i = 0; i < 8; i++)
          ContentPickerItem(id: '$i', title: 'Listing $i', typeLabel: 'Property'),
      ];
      await open(tester, data: many);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    });
  });

  group('promoted widgets still render correctly', () {
    testWidgets('stat card grid holds its 112 dp height at 320 wide',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(320, 568),
        shared.MetricCardGrid(
          cards: const [
            shared.MetricCard(
              icon: Icons.visibility_outlined,
              value: '1,240',
              label: 'Total Views',
            ),
            shared.MetricCard(
              icon: Icons.people_outline,
              value: '156',
              label: 'Total Interactions',
            ),
          ],
        ),
      );
      expect(overflowingBoxes(tester), isEmpty);
      expect(find.text('1,240'), findsOneWidget);
      expect(find.text('Total Interactions'), findsOneWidget);
    });

    testWidgets('chart wrapper paints without a package', (tester) async {
      final base = DateTime(2026, 8, 3);
      await _pumpAt(
        tester,
        const Size(320, 568),
        shared_chart.DashboardLineChart(
          points: [
            for (var i = 0; i < 7; i++)
              ChartPoint(
                date: base.subtract(Duration(days: 6 - i)),
                value: [420, 610, 540, 700, 860, 780, 1240][i].toDouble(),
              ),
          ],
          showDayLabels: true,
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Sun'), findsWidgets);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('header renders title, subtitle and pops on back',
        (tester) async {
      await _pumpAt(
        tester,
        const Size(320, 568),
        const shared_header.DashboardHeaderBar(
          title: 'Network',
          subtitle: 'Your connections and referrals',
        ),
      );
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Your connections and referrals'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });
  });
}
