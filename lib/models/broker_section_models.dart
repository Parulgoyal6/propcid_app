// models/broker_section_models.dart
//
// Row models for the broker dashboard's Spec I sections: Leads, Visit Bookings and
// the Broker Profile.
//
// `PropertyModel` is reused as-is for the listings these hang off; only the tables
// it does not cover are modelled here.
import '../core/constants/broker_section_options.dart';

/// One `property_inquiries` row, presented as the CRM "lead" the portal shows.
///
/// `BrokerLeadsManager.tsx:109-135` builds exactly this shape. Two of its fields
/// are acknowledged holes in the table rather than data:
///
///   * `buyer_name` is the literal string `'Interested Buyer'` — the comment says
///     "Database doesn't have name field", and it does not;
///   * `budget` is `undefined` — likewise.
///
/// Both are reproduced honestly below: [buyerName] is a getter returning the same
/// placeholder, and there is no budget field at all rather than a null one that
/// implies a column exists.
class BrokerLead {
  const BrokerLead({
    required this.id,
    required this.propertyId,
    required this.status,
    this.propertyTitle,
    this.inquirerId,
    this.contactEmail,
    this.contactPhone,
    this.preferredContactTime,
    this.message,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// NOT NULL, `ON DELETE CASCADE` from `properties`.
  final String propertyId;

  /// The **app-side** status, already mapped off the `inquiry_status` enum.
  final String status;

  /// Resolved from the broker's own property list, not from a join.
  final String? propertyTitle;

  /// NOT NULL in the schema. The person who enquired.
  final String? inquirerId;

  final String? contactEmail;
  final String? contactPhone;
  final String? preferredContactTime;
  final String? message;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// `property_inquiries` carries no name column, so the portal hard-codes this.
  ///
  /// A getter rather than a stored field, so it cannot be mistaken for something
  /// that came out of the database.
  String get buyerName => placeholderBuyerName;

  static const String placeholderBuyerName = 'Interested Buyer';

  static const String columns =
      'id, property_id, inquirer_id, message, contact_phone, contact_email, '
      'preferred_contact_time, status, created_at, updated_at';

  factory BrokerLead.fromSupabase(
    Map<String, dynamic> json, {
    String? propertyTitle,
  }) {
    return BrokerLead(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      status: brokerLeadStatusFromDb(json['status']?.toString()),
      propertyTitle: propertyTitle,
      inquirerId: _nullIfEmpty(json['inquirer_id']),
      contactEmail: _nullIfEmpty(json['contact_email']),
      contactPhone: _nullIfEmpty(json['contact_phone']),
      preferredContactTime: _nullIfEmpty(json['preferred_contact_time']),
      message: _nullIfEmpty(json['message']),
      createdAt: _date(json['created_at']),
      updatedAt: _date(json['updated_at']),
    );
  }

  BrokerLead withStatus(String status) => BrokerLead(
    id: id,
    propertyId: propertyId,
    status: status,
    propertyTitle: propertyTitle,
    inquirerId: inquirerId,
    contactEmail: contactEmail,
    contactPhone: contactPhone,
    preferredContactTime: preferredContactTime,
    message: message,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  bool get isActive => kActiveBrokerLeadStatuses.contains(status);
}

/// The four counters `BrokerLeadsManager.tsx:139-160` derives from the list.
class BrokerLeadStats {
  const BrokerLeadStats({
    this.total = 0,
    this.newLeads = 0,
    this.active = 0,
    this.closed = 0,
    this.conversionRate = 0,
    this.closedValue = 0,
  });

  final int total;
  final int newLeads;
  final int active;
  final int closed;

  /// `closed / total * 100`.
  final double conversionRate;

  /// Σ `price` of the listings behind closed leads, using the portal's own lossy
  /// parse (`parseFloat(price.replace(/[^0-9.]/g,''))`, `:151-156`) — the same one
  /// Spec C carried for `totalValue`.
  final double closedValue;

  static const BrokerLeadStats empty = BrokerLeadStats();
}

/// One `property_visit_bookings` row.
///
/// A different table from `project_visit_bookings`, which Spec H covers: this one
/// hangs off `properties`, that one off `builder_projects`. Same column shape, and
/// one difference that matters — this table has a `handle_updated_at` trigger
/// (20260314133000:58), so its `updated_at` maintains itself.
class PropertyVisitBooking {
  const PropertyVisitBooking({
    required this.id,
    required this.propertyId,
    required this.userId,
    required this.visitorName,
    required this.visitorPhone,
    required this.preferredDate,
    this.propertyTitle,
    this.propertyImageUrl,
    this.propertyLocation,
    this.ownerName,
    this.ownerPhone,
    this.preferredTime,
    this.message,
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final String propertyId;

  /// The visitor.
  final String userId;

  final String visitorName;
  final String visitorPhone;
  final DateTime preferredDate;

  /// Resolved from the broker's own property list.
  final String? propertyTitle;

  /// Buyer-side ("My Visits") hydration only — resolved from the inline
  /// `properties(...)` join in [VisitBookingService.listMyBookings]/
  /// [PropertyVisitBooking.fromBuyerRow]. Null on rows built via
  /// [PropertyVisitBooking.fromSupabase] (the broker path), which already has
  /// the title from its own property list and has no use for the image/location.
  final String? propertyImageUrl;
  final String? propertyLocation;

  /// The property owner's name/phone, resolved the same PII-aware way
  /// `PropertyService.getPropertyDetail` already does for the detail screen
  /// (`profiles.phone` selected only for a signed-in caller) — buyer-side only,
  /// same reasoning as [propertyImageUrl].
  final String? ownerName;
  final String? ownerPhone;

  final String? preferredTime;
  final String? message;

  /// `TEXT NOT NULL DEFAULT 'pending'` with **no** CHECK, so the five values the
  /// picker offers are the portal's list rather than a database rule.
  final String status;

  final DateTime? createdAt;

  static const String columns =
      'id, property_id, user_id, visitor_name, visitor_phone, preferred_date, '
      'preferred_time, message, status, created_at';

  factory PropertyVisitBooking.fromSupabase(
    Map<String, dynamic> json, {
    String? propertyTitle,
  }) {
    return PropertyVisitBooking(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      visitorName: json['visitor_name']?.toString() ?? '',
      visitorPhone: json['visitor_phone']?.toString() ?? '',
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      propertyTitle: propertyTitle,
      preferredTime: _nullIfEmpty(json['preferred_time']),
      message: _nullIfEmpty(json['message']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }

  /// A buyer's own row, as returned by [VisitBookingService.listMyBookings] or
  /// [VisitBookingService.createBooking] — `MyVisitRequests.tsx:99-110`'s
  /// property-source mapping, plus [ownerName]/[ownerPhone] resolved separately
  /// (see their doc comments) since the portal itself does not show either on
  /// this screen.
  factory PropertyVisitBooking.fromBuyerRow(
    Map<String, dynamic> json, {
    String? ownerName,
    String? ownerPhone,
  }) {
    final property = json['properties'] as Map<String, dynamic>?;
    final mediaUrls = property?['media_urls'];
    final firstImage = (mediaUrls is List && mediaUrls.isNotEmpty)
        ? mediaUrls.first
        : null;

    return PropertyVisitBooking(
      id: json['id']?.toString() ?? '',
      propertyId: json['property_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      visitorName: json['visitor_name']?.toString() ?? '',
      visitorPhone: json['visitor_phone']?.toString() ?? '',
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      propertyTitle: _nullIfEmpty(property?['title']?.toString()),
      propertyImageUrl: _nullIfEmpty(firstImage?.toString()),
      propertyLocation: _nullIfEmpty(property?['location']?.toString()),
      ownerName: _nullIfEmpty(ownerName),
      ownerPhone: _nullIfEmpty(ownerPhone),
      preferredTime: _nullIfEmpty(json['preferred_time']),
      message: _nullIfEmpty(json['message']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }

  PropertyVisitBooking copyWith({
    DateTime? preferredDate,
    String? preferredTime,
    String? status,
  }) {
    return PropertyVisitBooking(
      id: id,
      propertyId: propertyId,
      userId: userId,
      visitorName: visitorName,
      visitorPhone: visitorPhone,
      preferredDate: preferredDate ?? this.preferredDate,
      propertyTitle: propertyTitle,
      propertyImageUrl: propertyImageUrl,
      propertyLocation: propertyLocation,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      preferredTime: preferredTime ?? this.preferredTime,
      message: message,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  /// Compared day-to-day, so a booking for today is not overdue at 14:00.
  bool get isPast {
    final now = DateTime.now();
    final date = DateTime(
      preferredDate.year,
      preferredDate.month,
      preferredDate.day,
    );
    return date.isBefore(DateTime(now.year, now.month, now.day));
  }
}

/// Where a [UnifiedLead] came from — the `LeadSource` union
/// `IncomingLeadsManager.tsx:37` carries, minus `project_visit`/`profile`:
/// nothing in this app creates `project_visit_bookings` or
/// `profile_visit_requests` yet, so unifying them here would be a UI for a
/// data source that can't exist.
enum UnifiedLeadSource { inquiry, visit }

/// A [BrokerLead] and a [PropertyVisitBooking], folded onto one CRM shape —
/// the mobile port of `IncomingLeadsManager.tsx`'s `Lead` interface (`:41-55`).
///
/// [status] is always one of [kBrokerLeadStatuses]' five values (or `lost`,
/// which that list omits — see `broker_section_options.dart`), regardless of
/// [source]. `visitLeadStatusFromDb`/`visitLeadStatusToDb` do the extra fold
/// a visit booking needs; an inquiry's status is already in this vocabulary
/// coming out of [BrokerLead].
class UnifiedLead {
  const UnifiedLead({
    required this.id,
    required this.source,
    required this.propertyId,
    required this.buyerName,
    required this.status,
    this.propertyTitle,
    this.buyerEmail,
    this.buyerPhone,
    this.message,
    this.preferredContactTime,
    this.preferredVisitDate,
    this.preferredVisitTime,
    this.requesterUserId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final UnifiedLeadSource source;
  final String propertyId;
  final String? propertyTitle;
  final String buyerName;
  final String? buyerEmail;
  final String? buyerPhone;
  final String? message;

  /// Unified CRM status — see the class doc comment.
  final String status;

  /// Inquiry-only: `property_inquiries.preferred_contact_time`, a free-text
  /// preference like "Evenings" — not a scheduled slot.
  final String? preferredContactTime;

  /// Visit-only: the actual requested date/time.
  final DateTime? preferredVisitDate;
  final String? preferredVisitTime;

  /// The requester's `auth.users.id` — visit-only, needed to notify them on a
  /// status change. Inquiries don't notify from this picker (the portal's
  /// `handleStatusChange` only calls `notifyVisitBookingUpdate` for the
  /// non-inquiry branch).
  final String? requesterUserId;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory UnifiedLead.fromInquiry(BrokerLead lead) => UnifiedLead(
    id: lead.id,
    source: UnifiedLeadSource.inquiry,
    propertyId: lead.propertyId,
    propertyTitle: lead.propertyTitle,
    buyerName: lead.buyerName,
    buyerEmail: lead.contactEmail,
    buyerPhone: lead.contactPhone,
    message: lead.message,
    status: lead.status,
    preferredContactTime: lead.preferredContactTime,
    requesterUserId: lead.inquirerId,
    createdAt: lead.createdAt,
    updatedAt: lead.updatedAt,
  );

  factory UnifiedLead.fromVisit(PropertyVisitBooking booking) => UnifiedLead(
    id: booking.id,
    source: UnifiedLeadSource.visit,
    propertyId: booking.propertyId,
    propertyTitle: booking.propertyTitle,
    buyerName: booking.visitorName,
    buyerPhone: booking.visitorPhone,
    message: booking.message,
    status: visitLeadStatusFromDb(booking.status),
    preferredVisitDate: booking.preferredDate,
    preferredVisitTime: booking.preferredTime,
    requesterUserId: booking.userId,
    createdAt: booking.createdAt,
  );

  UnifiedLead withStatus(String status) => UnifiedLead(
    id: id,
    source: source,
    propertyId: propertyId,
    propertyTitle: propertyTitle,
    buyerName: buyerName,
    buyerEmail: buyerEmail,
    buyerPhone: buyerPhone,
    message: message,
    status: status,
    preferredContactTime: preferredContactTime,
    preferredVisitDate: preferredVisitDate,
    preferredVisitTime: preferredVisitTime,
    requesterUserId: requesterUserId,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// Fills in whatever contact/detail fields this lead itself is missing
  /// from [other] — used to combine an inquiry and a visit-booking lead from
  /// the same person on the same property into one card. Keeps this lead's
  /// own [id]/[source]/[status]: an "Update" on the merged card still writes
  /// to exactly the same underlying row it always did, nothing new is
  /// invented for the other, now-hidden record.
  ///
  /// [buyerName] is the one exception to "this lead wins, [other] only fills
  /// gaps": `property_inquiries` has no name column, so every inquiry-sourced
  /// lead carries the same [BrokerLead.placeholderBuyerName] stand-in rather
  /// than a null. A visit booking's real visitor name is strictly better
  /// information, so it's preferred over that placeholder even when this
  /// lead is the one kept as primary.
  UnifiedLead mergedWithContactFrom(UnifiedLead other) => UnifiedLead(
    id: id,
    source: source,
    propertyId: propertyId,
    propertyTitle: propertyTitle ?? other.propertyTitle,
    buyerName: buyerName == BrokerLead.placeholderBuyerName &&
            other.buyerName != BrokerLead.placeholderBuyerName
        ? other.buyerName
        : buyerName,
    buyerEmail: buyerEmail ?? other.buyerEmail,
    buyerPhone: buyerPhone ?? other.buyerPhone,
    message: message ?? other.message,
    status: status,
    preferredContactTime: preferredContactTime ?? other.preferredContactTime,
    preferredVisitDate: preferredVisitDate ?? other.preferredVisitDate,
    preferredVisitTime: preferredVisitTime ?? other.preferredVisitTime,
    requesterUserId: requesterUserId,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// One `broker_profiles` row.
///
/// Only `full_name` is NOT NULL. `approval_status` is CHECK-constrained and set by
/// a reviewer, never by the broker — it is read here and never written, matching
/// `BrokerProfileManager.tsx`'s own payload (`:132-149`).
class BrokerProfile {
  const BrokerProfile({
    this.id,
    required this.fullName,
    this.reraNumber,
    this.licenseNumber,
    this.agencyName,
    this.yearsOfExperience = 0,
    this.companyDescription,
    this.officeAddress,
    this.city,
    this.state,
    this.pincode,
    this.mobileNumber,
    this.email,
    this.website,
    this.propertyTypes = const [],
    this.operatingCities = const [],
    this.approvalStatus = 'pending',
    this.rejectionReason,
  });

  /// Null before the row exists — which is what decides insert vs update.
  final String? id;

  final String fullName;
  final String? reraNumber;
  final String? licenseNumber;
  final String? agencyName;
  final int yearsOfExperience;
  final String? companyDescription;
  final String? officeAddress;
  final String? city;
  final String? state;
  final String? pincode;
  final String? mobileNumber;
  final String? email;
  final String? website;

  /// Read and written back untouched — the portal has no editor for either, and
  /// they are populated by the registration flow.
  final List<String> propertyTypes;
  final List<String> operatingCities;

  /// Read-only here.
  final String approvalStatus;
  final String? rejectionReason;

  static const String columns =
      'id, full_name, rera_number, license_number, agency_name, '
      'years_of_experience, company_description, office_address, city, state, '
      'pincode, mobile_number, email, website, property_types, '
      'operating_cities, approval_status, rejection_reason';

  factory BrokerProfile.fromSupabase(Map<String, dynamic> json) {
    return BrokerProfile(
      id: _nullIfEmpty(json['id']),
      fullName: json['full_name']?.toString() ?? '',
      reraNumber: _nullIfEmpty(json['rera_number']),
      licenseNumber: _nullIfEmpty(json['license_number']),
      agencyName: _nullIfEmpty(json['agency_name']),
      yearsOfExperience: _int(json['years_of_experience']) ?? 0,
      companyDescription: _nullIfEmpty(json['company_description']),
      officeAddress: _nullIfEmpty(json['office_address']),
      city: _nullIfEmpty(json['city']),
      state: _nullIfEmpty(json['state']),
      pincode: _nullIfEmpty(json['pincode']),
      mobileNumber: _nullIfEmpty(json['mobile_number']),
      email: _nullIfEmpty(json['email']),
      website: _nullIfEmpty(json['website']),
      propertyTypes: _stringList(json['property_types']),
      operatingCities: _stringList(json['operating_cities']),
      approvalStatus: json['approval_status']?.toString() ?? 'pending',
      rejectionReason: _nullIfEmpty(json['rejection_reason']),
    );
  }

  /// True once a reviewer has rejected it, so the reason is worth showing.
  bool get isRejected => approvalStatus == 'rejected';
}

// ── Shared coercion ─────────────────────────────────────────────────────────

String? _nullIfEmpty(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

int? _int(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((e) => e?.toString() ?? '')
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
