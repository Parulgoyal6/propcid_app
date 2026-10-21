// core/utils/listing_price_parser.dart
//
// The single, canonical parser for a listing's effective asking price.
//
// Before this file existed, three different places each interpreted
// `properties.price` differently: PropertyModel.fromSupabase defaulted an
// unparseable value to 0, PropertyProvider's budget filter used a bare
// `double.tryParse` that rejects "₹95,00,000"/"85 Lakh"/"1.2 Cr", and price
// sorting ordered by the sparsely-populated `price_min` column instead of
// `price` altogether. Every one of those call sites now goes through the two
// functions below, so display, budget filtering and price sorting can never
// disagree with each other again.
library;

/// Parses one raw price value into a positive rupee amount, or `null` when it
/// cannot be safely interpreted as one.
///
/// Accepts a `num` directly, or a `String` in any of these forms (case- and
/// whitespace-insensitive): a plain digit string, a decimal numeric string,
/// Indian comma grouping ("45,00,000"), a `₹` prefix, and an `L`/`Lac`/`Lakh`
/// or `Cr`/`Crore` unit suffix ("85 Lakh", "85L", "1.2 Cr", "1.2 crore").
///
/// Deliberately never returns 0 or a negative number — an unparsed, blank,
/// non-positive, or "Contact for price"-style value is always `null`, never
/// a false ₹0, so callers can tell "unknown" apart from a genuine (if
/// nonsensical) zero price and never silently rank or filter on it.
double? parseListingPrice(dynamic raw) {
  if (raw == null) return null;

  if (raw is num) {
    final value = raw.toDouble();
    return (value.isFinite && value > 0) ? value : null;
  }

  if (raw is! String) return null;
  var text = raw.trim();
  if (text.isEmpty) return null;

  final lower = text.toLowerCase();
  // Known non-numeric placeholders the wizard/portal can leave in this
  // column instead of an actual amount.
  if (lower.contains('contact') || lower.contains('n/a') || lower == '-') {
    return null;
  }

  text = text.replaceAll('₹', '').trim();

  // Pull a trailing unit word off the end — "85 Lakh", "85L", "1.2 Cr",
  // "1.2 crore" — leaving just the numeric portion in `text`.
  double multiplier = 1;
  final unitMatch = RegExp(
    r'^(.*?)\s*(lakhs?|lacs?|l|crores?|cr)\s*$',
    caseSensitive: false,
  ).firstMatch(text);
  if (unitMatch != null) {
    final unit = unitMatch.group(2)!.toLowerCase();
    text = unitMatch.group(1)!.trim();
    multiplier = (unit == 'cr' || unit == 'crore' || unit == 'crores')
        ? 10000000
        : 100000;
  }

  // Once any unit word is already stripped off, every remaining comma is
  // purely an Indian/thousands grouping separator, never a decimal mark.
  text = text.replaceAll(',', '');
  if (text.isEmpty) return null;

  final parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite || parsed <= 0) return null;

  final result = parsed * multiplier;
  return (result.isFinite && result > 0) ? result : null;
}

/// Resolves the effective price (in rupees) for a raw Supabase `properties`
/// row.
///
/// Prefers a valid, positive parse of `price` — the headline amount both
/// apps actually display — and falls back to a valid, positive `price_min`
/// only when `price` itself cannot be interpreted. Never the reverse: an
/// invalid or zero `price_min` must never mask a perfectly valid `price`.
double? resolveEffectivePrice(Map<String, dynamic> row) {
  final headline = parseListingPrice(row['price']);
  if (headline != null) return headline;
  return parseListingPrice(row['price_min']);
}
