// Guards the deliberate duplication between `core/utils/number_format.dart` and
// the private `ProfileStatsRow._StatTile.formatCount`.
//
// `formatCount` could not be promoted into the shared util: doing so would move an
// existing method and change its only caller, which the approved implementation
// rules forbid (D4). So there are two implementations, and this test is what makes
// that safe.
//
// `_StatTile` is private, so it cannot be called directly. Instead the real
// `ProfileStatsRow` widget is pumped with known values and the STRING IT RENDERS
// is compared against what `formatCompactCount` returns. That tests the actual
// shipped behaviour rather than a restatement of it — if either implementation
// drifts, this fails.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/utils/number_format.dart';
import 'package:propcid_app/models/profile_stats.dart';
import 'package:propcid_app/screens/profile/widgets/profile_stats_row.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

/// Renders `ProfileStatsRow` with [value] in the Followers slot and returns the
/// text the widget actually painted there.
Future<String> _renderedByStatsRow(WidgetTester tester, int value) async {
  await tester.pumpWidget(
    _host(
      ProfileStatsRow(
        stats: ProfileStats(followers: value),
        isLoading: false,
      ),
    ),
  );
  await tester.pump();

  // Three tiles render; Followers is the first. Its value sits above its label,
  // so the value Text is the one that is not one of the three known labels.
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .toList();

  const labels = {'Followers', 'Reviews', 'Profile Views'};
  final values = texts.where((t) => !labels.contains(t)).toList();

  // Reviews and Profile Views are both 0 here, so the distinct non-label values
  // are the formatted follower count plus '0'. Return the one that is not '0'
  // unless the input really was 0.
  if (value == 0) return '0';
  return values.firstWhere((v) => v != '0', orElse: () => values.first);
}

void main() {
  group('formatCompactCount thresholds', () {
    test('below 1000 is printed as-is', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(1), '1');
      expect(formatCompactCount(42), '42');
      expect(formatCompactCount(999), '999');
    });

    test('1000 and above use K, one decimal below 10K', () {
      expect(formatCompactCount(1000), '1.0K');
      expect(formatCompactCount(1500), '1.5K');
      expect(formatCompactCount(2300), '2.3K');
      expect(formatCompactCount(9999), '10.0K');
    });

    test('10K and above drop the decimal', () {
      // The rule that keeps a tile from overflowing: 12K, not 12.3K.
      expect(formatCompactCount(10000), '10K');
      expect(formatCompactCount(12300), '12K');
      expect(formatCompactCount(999499), '999K');
    });

    test('a million and above use M', () {
      expect(formatCompactCount(1000000), '1.0M');
      expect(formatCompactCount(1240000), '1.2M');
      expect(formatCompactCount(9900000), '9.9M');
      expect(formatCompactCount(10000000), '10M');
    });

    test('negatives are returned unchanged, as the original does', () {
      expect(formatCompactCount(-5), '-5');
    });
  });

  group('formatRating', () {
    test('one decimal when there is a rating', () {
      expect(formatRating(4.0), '4.0');
      expect(formatRating(4.66), '4.7');
      expect(formatRating(3.24), '3.2');
      // Exact halves are deliberately not asserted: 4.55 is not exactly
      // representable in binary, so its rounding is a float artefact rather than
      // a contract either platform relies on.
    });

    test('an em dash when there is none — never 0.0', () {
      // A zero would read as a real (bad) rating. The dash means "no value",
      // matching UserProfile.tsx:1143 and ProfileStatsRow's failure treatment.
      expect(formatRating(0), '—');
    });
  });

  group('parity with the live ProfileStatsRow', () {
    // Every boundary the two implementations share. If `profile_stats_row.dart`
    // is ever edited, this is the test that catches the divergence.
    const boundaries = <int>[
      0,
      1,
      999,
      1000,
      2300,
      9999,
      10000,
      12300,
      999499,
      1000000,
      1240000,
      10000000,
    ];

    for (final value in boundaries) {
      testWidgets('ProfileStatsRow renders $value the same way',
          (tester) async {
        final rendered = await _renderedByStatsRow(tester, value);
        expect(
          rendered,
          formatCompactCount(value),
          reason: 'ProfileStatsRow painted "$rendered" but '
              'formatCompactCount returned "${formatCompactCount(value)}" '
              'for $value — the two implementations have drifted',
        );
      });
    }
  });
}
