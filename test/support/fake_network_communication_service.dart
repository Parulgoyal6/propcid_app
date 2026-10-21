import 'dart:async';

import 'package:propcid_app/models/network_models.dart';
import 'package:propcid_app/services/network_communication_service.dart';

/// Drives [NetworkCommunicationProvider] with canned results and captured
/// call arguments — no live or locally-initialized Supabase client involved.
/// Unlike `FakeTeamService` (`fake_auth_service.dart`), this never even
/// constructs a placeholder `SupabaseClient`: doing so starts a GoTrue
/// auto-refresh timer that trips `flutter_test`'s pending-timer check in a
/// `testWidgets` test. [NetworkCommunicationService]'s client is resolved
/// lazily per call precisely so a subclass overriding every call site never
/// needs one.
class FakeNetworkCommunicationService extends NetworkCommunicationService {
  FakeNetworkCommunicationService();

  ({List<NetworkChannel> channels, List<NetworkMember> members})?
  nextLoadResult;
  Object? nextLoadError;
  Completer<void>? pauseNextLoad;
  int loadCallCount = 0;

  Object? nextCreateError;
  String nextCreateChannelId = 'new-channel-id';
  Completer<void>? pauseNextCreate;
  int createCallCount = 0;
  Map<String, Object?>? lastCreateArgs;

  Object? nextSendError;
  Completer<void>? pauseNextSend;
  int sendCallCount = 0;
  List<NetworkMember>? lastSendRecipients;

  @override
  Future<({List<NetworkChannel> channels, List<NetworkMember> members})>
  loadCommunicationData(String userId, {required bool isBuilder}) async {
    loadCallCount++;
    final pause = pauseNextLoad;
    if (pause != null) {
      pauseNextLoad = null;
      await pause.future;
    }
    final error = nextLoadError;
    if (error != null) {
      nextLoadError = null;
      throw error;
    }
    return nextLoadResult ??
        (channels: const <NetworkChannel>[], members: const <NetworkMember>[]);
  }

  @override
  Future<String> createChannel({
    required String builderId,
    required String name,
    String? description,
    required String channelPurpose,
    required bool isAutoJoin,
    required List<String> memberTypes,
    required List<NetworkMember> acceptedMembers,
    List<String> manualMemberIds = const [],
  }) async {
    createCallCount++;
    lastCreateArgs = {
      'builderId': builderId,
      'name': name,
      'description': description,
      'channelPurpose': channelPurpose,
      'isAutoJoin': isAutoJoin,
      'memberTypes': memberTypes,
      'acceptedMembers': acceptedMembers,
      'manualMemberIds': manualMemberIds,
    };
    final pause = pauseNextCreate;
    if (pause != null) {
      pauseNextCreate = null;
      await pause.future;
    }
    final error = nextCreateError;
    if (error != null) {
      nextCreateError = null;
      throw error;
    }
    return nextCreateChannelId;
  }

  @override
  Future<int> sendBulkMessage({
    required List<NetworkMember> recipients,
    required String title,
    required String message,
    required String messageType,
    required String priority,
  }) async {
    sendCallCount++;
    lastSendRecipients = recipients;
    final pause = pauseNextSend;
    if (pause != null) {
      pauseNextSend = null;
      await pause.future;
    }
    final error = nextSendError;
    if (error != null) {
      nextSendError = null;
      throw error;
    }
    return recipients.length;
  }
}
