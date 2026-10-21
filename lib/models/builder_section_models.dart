// models/builder_section_models.dart
//
// Row models for the builder dashboard's four management sections.
//
// Grouped in one file rather than four because each is small, none is used
// outside its own section, and the four sections ship as one unit. `ProjectModel`
// is untouched and reused as-is for the project rows themselves — these only
// cover the tables it does not.

/// Per-project unit tallies from `project_inventory`.
///
/// The portal derives exactly these three by folding the rows client-side
/// (`BuilderInventoryManager.tsx:153-166`): every row increments `total`, and
/// `sold` / `available` are counted by status. Note what it does **not** count —
/// `booked` and `blocked` are in the CHECK constraint but land in neither bucket,
/// so `sold + available` can be less than `total`. Carried as-is.
class InventoryCounts {
  const InventoryCounts({this.total = 0, this.sold = 0, this.available = 0});

  final int total;
  final int sold;
  final int available;

  static const InventoryCounts empty = InventoryCounts();

  /// True when this project has no `project_inventory` rows at all — distinct
  /// from a project whose units are all booked.
  bool get isEmpty => total == 0;

  /// The rows the portal's two counters ignore.
  int get otherStatuses => total - sold - available;
}

/// One `project_inventory` row.
///
/// The builder dashboard never renders a unit individually —
/// `BuilderInventoryManager` only folds them into [InventoryCounts]. The
/// public project page does, though (`PublicProjectInventory.tsx`, ported by
/// `ProjectDetailScreen`'s "Available units" section), which is why
/// [floorPlanUrl] is read even though no builder-dashboard screen in this
/// app sets or shows it.
class InventoryUnit {
  const InventoryUnit({
    required this.id,
    required this.projectId,
    required this.unitType,
    required this.status,
    this.unitNumber,
    this.floorNumber,
    this.areaSqft = 0,
    this.price = 0,
    this.facingDirection,
    this.floorPlanUrl,
  });

  final String id;
  final String projectId;

  /// NOT NULL in the schema (`unit_type VARCHAR(100) NOT NULL`).
  final String unitType;
  final String status;
  final String? unitNumber;
  final int? floorNumber;

  /// Both NOT NULL and NUMERIC.
  final double areaSqft;
  final double price;

  /// `ProjectInventoryManager`'s and `InventoryTableEditor`'s
  /// `facing_direction` column — present in the schema since the first
  /// migration but never read by this model until now.
  final String? facingDirection;

  /// Per unit, shown publicly only while [status] is `'available'` —
  /// `PublicProjectInventory.tsx`'s own gate, carried as-is.
  final String? floorPlanUrl;

  static const String columns =
      'id, project_id, unit_type, unit_number, floor_number, area_sqft, '
      'price, status, facing_direction, floor_plan_url';

  factory InventoryUnit.fromSupabase(Map<String, dynamic> json) {
    return InventoryUnit(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      unitType: json['unit_type']?.toString() ?? '',
      status: json['status']?.toString() ?? 'available',
      unitNumber: _nullIfEmpty(json['unit_number']),
      floorNumber: _int(json['floor_number']),
      areaSqft: _double(json['area_sqft']),
      price: _double(json['price']),
      facingDirection: _nullIfEmpty(json['facing_direction']),
      floorPlanUrl: _nullIfEmpty(json['floor_plan_url']),
    );
  }
}

/// One `builder_project_offers` row, with the project and builder it embeds.
///
/// `FilteredOffersList.tsx:29-35` selects `*, project:builder_projects(*),
/// builder:profiles(*)`. Only the fields `ProjectOfferCard.tsx` actually renders
/// are read here.
class BuilderOffer {
  const BuilderOffer({
    required this.id,
    required this.title,
    this.builderId,
    this.projectId,
    this.description = '',
    this.mediaUrls = const [],
    this.videoUrl,
    this.status = 'active',
    this.createdAt,
    this.projectTitle,
    this.projectLocation,
    this.priceRangeMin,
    this.priceRangeMax,
  });

  final String id;

  /// `offer_title`, NOT NULL.
  final String title;

  /// Both are nullable FKs in the schema — `project_id` is
  /// `ON DELETE CASCADE`, so in practice it is present, but `builder_id` has no
  /// cascade and could outlive a profile.
  final String? builderId;
  final String? projectId;

  final String description;
  final List<String> mediaUrls;

  /// Added later by 20260415152226_add_offer_video_column.sql.
  final String? videoUrl;

  /// Bare TEXT DEFAULT 'active', no CHECK. `FilteredOffersList` filters
  /// `.eq('status','active')`, so nothing else is ever listed.
  final String status;

  final DateTime? createdAt;

  // ── From the embedded project ──────────────────────────────────────────
  final String? projectTitle;
  final String? projectLocation;
  final num? priceRangeMin;
  final num? priceRangeMax;

  /// The embedded select, spelled out.
  ///
  /// `profiles` is deliberately **not** embedded: the offer list only ever shows
  /// one builder's own offers here (`role === 'builder'` filters on
  /// `builder_id`), so the builder's own name adds nothing to their own screen.
  /// The portal embeds it because the same component also serves brokers.
  static const String columns =
      'id, project_id, builder_id, offer_title, offer_description, '
      'offer_media_urls, offer_video_url, status, created_at, '
      'project:builder_projects(title, location, price_range_min, '
      'price_range_max)';

  factory BuilderOffer.fromSupabase(Map<String, dynamic> json) {
    final project = json['project'];
    final projectMap = project is Map<String, dynamic> ? project : null;

    return BuilderOffer(
      id: json['id']?.toString() ?? '',
      title: json['offer_title']?.toString() ?? '',
      builderId: _nullIfEmpty(json['builder_id']),
      projectId: _nullIfEmpty(json['project_id']),
      description: json['offer_description']?.toString() ?? '',
      mediaUrls: _stringList(json['offer_media_urls']),
      videoUrl: _nullIfEmpty(json['offer_video_url']),
      status: json['status']?.toString() ?? 'active',
      createdAt: _date(json['created_at']),
      projectTitle: _nullIfEmpty(projectMap?['title']),
      projectLocation: _nullIfEmpty(projectMap?['location']),
      priceRangeMin: projectMap?['price_range_min'] as num?,
      priceRangeMax: projectMap?['price_range_max'] as num?,
    );
  }

  /// First media URL, or null. The portal falls back to a stock Unsplash photo
  /// (`ProjectOfferCard.tsx:42`); this returns null so the card can draw its own
  /// placeholder instead of loading a remote image the app does not own.
  String? get coverImage => mediaUrls.isEmpty ? null : mediaUrls.first;

  bool get hasPriceRange => priceRangeMin != null || priceRangeMax != null;
}

/// One `builder_team_members` row.
class BuilderTeamMember {
  const BuilderTeamMember({
    required this.id,
    this.builderId,
    required this.memberUserId,
    this.email,
    this.modules = const [],
    this.projectIds,
    this.status = 'active',
    this.createdAt,
  });

  final String id;

  /// Redundant when this came from `listMembers(builderId)` — the caller
  /// already knows it — but load-bearing for the invitee-side reads
  /// (`myActiveMemberships`), which, like `TeamMemberDashboard.tsx:56-64`,
  /// span every builder the member has joined and need it to tell those
  /// rows apart.
  final String? builderId;

  final String memberUserId;
  final String? email;

  /// Subset of `['inventory','offers','leads','site_visits']`, CHECK-enforced.
  final List<String> modules;

  /// **NULL means every project**, not "no projects" — 20270201000000:49
  /// documents it as `NULL => all of the builder's projects`. Modelled as a
  /// nullable list so that distinction survives; an empty list would lose it.
  final List<String>? projectIds;

  /// ('active','revoked').
  final String status;

  final DateTime? createdAt;

  static const String columns =
      'id, builder_id, member_user_id, email, modules, project_ids, status, '
      'created_at';

  factory BuilderTeamMember.fromSupabase(Map<String, dynamic> json) {
    return BuilderTeamMember(
      id: json['id']?.toString() ?? '',
      builderId: _nullIfEmpty(json['builder_id']),
      memberUserId: json['member_user_id']?.toString() ?? '',
      email: _nullIfEmpty(json['email']),
      modules: _stringList(json['modules']),
      projectIds: json['project_ids'] == null
          ? null
          : _stringList(json['project_ids']),
      status: json['status']?.toString() ?? 'active',
      createdAt: _date(json['created_at']),
    );
  }

  /// True when this member may act on every project the builder owns.
  bool get hasAllProjects => projectIds == null;
}

/// One `builder_team_invitations` row.
class BuilderTeamInvitation {
  const BuilderTeamInvitation({
    required this.id,
    this.builderId,
    this.email,
    this.phone,
    this.verificationMethod,
    this.modules = const [],
    this.projectIds,
    this.status = 'pending',
    this.token,
    this.expiresAt,
    this.createdAt,
  });

  final String id;

  /// Redundant from `listInvitations(builderId)`; load-bearing for
  /// `myPendingInvitations`, which — like `AcceptInvite.tsx:57-69` and
  /// `TeamInviteGate.tsx`'s email-based lookup — spans every builder that
  /// has invited this person, so the row must say which one.
  final String? builderId;

  /// Null for a phone-OTP invite (`invite-team-member`'s phone branch inserts
  /// `email: null`) — exactly one of [email]/[phone] is ever set, matching
  /// [verificationMethod].
  final String? email;

  /// Set only when [verificationMethod] is `'phone_otp'`.
  final String? phone;

  /// `null` (legacy/email rows) or `'phone_otp'` — the column
  /// `invite-team-member`'s phone branch writes (`index.ts:182`).
  final String? verificationMethod;

  final List<String> modules;
  final List<String>? projectIds;

  /// ('pending','accepted','revoked','expired').
  final String status;

  /// The invitation link's `?token=` value. `accept-team-invite` only checks
  /// it when the caller supplies one (`index.ts:58-60`); the builder's own
  /// list view never needed it before, so this is exclusively for the
  /// invitee-side accept call.
  final String? token;

  /// NOT NULL, defaults to `now() + 7 days`.
  final DateTime? expiresAt;

  final DateTime? createdAt;

  static const String columns =
      'id, builder_id, email, phone, verification_method, modules, '
      'project_ids, status, token, expires_at, created_at';

  factory BuilderTeamInvitation.fromSupabase(Map<String, dynamic> json) {
    return BuilderTeamInvitation(
      id: json['id']?.toString() ?? '',
      builderId: _nullIfEmpty(json['builder_id']),
      email: _nullIfEmpty(json['email']),
      phone: _nullIfEmpty(json['phone']),
      verificationMethod: _nullIfEmpty(json['verification_method']),
      modules: _stringList(json['modules']),
      token: _nullIfEmpty(json['token']),
      projectIds: json['project_ids'] == null
          ? null
          : _stringList(json['project_ids']),
      status: json['status']?.toString() ?? 'pending',
      expiresAt: _date(json['expires_at']),
      createdAt: _date(json['created_at']),
    );
  }

  /// True once [expiresAt] has passed, regardless of stored status.
  ///
  /// The column is only set to `'expired'` by whatever sweeps it; an invitation
  /// can therefore read `'pending'` while already being unusable. Computed so the
  /// list does not promise a link that will not work.
  bool get hasLapsed {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now());
  }

  bool get isPending => status == 'pending' && !hasLapsed;

  /// `team-invite-otp`/`accept-team-invite` both key off this exact string
  /// (`index.ts`'s `verification_method === 'phone_otp'` checks).
  bool get isPhoneInvite => verificationMethod == 'phone_otp';

  /// Whichever of [email]/[phone] this invitation actually carries, for
  /// display — exactly one is ever non-null.
  String get contactLabel => email ?? phone ?? 'this person';
}

/// One `builder_team_activity` row — a read-only audit log entry.
///
/// Populated entirely by the `log_team_activity()` DB trigger
/// (`20270202000000_builder_team_activity.sql`) on `builder_projects`/
/// `project_inventory`/`builder_project_offers`/`network_leads`/
/// `project_visit_bookings`, and ONLY when the actor is a delegated team
/// member, never the builder's own edits (the trigger no-ops when
/// `auth.uid() = builder_id`). Nothing in this app ever writes this table
/// directly — same as the portal, which only ever reads it.
class BuilderTeamActivity {
  const BuilderTeamActivity({
    required this.id,
    this.actorEmail,
    required this.action,
    required this.entityType,
    this.entityLabel,
    this.createdAt,
  });

  final String id;

  /// Null when the actor's `auth.users.email` could not be resolved at
  /// write time — `BuilderTeamManager.tsx`'s own fallback is "A team
  /// member", carried here as [actorLabel].
  final String? actorEmail;

  /// `insert` | `update` | `delete` (lowercased `TG_OP`).
  final String action;

  /// `project` | `inventory` | `offer` | `lead` | `booking` — shown as-is,
  /// not translated, matching `BuilderTeamManager.tsx`'s own render (it
  /// prints `a.entity_type` raw too).
  final String entityType;

  /// A human label for the specific row touched (project title, unit
  /// number, offer title, …) — null when the trigger had none to copy.
  final String? entityLabel;

  final DateTime? createdAt;

  static const String columns =
      'id, actor_email, action, entity_type, entity_label, created_at';

  factory BuilderTeamActivity.fromSupabase(Map<String, dynamic> json) {
    return BuilderTeamActivity(
      id: json['id']?.toString() ?? '',
      actorEmail: _nullIfEmpty(json['actor_email']),
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityLabel: _nullIfEmpty(json['entity_label']),
      createdAt: _date(json['created_at']),
    );
  }

  String get actorLabel => actorEmail ?? 'A team member';
}

/// One `project_visit_bookings` row.
class SiteVisitBooking {
  const SiteVisitBooking({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.visitorName,
    required this.visitorPhone,
    required this.preferredDate,
    this.preferredTime,
    this.message,
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final String projectId;

  /// The visitor. NOT NULL, cascades from `auth.users`.
  final String userId;

  /// All three NOT NULL.
  final String visitorName;
  final String visitorPhone;
  final DateTime preferredDate;

  final String? preferredTime;
  final String? message;

  /// Unconstrained TEXT NOT NULL DEFAULT 'pending'.
  final String status;

  final DateTime? createdAt;

  static const String columns =
      'id, project_id, user_id, visitor_name, visitor_phone, preferred_date, '
      'preferred_time, message, status, created_at';

  factory SiteVisitBooking.fromSupabase(Map<String, dynamic> json) {
    return SiteVisitBooking(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      visitorName: json['visitor_name']?.toString() ?? '',
      visitorPhone: json['visitor_phone']?.toString() ?? '',
      // `preferred_date` is a DATE and NOT NULL. The epoch fallback is
      // unreachable in practice and exists so the field can stay non-nullable —
      // every caller sorts and formats it.
      preferredDate:
          _date(json['preferred_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preferredTime: _nullIfEmpty(json['preferred_time']),
      message: _nullIfEmpty(json['message']),
      status: json['status']?.toString() ?? 'pending',
      createdAt: _date(json['created_at']),
    );
  }

  SiteVisitBooking copyWith({
    DateTime? preferredDate,
    String? preferredTime,
    String? status,
  }) {
    return SiteVisitBooking(
      id: id,
      projectId: projectId,
      userId: userId,
      visitorName: visitorName,
      visitorPhone: visitorPhone,
      preferredDate: preferredDate ?? this.preferredDate,
      preferredTime: preferredTime ?? this.preferredTime,
      message: message,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  /// True when the requested date is in the past.
  ///
  /// Compared day-to-day, not instant-to-instant: a booking for today is not
  /// overdue at 14:00 just because `preferred_date` parses to midnight.
  bool get isPast {
    final today = DateTime.now();
    final date = DateTime(
      preferredDate.year,
      preferredDate.month,
      preferredDate.day,
    );
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }
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

double _double(Object? value) => switch (value) {
  final double v => v,
  final num v => v.toDouble(),
  final String v => double.tryParse(v) ?? 0,
  _ => 0,
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
