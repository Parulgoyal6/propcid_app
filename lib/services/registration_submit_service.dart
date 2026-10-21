import 'package:supabase_flutter/supabase_flutter.dart';

/// Structured failure from a `*-registration-submit` or
/// `profile-completion-submit` call. Preserves the server's own error
/// message, the specific offending `field` (if any), the full `issues` list
/// from a failed validation pass, and `missing` identifiers from a 403
/// `identity_not_verified` response — modelled on
/// `IdentityVerificationFailure`'s split from a bare-string failure, for the
/// same reason: the caller needs more than a flattened message, e.g. to
/// detect `identity_not_verified` specifically rather than show it as an
/// opaque generic error.
class RegistrationSubmitFailure implements Exception {
  const RegistrationSubmitFailure({
    required this.message,
    this.status,
    this.field,
    this.issues,
    this.missing,
  });

  /// The server's `error` string — already a human-readable sentence for
  /// every case except `identity_not_verified` itself.
  final String message;
  final int? status;

  /// The single offending field name, present on most validation failures
  /// (`validationFailure()`'s shape) and on a 409 username conflict.
  final String? field;

  /// Every failed field from a validation pass, when the server sent one —
  /// `[{field, message}, ...]`. `null` when the failure wasn't a validation
  /// failure (e.g. identity/auth/conflict/server errors).
  final List<Map<String, String>>? issues;

  /// Present only for a 403 `identity_not_verified` response — which of
  /// `email`/`phone` the server does not consider verified (or matching).
  final List<String>? missing;

  bool get isIdentityNotVerified => missing != null;

  @override
  String toString() => message;
}

/// Thin client for the four authenticated final-submit Edge Functions:
/// `builder-registration-submit`, `broker-registration-submit`,
/// `influencer-registration-submit` and `profile-completion-submit`
/// (`individualFinalize` mode). The caller is always identified from the
/// Supabase session JWT — none of these send a `user_id`. Passwords are
/// never part of any body here; they're applied separately via
/// `supabase.auth.updateUser` before these are called.
class RegistrationSubmitService {
  RegistrationSubmitService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> builderSubmit({
    required Map<String, dynamic> form,
    required String countryCode,
    required String alternateCountryCode,
    required bool termsAccepted,
    required bool privacyAccepted,
    String? basicInfoFullName,
  }) => _invoke('builder-registration-submit', {
    'form': form,
    'countryCode': countryCode,
    'alternateCountryCode': alternateCountryCode,
    'termsAccepted': termsAccepted,
    'privacyAccepted': privacyAccepted,
    if (basicInfoFullName != null && basicInfoFullName.isNotEmpty)
      'basicInfoFullName': basicInfoFullName,
  });

  Future<void> brokerSubmit({
    required Map<String, dynamic> form,
    required String countryCode,
    required String alternateCountryCode,
    required bool termsAccepted,
    required bool privacyAccepted,
  }) => _invoke('broker-registration-submit', {
    'form': form,
    'countryCode': countryCode,
    'alternateCountryCode': alternateCountryCode,
    'termsAccepted': termsAccepted,
    'privacyAccepted': privacyAccepted,
  });

  Future<void> influencerSubmit({
    required Map<String, dynamic> form,
    required String countryCode,
    required String alternateCountryCode,
    required bool termsAccepted,
    required bool privacyAccepted,
  }) => _invoke('influencer-registration-submit', {
    'form': form,
    'countryCode': countryCode,
    'alternateCountryCode': alternateCountryCode,
    'termsAccepted': termsAccepted,
    'privacyAccepted': privacyAccepted,
  });

  /// `profile-completion-submit`'s `individualFinalize` mode. The function
  /// derives the user id from the session, re-verifies both identifiers
  /// server-side, and compares [individualPhone] against the verified one —
  /// this never sends `userType` (that mode always finalizes as
  /// `individual`) and never a `lockInUserType`/`fallback` body.
  Future<void> individualFinalize({
    required String fullName,
    String? avatarUrl,
    required String individualPhone,
    required String individualCity,
    required String individualUsername,
  }) => _invoke('profile-completion-submit', {
    'mode': 'individualFinalize',
    'fullName': fullName,
    if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
    'individualPhone': individualPhone,
    'individualCity': individualCity,
    'individualUsername': individualUsername,
  });

  Future<void> _invoke(String function, Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map && data['success'] == true) return;
      // 2xx but not the documented {success:true} shape — never claim
      // success for a response we don't recognize.
      throw const RegistrationSubmitFailure(
        message: 'Something went wrong. Please try again.',
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final errorBody = details is Map ? details : const {};
      final issuesRaw = errorBody['issues'];
      final missingRaw = errorBody['missing'];
      throw RegistrationSubmitFailure(
        status: e.status,
        message:
            errorBody['error']?.toString() ??
            'Something went wrong. Please try again.',
        field: errorBody['field']?.toString(),
        issues: issuesRaw is List
            ? issuesRaw
                  .whereType<Map>()
                  .map(
                    (i) => {
                      'field': i['field']?.toString() ?? '',
                      'message': i['message']?.toString() ?? '',
                    },
                  )
                  .toList()
            : null,
        missing: missingRaw is List
            ? missingRaw.whereType<String>().toList()
            : null,
      );
    } on RegistrationSubmitFailure {
      rethrow;
    } catch (_) {
      throw const RegistrationSubmitFailure(
        message: 'A network error occurred. Please try again.',
      );
    }
  }
}
