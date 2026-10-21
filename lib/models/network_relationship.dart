/// Classifies one `builder_networks` row from a viewer's perspective.
///
/// Why this file exists at all
/// ----------------------------
/// `builder_networks` was designed as `builder_id = network owner,
/// member_id = broker/influencer member`. The generic profile "Connect" flow
/// (`ProfileConnectionService.sendRequest`) writes to the *same* table with a
/// different convention: `builder_id = whoever's profile was viewed` (the
/// request recipient), `member_id = whoever clicked Connect` (the sender) —
/// regardless of either party's real role. RLS is symmetric
/// (`builder_id = auth.uid() OR member_id = auth.uid()`, verified against the
/// live migrations), so nothing server-side stops a builder from ending up as
/// `member_id` on a row, or a broker from ending up as `builder_id`.
///
/// Dashboard counts, Bulk Message eligibility and Channel auto-join all read
/// `builder_networks` with `.eq('builder_id', currentBuilderId)`. If that
/// pool is trusted at face value, a builder who happened to click "Connect"
/// on a broker's profile (landing them as `member_id`, not `builder_id`) gets
/// silently excluded from their own broadcast audience, while a random
/// individual or another builder who connected *to* them lands in
/// `builder_id = me` and would otherwise be silently included in it — a
/// content-audience-safety bug, not just a display quirk.
///
/// [classifyRelationship] is the single, reusable answer to "what is this
/// row, really, from this viewer's point of view" — used by every screen and
/// service in the Network module instead of each re-deriving its own
/// (previously contradictory) direction check.
library;

/// How one `builder_networks` row reads from the current viewer's side.
enum NetworkRelationshipKind {
  /// Accepted, `builder_id == viewer`, and the counterpart's *real* profile
  /// role (not the row's own possibly-stale `member_type`) is `broker` or
  /// `influencer`. The only pool Bulk Message, Channel auto-join, builder
  /// member management and the "Network Members" count may draw from.
  ownedNetworkMember,

  /// Accepted, `member_id == viewer`, and the counterpart's real profile role
  /// is `builder`. A network the viewer joined — not part of their own
  /// broadcast audience.
  joinedBuilderNetwork,

  /// Accepted, but not safely interpretable as either of the above (e.g. two
  /// builders connected to each other, or the counterpart is an individual/
  /// seller/dealer/agent). Stays visible under Connections; must never
  /// silently become bulk-message or auto-join eligible.
  peerConnection,

  /// Pending, and the viewer is the request recipient (`builder_id == viewer`
  /// — the sender is always `member_id`, see `ProfileConnectionService`).
  incomingPeerRequest,

  /// Pending, and the viewer is the request sender (`member_id == viewer`).
  outgoingPeerRequest,

  /// `status` is `rejected` or `removed` — must never render as active.
  rejectedOrRemoved,

  /// `status` is something else entirely, or the counterpart's profile could
  /// not be resolved at all. Never promoted to owned/joined — an unresolved
  /// profile must fail closed, not silently grant broadcast eligibility.
  unknownLegacyRelationship,
}

/// True for the two "this is an active membership, not just a pending
/// request or a rejected one" kinds.
bool isActiveMembershipKind(NetworkRelationshipKind kind) =>
    kind == NetworkRelationshipKind.ownedNetworkMember ||
    kind == NetworkRelationshipKind.joinedBuilderNetwork ||
    kind == NetworkRelationshipKind.peerConnection;

/// Classifies one `builder_networks` row.
///
/// [counterpartRealUserType] must come from an independent read of the
/// counterpart's own `profiles`/`profiles_public` row — never from
/// [memberType], which is whatever the writer of this specific row happened
/// to store (the sender's own `user_type` for a generic connect, a validated
/// `broker`/`influencer` for a formal invitation, or anything the broadened
/// `builder_networks_member_type_check` constraint now allows). Passing
/// `null` (profile unresolved) always yields [NetworkRelationshipKind.
/// unknownLegacyRelationship] for an otherwise-accepted row — this function
/// never guesses.
NetworkRelationshipKind classifyRelationship({
  required String viewerId,
  required String builderId,
  required String memberId,
  required String status,
  String? counterpartRealUserType,
}) {
  final normalizedStatus = status.toLowerCase();

  if (normalizedStatus == 'rejected' || normalizedStatus == 'removed') {
    return NetworkRelationshipKind.rejectedOrRemoved;
  }

  final viewerIsBuilderSide = builderId == viewerId;
  final viewerIsMemberSide = memberId == viewerId;

  if (normalizedStatus == 'pending') {
    if (viewerIsBuilderSide) return NetworkRelationshipKind.incomingPeerRequest;
    if (viewerIsMemberSide) return NetworkRelationshipKind.outgoingPeerRequest;
    return NetworkRelationshipKind.unknownLegacyRelationship;
  }

  if (normalizedStatus != 'accepted') {
    return NetworkRelationshipKind.unknownLegacyRelationship;
  }

  final counterpartType = counterpartRealUserType?.toLowerCase();
  if (counterpartType == null || counterpartType.isEmpty) {
    return NetworkRelationshipKind.unknownLegacyRelationship;
  }

  if (viewerIsBuilderSide) {
    return counterpartType == 'broker' || counterpartType == 'influencer'
        ? NetworkRelationshipKind.ownedNetworkMember
        : NetworkRelationshipKind.peerConnection;
  }

  if (viewerIsMemberSide) {
    return counterpartType == 'builder'
        ? NetworkRelationshipKind.joinedBuilderNetwork
        : NetworkRelationshipKind.peerConnection;
  }

  // Neither side is the viewer — should be unreachable given the caller only
  // ever fetches rows where the viewer is one side, but fails safe rather
  // than mis-classifying.
  return NetworkRelationshipKind.unknownLegacyRelationship;
}

/// One `builder_networks` row, hydrated with the counterpart's real profile
/// and classified from [viewerId]'s perspective.
class NetworkRelationship {
  const NetworkRelationship({
    required this.id,
    required this.builderId,
    required this.memberId,
    required this.memberType,
    required this.status,
    required this.viewerId,
    required this.kind,
    this.verified = false,
    this.commissionRate,
    this.autoConvertLeads = false,
    this.createdAt,
    this.counterpartUserId,
    this.counterpartDisplayName,
    this.counterpartAvatarUrl,
    this.counterpartCompanyName,
    this.counterpartUserType,
  });

  final String id;
  final String builderId;
  final String memberId;

  /// The row's own stored value — kept for display/back-compat, but never
  /// used to decide [kind] (see [classifyRelationship]'s doc).
  final String memberType;

  final String status;
  final String viewerId;
  final NetworkRelationshipKind kind;

  final bool verified;
  final double? commissionRate;
  final bool autoConvertLeads;
  final DateTime? createdAt;

  final String? counterpartUserId;
  final String? counterpartDisplayName;
  final String? counterpartAvatarUrl;
  final String? counterpartCompanyName;

  /// The counterpart's real, independently-resolved `profiles.user_type` —
  /// what [kind] was actually decided on.
  final String? counterpartUserType;

  bool get viewerIsBuilderSide => builderId == viewerId;
  bool get viewerIsMemberSide => memberId == viewerId;

  /// True when the viewer is the request recipient on a pending row — the
  /// sender is always `member_id` (`ProfileConnectionService.sendRequest`).
  bool get viewerIsRequestRecipient =>
      kind == NetworkRelationshipKind.incomingPeerRequest;

  bool get viewerIsRequestSender =>
      kind == NetworkRelationshipKind.outgoingPeerRequest;

  bool get isAccepted => status.toLowerCase() == 'accepted';

  /// The person's own name if resolved, else their company name, else an
  /// honest fallback — never a role-only placeholder like "Member of a
  /// builder network" when a real name exists. Display name comes first,
  /// matching the portal's own My Networks row (a person's name, with their
  /// company folded into the subtitle) — company-name-first is only correct
  /// for the notification-body wording `ProfileConnectionService` builds
  /// elsewhere, not for identifying a row in a list.
  String get counterpartDisplayLabel {
    final name = counterpartDisplayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final company = counterpartCompanyName?.trim();
    if (company != null && company.isNotEmpty) return company;
    return 'Unknown user';
  }

  /// The secondary line under the name — the counterpart's company, when
  /// they have one and it isn't already doing duty as [counterpartDisplayLabel]
  /// (an unresolved display name). Null when there is nothing worth a second
  /// line beyond the status pill.
  String? get counterpartSubtitle {
    final name = counterpartDisplayName?.trim();
    if (name == null || name.isEmpty) return null; // company already primary
    final company = counterpartCompanyName?.trim();
    return (company != null && company.isNotEmpty) ? company : null;
  }

  String get counterpartInitial => counterpartDisplayLabel.isEmpty
      ? '?'
      : counterpartDisplayLabel[0].toUpperCase();

  /// `broker` → `Broker`. Falls back to the row's own stored [memberType]
  /// when the real profile type could not be resolved, so a legacy/unknown
  /// row still shows *something* rather than a blank label.
  String get roleLabel {
    final type = (counterpartUserType?.trim().isNotEmpty ?? false)
        ? counterpartUserType!.trim()
        : memberType.trim();
    if (type.isEmpty) return 'Member';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  /// `2.5` → `2.5%`. Null when the row carries no rate.
  String? get commissionRateLabel {
    final rate = commissionRate;
    if (rate == null) return null;
    final trimmed = rate == rate.roundToDouble()
        ? rate.round().toString()
        : rate.toStringAsFixed(1);
    return '$trimmed%';
  }

  factory NetworkRelationship.classify(
    Map<String, dynamic> row, {
    required String viewerId,
    String? counterpartDisplayName,
    String? counterpartAvatarUrl,
    String? counterpartCompanyName,
    String? counterpartUserType,
  }) {
    final builderId = '${row['builder_id'] ?? ''}';
    final memberId = '${row['member_id'] ?? ''}';
    final status = '${row['status'] ?? 'pending'}';

    final kind = classifyRelationship(
      viewerId: viewerId,
      builderId: builderId,
      memberId: memberId,
      status: status,
      counterpartRealUserType: counterpartUserType,
    );

    final counterpartId = builderId == viewerId ? memberId : builderId;
    final rawRate = row['commission_rate'];

    return NetworkRelationship(
      id: '${row['id'] ?? ''}',
      builderId: builderId,
      memberId: memberId,
      memberType: '${row['member_type'] ?? ''}',
      status: status,
      viewerId: viewerId,
      kind: kind,
      verified: row['verified'] == true,
      commissionRate: rawRate == null ? null : double.tryParse('$rawRate'),
      autoConvertLeads: row['auto_convert_leads'] == true,
      createdAt: row['created_at'] == null
          ? null
          : DateTime.tryParse('${row['created_at']}'),
      counterpartUserId: counterpartId.isEmpty ? null : counterpartId,
      counterpartDisplayName: counterpartDisplayName,
      counterpartAvatarUrl: counterpartAvatarUrl,
      counterpartCompanyName: counterpartCompanyName,
      counterpartUserType: counterpartUserType,
    );
  }
}
