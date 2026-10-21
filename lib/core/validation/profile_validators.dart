// core/validation/profile_validators.dart
//
// The profile-form rules that `Validators` does not already cover.
//
// `Validators` is reused wherever it fits — `Validators.required`,
// `Validators.email`, `Validators.pincode` are all exact matches for the portal's
// rules and are called directly by the edit screen. This file adds only what is
// genuinely missing, so there is one validator per rule rather than two.
//
// Every threshold is transcribed from EditProfile.tsx's `handleSubmit`
// (lines 303-350). They are not house style: a GST number of the wrong length is
// rejected by the portal, so accepting one here would let the app write a value
// the portal then refuses to edit.
import 'validators.dart';

abstract final class ProfileValidators {
  /// Phone: **at least** 10 digits after stripping every non-digit.
  ///
  /// Deliberately NOT `Validators.phone`, which requires *exactly* 10.
  /// EditProfile.tsx:311-315 tests `cleanPhone.length < 10` — so 11+ digits is
  /// valid there, and the country code is stored separately. Using the stricter
  /// existing validator would reject numbers the portal accepts.
  static String? phoneAtLeast10(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Phone number is required.';
    if (digits.length < 10) return 'Phone number must be at least 10 digits.';
    return null;
  }

  /// Alternate mobile: blank passes, otherwise at least 10 digits.
  ///
  /// EditProfile.tsx:322-328.
  static String? optionalMobile(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      return 'Alternate mobile must be at least 10 digits.';
    }
    return null;
  }

  /// GSTIN: blank passes, otherwise exactly 15 characters.
  ///
  /// EditProfile.tsx:338-343 checks length only — no character-class pattern — so
  /// this does the same rather than imposing a stricter rule the portal would not.
  static String? gstNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (v.length != 15) return 'GST number must be exactly 15 characters.';
    return null;
  }

  /// PAN: blank passes, otherwise exactly 10 characters — **except** the literal
  /// sentinel `"uploaded"`.
  ///
  /// EditProfile.tsx:345-350 special-cases that string: the edit form writes
  /// `"uploaded"` into `pan_number` when a PAN document exists but no number was
  /// typed (EditProfile.tsx:162). Rejecting it would make an existing profile
  /// unsavable until the user cleared a field they never filled in.
  static String? panNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (v == 'uploaded') return null;
    if (v.length != 10) return 'PAN number must be exactly 10 characters.';
    return null;
  }

  /// Years of experience: blank passes, otherwise a whole number of 0 or more.
  ///
  /// `Validators.optionalPositiveNumber` rejects 0 and allows decimals, neither of
  /// which suits a year count — "0 years" is a legitimate answer for someone
  /// starting out, and "2.5 years" is not a value the integer column can hold.
  static String? optionalYears(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v);
    if (n == null) return 'Enter a whole number of years.';
    if (n < 0) return 'Years cannot be negative.';
    if (n > 100) return 'Enter a realistic number of years.';
    return null;
  }

  /// Follower / subscriber counts: blank passes, otherwise a non-negative whole
  /// number. EditProfile.tsx stores these with `parseInt`.
  static String? optionalCount(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final n = int.tryParse(v.replaceAll(',', ''));
    if (n == null) return 'Enter a whole number.';
    if (n < 0) return 'Count cannot be negative.';
    return null;
  }

  /// Website: blank passes; anything else is accepted.
  ///
  /// EditProfile.tsx applies **no** validation to this field and stores whatever
  /// is typed — `www.example.com` with no scheme is normal there, and the public
  /// profile prepends `https://` when opening it. `Validators.url` would reject
  /// that, so it is deliberately not used here.
  static String? website(String? value) => null;

  /// Letters, spaces, hyphens and apostrophes only — covers names like
  /// "Mary-Jane" or "D'Souza" while rejecting digits and other symbols.
  static final RegExp _namePattern = RegExp(r"^[a-zA-Z\s'-]+$");

  /// The required-name rule: non-blank, delegating to the existing validator so
  /// the message matches every other form in the app, plus a character-class
  /// check — a full name has no legitimate reason to contain digits.
  static String? fullName(String? value) {
    final requiredError = Validators.required(value);
    if (requiredError != null) return requiredError;
    if (!_namePattern.hasMatch(value!.trim())) {
      return 'Name can only contain letters, spaces and hyphens.';
    }
    return null;
  }
}
