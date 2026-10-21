// Direct port of propcid/src/lib/validation/requiredFields.ts.
//
// final-architecture-review Q6 requires the validator INTERNALS be ported
// verbatim rather than approximated: "A subtly different isBlank or phone regex
// will pass/fail different inputs than the Web, breaking step-gating parity."
//
// T0 ships only the engine. The rule table itself (propertyListingRules.ts) is
// T2 and is deliberately not started here.

/// Regexes copied character-for-character from `PATTERN` (requiredFields.ts:99).
class ListingPattern {
  ListingPattern._();

  static final RegExp email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp pincode = RegExp(r'^\d{6}$');
  static final RegExp phone = RegExp(r'^\+?[\d\s-]{8,15}$');

  /// Letters, digits, `/` and `-` only, 8 to 60 characters — not a React
  /// port. State RERA formats vary too widely (Maharashtra's `P51800012345`,
  /// Gujarat's long slash-segmented ids, Haryana's, Karnataka's...) to
  /// pattern-match beyond character set and length, so no state-specific
  /// format is enforced on purpose.
  static final RegExp rera = RegExp(r'^[A-Za-z0-9/-]{8,60}$');

  /// A time range like "10 AM - 6 PM", "9:30 am-5:45 pm" or "6 AM to 10 PM"
  /// — not a React port. The portal's own "Best Time to Call" input
  /// (MediaAndFinalStep.tsx) is unrestricted free text; added on explicit
  /// request so the field can't be saved with something that isn't a time
  /// range at all. Accepts "-" or "to" as the separator — both are how
  /// people naturally type a time range, and rejecting one of them was
  /// itself the bug this pattern was fixed for.
  static final RegExp timeRange = RegExp(
    r'^(1[0-2]|0?[1-9])(:[0-5][0-9])?\s*(AM|PM)\s*(?:-|to)\s*'
    r'(1[0-2]|0?[1-9])(:[0-5][0-9])?\s*(AM|PM)$',
    caseSensitive: false,
  );
}

/// Mirrors JavaScript's `Number(String)` coercion, which Dart does NOT share.
///
/// This matters: `Number('')` is **0** in JS, while `double.tryParse('')` is
/// null in Dart. React's [positiveNumber] strips non-numeric characters first,
/// so an input of `'abc'` becomes `''` -> 0 -> "must be greater than 0", NOT
/// "must be a number". Using tryParse directly would emit the wrong message and
/// take a different branch than the web for the same input.
///
/// Returns null where JS yields NaN.
double? _jsNumber(String raw) {
  final String t = raw.trim();
  if (t.isEmpty) return 0; // Number('') === 0
  return double.tryParse(t); // null == NaN
}

/// Strips everything except digits, dot and minus — React's
/// `String(value).replace(/[^\d.-]/g, '')`.
String _stripToNumeric(Object? value) =>
    value.toString().replaceAll(RegExp(r'[^\d.-]'), '');

/// A value counts as "provided" when it is a non-empty string, a finite number,
/// a non-empty collection, or a boolean.
///
/// Verbatim from `isBlank` (requiredFields.ts:42). The boolean case is the one
/// most easily got wrong: **`false` is a deliberate answer, not a blank**, so an
/// unchecked required checkbox passes this check.
bool isBlank(Object? value) {
  if (value == null) return true;
  if (value is String) return value.trim() == '';
  if (value is num) return value.isNaN;
  if (value is bool) return false; // false is an answer
  if (value is List) return value.isEmpty;
  if (value is Set) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  return false;
}

/// Rejects "0", "-5" and "abc" for amount/count inputs.
/// Verbatim from `positiveNumber` (requiredFields.ts:106).
String? Function(Object?) positiveNumber(String label) {
  return (Object? value) {
    final double? n = _jsNumber(_stripToNumeric(value));
    if (n == null) return '$label must be a number.';
    if (n <= 0) return '$label must be greater than 0.';
    return null;
  };
}

/// Same as [positiveNumber] but with a caller-supplied floor instead of a
/// bare "greater than 0" — not a React port.
String? Function(Object?) minNumber(num min, String label) {
  return (Object? value) {
    final double? n = _jsNumber(_stripToNumeric(value));
    if (n == null) return '$label must be a number.';
    if (n < min) return '$label must be at least $min.';
    return null;
  };
}

/// Same as [positiveNumber] but allows 0 (floor numbers, balcony counts...).
/// Verbatim from `nonNegativeNumber` (requiredFields.ts:116).
String? Function(Object?) nonNegativeNumber(String label) {
  return (Object? value) {
    final double? n = _jsNumber(_stripToNumeric(value));
    if (n == null) return '$label must be a number.';
    if (n < 0) return '$label cannot be negative.';
    return null;
  };
}

/// Same as [nonNegativeNumber] but also rejects anything above [max] — not a
/// React port. Added on explicit request as a real "Total Floors" ceiling
/// (163, the tallest habitable building anywhere today), so a mistyped or
/// unrealistic value can no longer be saved — on top of, not instead of, the
/// rendering-safety limits `PropertyDimensionsStep`'s floor-wise editors
/// already impose on themselves.
String? Function(Object?) nonNegativeNumberWithMax(num max, String label) {
  return (Object? value) {
    final double? n = _jsNumber(_stripToNumeric(value));
    if (n == null) return '$label must be a number.';
    if (n < 0) return '$label cannot be negative.';
    if (n > max) return '$label cannot exceed $max.';
    return null;
  };
}

/// Same as [positiveNumber] but also rejects anything above [max] — not a
/// React port; see [nonNegativeNumberWithMax].
String? Function(Object?) positiveNumberWithMax(num max, String label) {
  return (Object? value) {
    final double? n = _jsNumber(_stripToNumeric(value));
    if (n == null) return '$label must be a number.';
    if (n <= 0) return '$label must be greater than 0.';
    if (n > max) return '$label cannot exceed $max.';
    return null;
  };
}

/// NOTE: React does NOT trim before testing email, but DOES for pincode/phone.
/// Preserved exactly, so a trailing space fails email here as it does on web.
String? validEmail(Object? value) =>
    ListingPattern.email.hasMatch(value.toString())
    ? null
    : 'Enter a valid email address.';

String? validPincode(Object? value) =>
    ListingPattern.pincode.hasMatch(value.toString().trim())
    ? null
    : 'Pincode must be 6 digits.';

String? validPhone(Object? value) =>
    ListingPattern.phone.hasMatch(value.toString().trim())
    ? null
    : 'Enter a valid contact number.';

/// WhatsApp's own text field (media_contact_step.dart) restricts input to
/// digits-only, capped at 10 characters — unlike the free-text contact-phone
/// field [validPhone] is shared with (portal-matched to also accept
/// "+91 98765 43210"-style punctuation), a WhatsApp number here can never
/// contain anything but digits. Reusing [validPhone]'s 8-15-character range
/// against that digits-only input let incomplete 8- or 9-digit entries pass
/// as "valid" — this requires the full 10 digits a real number always has.
String? validWhatsappNumber(Object? value) =>
    RegExp(r'^\d{10}$').hasMatch(value.toString().trim())
    ? null
    : 'Enter a valid 10-digit WhatsApp number.';

/// Same fix as [validWhatsappNumber], for the builder project wizard's own
/// digits-only "Contact Number" field (`contact_media_step.dart`'s
/// `kProjectContactNumber`, capped at 10 characters by its own input
/// formatters). That field used to share [validPhone] for "identical
/// gating" with the property wizard's free-text phone field — but
/// [validPhone]'s 8-15-character range exists to allow that field's
/// "+91 98765 43210"-style punctuation, and against digits-only input it
/// let an 8- or 9-digit number through as "valid".
String? validProjectContactNumber(Object? value) =>
    RegExp(r'^\d{10}$').hasMatch(value.toString().trim())
    ? null
    : 'Enter a valid 10-digit contact number.';

String? validRera(Object? value) =>
    ListingPattern.rera.hasMatch(value.toString().trim())
    ? null
    : 'RERA number must be 8-60 characters, using only letters, numbers, '
          'slashes and hyphens.';

String? validTimeRange(Object? value) =>
    ListingPattern.timeRange.hasMatch(value.toString().trim())
    ? null
    : 'Enter a valid time range, e.g. 10 AM - 6 PM or 10 AM to 6 PM.';

String? Function(Object?) minLength(int n, String label) {
  return (Object? value) => value.toString().trim().length < n
      ? '$label must be at least $n characters.'
      : null;
}

/// Counts only letters and spaces (digits/punctuation ignored), after
/// collapsing repeat spaces. `countAlphaChars` (requiredFields.ts:224).
int countAlphaChars(Object? value) {
  final collapsed = value.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  return collapsed.replaceAll(RegExp(r'[^a-zA-Z ]'), '').length;
}

/// Enforces a minimum letters+spaces count on long-form text fields
/// (descriptions, bios, testimonials). `minAlphaChars` (requiredFields.ts:230)
/// — used for both the project and property description fields
/// (projectRules.ts:82, propertyListingRules.ts:59).
String? Function(Object?) minAlphaChars(int n, String label) {
  return (Object? value) {
    final count = countAlphaChars(value);
    return count < n
        ? '$label must be at least $n letters (currently $count).'
        : null;
  };
}

/// Compact one-line summary for a toast: "Area, Bedrooms, Bathrooms and 4 more".
/// Mirrors `summariseIssues` (requiredFields.ts:81).
String summariseIssues(List<String> labels, {int max = 4}) {
  if (labels.isEmpty) return '';
  if (labels.length <= max) {
    if (labels.length == 1) return labels.first;
    return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  }
  return '${labels.sublist(0, max).join(', ')} and ${labels.length - max} more';
}
