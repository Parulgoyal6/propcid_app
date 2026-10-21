// services/requirement_service.dart
//
// "Tell Your Needs" — inserts into `public.user_requirements`. Write-only: this
// service never reads, because the RLS SELECT policies only expose a row to its
// own author or an admin (20260326000003:39-51) and nothing in the app lists
// them back.
//
// INSERT is `WITH CHECK (true)` (20260326000003:54-57), so a guest submission is
// permitted; `user_id` is attached when there happens to be a session, exactly as
// `LeadForm.tsx:170` does with `user?.id || null`.
//
// PHONE IS STORED AS TYPED, NOT AS E.164
// --------------------------------------
// `LeadForm.tsx:163` sends `sanitizeText(formData.phone)` — the raw 10 digits.
// Every row an admin already reads in this column is in that shape, so writing
// `+91…` from the app only would fragment the column across two formats for the
// same field. The caller validates the format before getting here; E.164 is
// reserved for the OTP edge function, which is the only consumer that needs it.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RequirementService {
  RequirementService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'user_requirements';

  /// Submits one requirement.
  ///
  /// [budget] must be one of the portal's five slugs (`under-50l`, `50l-1cr`,
  /// `1cr-2cr`, `2cr-5cr`, `above-5cr`) and [propertyType] one of its five
  /// (`apartment`, `villa`, `plot`, `commercial`, `office`) — see
  /// `LeadForm.tsx:385-431`. Nothing here validates that, because the column is
  /// free text on both sides; the form owns the vocabulary.
  ///
  /// `status` is sent explicitly as `'pending'` rather than relying on the column
  /// default, matching `LeadForm.tsx:172`. It is one of the four values the CHECK
  /// constraint allows (`pending | contacted | resolved | rejected`).
  Future<void> submit({
    required String name,
    required String phone,
    required String budget,
    String? propertyType,
    String? location,
    String? requirements,
  }) async {
    try {
      await _supabase
          .from(_table)
          .insert(
            buildPayload(
              userId: _supabase.auth.currentUser?.id,
              name: name,
              phone: phone,
              budget: budget,
              propertyType: propertyType,
              location: location,
              requirements: requirements,
            ),
          );
    } catch (e) {
      debugPrint('RequirementService.submit failed: $e');
      rethrow;
    }
  }

  /// The exact row this service writes. Split out so the blank-to-null rule and
  /// the key names can be asserted without a database.
  @visibleForTesting
  static Map<String, dynamic> buildPayload({
    String? userId,
    required String name,
    required String phone,
    required String budget,
    String? propertyType,
    String? location,
    String? requirements,
  }) {
    return {
      'name': name.trim(),
      'phone': phone.trim(),
      'budget': budget,
      'property_type': _nullIfBlank(propertyType),
      'location': _nullIfBlank(location),
      'requirements': _nullIfBlank(requirements),
      'user_id': userId,
      'status': 'pending',
    };
  }

  /// An untouched optional field is NULL, never `''`.
  ///
  /// The admin panel renders these directly, and `''` shows as a present-but-
  /// empty value while NULL shows as absent. The portal gets this via
  /// `sanitizeNullable`.
  static String? _nullIfBlank(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
