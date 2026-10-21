// services/property_verification_service.dart
//
// Inserts into `public.property_verification_requests`. Submission only — OTP
// send/verify/resend stays in the existing `EdgeFunctionsService`, which already
// wraps the same `send-otp` function the portal's modal calls. Nothing about OTP
// is duplicated here.
//
// COLUMN NAMES VERIFIED, NOT ASSUMED
// ----------------------------------
// The base table (20250822171804:2-23) has no `requester_name`. It was added by
// `20251214112234_888a3ae0…sql:3` and re-asserted by
// `20260326000002_fix_property_verification_schema.sql:19`, so the key below is
// correct against the deployed schema. Every other key in the payload appears in
// the base CREATE or in that same 20260326000002 `ADD COLUMN IF NOT EXISTS` list.
//
// INSERT is `WITH CHECK (true)` (20260326000002:38-41), so guests may submit;
// `user_id` rides along when there is a session.
//
// THE UPID BRANCH IS A DATA RULE, NOT A UI RULE
// --------------------------------------------
// `PropertyVerificationModal.tsx:275-289` nulls every address-path column when
// `useUpid` is true, and nulls `upid` when it is false. That is reproduced here
// rather than in the sheet, so the exclusivity holds no matter what the form
// happens to be holding — a user who fills the address fields, then switches to
// the UPID tab, cannot leak the abandoned half into the row.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyVerificationService {
  PropertyVerificationService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _table = 'property_verification_requests';

  /// Country default, matching the column default and the portal's form seed.
  static const String defaultCountry = 'India';

  /// Submits one verification request.
  ///
  /// [contactNumber] is stored as the user typed it, matching
  /// `PropertyVerificationModal.tsx:290` (`sanitizeText(formData.contact_number)`);
  /// the E.164 form exists only for the OTP calls.
  ///
  /// `status` is left to the column default (`'pending'`) — the portal's insert
  /// does not send it either, and the CHECK constraint on this table would reject
  /// anything else anyway.
  Future<void> submit({
    required String requesterName,
    required String contactNumber,
    required bool useUpid,
    String? upid,
    String? propertyAddress,
    String? sellerName,
    String? registeredInName,
    String? plotFlatNo,
    String? propertyType,
    String? colonyName,
    String? khasraNo,
    String? mauja,
    String? tehsil,
    String? district,
    String? state,
    String? country,
    String? inquiryDetails,
  }) async {
    try {
      await _supabase
          .from(_table)
          .insert(
            buildPayload(
              userId: _supabase.auth.currentUser?.id,
              requesterName: requesterName,
              contactNumber: contactNumber,
              useUpid: useUpid,
              upid: upid,
              propertyAddress: propertyAddress,
              sellerName: sellerName,
              registeredInName: registeredInName,
              plotFlatNo: plotFlatNo,
              propertyType: propertyType,
              colonyName: colonyName,
              khasraNo: khasraNo,
              mauja: mauja,
              tehsil: tehsil,
              district: district,
              state: state,
              country: country,
              inquiryDetails: inquiryDetails,
            ),
          );
    } catch (e) {
      debugPrint('PropertyVerificationService.submit failed: $e');
      rethrow;
    }
  }

  /// The exact row this service writes.
  ///
  /// Split out from [submit] so the UPID/address exclusivity — the one rule in
  /// this feature that silently corrupts data if it drifts — can be asserted
  /// without a database. Key names are the column names verified in the header
  /// comment; changing one here changes what is written.
  @visibleForTesting
  static Map<String, dynamic> buildPayload({
    String? userId,
    required String requesterName,
    required String contactNumber,
    required bool useUpid,
    String? upid,
    String? propertyAddress,
    String? sellerName,
    String? registeredInName,
    String? plotFlatNo,
    String? propertyType,
    String? colonyName,
    String? khasraNo,
    String? mauja,
    String? tehsil,
    String? district,
    String? state,
    String? country,
    String? inquiryDetails,
  }) {
    // Only meaningful on the address path; collapses to null on the UPID path.
    String? addressField(String? value) => useUpid ? null : _nullIfBlank(value);

    return {
      'user_id': userId,
      'requester_name': requesterName.trim(),
      'contact_number': contactNumber.trim(),
      'upid': useUpid ? _nullIfBlank(upid) : null,
      'property_address': addressField(propertyAddress),
      'seller_name': addressField(sellerName),
      'registered_in_name': addressField(registeredInName),
      'plot_flat_no': addressField(plotFlatNo),
      'property_type': addressField(propertyType),
      'colony_name': addressField(colonyName),
      'khasra_no': addressField(khasraNo),
      'mauja': addressField(mauja),
      'tehsil': addressField(tehsil),
      'district': addressField(district),
      'state': addressField(state),
      // Falls back to the column default rather than writing null, so an
      // address-path row always records a country.
      'country': useUpid ? null : (_nullIfBlank(country) ?? defaultCountry),
      'inquiry_details': _nullIfBlank(inquiryDetails),
    };
  }

  static String? _nullIfBlank(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
