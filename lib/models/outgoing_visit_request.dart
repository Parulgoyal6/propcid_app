// models/outgoing_visit_request.dart
//
// One row of "my outgoing visit requests" — requests the signed-in user
// personally made on another property/project/profile. Mirrors the portal's
// `VisitRequest` interface (`MyVisitRequests.tsx:121-158`) and is fed
// entirely from the `my-visit-requests` Edge Function's response shape
// (`backend/functions/my-visit-requests/index.ts`), which already merges all
// three source tables scoped to the caller's own JWT — this model does not
// re-derive "mine" from any locally-known id list.
//
// Deliberately a distinct class from `PropertyVisitBooking`
// (`broker_section_models.dart`), even though [source] == property overlaps
// that model's own `fromBuyerRow`: this one also covers project and profile
// visits, which `PropertyVisitBooking` has no fields for, and a single
// shared class every dashboard Visits tab can render without a source-typed
// branch is the whole point of this fix.
enum OutgoingVisitSource { property, project, profile }

/// The `source` value `my-visit-booking-manage` expects on the wire — same
/// three strings the portal sends (`MyVisitRequests.tsx:172-231`).
extension OutgoingVisitSourceWire on OutgoingVisitSource {
  String get wireValue => name;

  static OutgoingVisitSource? fromWire(String? value) => switch (value) {
    'property' => OutgoingVisitSource.property,
    'project' => OutgoingVisitSource.project,
    'profile' => OutgoingVisitSource.profile,
    _ => null,
  };
}

class OutgoingVisitRequest {
  const OutgoingVisitRequest({
    required this.id,
    required this.source,
    required this.targetId,
    required this.title,
    required this.preferredDate,
    this.imageUrl,
    this.location = '',
    this.preferredTime,
    this.status = 'pending',
    this.createdAt,
  });

  /// The booking's own row id (`property_visit_bookings`/
  /// `project_visit_bookings`/`profile_visit_requests`.`id`) — NOT globally
  /// unique on its own, since each table has its own id sequence. Use
  /// [identity] (source + id) wherever two records must never collide, e.g.
  /// a `ListView`'s `key` or a notification's highlight match.
  final String id;

  final OutgoingVisitSource source;

  /// `property_id` / `project_id` / `target_user_id` — what to open when the
  /// card is tapped.
  final String targetId;

  final String title;
  final String? imageUrl;

  /// Always empty for a profile request — the portal's own
  /// `MyVisitRequests.tsx:158` does the same (`location: ""`), since a
  /// profile has no location concept.
  final String location;

  final DateTime preferredDate;
  final String? preferredTime;

  /// `pending | confirmed | rescheduled | completed | cancelled` — no CHECK
  /// constraint on any of the three tables, so this is read as-is rather
  /// than parsed into an enum (same reasoning `PropertyVisitBooking.status`
  /// already documents).
  final String status;

  final DateTime? createdAt;

  /// Collision-safe identity across all three source tables — "Use source +
  /// booking ID for identity" per the fix's own requirement, since a
  /// `property_visit_bookings` row and a `project_visit_bookings` row can
  /// share the same uuid by pure coincidence.
  String get identity => '${source.name}_$id';

  /// Mirrors `MyVisitRequests.tsx:60-65`'s client-side changeability rule:
  /// only a still-pending/confirmed request for a slot that has not already
  /// passed can be cancelled/rescheduled. The server re-checks both
  /// independently (`my-visit-booking-manage/index.ts`) and is the actual
  /// authority — this is only used to decide whether to show the
  /// cancel/reschedule affordance at all.
  bool get isChangeable {
    if (status != 'pending' && status != 'confirmed') return false;
    return !_isPastSlot;
  }

  bool get _isPastSlot {
    final time = preferredTime;
    if (time == null || time.isEmpty) {
      final day = DateTime(
        preferredDate.year,
        preferredDate.month,
        preferredDate.day,
      );
      final today = DateTime.now();
      return day.isBefore(DateTime(today.year, today.month, today.day));
    }
    final parts = time.split(':');
    final hour = int.tryParse(parts.elementAt(0)) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final slot = DateTime(
      preferredDate.year,
      preferredDate.month,
      preferredDate.day,
      hour,
      minute,
    );
    return slot.isBefore(DateTime.now());
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static String? _nullIfEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// One `property_visit_bookings` row, joined with `properties(id, title,
  /// location, media_urls)` — the exact shape
  /// `my-visit-requests/index.ts:22-26` returns under `propertyVisits`.
  factory OutgoingVisitRequest.fromPropertyRow(Map<String, dynamic> json) {
    final property = json['properties'] as Map<String, dynamic>?;
    final mediaUrls = property?['media_urls'];
    final firstImage = (mediaUrls is List && mediaUrls.isNotEmpty)
        ? mediaUrls.first
        : null;
    return OutgoingVisitRequest(
      id: json['id']?.toString() ?? '',
      source: OutgoingVisitSource.property,
      targetId: json['property_id']?.toString() ?? '',
      title: property?['title']?.toString() ?? '',
      imageUrl: _nullIfEmpty(firstImage),
      location: property?['location']?.toString() ?? '',
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preferredTime: _nullIfEmpty(json['preferred_time']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }

  /// One `project_visit_bookings` row, joined with `builder_projects(id,
  /// title, location, logo_url, master_layout_url)` — the exact shape
  /// `my-visit-requests/index.ts:28-32` returns under `projectVisits`.
  factory OutgoingVisitRequest.fromProjectRow(Map<String, dynamic> json) {
    final project = json['builder_projects'] as Map<String, dynamic>?;
    final image =
        _nullIfEmpty(project?['logo_url']) ??
        _nullIfEmpty(project?['master_layout_url']);
    return OutgoingVisitRequest(
      id: json['id']?.toString() ?? '',
      source: OutgoingVisitSource.project,
      targetId: json['project_id']?.toString() ?? '',
      title: project?['title']?.toString() ?? '',
      imageUrl: image,
      location: project?['location']?.toString() ?? '',
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preferredTime: _nullIfEmpty(json['preferred_time']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }

  /// One `profile_visit_requests` row, with `target_display_name`/
  /// `target_avatar_url` already attached by the Edge Function
  /// (`my-visit-requests/index.ts:48-63`) — the exact shape returned under
  /// `profileVisitRequests`.
  factory OutgoingVisitRequest.fromProfileRow(Map<String, dynamic> json) {
    return OutgoingVisitRequest(
      id: json['id']?.toString() ?? '',
      source: OutgoingVisitSource.profile,
      targetId: json['target_user_id']?.toString() ?? '',
      title: json['target_display_name']?.toString() ?? 'User',
      imageUrl: _nullIfEmpty(json['target_avatar_url']),
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preferredTime: _nullIfEmpty(json['preferred_time']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }
}
