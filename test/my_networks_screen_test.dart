// My Networks — the "Total Connections" / "Requests Sent" / "Requests
// Received" stat tiles. Fixes a bug where all three rendered as plain,
// non-interactive counters (no `onTap` anywhere) while the portal's
// `NetworkMemberships.tsx` renders them as tabs that switch the list card
// below between Connections / Sent / Received. Two of the three lists (Sent,
// Received) had no rendering path in the Flutter screen at all, so tapping
// those tiles previously did nothing and there was no way to view or act on
// a pending peer-connection request from this screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/network_relationship.dart';
import 'package:propcid_app/screens/network/my_networks_screen.dart';

NetworkRelationship _relationship({
  required NetworkRelationshipKind kind,
  required String id,
  String name = 'Jordan Lee',
}) {
  return NetworkRelationship(
    id: id,
    builderId: 'b',
    memberId: 'm',
    memberType: 'broker',
    status: kind == NetworkRelationshipKind.outgoingPeerRequest ||
            kind == NetworkRelationshipKind.incomingPeerRequest
        ? 'pending'
        : 'accepted',
    viewerId: 'viewer-1',
    kind: kind,
    counterpartUserId: 'counterpart-$id',
    counterpartDisplayName: name,
  );
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets(
    'defaults to the Total Connections view, matching the pre-existing '
    'behaviour when no tile has been tapped',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          MyNetworksBody(
            relationships: [
              _relationship(
                kind: NetworkRelationshipKind.ownedNetworkMember,
                id: 'owned-1',
                name: 'Owned Member',
              ),
              _relationship(
                kind: NetworkRelationshipKind.outgoingPeerRequest,
                id: 'sent-1',
                name: 'Sent To',
              ),
            ],
            loading: false,
            failed: false,
          ),
        ),
      );

      expect(find.text('Current Network Members'), findsOneWidget);
      expect(find.text('Owned Member'), findsOneWidget);
      // The Sent row must not leak into the default (Total Connections) view.
      expect(find.text('Sent To'), findsNothing);
    },
  );

  testWidgets(
    'tapping Requests Sent shows the sent list and its count matches',
    (tester) async {
      NetworkRelationship? cancelled;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              var tile = MyNetworksTile.total;
              return StatefulBuilder(
                builder: (context, setInner) {
                  return MyNetworksBody(
                    relationships: [
                      _relationship(
                        kind: NetworkRelationshipKind.outgoingPeerRequest,
                        id: 'sent-1',
                        name: 'Alex Sender',
                      ),
                    ],
                    loading: false,
                    failed: false,
                    activeTile: tile,
                    onSelectTile: (t) => setInner(() => tile = t),
                    onCancelSent: (r) => cancelled = r,
                  );
                },
              );
            },
          ),
        ),
      );

      // Count on the tile itself.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Requests Sent'), findsWidgets);

      await tester.tap(find.text('Requests Sent').first);
      await tester.pumpAndSettle();

      expect(find.text('Alex Sender'), findsOneWidget);
      expect(find.text('Cancel Request'), findsOneWidget);

      await tester.tap(find.text('Cancel Request'));
      await tester.pump();

      expect(cancelled?.id, 'sent-1');
    },
  );

  testWidgets(
    'tapping Requests Received shows the received list with Accept/Decline',
    (tester) async {
      NetworkRelationship? accepted;
      NetworkRelationship? declined;
      var tile = MyNetworksTile.total;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return MyNetworksBody(
                relationships: [
                  _relationship(
                    kind: NetworkRelationshipKind.incomingPeerRequest,
                    id: 'received-1',
                    name: 'Casey Receiver',
                  ),
                ],
                loading: false,
                failed: false,
                activeTile: tile,
                onSelectTile: (t) => setState(() => tile = t),
                onAcceptReceived: (r) => accepted = r,
                onDeclineReceived: (r) => declined = r,
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Requests Received').first);
      await tester.pumpAndSettle();

      expect(find.text('Casey Receiver'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(declined?.id, 'received-1');
      expect(accepted, isNull);
    },
  );

  testWidgets(
    'tapping Total Connections switches back from Sent/Received',
    (tester) async {
      var tile = MyNetworksTile.sent;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return MyNetworksBody(
                relationships: [
                  _relationship(
                    kind: NetworkRelationshipKind.peerConnection,
                    id: 'peer-1',
                    name: 'Peer Person',
                  ),
                  _relationship(
                    kind: NetworkRelationshipKind.outgoingPeerRequest,
                    id: 'sent-1',
                    name: 'Sent Person',
                  ),
                ],
                loading: false,
                failed: false,
                activeTile: tile,
                onSelectTile: (t) => setState(() => tile = t),
              );
            },
          ),
        ),
      );

      // Starts on Sent (as configured).
      expect(find.text('Sent Person'), findsOneWidget);
      expect(find.text('Peer Person'), findsNothing);

      await tester.tap(find.text('Total Connections').first);
      await tester.pumpAndSettle();

      expect(find.text('Peer Person'), findsOneWidget);
      expect(find.text('Sent Person'), findsNothing);
    },
  );

  testWidgets('an empty sent list shows an honest empty state, not a zero list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MyNetworksBody(
          relationships: const [],
          loading: false,
          failed: false,
          activeTile: MyNetworksTile.sent,
        ),
      ),
    );

    expect(find.text('No Pending Requests'), findsOneWidget);
  });
}
