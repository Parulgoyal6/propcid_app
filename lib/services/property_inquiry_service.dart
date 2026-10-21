// services/property_inquiry_service.dart
//
// Buyer-side enquiry creation on `property_inquiries`.
//
// There is no working portal INSERT path to pin this against: grep across
// `propcid/src` for `.from("property_inquiries").insert(` returns zero
// results. The table is owner/admin-read-only on the web today
// (`IncomingLeadsManager.tsx`, `BrokerLeadsManager.tsx` only ever `select`
// and `update` it). So the contract here is pinned to the schema itself
// (`20250724173621_...sql:33-45`) and to the DB triggers that already run on
// insert — this service does exactly one thing, insert a bare row, and lets
// the database do the rest:
//
//   * `increment_interest_on_inquiry` bumps `properties.interest_count`
//     (20250724173621:150-153);
//   * `trigger_notify_property_inquiry` notifies the property owner
//     (20251008174413:166-171);
//   * `trigger_auto_convert_inquiry` auto-converts + auto-assigns the row
//     into `network_leads` (20250920180727 / 20270329000000).
//
// None of those three are duplicated client-side.
//
// `UNIQUE(property_id, inquirer_id)` means a second enquiry on the same
// property from the same buyer fails with Postgres error 23505
// (`unique_violation`). That is surfaced as [DuplicateInquiryException]
// rather than a raw database message so the caller can show "you already
// enquired" instead of something unintelligible.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when the buyer has already enquired about this property —
/// `property_inquiries`'s `UNIQUE(property_id, inquirer_id)` constraint,
/// surfaced as Postgres error `23505`.
class DuplicateInquiryException implements Exception {
  const DuplicateInquiryException();

  @override
  String toString() => 'You have already sent an enquiry for this property.';
}

class PropertyInquiryService {
  PropertyInquiryService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String table = 'property_inquiries';

  /// Inserts one enquiry for the signed-in user. Throws [StateError] if
  /// nobody is signed in, [DuplicateInquiryException] on a repeat enquiry for
  /// the same property, and rethrows any other [PostgrestException]
  /// untouched.
  Future<void> submit({
    required String propertyId,
    required String message,
    String? contactPhone,
    String? contactEmail,
    String? preferredContactTime,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Sign in to send an enquiry.');
    }

    final payload = buildInsertPayload(
      inquirerId: userId,
      propertyId: propertyId,
      message: message,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      preferredContactTime: preferredContactTime,
    );

    try {
      await _supabase.from(table).insert(payload);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const DuplicateInquiryException();
      }
      rethrow;
    }
  }

  /// The exact row this service writes, split out so the shape and the
  /// blank-to-null rule can be asserted without a database — same pattern as
  /// `RequirementService.buildPayload`/`VisitBookingService.buildInsertPayload`.
  @visibleForTesting
  static Map<String, dynamic> buildInsertPayload({
    required String inquirerId,
    required String propertyId,
    required String message,
    String? contactPhone,
    String? contactEmail,
    String? preferredContactTime,
  }) {
    return {
      'property_id': propertyId,
      'inquirer_id': inquirerId,
      'message': _nullIfBlank(message),
      'contact_phone': _nullIfBlank(contactPhone),
      'contact_email': _nullIfBlank(contactEmail),
      'preferred_contact_time': _nullIfBlank(preferredContactTime),
      'status': 'pending',
    };
  }

  static String? _nullIfBlank(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
