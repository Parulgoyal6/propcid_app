// models/collaboration.dart
//
// The paid influencer Collaboration Marketplace — `collaborations`,
// `collab_payments`, `collab_assets`, `collab_invoices`.
//
// Every field here mirrors `useCollabState.ts`'s `Collaboration`/
// `CollabPayment`/`CollabAsset`/`CollabInvoice` interfaces and the
// `collab_status`/`collab_role`/`collab_asset_kind`/`collab_asset_status`/
// `collab_milestone` Postgres enums (20270421000000_collab_marketplace_enums.sql).
//
// Statuses and kinds are kept as raw strings, not Dart enums — same reasoning
// as `ChatMessage.messageType`: a Postgres enum can grow, and an unrecognised
// value must render as "unknown" rather than crash a whole screen.

/// The `collab_status` enum, in migration order. `advancePaid`/`finalPaid`
/// are declared server-side but never actually stored as `collaborations.status`
/// — `collab_transition`'s `advance_paid`/`final_paid` actions land the row on
/// `inProgress`/`deliverablePending` instead. Kept here anyway so an unknown
/// future value never reaches this table without being enumerable, and so
/// status-switch UI can render them safely if that ever changes.
class CollabStatuses {
  CollabStatuses._();

  static const String requested = 'requested';
  static const String declined = 'declined';
  static const String accepted = 'accepted';
  static const String agreementPending = 'agreement_pending';
  static const String advancePaid = 'advance_paid';
  static const String inProgress = 'in_progress';
  static const String finalPaid = 'final_paid';
  static const String deliverablePending = 'deliverable_pending';
  static const String delivered = 'delivered';
  static const String completed = 'completed';
  static const String disputed = 'disputed';
  static const String cancelled = 'cancelled';

  /// Statuses that no longer accept participant actions — the passive/frozen
  /// states Phase 4 calls out.
  static const Set<String> terminal = {completed, disputed, cancelled};
}

/// The two `collab_role` values. Never client-supplied — always derived
/// server-side from `profiles.user_type` (`collab_create_request`).
class CollabRoles {
  CollabRoles._();
  static const String influencer = 'influencer';
  static const String client = 'client';
}

class CollabAssetKinds {
  CollabAssetKinds._();
  static const String reference = 'reference';
  static const String sampleOnetime = 'sample_onetime';
  static const String deliverable = 'deliverable';
}

class CollabAssetStatuses {
  CollabAssetStatuses._();
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String viewed = 'viewed';
  static const String expired = 'expired';
  static const String purged = 'purged';
}

class CollabMilestones {
  CollabMilestones._();
  static const String advance = 'advance';
  static const String finalMilestone = 'final';
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};

DateTime? _asDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

List<String> _asStringList(Object? value) =>
    value is List ? value.map((e) => e.toString()).toList() : const <String>[];

/// A single `collaborations` row — the state-machine root. Never written to
/// directly; every mutation goes through `collab_create_request`/
/// `collab_transition`/`collab_asset_create` via [CollaborationService].
class Collaboration {
  final String id;

  /// `'influencer'` or `'client'` — which side sent the original request.
  final String initiatedBy;
  final String clientId;
  final String influencerId;

  /// Null until `collab_transition('accept')` creates the backing DM.
  final String? conversationId;

  /// Raw `collab_status` value — unknown-safe, see [CollabStatuses].
  final String status;
  final String currency;
  final int? agreedAmountMinor;
  final int? advanceAmountMinor;
  final int? finalAmountMinor;

  /// A storage path (`<id>/agreement.pdf`), not a URL — resolved to a signed
  /// URL on demand via `collab-agreement`.
  final String? agreementUrl;
  final String? requestMessage;
  final List<String> attachedReelIds;
  final DateTime? completedAt;
  final String? disputeReason;
  final DateTime? createdAt;

  /// The current negotiated-offer state — present only while `accepted` (an
  /// offer is on the table, awaiting the other participant). Null once
  /// accepted/countered/cancelled, since `accept_offer` clears these fields
  /// server-side. Raw `collab_role` value ('influencer'/'client'), same
  /// unknown-safe treatment as every other status/role string here.
  final int? pendingOfferAmountMinor;
  final String? pendingOfferBy;
  final bool pendingOfferIsFinal;

  const Collaboration({
    required this.id,
    required this.initiatedBy,
    required this.clientId,
    required this.influencerId,
    required this.status,
    this.conversationId,
    this.currency = 'INR',
    this.agreedAmountMinor,
    this.advanceAmountMinor,
    this.finalAmountMinor,
    this.agreementUrl,
    this.requestMessage,
    this.attachedReelIds = const [],
    this.completedAt,
    this.disputeReason,
    this.createdAt,
    this.pendingOfferAmountMinor,
    this.pendingOfferBy,
    this.pendingOfferIsFinal = false,
  });

  factory Collaboration.fromSupabase(Map<String, dynamic> json) {
    return Collaboration(
      id: json['id']?.toString() ?? '',
      initiatedBy: (json['initiated_by'] as String?) ?? CollabRoles.client,
      clientId: json['client_id']?.toString() ?? '',
      influencerId: json['influencer_id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString(),
      status: (json['status'] as String?) ?? CollabStatuses.requested,
      currency: (json['currency'] as String?) ?? 'INR',
      agreedAmountMinor: _asInt(json['agreed_amount_minor']),
      advanceAmountMinor: _asInt(json['advance_amount_minor']),
      finalAmountMinor: _asInt(json['final_amount_minor']),
      agreementUrl: json['agreement_url'] as String?,
      requestMessage: json['request_message'] as String?,
      attachedReelIds: _asStringList(json['attached_reel_ids']),
      completedAt: _asDate(json['completed_at']),
      disputeReason: json['dispute_reason'] as String?,
      createdAt: _asDate(json['created_at']),
      pendingOfferAmountMinor: _asInt(json['pending_offer_amount_minor']),
      pendingOfferBy: json['pending_offer_by'] as String?,
      pendingOfferIsFinal: json['pending_offer_is_final'] == true,
    );
  }

  /// An offer is on the table, awaiting a response, only while `accepted`
  /// (the RPC clears these fields on accept/cancel — a stray non-null value
  /// on any other status is not meaningful and must not drive UI).
  bool get hasPendingOffer =>
      status == CollabStatuses.accepted &&
      pendingOfferAmountMinor != null &&
      pendingOfferAmountMinor! > 0 &&
      pendingOfferBy != null;

  /// Whether [userId] is the one who proposed the current pending offer —
  /// they see a waiting state and cannot replace their own offer.
  bool proposedPendingOfferBy(String userId) {
    if (!hasPendingOffer) return false;
    return roleFor(userId) == pendingOfferBy;
  }

  /// `'influencer'` or `'client'` for [userId] — the role the state machine
  /// and the action panel key every permission check on.
  String? roleFor(String userId) {
    if (userId == influencerId) return CollabRoles.influencer;
    if (userId == clientId) return CollabRoles.client;
    return null;
  }

  bool involves(String userId) => userId == clientId || userId == influencerId;

  String? counterpartyIdFor(String userId) {
    if (userId == clientId) return influencerId;
    if (userId == influencerId) return clientId;
    return null;
  }

  bool get isRequested => status == CollabStatuses.requested;
  bool get isDeclined => status == CollabStatuses.declined;
  bool get isTerminal => CollabStatuses.terminal.contains(status);
  bool get isDisputed => status == CollabStatuses.disputed;
  bool get isCompleted => status == CollabStatuses.completed;
  bool get isCancelled => status == CollabStatuses.cancelled;

  /// Whether a chat thread exists for this collaboration yet — false only
  /// while still `requested`/`declined`.
  bool get hasConversation => conversationId != null;

  Collaboration copyWith({String? status, String? conversationId}) =>
      Collaboration(
        id: id,
        initiatedBy: initiatedBy,
        clientId: clientId,
        influencerId: influencerId,
        conversationId: conversationId ?? this.conversationId,
        status: status ?? this.status,
        currency: currency,
        agreedAmountMinor: agreedAmountMinor,
        advanceAmountMinor: advanceAmountMinor,
        finalAmountMinor: finalAmountMinor,
        agreementUrl: agreementUrl,
        requestMessage: requestMessage,
        attachedReelIds: attachedReelIds,
        completedAt: completedAt,
        disputeReason: disputeReason,
        createdAt: createdAt,
        pendingOfferAmountMinor: pendingOfferAmountMinor,
        pendingOfferBy: pendingOfferBy,
        pendingOfferIsFinal: pendingOfferIsFinal,
      );
}

class CollabPayment {
  final String id;

  /// `'advance'` or `'final'`.
  final String milestone;
  final int amountMinor;

  /// `'pending' | 'paid' | 'refunded'`.
  final String status;
  final DateTime? paidAt;

  const CollabPayment({
    required this.id,
    required this.milestone,
    required this.amountMinor,
    required this.status,
    this.paidAt,
  });

  factory CollabPayment.fromSupabase(Map<String, dynamic> json) =>
      CollabPayment(
        id: json['id']?.toString() ?? '',
        milestone: (json['milestone'] as String?) ?? '',
        amountMinor: _asInt(json['amount_minor']) ?? 0,
        status: (json['status'] as String?) ?? 'pending',
        paidAt: _asDate(json['paid_at']),
      );

  bool get isPaid => status == 'paid';
  bool get isAdvance => milestone == CollabMilestones.advance;
  bool get isFinal => milestone == CollabMilestones.finalMilestone;
}

class CollabAsset {
  final String id;

  /// `'reference' | 'sample_onetime' | 'deliverable'`.
  final String kind;

  /// `'pending' | 'approved' | 'rejected' | 'viewed' | 'expired' | 'purged'`.
  final String status;
  final String uploadedBy;
  final DateTime? viewedAt;
  final DateTime? downloadDeadline;
  final int downloadCount;
  final DateTime? createdAt;

  const CollabAsset({
    required this.id,
    required this.kind,
    required this.status,
    required this.uploadedBy,
    this.viewedAt,
    this.downloadDeadline,
    this.downloadCount = 0,
    this.createdAt,
  });

  factory CollabAsset.fromSupabase(Map<String, dynamic> json) => CollabAsset(
    id: json['id']?.toString() ?? '',
    kind: (json['kind'] as String?) ?? CollabAssetKinds.reference,
    status: (json['status'] as String?) ?? CollabAssetStatuses.pending,
    uploadedBy: json['uploaded_by']?.toString() ?? '',
    viewedAt: _asDate(json['viewed_at']),
    downloadDeadline: _asDate(json['download_deadline']),
    downloadCount: _asInt(json['download_count']) ?? 0,
    createdAt: _asDate(json['created_at']),
  );

  bool get isSample => kind == CollabAssetKinds.sampleOnetime;
  bool get isDeliverable => kind == CollabAssetKinds.deliverable;

  /// A sample already consumed (or server-flagged viewed) — never retry the
  /// same asset per Phase 5.
  bool get isConsumed =>
      status == CollabAssetStatuses.viewed || viewedAt != null;

  bool get isExpiredOrPurged =>
      status == CollabAssetStatuses.expired ||
      status == CollabAssetStatuses.purged;

  bool get deadlinePassed =>
      downloadDeadline != null && downloadDeadline!.isBefore(DateTime.now());

  /// Whether the 7-day deliverable window is still open.
  bool get isDownloadable =>
      isDeliverable && !isExpiredOrPurged && !deadlinePassed;
}

class CollabInvoice {
  final String id;

  /// `'advance' | 'final'`.
  final String milestone;

  /// `'admin' | 'client' | 'influencer'` — the caller only ever sees rows
  /// where `recipient_user_id = auth.uid()` (RLS), so this is always the
  /// caller's own role.
  final String recipientRole;
  final int total;
  final String currency;
  final String invoiceNumber;
  final DateTime? createdAt;

  const CollabInvoice({
    required this.id,
    required this.milestone,
    required this.recipientRole,
    required this.total,
    required this.currency,
    required this.invoiceNumber,
    this.createdAt,
  });

  factory CollabInvoice.fromSupabase(Map<String, dynamic> json) =>
      CollabInvoice(
        id: json['id']?.toString() ?? '',
        milestone: (json['milestone'] as String?) ?? '',
        recipientRole: (json['recipient_role'] as String?) ?? '',
        total: _asInt(json['total']) ?? 0,
        currency: (json['currency'] as String?) ?? 'INR',
        invoiceNumber: (json['invoice_number'] as String?) ?? '',
        createdAt: _asDate(json['created_at']),
      );
}

/// `UserProfile.tsx`'s `canCollaborate`: viewer authenticated, not looking at
/// themselves, and exactly one of {viewer, viewed profile} is an influencer
/// — a broker/builder/individual and an influencer, never two of the same
/// side. Extracted as a pure function (rather than left inline in the
/// screen) so it's unit-testable without pumping a widget tree.
bool isCollabEligible({
  required String? viewerId,
  required String viewedUserId,
  required bool viewedIsInfluencer,
  required bool viewerIsInfluencer,
}) {
  if (viewerId == null || viewerId == viewedUserId) return false;
  return viewedIsInfluencer != viewerIsInfluencer;
}

/// `COLLAB_STATUS_LABEL` in `Chat.tsx` — the short badge text for each
/// status, ported verbatim.
const Map<String, String> kCollabStatusLabels = {
  CollabStatuses.requested: 'Requested',
  CollabStatuses.declined: 'Declined',
  CollabStatuses.accepted: 'Accepted',
  CollabStatuses.agreementPending: 'Awaiting advance',
  CollabStatuses.advancePaid: 'In progress',
  CollabStatuses.inProgress: 'In progress',
  CollabStatuses.finalPaid: 'Awaiting deliverable',
  CollabStatuses.deliverablePending: 'Awaiting deliverable',
  CollabStatuses.delivered: 'Delivered',
  CollabStatuses.completed: 'Completed',
  CollabStatuses.disputed: 'Disputed',
  CollabStatuses.cancelled: 'Cancelled',
};

String collabStatusLabel(String status) =>
    kCollabStatusLabels[status] ?? 'Collaboration';

/// Renders a minor-unit amount (paise) as a whole-rupee display string with
/// thousands separators — `250000` -> `"₹2,500"`. INR-only, matching every
/// currency literal seen across the collab schema/edge functions.
String formatCollabAmount(int? minor, {String currency = 'INR'}) {
  if (minor == null) return '—';
  final whole = (minor / 100).round();
  final digits = whole.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    final grouped = fromEnd > 3 && (fromEnd - 3) % 2 == 1 && fromEnd > 1;
    if (i < digits.length - 1 && grouped) buffer.write(',');
  }
  final symbol = currency == 'INR' ? '₹' : '$currency ';
  return '${whole < 0 ? '-' : ''}$symbol$buffer';
}
