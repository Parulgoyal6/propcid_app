// services/project_visit_booking_service.dart
//
// Submits a visitor's "Book Site Visit" request on a builder project —
// `project_visit_bookings`, the project-side counterpart to
// `property_visit_bookings` (`VisitBookingService`).
//
// Goes through the `book-visit` Edge Function rather than a direct table
// insert. `BookVisitModal.tsx` (shared by the portal's property AND project
// detail pages) was refactored onto this function — it is the current,
// authoritative contract, not the direct `.insert()` an older property-side
// investigation in this app assumed. The function does, server-side, what a
// direct insert cannot: confirms the project exists, requires an approved
// profile (`isProfileApproved`), and validates the date/time is a real,
// future slot within the next 365 days — then writes
// `{visitor_name, visitor_phone, preferred_date, preferred_time, message,
// status:'pending', user_id, project_id}` itself. The existing
// `notify_on_visit_booking` DB trigger still fires on the resulting INSERT
// exactly as it does for a property booking, notifying the project's
// builder with `visit_booking_new`.
//
// `preferredTime` MUST be 24-hour `HH:MM` — the function's own
// `TIME_RE = /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/` rejects a 12-hour
// "10:00 AM" string outright, unlike `property_visit_bookings`'s free-text
// column (inserted directly, no format ever enforced).
import 'package:supabase_flutter/supabase_flutter.dart';

class ProjectVisitBookingService {
  ProjectVisitBookingService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Throws the function's own validation message on failure (e.g. "Visit
  /// date and time cannot be in the past.", "A valid 10-digit phone number
  /// is required.", the not-yet-approved-profile message) so the caller can
  /// show it directly — same pattern `MyVisitRequestsService`/
  /// `PropertyService.getOwnershipDocumentUrls` already use for this
  /// function-error shape.
  Future<void> createBooking({
    required String projectId,
    required String visitorName,
    required String visitorPhone,
    required DateTime preferredDate,
    required String preferredTime,
    String? message,
  }) async {
    try {
      await _supabase.functions.invoke(
        'book-visit',
        body: {
          'projectId': projectId,
          'visitorName': visitorName,
          'visitorPhone': visitorPhone,
          'preferredDate': _dateOnly(preferredDate),
          'preferredTime': preferredTime,
          'message': message?.trim() ?? '',
        },
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final serverMessage = details is Map
          ? details['error']?.toString()
          : null;
      throw serverMessage ?? 'Could not submit your visit request.';
    }
  }

  /// `yyyy-MM-dd`, local/IST wall-clock — matches `BookVisitModal.tsx`'s own
  /// `format(date, 'yyyy-MM-dd')` (never UTC-shifted) and the exact shape
  /// the function's `DATE_RE` requires.
  static String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
