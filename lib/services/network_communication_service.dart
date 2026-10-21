import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_models.dart';
import '../models/network_relationship.dart';

/// Thrown by [NetworkCommunicationService.createChannel] when the `channels`
/// row itself was created but a later write in the sequence (the
/// `network_channels` row, the creator's own `channel_participants` row, or
/// the auto-join batch) failed. [channelId] lets the caller refresh and show
/// whatever partial state actually landed, rather than pretending nothing
/// happened or claiming full success.
class NetworkChannelPartialFailure implements Exception {
  const NetworkChannelPartialFailure(this.message, {required this.channelId});

  final String message;
  final String channelId;

  @override
  String toString() => message;
}

/// Writes (and the richer reads) for Network ▸ Communication.
///
/// Deliberately separate from [NetworkService], which is documented as
/// read-only and is not the place for these writes, and separate from
/// [MessagingService], whose generic `createChannel`/channel plumbing must
/// stay untouched — a network channel needs two extra rows
/// (`network_channels`, plus an auto-join batch) the generic flow knows
/// nothing about.
///
/// No RPC exists for creating a network channel — same constraint the portal
/// is under (`NetworkCommunicationHub.tsx`'s `handleCreateChannel`) — so this
/// mirrors its exact multi-insert sequence and the same RLS-backed
/// assumptions: `channels` INSERT requires `created_by = auth.uid()`, and
/// `channel_participants` INSERT allows the channel's own creator to add any
/// `user_id` (verified against `20250823171340_...sql`'s
/// "Creator or admin can add participants" policy), which is what makes a
/// bulk client-side auto-join insert legal in one call.
class NetworkCommunicationService {
  NetworkCommunicationService({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  /// Resolved lazily, per call, rather than once in a field initialiser:
  /// constructing a real `SupabaseClient` starts a GoTrue auto-refresh timer,
  /// so a test subclass that overrides every method touching this getter
  /// (see `FakeNetworkCommunicationService`) never needs to pass one in just
  /// to satisfy the base constructor.
  SupabaseClient get _supabase => _clientOverride ?? Supabase.instance.client;

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Everything the Communication screen needs for one user: their visible
  /// channels (hydrated with the base `channels` row, a participant count and
  /// their own role) and their accepted network members.
  ///
  /// Matches the portal's `NetworkCommunicationHub.tsx` exactly: it runs the
  /// same `fetchCommunicationData`/`handleCreateChannel`/
  /// `handleSendBulkMessage` for every signed-in user, with no `user_type`
  /// check anywhere — a broker, influencer or individual can create a
  /// channel or send a bulk message exactly like a builder can, always
  /// scoped to rows where *they themselves* are `builder_id`. [isBuilder] is
  /// kept as a parameter only so existing call sites don't need to change;
  /// it no longer changes which rows are read.
  ///
  /// Channels are the union of two reads: [_loadBuilderChannels] (rows this
  /// user owns as `builder_id` — where a genuine builder's channels live,
  /// but now equally where anyone who has created their own channel here
  /// shows up) and [_loadMemberChannels] (channels this user was added to as
  /// a participant, e.g. via someone else's auto-join). A channel present in
  /// both collapses to one row, keeping the owned copy — it carries the
  /// admin role and hydration [_loadMemberChannels] alone wouldn't know
  /// about for the owner.
  Future<({List<NetworkChannel> channels, List<NetworkMember> members})>
  loadCommunicationData(String userId, {required bool isBuilder}) async {
    final results = await Future.wait([
      _loadBuilderChannels(userId),
      _loadMemberChannels(userId),
      _loadAcceptedMembers(userId),
    ]);

    final owned = results[0] as List<NetworkChannel>;
    final participant = results[1] as List<NetworkChannel>;
    final members = results[2] as List<NetworkMember>;

    final byChannelId = <String, NetworkChannel>{};
    for (final c in participant) {
      byChannelId[c.channelId] = c;
    }
    for (final c in owned) {
      byChannelId[c.channelId] = c; // owned copy wins — carries the admin role
    }
    final channels = byChannelId.values.toList()
      ..sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

    return (channels: channels, members: members);
  }

  Future<List<NetworkChannel>> _loadBuilderChannels(String builderId) async {
    final rows = await _supabase
        .from('network_channels')
        .select()
        .eq('builder_id', builderId)
        .order('created_at', ascending: false);

    final base = List<Map<String, dynamic>>.from(rows as List)
        .map((r) => NetworkChannel.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    return _hydrate(base, viewerId: builderId);
  }

  /// A member's own visible channels — never `.eq('builder_id', userId)`,
  /// which would always be empty for a non-builder and could be mistaken for
  /// "no channels" rather than "wrong query".
  Future<List<NetworkChannel>> _loadMemberChannels(String userId) async {
    final participantRows = await _supabase
        .from('channel_participants')
        .select('channel_id')
        .eq('user_id', userId);

    final myChannelIds = List<Map<String, dynamic>>.from(
      participantRows as List,
    ).map((r) => r['channel_id']?.toString()).whereType<String>().toSet();

    if (myChannelIds.isEmpty) return const [];

    final rows = await _supabase
        .from('network_channels')
        .select()
        .inFilter('channel_id', myChannelIds.toList())
        .order('created_at', ascending: false);

    final base = List<Map<String, dynamic>>.from(rows as List)
        .map((r) => NetworkChannel.fromJson(Map<String, dynamic>.from(r)))
        .toList();

    return _hydrate(base, viewerId: userId);
  }

  /// Batches the `channels` join and the participant counts/role lookup —
  /// one round trip apiece regardless of how many channels [base] has, the
  /// same `inFilter` pattern [MessagingService.listChannels] already uses.
  Future<List<NetworkChannel>> _hydrate(
    List<NetworkChannel> base, {
    required String viewerId,
  }) async {
    if (base.isEmpty) return const [];

    final channelIds = base
        .map((c) => c.channelId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (channelIds.isEmpty) return base;

    final results = await Future.wait([
      _supabase
          .from('channels')
          .select(
            'id, name, description, channel_type, is_active, created_by, max_participants',
          )
          .inFilter('id', channelIds),
      _supabase
          .from('channel_participants')
          .select('channel_id, user_id, role')
          .inFilter('channel_id', channelIds),
    ]);

    final channelDetailsById = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(results[0] as List)) {
      final id = row['id']?.toString();
      if (id != null) channelDetailsById[id] = row;
    }

    final participantCounts = <String, int>{};
    final myRoleByChannel = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(results[1] as List)) {
      final id = row['channel_id']?.toString();
      if (id == null) continue;
      participantCounts[id] = (participantCounts[id] ?? 0) + 1;
      if (row['user_id']?.toString() == viewerId) {
        myRoleByChannel[id] = (row['role'] as String?) ?? 'member';
      }
    }

    return base.map((c) {
      final details = channelDetailsById[c.channelId];
      final role = myRoleByChannel[c.channelId];
      return c.copyWith(
        name: details?['name'] as String?,
        description: details?['description'] as String?,
        channelType: details?['channel_type'] as String?,
        isActive: details?['is_active'] as bool?,
        createdBy: details?['created_by']?.toString(),
        maxParticipants: (details?['max_participants'] as num?)?.toInt(),
        participantCount: participantCounts[c.channelId] ?? 0,
        currentUserRole: role,
        isCurrentUserParticipant: role != null,
      );
    }).toList();
  }

  /// This user's *genuine* accepted network members — the pool Create
  /// Channel's auto-join and Bulk Message both draw from. Only ever
  /// `status = 'accepted'` with `builder_id = builderId`, whether `builderId`
  /// actually holds the `builder` role or not — matching the portal, which
  /// runs this exact query for any signed-in user.
  ///
  /// Critical: this does **not** trust the row's own `member_type` column.
  /// `builder_networks` RLS is fully symmetric and its `member_type` CHECK
  /// now allows `broker|influencer|builder|individual|seller|dealer|agent`
  /// (broadened by `20260428170000_broaden_network_types.sql`) — a row with
  /// `builder_id = builderId` can be a genuine network member, but it can
  /// just as easily be a generic profile-to-profile "Connect" where another
  /// builder, or an unrelated individual, happened to land on this side.
  /// [classifyRelationship] validates the counterpart's *independently
  /// hydrated* real `profiles.user_type` instead, and only a real broker/
  /// influencer counterpart is included — exactly the fix this method needed
  /// so Bulk Message ("All Members") and Channel auto-join can never reach
  /// someone who merely has a stray `builder_networks` row pointed at this
  /// user.
  Future<List<NetworkMember>> _loadAcceptedMembers(String builderId) async {
    final rows = await _supabase
        .from('builder_networks')
        .select('id, member_id, member_type, verified, status')
        .eq('builder_id', builderId)
        .eq('status', 'accepted');

    final base = List<Map<String, dynamic>>.from(
      rows as List,
    ).where((r) => r['member_id'] != null).toList();
    if (base.isEmpty) return const [];

    final memberIds = base.map((r) => r['member_id'].toString()).toSet();

    final profileRows = await _supabase
        .from('profiles_public')
        .select('user_id, display_name, avatar_url, user_type')
        .inFilter('user_id', memberIds.toList());

    final profilesById = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(profileRows as List)) {
      final id = row['user_id']?.toString();
      if (id != null) profilesById[id] = row;
    }

    final members = <NetworkMember>[];
    for (final r in base) {
      final memberId = r['member_id'].toString();
      final profile = profilesById[memberId];
      final counterpartUserType = profile?['user_type'] as String?;

      final kind = classifyRelationship(
        viewerId: builderId,
        builderId: builderId,
        memberId: memberId,
        status: '${r['status'] ?? 'accepted'}',
        counterpartRealUserType: counterpartUserType,
      );
      if (kind != NetworkRelationshipKind.ownedNetworkMember) continue;

      members.add(
        NetworkMember.fromSupabase(
          r,
          displayName: profile?['display_name'] as String?,
          avatarUrl: profile?['avatar_url'] as String?,
        ),
      );
    }
    return members;
  }

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Mirrors `NetworkCommunicationHub.tsx`'s `handleCreateChannel`: insert
  /// `channels`, then `network_channels`, then the creator as `admin`, then
  /// one deduplicated batch covering both [manualMemberIds] — specific people
  /// hand-picked in the sheet's member search, added regardless of
  /// [isAutoJoin] — and, only if [isAutoJoin], every accepted member whose
  /// `member_type` is in [memberTypes]. Both sources are excluded against the
  /// builder and each other so the batch can never violate
  /// `channel_participants`'s `UNIQUE(channel_id, user_id)`.
  ///
  /// No backend RPC exists to make this one atomic transaction (out of scope
  /// — this task may not add one), so once the `channels` row exists, every
  /// later failure is reported as [NetworkChannelPartialFailure] carrying the
  /// id that *was* created, rather than a generic error that would hide a
  /// half-created channel from the caller.
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
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Channel name is required.');
    }
    if (channelPurpose.isEmpty) {
      throw ArgumentError('Channel purpose is required.');
    }

    final channelInserted = await _supabase
        .from('channels')
        .insert({
          'name': trimmedName,
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          'created_by': builderId,
          'channel_type': 'group',
        })
        .select('id')
        .single();

    final channelId = channelInserted['id']?.toString();
    if (channelId == null) {
      throw StateError('Channel insert returned no id.');
    }

    try {
      await _supabase.from('network_channels').insert({
        'channel_id': channelId,
        'builder_id': builderId,
        'channel_purpose': channelPurpose,
        'is_auto_join': isAutoJoin,
        'member_types': memberTypes,
      });
    } catch (e) {
      debugPrint(
        'NetworkCommunicationService.createChannel: network_channels insert failed: $e',
      );
      throw NetworkChannelPartialFailure(
        'The channel was created, but its network settings could not be '
        'saved. Pull to refresh, then try creating it again.',
        channelId: channelId,
      );
    }

    try {
      await _supabase.from('channel_participants').insert({
        'channel_id': channelId,
        'user_id': builderId,
        'role': 'admin',
      });
    } catch (e) {
      debugPrint(
        'NetworkCommunicationService.createChannel: creator participant insert failed: $e',
      );
      throw NetworkChannelPartialFailure(
        "The channel was created, but you weren't added as its admin. "
        'Pull to refresh and try opening it.',
        channelId: channelId,
      );
    }

    final seen = <String>{builderId};
    final inserts = <Map<String, dynamic>>[];
    void addParticipant(String userId) {
      if (userId.isEmpty) return;
      if (!seen.add(userId)) return;
      inserts.add({
        'channel_id': channelId,
        'user_id': userId,
        'role': 'member',
      });
    }

    for (final memberId in manualMemberIds) {
      addParticipant(memberId);
    }

    if (isAutoJoin) {
      for (final member in acceptedMembers) {
        if (!memberTypes.contains(member.memberType)) continue;
        addParticipant(member.memberId);
      }
    }

    if (inserts.isNotEmpty) {
      try {
        await _supabase.from('channel_participants').insert(inserts);
      } catch (e) {
        debugPrint(
          'NetworkCommunicationService.createChannel: member batch failed: $e',
        );
        throw NetworkChannelPartialFailure(
          'The channel was created, but some members could not be '
          'added. Pull to refresh to see who made it in.',
          channelId: channelId,
        );
      }
    }

    return channelId;
  }

  /// One `notifications` row per recipient, `type = 'bulk_message'`,
  /// `data = {message_type, priority}`. [recipients] is expected to already
  /// be the result of [filterBulkMessageRecipients] — this does not re-filter,
  /// only inserts. Returns the number of rows written. The existing
  /// `trigger_send_web_push` AFTER INSERT trigger delivers push for every row
  /// automatically; this must never also call a push function directly.
  ///
  /// `type` was `'builder_network_addition'` until this fix — the same value
  /// a connection request uses, and with no `sender_id`/`sender_name` in its
  /// payload (unlike a real connection request), so a tap had nothing good to
  /// route to. `bulk_message` is the type the backend's own broadcast path
  /// (`network-channels-manage`'s `"broadcast"` action) already writes —
  /// 20270915030000_add_bulk_message_notification_type.sql adds exactly this
  /// value for exactly this reason. `NotificationsScreen` shows it in a detail
  /// dialog rather than navigating, since there is no conversation/message row
  /// behind a bulk message on either platform.
  Future<int> sendBulkMessage({
    required List<NetworkMember> recipients,
    required String title,
    required String message,
    required String messageType,
    required String priority,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedMessage = message.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Message title is required.');
    }
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message is required.');
    }
    if (recipients.isEmpty) {
      throw ArgumentError('There are no eligible recipients.');
    }

    final rows = recipients
        .map(
          (m) => {
            'user_id': m.memberId,
            'type': 'bulk_message',
            'title': trimmedTitle,
            'message': trimmedMessage,
            'data': {'message_type': messageType, 'priority': priority},
          },
        )
        .toList();

    await _supabase.from('notifications').insert(rows);
    return rows.length;
  }
}
