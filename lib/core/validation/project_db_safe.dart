// core/validation/project_db_safe.dart
//
// Null-safe coercion for everything the builder project wizard writes.
//
// WHY THIS EXISTS AT ALL
// ----------------------
// `20270315000000_no_null_listing_and_project_columns.sql:251-275` makes **24 of
// `builder_projects`' columns NOT NULL** — description, status, approval_status,
// rera_number, brochure_url, website_url, contact_number, logo_url,
// master_layout_url, total_units, available_units, price_range_min/max,
// area_sqft_min/max, latitude, longitude, likes, views, amenities, media_urls,
// map_images, videos_urls, other_images. Passing `null` for any of them fails the
// whole insert with a `23502`, so "the user left it blank" has to become a
// concrete typed value before it reaches PostgREST:
//
//   text -> ''      numeric -> 0      array -> []
//
// Two deliberate exceptions, because Postgres cannot represent "empty" for them
// and a placeholder would be a lie:
//   * `completion_date` / `possession_date` are `date` and stay nullable, so
//     [dbDate] still returns null for a blank. Both are made mandatory by the
//     wizard's step rules, so a null is rare rather than normal.
//   * foreign keys are not coerced — a fake uuid would break referential
//     integrity. Nothing in this payload is an FK except `builder_id`, which is
//     always `auth.uid()`.
//
// A direct port of `propcid/src/lib/validation/dbSafe.ts`.
//
// WHY IT IS SCOPED TO THE PROJECT FEATURE
// ---------------------------------------
// The `project_` prefix is deliberate. The listing wizard
// (`PostPropertyProvider` / `PropertyService`) builds its payload its own way and
// is not routed through here; making this a global helper would imply a
// consistency the app does not have and would invite a future edit that changes
// listing behaviour. This is the project payload's coercion layer, nothing more.

/// Sanitised, never-null string. Blank falls back to [fallback] (default `''`).
///
/// `dbSafe.ts:24-28`.
String dbText(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final cleaned = sanitizeText(value.toString());
  return cleaned.isNotEmpty ? cleaned : fallback;
}

/// Never-null numeric. Strips currency symbols and commas before parsing.
///
/// `dbSafe.ts:31-35`. Note the empty-string check is against the **original**
/// value, exactly as the reference does it: `'abc'` is not `''`, so it strips to
/// `''`, fails to parse, and lands on the fallback anyway.
double dbNum(Object? value, {double fallback = 0}) {
  if (value == null || value == '') return fallback;
  if (value is num) {
    return value.isFinite ? value.toDouble() : fallback;
  }
  final stripped = value.toString().replaceAll(RegExp(r'[^\d.-]'), '');
  final parsed = jsParseFloat(stripped);
  return (parsed != null && parsed.isFinite) ? parsed : fallback;
}

/// Never-null integer, for `integer` columns (`total_units`, `available_units`).
///
/// `dbSafe.ts:38-41` — `Math.trunc`, which truncates toward zero rather than
/// rounding, so `2.9` is 2 and `-2.9` is -2.
int dbInt(Object? value, {int fallback = 0}) =>
    dbNum(value, fallback: fallback.toDouble()).truncate();

/// Never-null `text[]`. Drops null and blank entries.
///
/// `dbSafe.ts:49-52`.
List<String> dbArray(Object? value, {List<String> fallback = const []}) {
  if (value is! List) return fallback;
  return value
      .where((item) => item != null && item.toString().trim().isNotEmpty)
      .map((item) => item.toString())
      .toList(growable: false);
}

/// `date` columns: Postgres rejects `''`, so a blank becomes null.
///
/// `dbSafe.ts:66-69`. The value is passed through untouched otherwise — the
/// caller supplies an ISO `yyyy-MM-dd`.
String? dbDate(Object? value) {
  final text = value is String ? value.trim() : '';
  return text.isEmpty ? null : text;
}

/// Mirrors JavaScript's `parseFloat`, which Dart's `double.tryParse` does not.
///
/// The difference bites on exactly one input this payload can produce: after
/// [dbNum] strips to `[\d.-]`, a value like `12.5.7` survives. `parseFloat`
/// returns `12.5` (longest valid prefix); `double.tryParse` returns null, which
/// would silently become 0 and store a different number than the website does for
/// the same keystrokes.
/// Public so the parity can be asserted directly.
double? jsParseFloat(String input) {
  final match = RegExp(
    r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?',
  ).firstMatch(input.trimLeft());
  if (match == null) return null;
  return double.tryParse(match.group(0)!);
}

/// Strips scripts, inline event handlers, `javascript:` URLs and control
/// characters, then trims and collapses whitespace.
///
/// A port of `propcid/src/utils/sanitize.ts:20-36`, which every `dbText` value
/// passes through on the website.
///
/// The reference's replace order has two defects. They are handled
/// differently, on purpose - see PD8 and PD9 in
/// docs/BUILDER_FLOW_IMPLEMENTATION_PLAN.md.
///
/// **PD8 - script content is not removed. Reproduced as-is.**
/// `</script>` is stripped by the *first* rule, which leaves the *second* rule
/// - the paired `<script>...</script>` matcher - with nothing to match, so
/// `<script>bad()</script>x` becomes `<script>bad()x`. This helper is therefore
/// **not** a sanitiser in any meaningful sense; treat every value that passes
/// through it as untrusted text. The reference's own header calls it
/// "defense-in-depth" and says server-side and RLS protections remain
/// authoritative. There is no live injection path - React escapes by default and
/// nothing in this app renders these values as HTML - so the behaviour is kept
/// rather than diverging over a difference that changes no outcome. **Do not
/// introduce an HTML rendering path for any value that came through here.**
///
/// **PD9 - newlines used to be deleted. Fixed here, deliberately diverging.**
/// A newline is \x0A, so the reference's control-character strip removes it
/// *before* its whitespace collapse can turn it into a space:
/// `'line one\nline two'` is stored by the website as `'line oneline two'`,
/// with adjacent lines joined and **no separator at all**. That is data
/// corruption rather than a business rule, so it is not carried into new code.
/// Whitespace control characters are converted to a space *before* the strip,
/// which makes the collapse behave the way the reference plainly intended.
///
/// The divergence is real and one-sided: the same text typed on the website is
/// still mangled there. Approved knowingly.
String sanitizeText(String? value) {
  if (value == null || value.isEmpty) return '';

  var v = value
      // Closing tags first, matching the reference's order - and its PD8.
      .replaceAll(RegExp(r'</(script|style)>', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'<(script|style)[^>]*>[\s\S]*?</(script|style)>',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'''on[a-z]+\s*=\s*"[^"]*"''', caseSensitive: false),
        '',
      )
      .replaceAll(
        RegExp(r"""on[a-z]+\s*=\s*'[^']*'""", caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'on[a-z]+\s*=\s*[^\s>]+', caseSensitive: false), '')
      .replaceAll(RegExp(r'javascript:', caseSensitive: false), '')
      // PD9 FIX - this line is the divergence.
      //
      // Tab, newline, vertical tab, form feed and carriage return (\x09-\x0D)
      // become a space before the strip below deletes them outright. Without
      // this, 'line one' + newline + 'line two' arrives at the collapse as
      // 'line oneline two' and there is nothing left to collapse.
      .replaceAll(RegExp(r'[\x09-\x0D]'), ' ')
      // The remaining control characters carry no meaning and are removed:
      // \x00-\x08, \x0E-\x1F and \x7F.
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .trim();

  // Collapse the runs the conversion above may have produced.
  v = v.replaceAll(RegExp(r'\s+'), ' ');
  return v;
}

/// Blank becomes null rather than `''`.
///
/// `sanitize.ts:38-41`. Used for the nullable columns the project payload
/// touches, so an untouched optional field reads as absent in the admin panel
/// rather than present-but-empty.
String? sanitizeNullable(String? value) {
  final s = sanitizeText(value ?? '');
  return s.isEmpty ? null : s;
}
