// Builder flow — Phase B3: the two dashboard fixes.
//
//   1. "Add Project" opens the project wizard, not the property listing wizard.
//   2. "My Listings" collapses entirely — heading and spacing included — when a
//      builder has no listings, and stays put when they do or when the load
//      failed.
//
// The collapse is the part with real failure modes: hiding on "not loaded yet"
// flashes the section away and back, and hiding on a failed load would take
// `MyListingsSection`'s own error state and its Retry with it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/screens/dashboard/my_listings_section.dart';
import 'package:propcid_app/screens/dashboard/widgets/builder_listings_block.dart';

import 'support/overflow_detector.dart';

/// Stands in for `MyListingsSection`, reporting a count on command.
class _StubSection extends StatefulWidget {
  const _StubSection({required this.onCountChanged, required this.report});

  final ValueChanged<int> onCountChanged;

  /// The count to publish once mounted, or null to publish nothing — the
  /// still-loading and failed-load cases, which look identical from here.
  final int? report;

  @override
  State<_StubSection> createState() => _StubSectionState();
}

class _StubSectionState extends State<_StubSection> {
  static int builds = 0;

  @override
  void initState() {
    super.initState();
    builds++;
    final count = widget.report;
    if (count == null) return;
    // After the frame, exactly as MyListingsSection reports after its load.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onCountChanged(count);
    });
  }

  @override
  Widget build(BuildContext context) => const Text('LISTINGS BODY');
}

Future<void> _pumpBlock(WidgetTester tester, {int? report}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const Text('ABOVE'),
              BuilderListingsBlock(
                userId: 'b-1',
                sectionBuilder: (onCountChanged) => _StubSection(
                  onCountChanged: onCountChanged,
                  report: report,
                ),
              ),
            ],
          ),
        ),
      ),
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

  setUp(() => _StubSectionState.builds = 0);

  // ── 1. The route fix ───────────────────────────────────────────────────
  group('add project route', () {
    test('the project wizard and the listing wizard are different routes', () {
      // The defect was `_onCreate` pushing postPropertyScreen, so a builder
      // tapping "Add Project" wrote a row to `properties`. These must never be
      // the same string.
      expect(AppConstants.addProjectScreen, '/add-project');
      expect(AppConstants.postPropertyScreen, isNot('/add-project'));
      expect(
        AppConstants.addProjectScreen,
        isNot(AppConstants.postPropertyScreen),
      );
    });
  });

  // ── 2. The collapse ────────────────────────────────────────────────────
  group('My Listings block', () {
    testWidgets('shows heading and body when the builder has listings',
        (tester) async {
      await _pumpBlock(tester, report: 3);

      expect(find.text('MY LISTINGS'), findsOneWidget);
      expect(find.text('LISTINGS BODY'), findsOneWidget);
      expect(overflowingBoxes(tester), isEmpty);
    });

    testWidgets('collapses heading, spacing and body on a zero count',
        (tester) async {
      await _pumpBlock(tester, report: 0);

      expect(find.text('MY LISTINGS'), findsNothing);
      expect(find.text('LISTINGS BODY'), findsNothing);
      // The whole block, including the 22 dp gap that used to live in the
      // dashboard's own list — otherwise a hole survives the section.
      expect(tester.getSize(find.byType(BuilderListingsBlock)).height, 0);
    });

    testWidgets('stays visible while the count is still unknown',
        (tester) async {
      // Hiding on "not loaded yet" would flash the section away and back on
      // every dashboard open.
      await _pumpBlock(tester, report: null);

      expect(find.text('MY LISTINGS'), findsOneWidget);
      expect(find.text('LISTINGS BODY'), findsOneWidget);
    });

    testWidgets('stays visible when the load failed', (tester) async {
      // A failure never reports a count, so it is indistinguishable from
      // loading here — deliberately. `MyListingsSection` keeps rendering its own
      // error state and its Retry stays reachable.
      await _pumpBlock(tester, report: null);

      expect(find.text('MY LISTINGS'), findsOneWidget);
    });

    testWidgets('collapses when the last listing is deleted', (tester) async {
      // The delete path prunes locally rather than re-fetching, which is why
      // MyListingsSection reports the count from there too.
      late ValueChanged<int> report;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BuilderListingsBlock(
              userId: 'b-1',
              sectionBuilder: (onCountChanged) {
                report = onCountChanged;
                return const Text('LISTINGS BODY');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      report(1);
      await tester.pumpAndSettle();
      expect(find.text('MY LISTINGS'), findsOneWidget);

      report(0);
      await tester.pumpAndSettle();
      expect(find.text('MY LISTINGS'), findsNothing);
    });

    testWidgets('a repeated count does not rebuild the section', (tester) async {
      // The loop this guards: the block rebuilds when a count arrives, which
      // re-creates an un-keyed child, whose initState reports again.
      late ValueChanged<int> report;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BuilderListingsBlock(
              userId: 'b-1',
              sectionBuilder: (onCountChanged) {
                report = onCountChanged;
                return _StubSection(onCountChanged: onCountChanged, report: 2);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final buildsAfterFirstReport = _StubSectionState.builds;

      report(2); // same value again
      await tester.pumpAndSettle();

      expect(_StubSectionState.builds, buildsAfterFirstReport,
          reason: 'an unchanged count must not re-create the section');
    });
  });

  // ── 3. The real section's callback contract ────────────────────────────
  group('MyListingsSection', () {
    testWidgets('does not report a count when the fetch fails', (tester) async {
      // Against the loopback client the fetch throws, so this exercises the real
      // failure path end to end: no count, so the block cannot collapse, and the
      // section's own error state is what the user sees.
      final reported = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyListingsSection(
                userId: 'b-1',
                onCountChanged: reported.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(reported, isEmpty,
          reason: 'a failed load is not an empty list');
    });

    testWidgets('accepts being constructed without the callback',
        (tester) async {
      // The parameter is optional; any existing caller keeps compiling.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MyListingsSection(userId: 'b-1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
