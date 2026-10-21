import 'package:flutter/foundation.dart';

import '../models/network_relationship.dart';
import '../services/network_relationship_service.dart';
import '../services/profile_connection_service.dart';

/// Screen-scoped state for My Networks: every `builder_networks` row the
/// viewer is a party to, hydrated and classified via
/// [NetworkRelationshipService.listRelationships].
///
/// Deliberately not a replacement for [NetworkMembershipsSection] — that
/// class still backs its own isolated Phase 9 test and other code may still
/// construct it; this is the richer, classified read the redesigned My
/// Networks screen actually needs.
class NetworkRelationshipsProvider extends ChangeNotifier {
  NetworkRelationshipsProvider({
    NetworkRelationshipService? service,
    ProfileConnectionService? connectionService,
  }) : _service = service ?? NetworkRelationshipService(),
       _connections = connectionService ?? ProfileConnectionService();

  final NetworkRelationshipService _service;

  /// Owns every `builder_networks` write already — see its own header for
  /// why "leave" belongs there rather than in the read-only relationship
  /// service.
  final ProfileConnectionService _connections;

  String? _userId;
  bool _disposed = false;

  List<NetworkRelationship> _relationships = const [];
  bool _loading = true;
  bool _failed = false;

  String? _leavingId;
  String? _leaveError;

  List<NetworkRelationship> get relationships =>
      List.unmodifiable(_relationships);
  bool get loading => _loading;
  bool get failed => _failed;

  /// The `builder_networks.id` currently being left, or null. Drives the
  /// per-row busy state and blocks a second concurrent leave.
  String? get leavingId => _leavingId;
  String? get leaveError => _leaveError;

  List<NetworkRelationship> _where(NetworkRelationshipKind kind) =>
      _relationships.where((r) => r.kind == kind).toList(growable: false);

  List<NetworkRelationship> get ownedNetworkMembers =>
      _where(NetworkRelationshipKind.ownedNetworkMember);
  List<NetworkRelationship> get joinedBuilderNetworks =>
      _where(NetworkRelationshipKind.joinedBuilderNetwork);
  List<NetworkRelationship> get peerConnections =>
      _where(NetworkRelationshipKind.peerConnection);

  /// Pending `builder_networks` rows where this viewer is the sender — the
  /// "Requests Sent" tile's underlying list on My Networks.
  List<NetworkRelationship> get sentRequests =>
      _where(NetworkRelationshipKind.outgoingPeerRequest);

  /// Pending `builder_networks` rows where this viewer is the recipient —
  /// the "Requests Received" tile's underlying list on My Networks.
  List<NetworkRelationship> get receivedRequests =>
      _where(NetworkRelationshipKind.incomingPeerRequest);

  Future<void> load(String userId) async {
    if (userId != _userId) _relationships = const [];
    _userId = userId;
    _loading = true;
    _failed = false;
    _safeNotify();

    try {
      final loaded = await _service.listRelationships(userId);
      if (_userId != userId) return;
      _relationships = loaded;
      _failed = false;
    } catch (e) {
      if (_userId != userId) return;
      debugPrint('NetworkRelationshipsProvider.load failed: $e');
      _failed = true;
      _relationships = const [];
    } finally {
      if (_userId == userId) {
        _loading = false;
        _safeNotify();
      }
    }
  }

  Future<void> refresh() {
    final userId = _userId;
    if (userId == null) return Future.value();
    return load(userId);
  }

  /// Leaves the relationship identified by [relationshipId] (its
  /// `builder_networks.id`), then refreshes so the row disappears (it's now
  /// `'removed'`, which [classifyRelationship] never treats as active).
  /// Returns `true` on success. A second call while one is already in flight
  /// is a no-op, matching every other write in this module's double-tap guard.
  Future<bool> leaveNetwork(String relationshipId) async {
    if (_leavingId != null) return false;

    _leavingId = relationshipId;
    _leaveError = null;
    _safeNotify();

    try {
      final error = await _connections.leaveNetwork(relationshipId);
      if (error != null) {
        _leaveError = "Couldn't leave this network. Please try again.";
        return false;
      }
      await refresh();
      return true;
    } catch (e) {
      debugPrint('NetworkRelationshipsProvider.leaveNetwork failed: $e');
      _leaveError = "Couldn't leave this network. Please try again.";
      return false;
    } finally {
      _leavingId = null;
      _safeNotify();
    }
  }

  String? _actingId;
  String? _actionError;

  /// The `builder_networks.id` of a pending request currently being
  /// cancelled/accepted/declined, or null. Mirrors [leavingId]'s busy/guard
  /// pattern but for the three request-response writes below — kept as a
  /// separate field since a leave (accepted rows) and a request response
  /// (pending rows) can never target the same row, so there is nothing to
  /// reconcile between them.
  String? get actingId => _actingId;
  String? get actionError => _actionError;

  Future<bool> _actOnRequest(
    NetworkRelationship relationship,
    Future<ConnectionWriteError?> Function(String viewerId, String counterpartId)
    action,
    String failureMessage,
  ) async {
    if (_actingId != null) return false;
    final viewerId = _userId;
    final counterpartId = relationship.counterpartUserId;
    if (viewerId == null || counterpartId == null) return false;

    _actingId = relationship.id;
    _actionError = null;
    _safeNotify();

    try {
      final error = await action(viewerId, counterpartId);
      if (error != null) {
        _actionError = failureMessage;
        return false;
      }
      await refresh();
      return true;
    } catch (e) {
      debugPrint('NetworkRelationshipsProvider action failed: $e');
      _actionError = failureMessage;
      return false;
    } finally {
      _actingId = null;
      _safeNotify();
    }
  }

  /// Withdraws a request this viewer sent — the "Requests Sent" tile's
  /// Cancel action, reusing [ProfileConnectionService.cancelRequest] (the
  /// same write the public profile page's own Cancel button already makes).
  Future<bool> cancelSentRequest(NetworkRelationship relationship) =>
      _actOnRequest(
        relationship,
        (viewerId, counterpartId) => _connections.cancelRequest(
          viewerId: viewerId,
          profileUserId: counterpartId,
        ),
        "Couldn't cancel this request. Please try again.",
      );

  /// Accepts a request this viewer received — the "Requests Received" tile's
  /// Accept action, reusing [ProfileConnectionService.acceptRequest].
  Future<bool> acceptReceivedRequest(NetworkRelationship relationship) =>
      _actOnRequest(
        relationship,
        (viewerId, counterpartId) => _connections.acceptRequest(
          viewerId: viewerId,
          profileUserId: counterpartId,
        ),
        "Couldn't accept this request. Please try again.",
      );

  /// Declines a request this viewer received — the "Requests Received"
  /// tile's Decline action, reusing [ProfileConnectionService.declineRequest].
  Future<bool> declineReceivedRequest(NetworkRelationship relationship) =>
      _actOnRequest(
        relationship,
        (viewerId, counterpartId) => _connections.declineRequest(
          viewerId: viewerId,
          profileUserId: counterpartId,
        ),
        "Couldn't decline this request. Please try again.",
      );

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
