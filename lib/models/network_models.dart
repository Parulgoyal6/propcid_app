/// Read-only models for the Network leaf screens.
///
/// Column names come from the live `builder_networks`, `network_leads`,
/// `network_referrals`, `network_commissions`, `network_channels` and
/// `network_performance` tables, verified against `information_schema`.
///
/// Money note: unlike the billing and social-ads tables, every amount here is
/// `numeric` in **rupees**, not an integer in minor units. React sums
/// `network_commissions.amount` directly with no division, so these models do
/// the same. Getting this backwards would misstate every figure by 100×.
library;

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse('$value');

double _double(dynamic value) =>
    value == null ? 0 : (double.tryParse('$value') ?? 0);

double? _doubleOrNull(dynamic value) =>
    value == null ? null : double.tryParse('$value');

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

/// `24500` → `₹24,500` — Indian digit grouping, whole rupees.
String formatRupeeAmount(num amount) {
  final whole = amount.round().abs();
  final digits = whole.toString();

  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final lastThree = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final pairs = <String>[];
    while (rest.length > 2) {
      pairs.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) pairs.insert(0, rest);
    grouped = '${pairs.join(',')},$lastThree';
  }

  return '${amount < 0 ? '-' : ''}₹$grouped';
}

/// One `builder_networks` row — a connection between a builder and a member.
///
/// The caller may be either side, which is why React selects with
/// `.or(member_id.eq.X, builder_id.eq.X)`; [isBuilderSide] records which.
class NetworkMembership {
  final String id;
  final String builderId;
  final String memberId;
  final String memberType;
  final String status;
  final bool verified;
  final double? commissionRate;
  final bool autoConvertLeads;
  final DateTime? createdAt;

  /// True when the caller owns the network rather than belonging to it.
  final bool isBuilderSide;

  const NetworkMembership({
    required this.id,
    required this.builderId,
    required this.memberId,
    required this.memberType,
    required this.status,
    this.verified = false,
    this.commissionRate,
    this.autoConvertLeads = false,
    this.createdAt,
    this.isBuilderSide = false,
  });

  factory NetworkMembership.fromJson(
    Map<String, dynamic> json, {
    required String viewerId,
  }) {
    final builderId = '${json['builder_id'] ?? ''}';
    return NetworkMembership(
      id: '${json['id'] ?? ''}',
      builderId: builderId,
      memberId: '${json['member_id'] ?? ''}',
      memberType: '${json['member_type'] ?? ''}',
      // Nullable in the schema; React treats a null status as pending.
      status: '${json['status'] ?? 'pending'}',
      verified: json['verified'] == true,
      commissionRate: _doubleOrNull(json['commission_rate']),
      autoConvertLeads: json['auto_convert_leads'] == true,
      createdAt: _date(json['created_at']),
      isBuilderSide: builderId == viewerId,
    );
  }

  bool get isAccepted => status == 'accepted';

  /// "Broker" / "Influencer" — the stored value is a lowercase token.
  String get memberTypeLabel => memberType.isEmpty
      ? 'Member'
      : memberType[0].toUpperCase() + memberType.substring(1).toLowerCase();

  /// `2.5` → `2.5%`. Null when the connection carries no rate.
  String? get commissionRateLabel {
    final rate = commissionRate;
    if (rate == null) return null;
    final trimmed = rate == rate.roundToDouble()
        ? rate.round().toString()
        : rate.toStringAsFixed(1);
    return '$trimmed%';
  }
}

/// One `network_leads` row.
class NetworkLead {
  final String id;
  final String leadType;
  final String priority;
  final String status;
  final String assignmentMethod;
  final String? assignedMemberId;
  final bool autoAssigned;
  final String? notes;
  final DateTime? assignedAt;
  final DateTime? createdAt;

  /// Free-form `jsonb`. `NetworkService.listLeads`'s `.select()` already
  /// fetches it (a bare `select()` is `select("*")`) — only the model was
  /// never taught to keep it. Needed for [displayName]/[displayPhone], which
  /// `TeamLeadsView.tsx:102-103` reads the same way.
  final Map<String, dynamic>? metadata;

  const NetworkLead({
    required this.id,
    required this.leadType,
    required this.priority,
    required this.status,
    required this.assignmentMethod,
    this.assignedMemberId,
    this.autoAssigned = false,
    this.notes,
    this.assignedAt,
    this.createdAt,
    this.metadata,
  });

  factory NetworkLead.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    return NetworkLead(
      id: '${json['id'] ?? ''}',
      leadType: '${json['lead_type'] ?? ''}',
      priority: '${json['priority'] ?? ''}',
      status: '${json['status'] ?? ''}',
      assignmentMethod: '${json['assignment_method'] ?? ''}',
      assignedMemberId: json['assigned_member_id'] as String?,
      autoAssigned: json['auto_assigned'] == true,
      notes: json['notes'] as String?,
      assignedAt: _date(json['assigned_at']),
      createdAt: _date(json['created_at']),
      metadata: rawMetadata is Map
          ? Map<String, dynamic>.from(rawMetadata)
          : null,
    );
  }

  /// `TeamLeadsView.tsx:102`: `metadata?.name || metadata?.customer_name || "Lead"`.
  String get displayName {
    final name = metadata?['name'] ?? metadata?['customer_name'];
    final text = name?.toString().trim() ?? '';
    return text.isEmpty ? 'Lead' : text;
  }

  /// `TeamLeadsView.tsx:103`: `metadata?.phone || metadata?.contact`.
  String? get displayPhone {
    final phone = metadata?['phone'] ?? metadata?['contact'];
    final text = phone?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// The four status counts on the My Leads screen.
///
/// The design shows Pending / Assigned / Contacted / Converted, which are the
/// `network_leads.status` values React filters on.
class LeadStatusCounts {
  final int pending;
  final int assigned;
  final int contacted;
  final int converted;

  const LeadStatusCounts({
    this.pending = 0,
    this.assigned = 0,
    this.contacted = 0,
    this.converted = 0,
  });

  static const LeadStatusCounts empty = LeadStatusCounts();

  factory LeadStatusCounts.fromLeads(List<NetworkLead> leads) {
    int count(String status) => leads.where((l) => l.status == status).length;
    return LeadStatusCounts(
      pending: count('pending'),
      assigned: count('assigned'),
      contacted: count('contacted'),
      converted: count('converted'),
    );
  }

  int get total => pending + assigned + contacted + converted;
}

/// One `network_referrals` row.
class NetworkReferral {
  final String id;
  final String referralType;
  final String status;
  final String commissionStatus;
  final double? commissionAmount;
  final double? commissionRate;
  final double? conversionValue;
  final DateTime? conversionDate;
  final DateTime? createdAt;

  const NetworkReferral({
    required this.id,
    required this.referralType,
    required this.status,
    required this.commissionStatus,
    this.commissionAmount,
    this.commissionRate,
    this.conversionValue,
    this.conversionDate,
    this.createdAt,
  });

  factory NetworkReferral.fromJson(Map<String, dynamic> json) {
    return NetworkReferral(
      id: '${json['id'] ?? ''}',
      referralType: '${json['referral_type'] ?? ''}',
      status: '${json['status'] ?? ''}',
      commissionStatus: '${json['commission_status'] ?? ''}',
      commissionAmount: _doubleOrNull(json['commission_amount']),
      commissionRate: _doubleOrNull(json['commission_rate']),
      conversionValue: _doubleOrNull(json['conversion_value']),
      conversionDate: _date(json['conversion_date']),
      createdAt: _date(json['created_at']),
    );
  }

  bool get isConverted => status == 'converted';
}

/// One `network_commissions` row.
class NetworkCommission {
  final String id;
  final String commissionType;
  final double amount;
  final String status;
  final String? description;
  final DateTime? paymentDate;
  final DateTime? createdAt;

  const NetworkCommission({
    required this.id,
    required this.commissionType,
    required this.amount,
    required this.status,
    this.description,
    this.paymentDate,
    this.createdAt,
  });

  factory NetworkCommission.fromJson(Map<String, dynamic> json) {
    return NetworkCommission(
      id: '${json['id'] ?? ''}',
      commissionType: '${json['commission_type'] ?? ''}',
      amount: _double(json['amount']),
      status: '${json['status'] ?? ''}',
      description: json['description'] as String?,
      paymentDate: _date(json['payment_date']),
      createdAt: _date(json['created_at']),
    );
  }

  /// A commission counts as paid out once it has been marked paid.
  bool get isPaid => status == 'paid';

  String get amountDisplay => formatRupeeAmount(amount);
}

/// The four KPIs on the Referrals ▸ Overview sub-tab.
///
/// The design labels them Total Referrals / Converted / Total Commissions /
/// Paid Out — all derivable from the two lists, so nothing here is invented.
class ReferralSummary {
  final int totalReferrals;
  final int converted;
  final double totalCommissions;
  final double paidOut;

  const ReferralSummary({
    this.totalReferrals = 0,
    this.converted = 0,
    this.totalCommissions = 0,
    this.paidOut = 0,
  });

  static const ReferralSummary empty = ReferralSummary();

  factory ReferralSummary.from({
    required List<NetworkReferral> referrals,
    required List<NetworkCommission> commissions,
  }) {
    return ReferralSummary(
      totalReferrals: referrals.length,
      converted: referrals.where((r) => r.isConverted).length,
      totalCommissions: commissions.fold<double>(0, (sum, c) => sum + c.amount),
      paidOut: commissions
          .where((c) => c.isPaid)
          .fold<double>(0, (sum, c) => sum + c.amount),
    );
  }

  String get totalCommissionsDisplay => formatRupeeAmount(totalCommissions);
  String get paidOutDisplay => formatRupeeAmount(paidOut);
}

/// One `network_performance` row — a scored period per member.
class NetworkPerformance {
  final String id;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int leadsReceived;
  final int leadsConverted;
  final int referralsMade;
  final int referralsConverted;
  final double? conversionRate;
  final double? performanceScore;

  const NetworkPerformance({
    required this.id,
    this.periodStart,
    this.periodEnd,
    this.leadsReceived = 0,
    this.leadsConverted = 0,
    this.referralsMade = 0,
    this.referralsConverted = 0,
    this.conversionRate,
    this.performanceScore,
  });

  factory NetworkPerformance.fromJson(Map<String, dynamic> json) {
    return NetworkPerformance(
      id: '${json['id'] ?? ''}',
      periodStart: _date(json['period_start']),
      periodEnd: _date(json['period_end']),
      leadsReceived: _int(json['leads_received']),
      leadsConverted: _int(json['leads_converted']),
      referralsMade: _int(json['referrals_made']),
      referralsConverted: _int(json['referrals_converted']),
      conversionRate: _doubleOrNull(json['conversion_rate']),
      performanceScore: _doubleOrNull(json['performance_score']),
    );
  }
}

/// One `network_channels` row, optionally hydrated with its `channels` row and
/// the caller's own participation — see [NetworkCommunicationService.
/// loadCommunicationData]. [NetworkChannel.fromJson] only ever parses the flat
/// `network_channels` shape (no nested relation), so every hydrated field below
/// defaults safely and every existing call site/test keeps working unchanged.
class NetworkChannel {
  final String id;
  final String channelId;
  final String builderId;
  final String channelPurpose;
  final bool isAutoJoin;
  final List<String> memberTypes;
  final DateTime? createdAt;

  /// `channels.name` — null until hydrated.
  final String? name;

  /// `channels.description` — null until hydrated (or genuinely absent).
  final String? description;

  /// `channels.channel_type` — null until hydrated.
  final String? channelType;

  /// `channels.is_active` — null until hydrated (never defaulted to `true`,
  /// so "unknown" is never confused with "known active").
  final bool? isActive;

  /// `channels.created_by` — null until hydrated.
  final String? createdBy;

  /// `channels.max_participants` — null until hydrated.
  final int? maxParticipants;

  /// Count of `channel_participants` rows for this channel — 0 until
  /// hydrated, which is indistinguishable from "hydrated and empty"; callers
  /// needing that distinction should check [name] for hydration first.
  final int participantCount;

  /// The signed-in user's own `channel_participants.role` for this channel —
  /// null until hydrated, or if they are not a participant.
  final String? currentUserRole;

  /// Whether the signed-in user has a `channel_participants` row here.
  final bool isCurrentUserParticipant;

  const NetworkChannel({
    required this.id,
    required this.channelId,
    required this.channelPurpose,
    this.builderId = '',
    this.isAutoJoin = false,
    this.memberTypes = const [],
    this.createdAt,
    this.name,
    this.description,
    this.channelType,
    this.isActive,
    this.createdBy,
    this.maxParticipants,
    this.participantCount = 0,
    this.currentUserRole,
    this.isCurrentUserParticipant = false,
  });

  factory NetworkChannel.fromJson(Map<String, dynamic> json) {
    final types = json['member_types'];
    return NetworkChannel(
      id: '${json['id'] ?? ''}',
      channelId: '${json['channel_id'] ?? ''}',
      builderId: '${json['builder_id'] ?? ''}',
      channelPurpose: '${json['channel_purpose'] ?? ''}',
      isAutoJoin: json['is_auto_join'] == true,
      memberTypes: types is List ? types.map((e) => '$e').toList() : const [],
      createdAt: _date(json['created_at']),
    );
  }

  /// `lead_distribution` → `Lead distribution`.
  String get purposeLabel {
    if (channelPurpose.isEmpty) return 'Channel';
    final spaced = channelPurpose.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// True once `channels.admin` has been checked, and it is `admin`.
  bool get isCurrentUserAdmin => currentUserRole?.toLowerCase() == 'admin';

  /// Two-letter avatar fallback — the channel name when hydrated, otherwise
  /// its purpose. Mirrors [ChannelSummary.initials].
  String get initials {
    final base = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()
        : purposeLabel;
    final parts = base.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '#';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  /// The name shown on a channel card/thread header — the real channel name
  /// when hydrated, falling back to the humanised purpose so a card is never
  /// left blank while (or if) hydration hasn't happened.
  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : purposeLabel;

  NetworkChannel copyWith({
    String? name,
    String? description,
    String? channelType,
    bool? isActive,
    String? createdBy,
    int? maxParticipants,
    int? participantCount,
    String? currentUserRole,
    bool? isCurrentUserParticipant,
  }) {
    return NetworkChannel(
      id: id,
      channelId: channelId,
      builderId: builderId,
      channelPurpose: channelPurpose,
      isAutoJoin: isAutoJoin,
      memberTypes: memberTypes,
      createdAt: createdAt,
      name: name ?? this.name,
      description: description ?? this.description,
      channelType: channelType ?? this.channelType,
      isActive: isActive ?? this.isActive,
      createdBy: createdBy ?? this.createdBy,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      participantCount: participantCount ?? this.participantCount,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      isCurrentUserParticipant:
          isCurrentUserParticipant ?? this.isCurrentUserParticipant,
    );
  }
}

/// One accepted `builder_networks` row, with the member's public profile
/// resolved — the pool Create Channel's auto-join and Bulk Message draw from.
///
/// Only ever populated from rows the service already filtered to
/// `status = 'accepted'` — there is no `status` field here because an
/// unaccepted row must never reach this model in the first place.
class NetworkMember {
  final String id;
  final String memberId;
  final String memberType;
  final bool verified;
  final String? displayName;
  final String? avatarUrl;

  const NetworkMember({
    required this.id,
    required this.memberId,
    required this.memberType,
    this.verified = false,
    this.displayName,
    this.avatarUrl,
  });

  factory NetworkMember.fromSupabase(
    Map<String, dynamic> json, {
    String? displayName,
    String? avatarUrl,
  }) {
    return NetworkMember(
      id: '${json['id'] ?? ''}',
      memberId: '${json['member_id'] ?? ''}',
      memberType: '${json['member_type'] ?? ''}',
      verified: json['verified'] == true,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  String get resolvedName =>
      (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!.trim()
      : 'Unknown';

  String get initial =>
      resolvedName.isEmpty ? '?' : resolvedName[0].toUpperCase();
}

/// A channel's `channel_purpose` options, in the portal's own dropdown order
/// (`NetworkCommunicationHub.tsx`'s `SelectItem`s) — distinct from
/// [NetworkChannel.purposeLabel]'s generic humanisation, since the portal's
/// labels ("Lead Updates", not "Leads") are not derivable from the stored
/// token alone.
class ChannelPurposeOption {
  const ChannelPurposeOption(this.value, this.label);

  final String value;
  final String label;
}

const List<ChannelPurposeOption> kChannelPurposeOptions = [
  ChannelPurposeOption('general', 'General Discussion'),
  ChannelPurposeOption('leads', 'Lead Updates'),
  ChannelPurposeOption('announcements', 'Announcements'),
  ChannelPurposeOption('training', 'Training & Resources'),
  ChannelPurposeOption('performance', 'Performance Updates'),
];

/// Bulk Message's three pickers, each in the portal's own dropdown order.
class BulkMessageOption {
  const BulkMessageOption(this.value, this.label);

  final String value;
  final String label;
}

const List<BulkMessageOption> kBulkMessageRecipientTypes = [
  BulkMessageOption('all', 'All Members'),
  BulkMessageOption('brokers', 'Brokers Only'),
  BulkMessageOption('influencers', 'Influencers Only'),
  BulkMessageOption('verified_only', 'Verified Members Only'),
];

const List<BulkMessageOption> kBulkMessageTypes = [
  BulkMessageOption('announcement', 'Announcement'),
  BulkMessageOption('lead_alert', 'Lead Alert'),
  BulkMessageOption('training', 'Training Update'),
  BulkMessageOption('performance_update', 'Performance Update'),
];

const List<BulkMessageOption> kBulkMessagePriorities = [
  BulkMessageOption('low', 'Low'),
  BulkMessageOption('medium', 'Medium'),
  BulkMessageOption('high', 'High'),
  BulkMessageOption('urgent', 'Urgent'),
];

/// Bulk Message's recipient filter — a pure function so it is unit-testable
/// with no backend, and so the sheet's live recipient count and the actual
/// send use the exact same logic. Mirrors
/// `NetworkCommunicationHub.tsx`'s `recipient_type` switch: `all` keeps
/// everyone, the other three narrow by `member_type`/`verified`. [members] is
/// assumed already filtered to accepted rows for this builder (the only rows
/// the service ever produces) — this only applies the recipient-type filter,
/// de-dupes by [NetworkMember.memberId], and excludes [builderId] as a
/// last-resort safety net against a member row ever naming the builder.
List<NetworkMember> filterBulkMessageRecipients({
  required List<NetworkMember> members,
  required String recipientType,
  required String builderId,
}) {
  bool matchesType(NetworkMember member) {
    switch (recipientType) {
      case 'brokers':
        return member.memberType == 'broker';
      case 'influencers':
        return member.memberType == 'influencer';
      case 'verified_only':
        return member.verified;
      case 'all':
      default:
        return true;
    }
  }

  final seen = <String>{};
  final result = <NetworkMember>[];
  for (final member in members) {
    if (!matchesType(member)) continue;
    if (member.memberId.isEmpty || member.memberId == builderId) continue;
    if (!seen.add(member.memberId)) continue;
    result.add(member);
  }
  return result;
}

/// The Referrals bundle, so one section can feed all four sub-tabs.
class ReferralBundle {
  final List<NetworkReferral> referrals;
  final List<NetworkCommission> commissions;
  final List<NetworkPerformance> performance;

  const ReferralBundle({
    this.referrals = const [],
    this.commissions = const [],
    this.performance = const [],
  });

  static const ReferralBundle empty = ReferralBundle();

  ReferralSummary get summary =>
      ReferralSummary.from(referrals: referrals, commissions: commissions);
}

// ── Spec F: network invitations ───────────────────────────────────────────────
//
// `builder_network_invitations` (20250905144708_cc6b51bd…sql:45-57). Extended into
// this file rather than forked into a new one, per the contract: `network_models`
// already owns `NetworkMembership`, which is the accepted end of the same
// relationship.
//
// The column facts that shape everything below:
//
//   member_type  TEXT NOT NULL CHECK (member_type IN ('broker','influencer'))
//   status       TEXT DEFAULT 'pending'
//                CHECK (status IN ('pending','accepted','rejected','expired'))
//   expires_at   TIMESTAMPTZ DEFAULT (now() + INTERVAL '7 days')
//   invited_user_id  UUID  NULL   ← nullable, hence the two invite paths
//   email / phone    TEXT  NULL

/// The two member types a builder may invite.
///
/// The whole CHECK constraint, and the portal's TS union is identical:
/// `member_type: 'broker' | 'influencer'`
/// (BuilderNetworkInvitations.tsx:20). A builder does not invite other builders,
/// and `individual` — which `builder_networks.member_type` does carry — is not
/// accepted here.
class NetworkMemberTypeOption {
  const NetworkMemberTypeOption(this.value, this.label);

  final String value;
  final String label;
}

/// In the portal's picker order (BuilderNetworkInvitations.tsx:501-505).
const List<NetworkMemberTypeOption> kNetworkMemberTypes = [
  NetworkMemberTypeOption('broker', 'Broker'),
  NetworkMemberTypeOption('influencer', 'Influencer'),
];

/// Whether [value] is one the CHECK constraint accepts.
///
/// Guards the payload, not the picker: a value from outside this set is a `23514`,
/// so it is worth refusing before the round trip.
bool isValidNetworkMemberType(String? value) =>
    kNetworkMemberTypes.any((t) => t.value == value);

/// Label for a stored `member_type`.
///
/// Falls back for `individual` and anything else, because `builder_networks` rows
/// created by the peer-connect path do carry other values even though an
/// *invitation* cannot.
String networkMemberTypeLabel(String? value) {
  for (final type in kNetworkMemberTypes) {
    if (type.value == value) return type.label;
  }
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return 'Member';
  return '${raw[0].toUpperCase()}${raw.substring(1)}';
}

/// One `builder_network_invitations` row, with the counterpart resolved.
class NetworkInvitation {
  const NetworkInvitation({
    required this.id,
    required this.builderId,
    required this.memberType,
    this.invitedUserId,
    this.email,
    this.phone,
    this.message,
    this.status = 'pending',
    this.expiresAt,
    this.createdAt,
    this.counterpartName,
    this.counterpartAvatarUrl,
    this.counterpartUserType,
  });

  final String id;

  /// The inviting builder. NOT NULL.
  final String builderId;

  /// `broker` or `influencer`.
  final String memberType;

  /// Null when the builder invited by email or phone instead of picking a user.
  final String? invitedUserId;

  final String? email;
  final String? phone;

  /// `invitation_message`.
  final String? message;

  /// `pending` | `accepted` | `rejected` | `expired`.
  final String status;

  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// Resolved from `profiles` by the service — the row itself has no name.
  final String? counterpartName;
  final String? counterpartAvatarUrl;
  final String? counterpartUserType;

  static const String columns =
      'id, builder_id, invited_user_id, email, phone, member_type, '
      'invitation_message, status, expires_at, created_at';

  factory NetworkInvitation.fromSupabase(
    Map<String, dynamic> json, {
    String? counterpartName,
    String? counterpartAvatarUrl,
    String? counterpartUserType,
  }) {
    return NetworkInvitation(
      id: json['id']?.toString() ?? '',
      builderId: json['builder_id']?.toString() ?? '',
      memberType: json['member_type']?.toString() ?? '',
      invitedUserId: _nullIfBlank(json['invited_user_id']),
      email: _nullIfBlank(json['email']),
      phone: _nullIfBlank(json['phone']),
      message: _nullIfBlank(json['invitation_message']),
      status: json['status']?.toString() ?? 'pending',
      expiresAt: _parseDate(json['expires_at']),
      createdAt: _parseDate(json['created_at']),
      counterpartName: counterpartName,
      counterpartAvatarUrl: counterpartAvatarUrl,
      counterpartUserType: counterpartUserType,
    );
  }

  /// True once `expires_at` has passed.
  ///
  /// Computed, not read off `status`: nothing flips a row to `'expired'`
  /// synchronously, so an invitation can read `'pending'` while already being
  /// unusable. The contract requires an expired invite not be actionable, and this
  /// is what makes that possible.
  bool get hasLapsed {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return expiry.isBefore(DateTime.now());
  }

  /// Actionable only when pending **and** not lapsed.
  bool get isActionable => status == 'pending' && !hasLapsed;

  /// Who this went to, for display.
  ///
  /// Prefers the resolved profile name, then the email, then the phone — the order
  /// in which the builder is likely to recognise them. An invitation always has at
  /// least one of the three.
  String get recipientLabel =>
      counterpartName ?? email ?? phone ?? 'Unknown recipient';

  /// True when the builder invited someone who has no account yet.
  ///
  /// Those invitations cannot be accepted in-app — there is no `invited_user_id`
  /// for the recipient's session to match — so the UI marks them differently.
  bool get isOffPlatform => invitedUserId == null;

  static String? _nullIfBlank(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

/// The two lists the invitation UI shows, fetched together.
class NetworkInvitationInbox {
  const NetworkInvitationInbox({
    this.received = const [],
    this.sent = const [],
  });

  /// Invitations addressed to this user — `invited_user_id = me`.
  ///
  /// What `InfluencerCollaborationHub.tsx:109-112` lists, and the only ones with
  /// accept/reject actions.
  final List<NetworkInvitation> received;

  /// Invitations this user sent as a builder — `builder_id = me`.
  ///
  /// What `BuilderNetworkInvitations.tsx:145-148` lists.
  final List<NetworkInvitation> sent;

  static const NetworkInvitationInbox empty = NetworkInvitationInbox();

  bool get isEmpty => received.isEmpty && sent.isEmpty;

  /// Received invitations a user can still act on.
  List<NetworkInvitation> get actionable =>
      received.where((i) => i.isActionable).toList(growable: false);
}
