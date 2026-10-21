import 'package:flutter/foundation.dart';

import '../models/network_models.dart';
import '../services/network_communication_service.dart';

/// Screen-scoped state for Network ▸ Communication: the channel list, the
/// builder's accepted members, and the submission state for Create Channel
/// and Bulk Message.
///
/// Kept separate from [NetworkChannelsSection] (which still backs its own
/// Phase 9 test in isolation) rather than extending it — this needs mutation
/// state (in-flight flags, per-action errors) that a plain read section has
/// no reason to carry, and a compelling reason to touch that class never
/// materialised.
class NetworkCommunicationProvider extends ChangeNotifier {
  NetworkCommunicationProvider({NetworkCommunicationService? service})
    : _service = service ?? NetworkCommunicationService();

  final NetworkCommunicationService _service;

  String? _userId;
  bool _isBuilder = false;
  bool _disposed = false;

  List<NetworkChannel> _channels = const [];
  List<NetworkMember> _acceptedMembers = const [];
  bool _loading = true;
  bool _failed = false;

  bool _creatingChannel = false;
  String? _createChannelError;

  bool _sendingBulkMessage = false;
  String? _bulkMessageError;
  int _lastBulkMessageRecipientCount = 0;

  List<NetworkChannel> get channels => List.unmodifiable(_channels);
  List<NetworkMember> get acceptedMembers =>
      List.unmodifiable(_acceptedMembers);
  bool get loading => _loading;
  bool get failed => _failed;
  bool get isBuilder => _isBuilder;
  String? get userId => _userId;

  bool get creatingChannel => _creatingChannel;
  String? get createChannelError => _createChannelError;

  bool get sendingBulkMessage => _sendingBulkMessage;
  String? get bulkMessageError => _bulkMessageError;
  int get lastBulkMessageRecipientCount => _lastBulkMessageRecipientCount;

  /// Loads (or reloads) for [userId]. Safe to call again for a different
  /// user — e.g. an account switch — which drops whatever the previous
  /// user's rows were rather than showing them under the new identity while
  /// the fresh load is in flight.
  Future<void> load(String userId, {required bool isBuilder}) async {
    if (userId != _userId) {
      _channels = const [];
      _acceptedMembers = const [];
      _createChannelError = null;
      _bulkMessageError = null;
    }
    _userId = userId;
    _isBuilder = isBuilder;
    _loading = true;
    _failed = false;
    _safeNotify();

    try {
      final result = await _service.loadCommunicationData(
        userId,
        isBuilder: isBuilder,
      );
      // A newer load (or a sign-out) has since superseded this one — never
      // let a slow, stale response overwrite the current identity's state.
      if (_userId != userId) return;
      _channels = result.channels;
      _acceptedMembers = result.members;
      _failed = false;
    } catch (e) {
      if (_userId != userId) return;
      debugPrint('NetworkCommunicationProvider.load failed: $e');
      _failed = true;
      _channels = const [];
      _acceptedMembers = const [];
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
    return load(userId, isBuilder: _isBuilder);
  }

  /// Recipients a Bulk Message with [recipientType] would actually reach —
  /// used both for the sheet's live count and (via [sendBulkMessage]) the
  /// real send, so the two can never disagree.
  List<NetworkMember> recipientsFor(String recipientType) {
    return filterBulkMessageRecipients(
      members: _acceptedMembers,
      recipientType: recipientType,
      builderId: _userId ?? '',
    );
  }

  /// Creates a network channel. Returns `true` on full success. On a partial
  /// failure (channel created, a later write failed) this still refreshes so
  /// the caller's list reflects whatever landed, sets [createChannelError],
  /// and returns `false` — never `true` for a half-created channel.
  Future<bool> createChannel({
    required String name,
    String? description,
    required String channelPurpose,
    required bool isAutoJoin,
    required List<String> memberTypes,
    List<String> manualMemberIds = const [],
  }) async {
    final userId = _userId;
    if (userId == null || _creatingChannel) return false;

    _creatingChannel = true;
    _createChannelError = null;
    _safeNotify();

    try {
      await _service.createChannel(
        builderId: userId,
        name: name,
        description: description,
        channelPurpose: channelPurpose,
        isAutoJoin: isAutoJoin,
        memberTypes: memberTypes,
        acceptedMembers: _acceptedMembers,
        manualMemberIds: manualMemberIds,
      );
      await refresh();
      return true;
    } on NetworkChannelPartialFailure catch (e) {
      _createChannelError = e.message;
      await refresh();
      return false;
    } catch (e) {
      debugPrint('NetworkCommunicationProvider.createChannel failed: $e');
      _createChannelError = "Couldn't create the channel. Please try again.";
      return false;
    } finally {
      _creatingChannel = false;
      _safeNotify();
    }
  }

  /// Sends a bulk message to every recipient [recipientsFor] resolves for
  /// [recipientType]. Returns `true` on success — [lastBulkMessageRecipientCount]
  /// then holds how many rows were written, for the caller's confirmation
  /// copy. Never retries automatically: a failure after the insert may have
  /// partially landed, and re-sending could duplicate notifications.
  Future<bool> sendBulkMessage({
    required String recipientType,
    required String messageType,
    required String priority,
    required String title,
    required String message,
  }) async {
    if (_sendingBulkMessage) return false;

    final recipients = recipientsFor(recipientType);

    _sendingBulkMessage = true;
    _bulkMessageError = null;
    _safeNotify();

    try {
      if (recipients.isEmpty) {
        _bulkMessageError = 'There are no eligible recipients for this filter.';
        return false;
      }
      final count = await _service.sendBulkMessage(
        recipients: recipients,
        title: title,
        message: message,
        messageType: messageType,
        priority: priority,
      );
      _lastBulkMessageRecipientCount = count;
      return true;
    } catch (e) {
      debugPrint('NetworkCommunicationProvider.sendBulkMessage failed: $e');
      _bulkMessageError = "Couldn't send the message. Please try again.";
      return false;
    } finally {
      _sendingBulkMessage = false;
      _safeNotify();
    }
  }

  void clearCreateChannelError() {
    _createChannelError = null;
  }

  void clearBulkMessageError() {
    _bulkMessageError = null;
  }

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
