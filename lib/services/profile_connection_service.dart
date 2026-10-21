// services/profile_connection_service.dart
//
// READ-ONLY companion service: what is the connection state between the signed-in
// viewer and the profile they are looking at?
//
// WHY A COMPANION AND NOT A METHOD ON NetworkService
// -------------------------------------------------
// `NetworkService` is consumed by `NetworkHubProvider`, `NetworkSectionProvider`,
// `ProfileProvider` and the four Network leaf screens. Approved decision D4 allows
// appending to an existing client service only when nothing existing changes —
// and Stage 1's approved modification list is `app_constants.dart` and `app.dart`
// only. So the read lives here instead, and `network_service.dart` is untouched.
//
// `NetworkService.getAcceptedCount()` IS reused, by calling it — see
// `PublicProfileProvider`. Calling is not modifying.
//
// WRITES (Phase 6) live here too, for the same reason: `NetworkService` declares
// itself read-only —
//
//   "Every method is a `select`. All the Network writes React owns — accepting or
//    declining an invitation, assigning a lead, creating a referral or a channel,
//    sending a bulk message — stay with the web portal."
//   (network_service.dart:13-15)
//
// — and the Flutter Network module has no write path anywhere: not in
// `NetworkHubProvider`, not in `NetworkSectionProvider`, not in any of its five
// screens. So there was no existing accept/decline flow to reuse or to preserve,
// and adding one to `NetworkService` would have contradicted its stated contract
// and touched a file four providers depend on. The writes are additive here
// instead, and `NetworkService` stays exactly as it is.
//
// Rows written here DO flow into the existing Network screens, because
// `NetworkService.getAcceptedCount` and `listMemberships` read the same
// `builder_networks` table. That is the intended outcome — a new connection should
// appear in the hub — and it is data reaching those screens, not a change to how
// they behave.
//
// SPEC F
// ------
// Spec F specified a brand-new `NetworkInvitationService` for send / accept /
// reject against `builder_network_invitations`. That would have duplicated this
// file: `sendRequest`, `cancelRequest` and `acceptRequest` already write that
// table, and `acceptRequest` already performs the two-step the portal's
// Collaboration Hub performs (mark the invitation accepted, then upsert the
// `builder_networks` row). So the four genuinely missing operations were appended
// here instead:
//
//   * `declineRequest`      — recipient-side reject. There was a sender-side
//                             cancel and an accept, but no decline.
//   * `listInvitations`     — the inbox both portal components render. `getStatus`
//                             only ever answered one viewer↔profile pair.
//   * `sendBuilderInvite`   — the builder's invite form, which carries a
//                             `member_type` and a message that peer-connect does
//                             not, and has an email/phone variant.
//   * `searchInvitees`      — the recipient picker behind that form.
//
// Nothing existing changed: no signature, no behaviour, no caller.
// `network_service.dart` remains untouched and read-only, which is the boundary
// this file was created to respect in the first place.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/network_models.dart';

/// Connection state between two users, mirroring the portal's
/// `networkStatus` union (pages/UserProfile.tsx:200-202).
enum ProfileConnectionStatus {
  /// No row in either table, or the viewer is anonymous / looking at themselves.
  none,

  /// The viewer asked to connect and is waiting.
  pendingSent,

  /// The other user asked, and the viewer can accept.
  pendingReceived,

  /// Accepted — this is what unlocks contact details.
  connected;

  bool get isConnected => this == ProfileConnectionStatus.connected;
}

class ProfileConnectionService {
  ProfileConnectionService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Resolves the state between [viewerId] and [profileUserId].
  ///
  /// A direct port of `fetchNetworkStatus` (pages/UserProfile.tsx:258-309),
  /// including its two-table order: the unified peer table first, then the legacy
  /// invitations table. Skipping the second would make older connections read as
  /// `none`, which would wrongly re-lock contact details for users who are
  /// already connected.
  ///
  /// Returns [ProfileConnectionStatus.none] for an anonymous viewer and for a
  /// self-view, before touching the network — the portal guards the same way, and
  /// RLS would return nothing regardless.
  ///
  /// Never throws. A failed lookup degrades to `none`, which fails *closed*:
  /// contact details stay hidden. Throwing would take down a screen whose other
  /// eleven sections are fine.
  Future<ProfileConnectionStatus> getStatus({
    required String? viewerId,
    required String profileUserId,
  }) async {
    if (viewerId == null || viewerId.isEmpty) {
      return ProfileConnectionStatus.none;
    }
    if (profileUserId.isEmpty || viewerId == profileUserId) {
      return ProfileConnectionStatus.none;
    }

    try {
      // ── 1. Unified peer connections ──────────────────────────────────────
      // Either direction: the sender is always `member_id`, the recipient always
      // `builder_id`, so both orderings have to be checked.
      final connection = await _supabase
          .from('builder_networks')
          .select('status, builder_id, member_id')
          .or(
            'and(builder_id.eq.$viewerId,member_id.eq.$profileUserId),'
            'and(builder_id.eq.$profileUserId,member_id.eq.$viewerId)',
          )
          .maybeSingle();

      if (connection != null) {
        final status = connection['status']?.toString().toLowerCase();
        if (status == 'accepted') return ProfileConnectionStatus.connected;
        if (status == 'pending') {
          // The sender is `member_id`. If that is the viewer, the viewer asked.
          return connection['member_id']?.toString() == viewerId
              ? ProfileConnectionStatus.pendingSent
              : ProfileConnectionStatus.pendingReceived;
        }
        // Any other status (e.g. rejected/removed) reads as no connection, which
        // is what the portal's fall-through does.
        return ProfileConnectionStatus.none;
      }

      // ── 2. Legacy invitations ────────────────────────────────────────────
      final invitation = await _supabase
          .from('builder_network_invitations')
          .select('status, builder_id, invited_user_id')
          .or(
            'and(builder_id.eq.$viewerId,invited_user_id.eq.$profileUserId),'
            'and(builder_id.eq.$profileUserId,invited_user_id.eq.$viewerId)',
          )
          .inFilter('status', ['pending', 'accepted'])
          .maybeSingle();

      if (invitation != null) {
        final status = invitation['status']?.toString().toLowerCase();
        if (status == 'accepted') return ProfileConnectionStatus.connected;
        // On this table the *inviter* is `builder_id`.
        return invitation['builder_id']?.toString() == viewerId
            ? ProfileConnectionStatus.pendingSent
            : ProfileConnectionStatus.pendingReceived;
      }

      return ProfileConnectionStatus.none;
    } catch (e) {
      debugPrint('ProfileConnectionService.getStatus failed: $e');
      return ProfileConnectionStatus.none;
    }
  }

  // ── Writes (Phase 6) ───────────────────────────────────────────────────────
  //
  // RLS, verified — no backend change needed:
  //   builder_networks              FOR ALL USING (builder_id = auth.uid()
  //                                              OR member_id = auth.uid())
  //   builder_network_invitations   symmetric policies
  //   notifications                 FOR INSERT TO authenticated
  //                                 WITH CHECK (auth.uid() IS NOT NULL)
  //
  // For a `FOR ALL` policy Postgres applies USING as the insert check, and the
  // sender is always `member_id`, so the upsert below passes. The cross-user
  // notification insert is permitted outright.

  /// Sends a connection request.
  ///
  /// A direct port of `handleNetworkAction`'s `none` branch
  /// (UserProfile.tsx:612-650). Two details are load-bearing:
  ///
  /// * **UPSERT, not insert**, on `(builder_id, member_id)`. A prior removed or
  ///   rejected row still occupies that unique pair, so an insert would fail with
  ///   23505 and the user could never reconnect after a removal.
  /// * **The recipient is `builder_id`, the sender is `member_id`** — regardless of
  ///   either party's role. Reversing them still satisfies RLS (both sides are
  ///   permitted) but inverts the meaning, and the recipient would see nothing.
  Future<ConnectionWriteError?> sendRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    final guard = _writeGuard(viewerId, profileUserId);
    if (guard != null) return guard;

    try {
      final sender = await _senderContext(viewerId!);

      await _supabase.from('builder_networks').upsert({
        'builder_id': profileUserId,
        'member_id': viewerId,
        'member_type': sender.userType ?? 'individual',
        'status': 'pending',
      }, onConflict: 'builder_id,member_id');

      // Best-effort, exactly as the portal treats it (UserProfile.tsx:642-644):
      // it logs a failed notification and carries on. The connection is the
      // outcome the user asked for; a missing notification must not undo it.
      try {
        await _supabase.from('notifications').insert({
          'user_id': profileUserId,
          'type': 'builder_network_addition',
          'title': 'Network Connection Request',
          'message': '${sender.name} wants to connect with you',
          'data': {'sender_id': viewerId, 'sender_name': sender.name},
        });
      } catch (e) {
        debugPrint('ProfileConnectionService: notification insert failed: $e');
      }

      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.sendRequest failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Cancels a pending request in either direction.
  ///
  /// UserProfile.tsx:651-675. Deletes from **both** tables: a legacy invitation
  /// left behind would make `getStatus` report `pendingSent` again on the next
  /// load, so the request would appear to un-cancel itself.
  Future<ConnectionWriteError?> cancelRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    final guard = _writeGuard(viewerId, profileUserId);
    if (guard != null) return guard;

    try {
      await _supabase
          .from('builder_networks')
          .delete()
          .or(
            'and(builder_id.eq.$viewerId,member_id.eq.$profileUserId),'
            'and(builder_id.eq.$profileUserId,member_id.eq.$viewerId)',
          )
          .eq('status', 'pending');

      await _supabase
          .from('builder_network_invitations')
          .delete()
          .or(
            'and(builder_id.eq.$viewerId,invited_user_id.eq.$profileUserId),'
            'and(builder_id.eq.$profileUserId,invited_user_id.eq.$viewerId)',
          )
          .eq('status', 'pending');

      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.cancelRequest failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Accepts an incoming request.
  ///
  /// UserProfile.tsx:676-725. Two paths, in this order:
  ///
  /// 1. A unified peer row in `builder_networks` where the viewer is the
  ///    recipient — flip it to `accepted`.
  /// 2. Otherwise a legacy `builder_network_invitations` row — mark it accepted
  ///    **and** upsert the corresponding `builder_networks` row, because that is
  ///    the table every count and list reads. Marking only the invitation would
  ///    leave the connection invisible everywhere.
  Future<ConnectionWriteError?> acceptRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    final guard = _writeGuard(viewerId, profileUserId);
    if (guard != null) return guard;

    try {
      final existing = await _supabase
          .from('builder_networks')
          .select('id')
          .eq('builder_id', viewerId!)
          .eq('member_id', profileUserId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('builder_networks')
            .update({'status': 'accepted'})
            .eq('id', existing['id']);
        return null;
      }

      final invitation = await _supabase
          .from('builder_network_invitations')
          .select('id, member_type')
          .eq('builder_id', profileUserId)
          .eq('invited_user_id', viewerId)
          .eq('status', 'pending')
          .maybeSingle();

      if (invitation == null) {
        // Nothing to accept — the request was withdrawn, or the status was stale.
        return ConnectionWriteError.nothingToAccept;
      }

      await _supabase
          .from('builder_network_invitations')
          .update({'status': 'accepted'})
          .eq('id', invitation['id']);

      await _supabase.from('builder_networks').upsert({
        'builder_id': profileUserId,
        'member_id': viewerId,
        'member_type': invitation['member_type'] ?? 'individual',
        'status': 'accepted',
      }, onConflict: 'builder_id,member_id');

      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.acceptRequest failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  // ── Spec F additions ──────────────────────────────────────────────────────

  /// Declines an incoming request or invitation.
  ///
  /// The counterpart to [acceptRequest], and the operation this file was missing:
  /// [cancelRequest] is the *sender* withdrawing, which deletes the row. A decline
  /// is the *recipient* refusing, and the portal marks rather than deletes
  /// (`InfluencerCollaborationHub.tsx:188-190`) so the sender can see it was
  /// declined rather than watching their request silently vanish.
  ///
  /// Both tables are handled, in [acceptRequest]'s order and for its reason: a
  /// leftover pending row in the other table would make `getStatus` report a live
  /// request again on the next load.
  ///
  /// `builder_networks` has no `rejected` value in play for this app's reads —
  /// `getStatus` treats anything that is not `pending`/`accepted` as no connection
  /// (see its own comment) — so `'rejected'` there is both accurate and inert.
  Future<ConnectionWriteError?> declineRequest({
    required String? viewerId,
    required String profileUserId,
  }) async {
    final guard = _writeGuard(viewerId, profileUserId);
    if (guard != null) return guard;

    try {
      var touched = false;

      final peer = await _supabase
          .from('builder_networks')
          .select('id')
          .eq('builder_id', viewerId!)
          .eq('member_id', profileUserId)
          .eq('status', 'pending')
          .maybeSingle();

      if (peer != null) {
        await _supabase
            .from('builder_networks')
            .update({'status': 'rejected'})
            .eq('id', peer['id']);
        touched = true;
      }

      final invitation = await _supabase
          .from('builder_network_invitations')
          .select('id')
          .eq('builder_id', profileUserId)
          .eq('invited_user_id', viewerId)
          .eq('status', 'pending')
          .maybeSingle();

      if (invitation != null) {
        await _supabase
            .from('builder_network_invitations')
            .update({'status': 'rejected'})
            .eq('id', invitation['id']);
        touched = true;
      }

      // Same signal `acceptRequest` gives: there was nothing pending, so the
      // caller should refresh rather than report success.
      if (!touched) return ConnectionWriteError.nothingToAccept;
      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.declineRequest failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Leaves an *accepted* network relationship — the portal's
  /// `handleLeaveNetwork` (`NetworkMemberships.tsx`), which marks the row
  /// `'removed'` rather than deleting it, the same way [declineRequest] marks
  /// rather than deletes: the other party can still see the relationship
  /// ended instead of it silently vanishing.
  ///
  /// [relationshipId] is the `builder_networks.id` of the row itself — the
  /// caller already has it from the row being displayed, so this is a single
  /// `UPDATE ... WHERE id = :id`, the same one-column-filter pattern
  /// `NetworkService.updateLeadStatus` uses; RLS
  /// (`builder_id = auth.uid() OR member_id = auth.uid()`) is what actually
  /// restricts this to a row the caller is a party to; both `builder_id` and
  /// `member_id` can leave. This works for a `peerConnection` row exactly as
  /// well as for a genuine owned-member/joined-network one — "leave" is
  /// meaningful for any accepted relationship, not just a classified one.
  Future<ConnectionWriteError?> leaveNetwork(String relationshipId) async {
    if (relationshipId.isEmpty) return ConnectionWriteError.notAllowed;
    try {
      await _supabase
          .from('builder_networks')
          .update({'status': 'removed'})
          .eq('id', relationshipId);
      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.leaveNetwork failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Declines one invitation by its row id.
  ///
  /// `InfluencerCollaborationHub.tsx:186-191` — the Collaboration Hub acts on a row
  /// it already has, and does not know or need the other party's user id.
  Future<ConnectionWriteError?> declineInvitation({
    required String? viewerId,
    required NetworkInvitation invitation,
  }) async {
    if (viewerId == null || viewerId.isEmpty) {
      return ConnectionWriteError.notAllowed;
    }
    // An expired invitation must not be actionable — the contract's explicit
    // requirement, and the reason `isActionable` exists.
    if (!invitation.isActionable) return ConnectionWriteError.nothingToAccept;

    try {
      await _supabase
          .from('builder_network_invitations')
          .update({'status': 'rejected'})
          .eq('id', invitation.id);
      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.declineInvitation failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Accepts one invitation by its row id.
  ///
  /// `InfluencerCollaborationHub.tsx:148-170`: mark the invitation accepted, then
  /// insert the `builder_networks` row. The insert is an **upsert** here for the
  /// reason `sendRequest` documents — a prior removed or rejected row still holds
  /// the `(builder_id, member_id)` pair, and a plain insert would fail with 23505.
  /// The portal's plain insert is what would break on a re-invite.
  Future<ConnectionWriteError?> acceptInvitation({
    required String? viewerId,
    required NetworkInvitation invitation,
  }) async {
    if (viewerId == null || viewerId.isEmpty) {
      return ConnectionWriteError.notAllowed;
    }
    if (!invitation.isActionable) return ConnectionWriteError.nothingToAccept;

    try {
      await _supabase
          .from('builder_network_invitations')
          .update({'status': 'accepted'})
          .eq('id', invitation.id);

      await _supabase.from('builder_networks').upsert({
        'builder_id': invitation.builderId,
        'member_id': viewerId,
        'member_type': invitation.memberType,
        'status': 'accepted',
      }, onConflict: 'builder_id,member_id');

      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.acceptInvitation failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Every invitation this user is either side of.
  ///
  /// Two reads, matching the two portal components:
  ///
  ///   * received — `invited_user_id = me`
  ///     (`InfluencerCollaborationHub.tsx:109-112`);
  ///   * sent     — `builder_id = me`
  ///     (`BuilderNetworkInvitations.tsx:145-148`).
  ///
  /// Both portal queries filter `status = 'pending'`. This one does **not**, and
  /// filters client-side instead, because a builder needs to see that an invitation
  /// was rejected — otherwise a declined invite simply disappears and they re-send
  /// it. `isActionable` is what gates the buttons.
  ///
  /// Names are resolved in one batched `profiles` read, the same shape
  /// `ProjectShareService` uses. Never throws: an empty inbox is a safe
  /// degradation for a list, and the caller shows its own error state on null.
  Future<NetworkInvitationInbox> listInvitations(String? viewerId) async {
    if (viewerId == null || viewerId.isEmpty) {
      return NetworkInvitationInbox.empty;
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('builder_network_invitations')
            .select(NetworkInvitation.columns)
            .eq('invited_user_id', viewerId)
            .order('created_at', ascending: false),
        _supabase
            .from('builder_network_invitations')
            .select(NetworkInvitation.columns)
            .eq('builder_id', viewerId)
            .order('created_at', ascending: false),
      ]);

      final receivedRows = List<Map<String, dynamic>>.from(results[0]);
      final sentRows = List<Map<String, dynamic>>.from(results[1]);

      // The counterpart is the builder on a received row and the invitee on a sent
      // one. Off-platform sends have no invited_user_id at all.
      final ids = <String>{
        for (final row in receivedRows) row['builder_id'].toString(),
        for (final row in sentRows)
          if (row['invited_user_id'] != null) row['invited_user_id'].toString(),
      }..remove('');

      final names = await _profileSummaries(ids);

      return NetworkInvitationInbox(
        received: receivedRows
            .map((row) {
              final profile = names[row['builder_id'].toString()];
              return NetworkInvitation.fromSupabase(
                row,
                counterpartName: profile?.name,
                counterpartAvatarUrl: profile?.avatarUrl,
                counterpartUserType: profile?.userType,
              );
            })
            .toList(growable: false),
        sent: sentRows
            .map((row) {
              final profile = names[row['invited_user_id']?.toString()];
              return NetworkInvitation.fromSupabase(
                row,
                counterpartName: profile?.name,
                counterpartAvatarUrl: profile?.avatarUrl,
                counterpartUserType: profile?.userType,
              );
            })
            .toList(growable: false),
      );
    } catch (e) {
      debugPrint('ProfileConnectionService.listInvitations failed: $e');
      return NetworkInvitationInbox.empty;
    }
  }

  /// Sends a builder's network invitation.
  ///
  /// `BuilderNetworkInvitations.tsx` has two insert paths and this covers both:
  /// `:202-208` when a user was picked from search, `:264-273` when only an email
  /// or phone is known. The difference is which of `invited_user_id` / `email` /
  /// `phone` is populated; everything else is identical.
  ///
  /// Distinct from [sendRequest], which is the peer-to-peer connect on a profile
  /// page: that writes `builder_networks` directly with the *sender's* own
  /// `user_type` and no message. This writes an invitation with a chosen
  /// `member_type` and an optional note, which is what the builder's form collects.
  ///
  /// `expires_at` is left to the column default of `now() + 7 days` — the portal
  /// does not send it either, and hard-coding a window client-side would let the
  /// two platforms disagree.
  Future<ConnectionWriteError?> sendBuilderInvite({
    required String? viewerId,
    required String memberType,
    String? invitedUserId,
    String? email,
    String? phone,
    String? message,
  }) async {
    if (viewerId == null || viewerId.isEmpty) {
      return ConnectionWriteError.notAllowed;
    }
    if (invitedUserId == viewerId) return ConnectionWriteError.notAllowed;
    // CHECK-constrained: anything else is a 23514.
    if (!isValidNetworkMemberType(memberType)) {
      return ConnectionWriteError.notAllowed;
    }
    // The row is meaningless without a recipient, and all three columns are
    // nullable so the database would accept one.
    final hasRecipient =
        (invitedUserId?.isNotEmpty ?? false) ||
        (email?.isNotEmpty ?? false) ||
        (phone?.isNotEmpty ?? false);
    if (!hasRecipient) return ConnectionWriteError.notAllowed;

    try {
      final sender = await _senderContext(viewerId);

      await _supabase.from('builder_network_invitations').insert({
        'builder_id': viewerId,
        'invited_user_id': invitedUserId,
        'email': email,
        'phone': phone,
        'member_type': memberType,
        'invitation_message': message,
      });

      // Only when there is an account to notify. The portal resolves an email back
      // to a user before notifying (`:277-287`); here the id is already known when
      // it exists, and an off-platform invite simply has nobody to notify yet.
      if (invitedUserId != null && invitedUserId.isNotEmpty) {
        try {
          await _supabase.from('notifications').insert({
            'user_id': invitedUserId,
            'type': 'builder_network_addition',
            'title': 'Network Invitation',
            'message':
                '${sender.name} invited you to join their network as a '
                '${networkMemberTypeLabel(memberType).toLowerCase()}',
            'data': {
              'sender_id': viewerId,
              'sender_name': sender.name,
              'member_type': memberType,
            },
          });
        } catch (e) {
          // Best-effort, as everywhere else in this file: the invitation is the
          // outcome the builder asked for.
          debugPrint(
            'ProfileConnectionService: invite notification failed: $e',
          );
        }
      }

      return null;
    } catch (e) {
      debugPrint('ProfileConnectionService.sendBuilderInvite failed: $e');
      return ConnectionWriteError.failed;
    }
  }

  /// Finds people a builder could invite.
  ///
  /// `BuilderNetworkInvitations.tsx:93-99` searches `profiles` by display name and
  /// filters to the two invitable roles. Reads `profiles_public` rather than
  /// `profiles`: it is the view this app uses everywhere for looking at other
  /// people, and it already excludes blocked and unapproved accounts — which the
  /// portal's raw `profiles` read does not.
  ///
  /// Returns an empty list below two characters, so an empty search box does not
  /// pull the whole table.
  Future<List<InviteeSuggestion>> searchInvitees(String term) async {
    final query = term.trim();
    if (query.length < 2) return const [];

    try {
      final rows = await _supabase
          .from('profiles_public')
          .select('user_id, display_name, company_name, avatar_url, user_type')
          .inFilter(
            'user_type',
            kNetworkMemberTypes.map((t) => t.value).toList(),
          )
          .ilike('display_name', '%$query%')
          .limit(10);

      return List<Map<String, dynamic>>.from(rows)
          .map(
            (row) => InviteeSuggestion(
              userId: row['user_id'].toString(),
              name: (row['company_name']?.toString().isNotEmpty ?? false)
                  ? row['company_name'].toString()
                  : (row['display_name']?.toString() ?? 'Unnamed'),
              userType: row['user_type']?.toString() ?? '',
              avatarUrl: row['avatar_url']?.toString(),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('ProfileConnectionService.searchInvitees failed: $e');
      return const [];
    }
  }

  /// Name, avatar and role for a set of user ids, in one read.
  Future<Map<String, _ProfileSummary>> _profileSummaries(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};
    try {
      final rows = await _supabase
          .from('profiles_public')
          .select('user_id, display_name, company_name, avatar_url, user_type')
          .inFilter('user_id', userIds.toList());

      return {
        for (final row in List<Map<String, dynamic>>.from(rows))
          row['user_id'].toString(): _ProfileSummary(
            name: (row['company_name']?.toString().isNotEmpty ?? false)
                ? row['company_name'].toString()
                : (row['display_name']?.toString() ?? 'Unnamed'),
            avatarUrl: row['avatar_url']?.toString(),
            userType: row['user_type']?.toString(),
          ),
      };
    } catch (e) {
      // A missing name is cosmetic; the invitation still lists and still acts.
      debugPrint('ProfileConnectionService._profileSummaries failed: $e');
      return const {};
    }
  }

  /// Shared pre-flight for every write.
  @visibleForTesting
  static ConnectionWriteError? writeGuardFor({
    required String? viewerId,
    required String profileUserId,
  }) => _writeGuard(viewerId, profileUserId);

  static ConnectionWriteError? _writeGuard(
    String? viewerId,
    String profileUserId,
  ) {
    if (viewerId == null || viewerId.isEmpty) {
      return ConnectionWriteError.notAllowed;
    }
    if (profileUserId.isEmpty || viewerId == profileUserId) {
      return ConnectionWriteError.notAllowed;
    }
    return null;
  }

  /// The sender's display name and role, for the notification body and
  /// `member_type`.
  ///
  /// The portal reads `company_name, display_name` and falls back
  /// `company_name || display_name || 'Someone'` (UserProfile.tsx:603-610).
  /// `UserProfileService.fetchProfilesByIds` is not reused here because its
  /// projection omits `company_name`, which would silently degrade a company's
  /// notification to a personal name.
  Future<({String name, String? userType})> _senderContext(
    String viewerId,
  ) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select('display_name, company_name, user_type')
          .eq('user_id', viewerId)
          .maybeSingle();

      final company = (row?['company_name'] as String?)?.trim();
      final display = (row?['display_name'] as String?)?.trim();
      final name = (company != null && company.isNotEmpty)
          ? company
          : (display != null && display.isNotEmpty ? display : 'Someone');

      return (name: name, userType: row?['user_type'] as String?);
    } catch (e) {
      debugPrint('ProfileConnectionService._senderContext failed: $e');
      // The request still goes out; only the notification wording is generic.
      return (name: 'Someone', userType: null);
    }
  }
}

/// Why a connection write failed.
enum ConnectionWriteError {
  /// Anonymous viewer, or a self-connection. Blocked before the round-trip.
  notAllowed,

  /// Accept found no pending row — withdrawn, or the local status was stale.
  nothingToAccept,

  /// Anything else.
  failed,
}

/// One person a builder could invite.
class InviteeSuggestion {
  const InviteeSuggestion({
    required this.userId,
    required this.name,
    required this.userType,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String userType;
  final String? avatarUrl;
}

/// Internal: the three profile fields the invitation list needs.
class _ProfileSummary {
  const _ProfileSummary({required this.name, this.avatarUrl, this.userType});

  final String name;
  final String? avatarUrl;
  final String? userType;
}
