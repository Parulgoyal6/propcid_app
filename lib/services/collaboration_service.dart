// services/collaboration_service.dart
//
// The paid influencer Collaboration Marketplace — the ONLY place in this app
// that talks to `collaborations`/`collab_payments`/`collab_assets`/
// `collab_invoices`, their RPCs (`collab_create_request`, `collab_transition`,
// `collab_asset_create`) and their Edge Functions (`collab-create-order`,
// `collab-agreement`, `collab-sample-view`, `collab-deliverable-url`,
// `collab-dispute`, `download-collab-invoice`).
//
// NEVER WRITES COLLAB TABLE STATE DIRECTLY
// -----------------------------------------
// None of `collaborations`/`collab_payments`/`collab_assets`/`collab_invoices`
// has an INSERT/UPDATE RLS policy for `authenticated` — every mutation is a
// SECURITY DEFINER RPC or Edge Function, exactly mirroring
// `features/messaging/lib/useCollabState.ts`. This file only ever calls those;
// it never trusts the client for authorization, amounts, payment completion,
// one-time viewing, retention, or status transitions — the server (or, for
// `advance_paid`/`final_paid`/`complete`, the service-role payment webhook) is
// the sole authority on every one of those, and this service just reflects
// what it returns.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../models/collaboration.dart';
import '../models/conversation_summary.dart';
import 'collab_functions_client.dart';
import 'collaboration_exceptions.dart';

/// A reel (`influencer_videos` row) as it appears in the collaboration
/// request sheet's attach picker and in a request's attached-reel previews.
class CollabReelPreview {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? videoUrl;

  const CollabReelPreview({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.videoUrl,
  });

  factory CollabReelPreview.fromSupabase(Map<String, dynamic> json) =>
      CollabReelPreview(
        id: json['id']?.toString() ?? '',
        title: (json['title'] as String?)?.trim().isNotEmpty == true
            ? json['title'] as String
            : 'Untitled reel',
        thumbnailUrl: json['thumbnail_url'] as String?,
        videoUrl: json['video_url'] as String?,
      );
}

/// Where a `collab_*` notification should open — see
/// [CollaborationService.resolveNotificationDestination].
enum CollabNotificationTarget {
  /// The collaboration has no conversation yet (still `requested`) or could
  /// not be resolved — open the Collabs tab rather than guessing a thread.
  collabsInbox,

  /// The collaboration is `accepted` or later — open its conversation.
  conversation,
}

class CollabNotificationDestination {
  final CollabNotificationTarget target;
  final String? conversationId;
  final String? counterpartyId;
  final String? counterpartyName;
  final String? counterpartyAvatarUrl;

  const CollabNotificationDestination._(
    this.target, {
    this.conversationId,
    this.counterpartyId,
    this.counterpartyName,
    this.counterpartyAvatarUrl,
  });

  const CollabNotificationDestination.inbox()
    : this._(CollabNotificationTarget.collabsInbox);

  const CollabNotificationDestination.conversation({
    required String conversationId,
    required String counterpartyId,
    required String counterpartyName,
    String? counterpartyAvatarUrl,
  }) : this._(
         CollabNotificationTarget.conversation,
         conversationId: conversationId,
         counterpartyId: counterpartyId,
         counterpartyName: counterpartyName,
         counterpartyAvatarUrl: counterpartyAvatarUrl,
       );
}

class CollaborationService {
  CollaborationService({
    SupabaseClient? client,
    CollabFunctionsClient? functionsClient,
  }) : _supabase = client ?? Supabase.instance.client,
       _functions = functionsClient ?? CollabFunctionsClient(client: client);

  final SupabaseClient _supabase;
  final CollabFunctionsClient _functions;
  static const _uuid = Uuid();

  // Phase 5 constants — portal parity (CollabActionPanel.tsx: SAMPLE_MIN/MAX
  // _SECONDS = 9/16, "spec: 10-15s, with a small tolerance for encoder
  // rounding"; bucket file_size_limit columns for collab-onetime/
  // collab-deliverables).
  static const int maxSampleBytes = 60 * 1024 * 1024;
  static const int maxDeliverableBytes = 300 * 1024 * 1024;
  static const Duration sampleMinDuration = Duration(seconds: 9);
  static const Duration sampleMaxDuration = Duration(seconds: 16);

  /// `collab-dispute`'s own server-side cap (`reason.trim().slice(0, 1000)`).
  static const int maxDisputeReasonLength = 1000;

  static const String _sampleBucket = 'collab-onetime';
  static const String _deliverableBucket = 'collab-deliverables';

  String? get currentUserIdOrNull => _supabase.auth.currentUser?.id;

  // ── Reads ──────────────────────────────────────────────────────────────

  Future<Collaboration?> fetchCollaboration(String id) async {
    try {
      final row = await _supabase
          .from('collaborations')
          .select()
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : Collaboration.fromSupabase(row);
    } catch (e) {
      debugPrint('CollaborationService.fetchCollaboration failed: $e');
      rethrow;
    }
  }

  Future<List<CollabPayment>> fetchPayments(String collaborationId) async {
    try {
      final rows = await _supabase
          .from('collab_payments')
          .select('id, milestone, amount_minor, status, paid_at')
          .eq('collaboration_id', collaborationId);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(CollabPayment.fromSupabase).toList();
    } catch (e) {
      debugPrint('CollaborationService.fetchPayments failed: $e');
      rethrow;
    }
  }

  /// Newest first — matches `useCollabState.ts`'s `collab_assets` select.
  Future<List<CollabAsset>> fetchAssets(String collaborationId) async {
    try {
      final rows = await _supabase
          .from('collab_assets')
          .select(
            'id, kind, status, uploaded_by, viewed_at, download_deadline, '
            'download_count, created_at',
          )
          .eq('collaboration_id', collaborationId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(CollabAsset.fromSupabase).toList();
    } catch (e) {
      debugPrint('CollaborationService.fetchAssets failed: $e');
      rethrow;
    }
  }

  /// Only the caller's own recipient-role row is visible (RLS scopes
  /// `collab_invoices` to `recipient_user_id = auth.uid()` or admin).
  Future<List<CollabInvoice>> fetchInvoices(String collaborationId) async {
    try {
      final rows = await _supabase
          .from('collab_invoices')
          .select(
            'id, milestone, recipient_role, total, currency, '
            'invoice_number, created_at',
          )
          .eq('collaboration_id', collaborationId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(CollabInvoice.fromSupabase).toList();
    } catch (e) {
      debugPrint('CollaborationService.fetchInvoices failed: $e');
      rethrow;
    }
  }

  /// Every collaboration [userId] is a party to, newest first — the data
  /// behind the Collabs tab. Mirrors `Chat.tsx`'s pending-requests query plus
  /// the accepted+ ones already surfaced via `conversations.collaboration_id`.
  Future<List<Collaboration>> listMyCollaborations(String userId) async {
    try {
      final rows = await _supabase
          .from('collaborations')
          .select()
          .or('client_id.eq.$userId,influencer_id.eq.$userId')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(Collaboration.fromSupabase).toList();
    } catch (e) {
      debugPrint('CollaborationService.listMyCollaborations failed: $e');
      rethrow;
    }
  }

  Future<Map<String, ConversationParticipant>> resolveProfiles(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('profiles_public')
          .select('user_id, display_name, avatar_url, is_online, last_seen_at')
          .inFilter('user_id', userIds.toList());

      final result = <String, ConversationParticipant>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final id = row['user_id']?.toString();
        if (id == null) continue;
        final lastSeenRaw = row['last_seen_at'] as String?;
        result[id] = ConversationParticipant(
          userId: id,
          displayName: (row['display_name'] as String?) ?? 'Unknown',
          avatarUrl: row['avatar_url'] as String?,
          isOnline: (row['is_online'] as bool?) ?? false,
          lastSeenAt: lastSeenRaw == null
              ? null
              : DateTime.tryParse(lastSeenRaw),
        );
      }
      return result;
    } catch (e) {
      debugPrint('CollaborationService.resolveProfiles failed: $e');
      return const {};
    }
  }

  /// The signed-in influencer's own active reels — the attach picker in the
  /// request sheet. Mirrors `UserProfile.tsx`'s `myReels` query: both
  /// `status = 'active'` AND `approval_status = 'approved'` — a
  /// pending/rejected reel must never be offered for attachment.
  Future<List<CollabReelPreview>> listMyActiveReels(String userId) async {
    try {
      final rows = await _supabase
          .from('influencer_videos')
          .select('id, title, thumbnail_url, video_url')
          .eq('user_id', userId)
          .eq('status', 'active')
          .eq('approval_status', 'approved')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(
        rows as List,
      ).map(CollabReelPreview.fromSupabase).toList();
    } catch (e) {
      debugPrint('CollaborationService.listMyActiveReels failed: $e');
      return const [];
    }
  }

  /// An existing `requested` collaboration between the signed-in user and
  /// [counterpartyId], if any — `UserProfile.tsx`'s duplicate-request guard.
  /// Drives the "Collab Requested" CTA state instead of letting a second
  /// request be sent for the same pair.
  Future<Collaboration?> findExistingRequest({
    required String viewerId,
    required String counterpartyId,
  }) async {
    try {
      final rows = await _supabase
          .from('collaborations')
          .select()
          .or(
            'and(client_id.eq.$viewerId,influencer_id.eq.$counterpartyId),'
            'and(client_id.eq.$counterpartyId,influencer_id.eq.$viewerId)',
          )
          .eq('status', CollabStatuses.requested)
          .order('created_at', ascending: false)
          .limit(1);
      final list = List<Map<String, dynamic>>.from(rows as List);
      if (list.isEmpty) return null;
      return Collaboration.fromSupabase(list.first);
    } catch (e) {
      debugPrint('CollaborationService.findExistingRequest failed: $e');
      return null;
    }
  }

  Future<Map<String, CollabReelPreview>> resolveReels(
    Set<String> reelIds,
  ) async {
    if (reelIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('influencer_videos')
          .select('id, title, thumbnail_url, video_url')
          .inFilter('id', reelIds.toList());
      final result = <String, CollabReelPreview>{};
      for (final row in List<Map<String, dynamic>>.from(rows as List)) {
        final preview = CollabReelPreview.fromSupabase(row);
        if (preview.id.isNotEmpty) result[preview.id] = preview;
      }
      return result;
    } catch (e) {
      debugPrint('CollaborationService.resolveReels failed: $e');
      return const {};
    }
  }

  // ── RPCs — collab_create_request / collab_transition / collab_asset_create ─

  /// `UserProfile.tsx`'s `handleSendCollabRequest`. Deliberately does **not**
  /// create (or reuse) a normal DM — a request has no `conversations` row
  /// until the recipient calls [accept].
  Future<Collaboration> createRequest({
    required String counterpartyId,
    String? message,
    List<String> attachedReelIds = const [],
  }) async {
    try {
      final row = await _supabase.rpc(
        'collab_create_request',
        params: {
          'p_counterparty_id': counterpartyId,
          'p_message': (message?.trim().isEmpty ?? true)
              ? null
              : message!.trim(),
          'p_attached_reel_ids': attachedReelIds,
        },
      );
      return Collaboration.fromSupabase(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      debugPrint('CollaborationService.createRequest failed: $e');
      throw CollaborationException(_messageFor(e));
    }
  }

  Future<Collaboration> _transition(
    String collaborationId,
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      final row = await _supabase.rpc(
        'collab_transition',
        params: {
          'p_collab_id': collaborationId,
          'p_action': action,
          'p_payload': payload,
        },
      );
      return Collaboration.fromSupabase(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      debugPrint('CollaborationService.transition($action) failed: $e');
      throw CollaborationException(_messageFor(e));
    }
  }

  /// Recipient-only server-side. Returns the row with its new
  /// `conversation_id` set — the caller opens that thread directly rather
  /// than re-fetching the list.
  Future<Collaboration> accept(String collaborationId) =>
      _transition(collaborationId, 'accept');

  Future<Collaboration> decline(String collaborationId) =>
      _transition(collaborationId, 'decline');

  /// Either participant proposes a positive total amount while `accepted` —
  /// the current negotiated-offer workflow (`collab_transition`'s
  /// `propose_offer` action). [isFinal] marks this as a take-it-or-leave-it
  /// offer: the recipient can then only Accept it or Cancel the
  /// collaboration, never counter it — enforced server-side, not just in
  /// the UI.
  Future<Collaboration> proposeOffer(
    String collaborationId, {
    required int amountMinor,
    required bool isFinal,
  }) {
    if (amountMinor <= 0) {
      throw const CollaborationException('Enter an amount greater than zero.');
    }
    return _transition(collaborationId, 'propose_offer', {
      'amount_minor': amountMinor,
      'is_final': isFinal,
    });
  }

  /// Accepts the OTHER participant's pending offer only — the server itself
  /// enforces "not your own offer" (`collab_transition`'s `accept_offer`
  /// action); this never sends the amount back, since the server already
  /// knows which offer is pending. Locks the amount, creates/updates the
  /// 25%/75% payment rows and moves the collaboration to
  /// `agreement_pending`.
  Future<Collaboration> acceptOffer(String collaborationId) =>
      _transition(collaborationId, 'accept_offer');

  /// Either participant may cancel while `accepted`, or while
  /// `agreement_pending` before the advance has been paid — server-enforced;
  /// this just forwards the (optional, <=1000 char) reason.
  Future<Collaboration> cancelCollaboration(
    String collaborationId, {
    String? reason,
  }) {
    final trimmed = reason?.trim();
    final capped = (trimmed != null && trimmed.length > maxDisputeReasonLength)
        ? trimmed.substring(0, maxDisputeReasonLength)
        : trimmed;
    return _transition(collaborationId, 'cancel', {
      if (capped != null && capped.isNotEmpty) 'reason': capped,
    });
  }

  // ── Edge Functions ────────────────────────────────────────────────────
  //
  // Every one of these routes through [CollabFunctionsClient], which
  // requires a real current session, refreshes an expired one before
  // calling, sends the latest bearer token explicitly, times out, and
  // retries exactly once on a 401 with a freshly refreshed token — never
  // blindly, and never more than once.

  Future<Map<String, dynamic>> _invoke(
    String function, {
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _functions.invoke(function, body: body);
    } on CollabAuthException catch (e) {
      throw CollaborationException(e.message);
    } catch (e) {
      debugPrint('CollaborationService._invoke($function) failed: $e');
      throw const CollaborationException(
        'A network error occurred. Please try again.',
      );
    }
  }

  /// Verifies a completed Razorpay payment for a collaboration milestone —
  /// the same `verify-payment` function the subscription checkout uses, but
  /// invoked through the collaboration auth helper rather than
  /// `PaymentService`, per the collaboration marketplace's own auth
  /// requirements. Never advances collaboration state locally: the
  /// collaboration/payment rows only ever change server-side, and the
  /// caller's own refresh/realtime subscription is what shows the result.
  Future<Map<String, dynamic>> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final data = await _invoke(
      'verify-payment',
      body: {
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
    );
    if (data['success'] != true) {
      throw const CollaborationException('Payment verification failed.');
    }
    return data;
  }

  /// Always the *current* agreement PDF (server regenerates on every call),
  /// signed for 300s.
  Future<String> fetchAgreementUrl(String collaborationId) async {
    final data = await _invoke(
      'collab-agreement',
      body: {'collaborationId': collaborationId},
    );
    final url = data['url'] as String?;
    if (url == null) {
      throw const CollaborationException('Failed to generate the agreement.');
    }
    return url;
  }

  Future<String> fetchInvoiceUrl(String invoiceId) async {
    final data = await _invoke(
      'download-collab-invoice',
      body: {'invoiceId': invoiceId},
    );
    final url = data['url'] as String?;
    if (url == null) {
      throw const CollaborationException('Failed to generate the invoice.');
    }
    return url;
  }

  /// Client-only. Server ignores any client-supplied amount — it reads
  /// `collab_payments.amount_minor` itself. Returns the raw Razorpay order
  /// payload (`orderId`, `amount`, `currency`, `keyId`, `customerId`,
  /// `prefill`) for the checkout widget to open verbatim.
  Future<Map<String, dynamic>> createPaymentOrder({
    required String collaborationId,
    required String milestone,
  }) => _invoke(
    'collab-create-order',
    body: {'collaborationId': collaborationId, 'milestone': milestone},
  );

  /// Client-only. Reveals a one-time sample — the URL is valid ~60s and can
  /// only be opened once, ever (server-enforced compare-and-swap). Never
  /// call this except in direct response to the user tapping "view" — never
  /// prefetch, never call twice for the same asset.
  Future<String> viewSample(String assetId) async {
    final data = await _invoke(
      'collab-sample-view',
      body: {'assetId': assetId},
    );
    final url = data['url'] as String?;
    if (url == null) {
      throw const CollaborationException('Failed to open the sample.');
    }
    return url;
  }

  /// Client-only. 300s signed URL; also the call that flips the collaboration
  /// to `completed` server-side on first download — never marked locally.
  Future<String> fetchDeliverableUrl(String assetId) async {
    final data = await _invoke(
      'collab-deliverable-url',
      body: {'assetId': assetId},
    );
    final url = data['url'] as String?;
    if (url == null) {
      throw const CollaborationException('Failed to generate a download link.');
    }
    return url;
  }

  /// Either party, no extra role gate beyond being a participant — matches
  /// `CollabActionPanel.tsx`'s `canDispute`. The reason is required and
  /// capped locally at [maxDisputeReasonLength] (the server caps it too).
  Future<Collaboration> raiseDispute(
    String collaborationId,
    String reason,
  ) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      throw const CollaborationException('Enter a reason for the dispute.');
    }
    final capped = trimmed.length > maxDisputeReasonLength
        ? trimmed.substring(0, maxDisputeReasonLength)
        : trimmed;
    final data = await _invoke(
      'collab-dispute',
      body: {'collaborationId': collaborationId, 'reason': capped},
    );
    final collab = data['collaboration'];
    if (collab is Map) {
      return Collaboration.fromSupabase(Map<String, dynamic>.from(collab));
    }
    // The function's own contract always returns `{success, collaboration}`
    // on 200; a missing key means the response shape changed server-side —
    // reload rather than guess.
    final reloaded = await fetchCollaboration(collaborationId);
    if (reloaded == null) {
      throw const CollaborationException(
        'Dispute submitted, but the collaboration could not be reloaded.',
      );
    }
    return reloaded;
  }

  // ── Uploads (collab_asset_create) ─────────────────────────────────────

  /// Streams the file straight from disk rather than reading it into memory
  /// first — the deliverable bucket allows up to 300 MB, and this app's
  /// existing media services (which top out at 50 MB) can afford the
  /// bytes-in-memory pattern; this one cannot.
  Future<CollabAsset> _uploadAndCreateAsset({
    required String collaborationId,
    required File file,
    required String kind,
    required String bucket,
  }) async {
    final authUid = _supabase.auth.currentUser?.id;
    if (authUid == null) {
      throw const CollaborationException('You need to be signed in.');
    }
    final path = '$authUid/${_uuid.v4()}.mp4';

    try {
      await _supabase.storage
          .from(bucket)
          .upload(
            path,
            file,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          );
    } catch (e) {
      debugPrint('CollaborationService: upload to $bucket failed: $e');
      throw const CollaborationException(
        'Upload failed. Check your connection and try again.',
      );
    }

    try {
      final row = await _supabase.rpc(
        'collab_asset_create',
        params: {
          'p_collab_id': collaborationId,
          'p_kind': kind,
          'p_bucket': bucket,
          'p_storage_path': path,
        },
      );
      return CollabAsset.fromSupabase(Map<String, dynamic>.from(row as Map));
    } catch (e) {
      debugPrint('CollaborationService: collab_asset_create failed: $e');
      throw CollaborationException(_messageFor(e));
    }
  }

  /// Influencer-only (server-enforced). MP4 only, ~9-16s (portal tolerance
  /// around a 10-15s spec), max 60 MB. The 5-resend cap is server-owned —
  /// this surfaces whatever the RPC raises rather than pre-counting.
  Future<CollabAsset> uploadSample({
    required String collaborationId,
    required File file,
  }) async {
    await _validateVideoFile(
      file,
      maxBytes: maxSampleBytes,
      maxBytesMessage: 'Sample must be 60MB or smaller.',
      checkDuration: true,
    );
    return _uploadAndCreateAsset(
      collaborationId: collaborationId,
      file: file,
      kind: CollabAssetKinds.sampleOnetime,
      bucket: _sampleBucket,
    );
  }

  /// Influencer-only (server-enforced). MP4 only, max 300 MB, uploaded
  /// original and uncompressed — never reuse the influencer-video
  /// compression pipeline. No duration check, matching the portal.
  Future<CollabAsset> uploadDeliverable({
    required String collaborationId,
    required File file,
  }) async {
    await _validateVideoFile(
      file,
      maxBytes: maxDeliverableBytes,
      maxBytesMessage: 'Deliverable must be 300MB or smaller.',
      checkDuration: false,
    );
    return _uploadAndCreateAsset(
      collaborationId: collaborationId,
      file: file,
      kind: CollabAssetKinds.deliverable,
      bucket: _deliverableBucket,
    );
  }

  Future<void> _validateVideoFile(
    File file, {
    required int maxBytes,
    required String maxBytesMessage,
    required bool checkDuration,
  }) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (ext != 'mp4') {
      throw const CollabMediaValidationError('Only MP4 videos are supported.');
    }

    final size = await file.length();
    if (size > maxBytes) {
      throw CollabMediaValidationError(maxBytesMessage);
    }
    if (size == 0) {
      throw const CollabMediaValidationError(
        "That file is empty. Please choose a different video.",
      );
    }

    if (!checkDuration) return;

    final duration = await _probeDuration(file);
    if (duration == null) {
      // Fails open on a probe failure (corrupt metadata reader, not a
      // corrupt file) — the server has no duration check of its own, so
      // this is a UX guard, not a security boundary.
      debugPrint(
        'CollaborationService: duration probe failed, allowing upload',
      );
      return;
    }
    if (duration < sampleMinDuration || duration > sampleMaxDuration) {
      throw CollabMediaValidationError(
        'Sample must be about 10-15 seconds long '
        '(got ${duration.inSeconds}s).',
      );
    }
  }

  Future<Duration?> _probeDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.duration;
    } catch (e) {
      debugPrint('CollaborationService._probeDuration failed: $e');
      return null;
    } finally {
      await controller.dispose();
    }
  }

  // ── Plain message inserts (not state-machine, no `refresh` needed by the
  // ── caller beyond what the thread's own realtime subscription already does)

  /// `CollabActionPanel.tsx`'s "Share my location" (client-only). Content
  /// format is `"<label>\n<mapsUrl>"`, matching the portal exactly.
  Future<void> sendLocationMessage({
    required String conversationId,
    required String senderId,
    required double latitude,
    required double longitude,
    String label = 'Current location',
  }) async {
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    try {
      await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': '$label\n$mapsUrl',
        'message_type': 'location',
      });
    } catch (e) {
      debugPrint('CollaborationService.sendLocationMessage failed: $e');
      throw const CollaborationException(
        "Couldn't share your location. Check your connection and try again.",
      );
    }
  }

  /// `CollabActionPanel.tsx`'s "Request site location" (influencer-only) —
  /// a plain, ordinary text message (`message_type: 'text'`), NOT a
  /// `collab_system` note; the portal's `requestLocation()` inserts exactly
  /// this content as a normal message so it reads and behaves like anything
  /// else either participant could have typed.
  Future<void> requestLocationMessage({
    required String conversationId,
    required String senderId,
  }) async {
    try {
      await _supabase.from('messages').insert({
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': 'Could you share your current location?',
        'message_type': 'text',
      });
    } catch (e) {
      debugPrint('CollaborationService.requestLocationMessage failed: $e');
      throw const CollaborationException(
        "Couldn't send the request. Check your connection and try again.",
      );
    }
  }

  // ── Notification routing ──────────────────────────────────────────────

  /// Never guesses a conversation id: `requested`/no-conversation states
  /// route to the Collabs inbox; `accepted` and later resolve the actual
  /// linked conversation and its counterparty.
  Future<CollabNotificationDestination> resolveNotificationDestination({
    required String collaborationId,
    required String currentUserId,
  }) async {
    final collab = await fetchCollaboration(collaborationId);
    if (collab == null || !collab.hasConversation) {
      return const CollabNotificationDestination.inbox();
    }
    final counterpartyId = collab.counterpartyIdFor(currentUserId);
    if (counterpartyId == null) {
      return const CollabNotificationDestination.inbox();
    }
    final profiles = await resolveProfiles({counterpartyId});
    final profile = profiles[counterpartyId];
    return CollabNotificationDestination.conversation(
      conversationId: collab.conversationId!,
      counterpartyId: counterpartyId,
      counterpartyName: profile?.displayName ?? 'Collaboration',
      counterpartyAvatarUrl: profile?.avatarUrl,
    );
  }

  String _messageFor(Object e) {
    if (e is CollaborationException) return e.message;
    final text = e.toString();
    // PostgrestException/PostgrestException-like objects stringify with a
    // `PostgrestException(message: ..., code: ...)` wrapper — strip it so a
    // raw RPC RAISE EXCEPTION message (already user-appropriate; see the
    // migration's per-action error text) reaches the UI cleanly.
    final match = RegExp(r'message:\s*([^,]+)').firstMatch(text);
    return match?.group(1)?.trim() ?? text;
  }
}
