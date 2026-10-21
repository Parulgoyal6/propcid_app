// core/utils/number_format.dart
//
// Compact count formatting for stat tiles: 2300 -> "2.3K", 1_240_000 -> "1.2M".
//
// WHY THIS IS A SECOND COPY, DELIBERATELY
// ---------------------------------------
// `ProfileStatsRow._StatTile.formatCount` in
// screens/profile/widgets/profile_stats_row.dart already implements exactly this.
// Promoting it here and deleting it there would have been the DRY choice, but it
// would move an existing method and change its only caller — which the approved
// implementation rules forbid (D4: "appending is acceptable only if no existing
// methods change, no existing behaviour changes, no existing callers are
// affected. Otherwise create companion services").
//
// So this is a companion, and `profile_stats_row.dart` is untouched. The
// duplication is made safe mechanically rather than by convention:
// test/number_format_test.dart pumps the real `ProfileStatsRow` widget and
// asserts the string it renders equals the string this function returns, for
// every threshold. If either implementation drifts, that test fails.
//
// If the two are ever unified, delete this file and its test — not the widget's
// copy, which is the incumbent.
library;

/// 2300 -> "2.3K", 12_300 -> "12K", 1_240_000 -> "1.2M", 999 -> "999".
///
/// A byte-for-byte port of `ProfileStatsRow._StatTile.formatCount`, including
/// the "drop the decimal at 10 or above" rule that keeps the tile from
/// overflowing ("12K" not "12.3K").
///
/// Negative values are returned unchanged, as the original does — no count in
/// this app can be negative, and inventing a formatting rule for one would be
/// guessing.
String formatCompactCount(int value) {
  if (value >= 1000000) {
    final m = value / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final k = value / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}K';
  }
  return '$value';
}

/// A rating rendered to one decimal, or an em dash when there is nothing to
/// show.
///
/// The portal prints `avg.toFixed(1)` when `avg > 0` and a literal "—"
/// otherwise (UserProfile.tsx:1143). An em dash rather than "0.0" matters: the
/// app's existing convention is that a dash means "no value" while a number is a
/// claim — see `ProfileStatsRow`'s `hasFailed` handling.
String formatRating(double average) =>
    average > 0 ? average.toStringAsFixed(1) : '—';
