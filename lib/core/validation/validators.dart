/// Pure-function validators for use in providers and [TextFormField.validator]
/// callbacks.
///
/// Every method returns [null] when the value is **valid** and a user-facing
/// error [String] when it is **not**. This matches the Flutter [FormFieldValidator]
/// convention so the same call works in both a [TextFormField] and a provider
/// boolean guard (`Validators.someMethod(v) == null`).
abstract final class Validators {
  // ── Presence ────────────────────────────────────────────────────────────

  /// The value must be non-null and non-blank after trimming.
  static String? required(String? value) {
    if (value == null || value.trim().isEmpty) return 'This field is required.';
    return null;
  }

  // ── Format ──────────────────────────────────────────────────────────────

  /// Must contain at least one character before and after `@`, and a `.` in
  /// the domain part. Blank values pass — combine with [required] when the
  /// field is mandatory.
  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (!RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    ).hasMatch(v)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Exactly 10 digits after stripping spaces. Blank values pass.
  static String? phone(String? value) {
    final v = (value ?? '').trim().replaceAll(' ', '');
    if (v.isEmpty) return null;
    if (!RegExp(r'^\d{10}$').hasMatch(v)) {
      return 'Enter a valid 10-digit phone number.';
    }
    return null;
  }

  /// Normalises any accepted mobile input (with/without `+91`, spaces,
  /// dashes) to the E.164 form the `send-otp` edge function expects.
  static String toE164(String value) {
    final String digits = value.replaceAll(RegExp(r'\D'), '');
    final String last10 = digits.length > 10
        ? digits.substring(digits.length - 10)
        : digits;
    return '+91$last10';
  }

  /// Exactly 6 digits. Blank values pass.
  static String? pincode(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      return 'Enter a valid 6-digit pincode.';
    }
    return null;
  }

  /// Well-formed http / https URL. Blank values pass.
  static String? url(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final uri = Uri.tryParse(v);
    if (uri == null || uri.host.isEmpty) {
      return 'Enter a valid URL (e.g., https://example.com).';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL must start with http:// or https://.';
    }
    return null;
  }

  // ── Numeric — required ───────────────────────────────────────────────────

  /// Non-blank AND a finite number greater than zero. Scientific notation
  /// (e.g. `"1e5"`) is rejected to prevent ambiguous input.
  static String? requiredPositiveNumber(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required.';
    if (v.contains('e') || v.contains('E')) {
      return 'Enter a plain number (no scientific notation).';
    }
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return 'Enter a valid number.';
    if (n <= 0) return 'Value must be greater than zero.';
    return null;
  }

  /// Non-blank AND a positive integer. Rejects decimals, zero, and negatives.
  static String? requiredPositiveInt(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'This field is required.';
    final n = int.tryParse(v);
    if (n == null) return 'Enter a whole number (no decimals).';
    if (n <= 0) return 'Value must be greater than zero.';
    return null;
  }

  // ── Numeric — optional ───────────────────────────────────────────────────

  /// Blank passes. Non-blank must be a finite number greater than zero with no
  /// scientific notation.
  static String? optionalPositiveNumber(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains('e') || v.contains('E')) {
      return 'Enter a plain number (no scientific notation).';
    }
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return 'Enter a valid number.';
    if (n <= 0) return 'Value must be greater than zero.';
    return null;
  }

  /// Blank passes. Non-blank must be a finite number of zero or more with no
  /// scientific notation. Allows zero (e.g., "no security deposit").
  static String? optionalNonNegativeNumber(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains('e') || v.contains('E')) {
      return 'Enter a plain number (no scientific notation).';
    }
    final n = double.tryParse(v);
    if (n == null || !n.isFinite) return 'Enter a valid number.';
    if (n < 0) return 'Value must be zero or greater.';
    return null;
  }

  /// Blank passes. Non-blank must be a number in the range [0, 100] with no
  /// scientific notation. Used for percentage fields.
  static String? optionalPercent(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    if (v.contains('e') || v.contains('E')) {
      return 'Enter a plain number (no scientific notation).';
    }
    final n = double.tryParse(v);
    if (n == null) return 'Enter a valid number.';
    if (n < 0 || n > 100) return 'Value must be between 0 and 100.';
    return null;
  }
}
