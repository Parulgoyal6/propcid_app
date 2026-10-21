// providers/collaboration_thread_controller.dart
//
// State for one open collaboration — the data behind the action panel
// rendered inside its DM thread (Phase 3). Scoped to a collaboration that
// already has a conversation (`accepted` or later); accepting/declining a
// bare *request* happens one level up, in the Collabs inbox, before this
// controller ever exists — see `MessagingProvider`'s collab section.
//
// Mirrors `useCollabState.ts`: one realtime channel over `collaborations`,
// `collab_payments`, `collab_assets` and `collab_invoices` for this id, every
// mutator re-`refresh()`es rather than mutating local state (the server is
// the sole authority on status/amounts/assets), and a request-id counter
// discards a stale response the same way `ChatThreadProvider`/
// `PublicProfileProvider` already do in this codebase.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collaboration.dart';
import '../services/collaboration_exceptions.dart';
import '../services/collaboration_service.dart';

class CollaborationThreadController extends ChangeNotifier {
  CollaborationThreadController({
    required this.collaborationId,
    required this.userId,
    CollaborationService? service,
  }) : _service = service ?? CollaborationService();

  final String collaborationId;
  final String userId;
  final CollaborationService _service;
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _realtime;
  bool _disposed = false;
  int _requestId = 0;

  Collaboration? _collaboration;
  List<CollabPayment> _payments = const [];
  List<CollabAsset> _assets = const [];
  List<CollabInvoice> _invoices = const [];
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;

  Collaboration? get collaboration => _collaboration;
  List<CollabPayment> get payments => List.unmodifiable(_payments);

  /// Newest first, per [CollaborationService.fetchAssets].
  List<CollabAsset> get assets => List.unmodifiable(_assets);
  List<CollabInvoice> get invoices => List.unmodifiable(_invoices);
  bool get loading => _loading;
  bool get failed => _failed;

  /// True while an action is in flight — callers disable their CTA on this
  /// to prevent double-taps (Phase 6's double-tap requirement applies to
  /// every mutating action here, not just Razorpay).
  bool get busy => _busy;

  String? get myRole => _collaboration?.roleFor(userId);
  bool get isClient => myRole == CollabRoles.client;
  bool get isInfluencer => myRole == CollabRoles.influencer;

  CollabPayment? get advancePayment =>
      _payments.where((p) => p.isAdvance).firstOrNull;
  CollabPayment? get finalPayment =>
      _payments.where((p) => p.isFinal).firstOrNull;

  Future<void> load() async {
    _subscribe();
    await refresh();
  }

  Future<void> refresh() async {
    final requestId = ++_requestId;
    _loading = _collaboration == null;
    _safeNotify();

    try {
      final results = await Future.wait([
        _service.fetchCollaboration(collaborationId),
        _service.fetchPayments(collaborationId),
        _service.fetchAssets(collaborationId),
        _service.fetchInvoices(collaborationId),
      ]);
      if (requestId != _requestId) return;
      _collaboration = results[0] as Collaboration?;
      _payments = results[1] as List<CollabPayment>;
      _assets = results[2] as List<CollabAsset>;
      _invoices = results[3] as List<CollabInvoice>;
      _failed = false;
    } catch (e) {
      if (requestId != _requestId) return;
      debugPrint('CollaborationThreadController.refresh failed: $e');
      _failed = true;
    } finally {
      if (requestId == _requestId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  void _subscribe() {
    if (_realtime != null) return;
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final idFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: collaborationId,
    );
    final collabIdFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'collaboration_id',
      value: collaborationId,
    );

    _realtime = _supabase.channel('collab-$collaborationId-$suffix')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'collaborations',
        filter: idFilter,
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'collab_payments',
        filter: collabIdFilter,
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'collab_assets',
        filter: collabIdFilter,
        callback: (_) => refresh(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'collab_invoices',
        filter: collabIdFilter,
        callback: (_) => refresh(),
      )
      ..subscribe();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final channel = _realtime;
    if (channel != null) {
      _realtime = null;
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────
  //
  // Every one of these re-reads state from the server afterward rather than
  // predicting the new status locally — the realtime subscription above will
  // usually get there first, but a mutator awaiting its own `refresh()`
  // means the caller's `busy` flag clears only once the UI has something
  // fresh to show, not the instant the write lands.

  Future<String?> _run(Future<void> Function() action) async {
    if (_busy) return null;
    _busy = true;
    _safeNotify();
    try {
      await action();
      return null;
    } on CollaborationException catch (e) {
      return e.message;
    } on CollabMediaValidationError catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('CollaborationThreadController action failed: $e');
      return 'Something went wrong. Please try again.';
    } finally {
      _busy = false;
      _safeNotify();
    }
  }

  /// Proposes a new offer (or a counter-offer) while `accepted`. The server
  /// rejects it if the caller already has a pending offer of their own on
  /// the table (`propose_offer` requires responding to the OTHER
  /// participant's offer, not replacing your own) or if the prior offer was
  /// marked final.
  Future<String?> proposeOffer({
    required int amountMinor,
    required bool isFinal,
  }) => _run(() async {
    await _service.proposeOffer(
      collaborationId,
      amountMinor: amountMinor,
      isFinal: isFinal,
    );
    await refresh();
  });

  /// Accepts the counterparty's pending offer — locks the amount and moves
  /// to `agreement_pending` server-side.
  Future<String?> acceptOffer() => _run(() async {
    await _service.acceptOffer(collaborationId);
    await refresh();
  });

  /// Either participant, during `accepted` or unpaid `agreement_pending`.
  Future<String?> cancelCollaboration({String? reason}) => _run(() async {
    await _service.cancelCollaboration(collaborationId, reason: reason);
    await refresh();
  });

  /// Verifies a completed collaboration-milestone payment through the
  /// collaboration auth helper. Never advances state locally — the caller's
  /// own `refresh()`/realtime subscription reflects the server's result.
  Future<void> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) => _service.verifyPayment(
    razorpayOrderId: razorpayOrderId,
    razorpayPaymentId: razorpayPaymentId,
    razorpaySignature: razorpaySignature,
  );

  Future<String?> raiseDispute(String reason) => _run(() async {
    await _service.raiseDispute(collaborationId, reason);
    await refresh();
  });

  Future<String?> uploadSample(File file) => _run(() async {
    await _service.uploadSample(collaborationId: collaborationId, file: file);
    await refresh();
  });

  Future<String?> uploadDeliverable(File file) => _run(() async {
    await _service.uploadDeliverable(
      collaborationId: collaborationId,
      file: file,
    );
    await refresh();
  });

  /// Returns the signed agreement PDF URL, or null on failure (a snackbar
  /// message is returned via the second element instead of a throw, so the
  /// caller doesn't need a try/catch for what is fundamentally a read).
  Future<(String?, String?)> fetchAgreementUrl() async {
    try {
      return (await _service.fetchAgreementUrl(collaborationId), null);
    } catch (e) {
      return (
        null,
        e is CollaborationException
            ? e.message
            : 'Failed to open the agreement.',
      );
    }
  }

  Future<(String?, String?)> fetchInvoiceUrl(String invoiceId) async {
    try {
      return (await _service.fetchInvoiceUrl(invoiceId), null);
    } catch (e) {
      return (
        null,
        e is CollaborationException ? e.message : 'Failed to open the invoice.',
      );
    }
  }

  /// Never call except in direct response to the user tapping "view" —
  /// never prefetch, never retry the same asset once consumed.
  Future<(String?, String?)> viewSample(String assetId) async {
    try {
      final url = await _service.viewSample(assetId);
      // The server has already flipped this asset to `viewed` — reflect it
      // immediately rather than waiting for the realtime round-trip so the
      // bubble can't be tapped a second time before that arrives.
      unawaited(refresh());
      return (url, null);
    } catch (e) {
      return (
        null,
        e is CollaborationException ? e.message : 'Failed to open the sample.',
      );
    }
  }

  Future<(String?, String?)> fetchDeliverableUrl(String assetId) async {
    try {
      final url = await _service.fetchDeliverableUrl(assetId);
      unawaited(refresh());
      return (url, null);
    } catch (e) {
      return (
        null,
        e is CollaborationException
            ? e.message
            : 'Failed to generate a download link.',
      );
    }
  }

  Future<String?> sendLocation({
    required double latitude,
    required double longitude,
  }) => _run(() async {
    final conversationId = _collaboration?.conversationId;
    if (conversationId == null) {
      throw const CollaborationException(
        'This collaboration has no open chat yet.',
      );
    }
    await _service.sendLocationMessage(
      conversationId: conversationId,
      senderId: userId,
      latitude: latitude,
      longitude: longitude,
    );
  });

  Future<String?> requestLocation() => _run(() async {
    final conversationId = _collaboration?.conversationId;
    if (conversationId == null) {
      throw const CollaborationException(
        'This collaboration has no open chat yet.',
      );
    }
    await _service.requestLocationMessage(
      conversationId: conversationId,
      senderId: userId,
    );
  });

  /// Raw Razorpay order payload for the checkout widget — never returns a
  /// client-trusted amount, only what `collab-create-order` issued.
  Future<Map<String, dynamic>> createPaymentOrder(String milestone) =>
      _service.createPaymentOrder(
        collaborationId: collaborationId,
        milestone: milestone,
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
