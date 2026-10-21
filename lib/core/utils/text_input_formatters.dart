import 'package:flutter/services.dart';

/// Upper-cases input as it is typed.
///
/// Used by the registration flows for identifier fields (RERA / GST style
/// codes) that are stored upper-case.
///
/// Consolidated in Phase 11: this class previously existed as two byte-identical
/// private copies inside `broker_registration_screen.dart` and
/// `builder_registration_screen.dart`. Behaviour is unchanged.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
