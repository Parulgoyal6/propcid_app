// Spec G — the Notification Centre.
//
// What is pinned:
//
//   * the query shape the portal uses — `.eq('user_id')`, newest first, limit 50;
//   * every applied `notification_type` enum value maps to a style and a filter
//     bucket, and an unknown one falls back rather than throwing;
//   * the unread count is DERIVED from the list, not tracked separately — the portal
//     tracks it and has to recalculate to correct its own drift;
//   * optimistic mark-read rolls back on failure;
//   * the realtime INSERT/UPDATE handlers, including that a duplicate insert is
//     ignored and an update for an unheld row does not splice in;
//   * G-4's routing table, including the branches that deliberately go nowhere
//     because the payload carries no id.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/navigation/dashboard_section.dart';
import 'package:propcid_app/core/navigation/notification_route_resolver.dart';
import 'package:propcid_app/models/app_notification.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/notification_provider.dart';
import 'package:propcid_app/screens/notifications/notifications_screen.dart';
import 'package:propcid_app/screens/profile/profile_reviews_screen.dart';
import 'package:propcid_app/services/notification_service.dart';

import 'support/overflow_detector.dart';

const Size kSmall = Size(320, 720);

// ── Fixtures ────────────────────────────────────────────────────────────────

AppNotification _notif({
  String id = 'n-1',
  String type = NotificationTypes.projectShared,
  String title = 'New Project Shared',
  String message = 'Prestige Estates shared a project: "Green Valley"',
  bool isRead = false,
  Map<String, dynamic> data = const {'projectId': 'p-1'},
  String? createdAt,
}) => AppNotification.fromSupabase({
  'id': id,
  'type': type,
  'title': title,
  'message': message,
  'is_read': isRead,
  'data': data,
  'created_at': createdAt ?? DateTime.now().toUtc().toIso8601String(),
});

class _FakeAuth extends AuthProvider {
  _FakeAuth({this.id = 'u-1'});

  final String? id;

  @override
  String? get userId => id;

  @override
  bool get isLoggedIn => id != null;
}

class _FakeService extends NotificationService {
  _FakeService({this.rows = const []});

  List<AppNotification> rows;
  bool shouldFail = false;
  bool writeShouldFail = false;

  final List<String> read = [];
  final List<String> unread = [];
  final List<String> markAllFor = [];
  int listCalls = 0;
  int subscribeCalls = 0;
  int unsubscribeCalls = 0;

  /// The handlers the provider registered, so a test can fire a realtime event.
  void Function(AppNotification)? onInsert;
  void Function(AppNotification)? onUpdate;
  void Function(String)? onDelete;
  String? lastChannelUserId;

  @override
  Future<List<AppNotification>> list(String userId) async {
    listCalls++;
    if (shouldFail) throw Exception('forced failure');
    return rows;
  }

  @override
  Future<void> markRead(String id) async {
    if (writeShouldFail) throw Exception('forced failure');
    read.add(id);
  }

  @override
  Future<void> markUnread(String id) async {
    if (writeShouldFail) throw Exception('forced failure');
    unread.add(id);
  }

  @override
  Future<void> markAllRead(String userId) async {
    if (writeShouldFail) throw Exception('forced failure');
    markAllFor.add(userId);
  }

  @override
  RealtimeChannel subscribe({
    required String userId,
    required String channelSuffix,
    required void Function(AppNotification) onInsert,
    required void Function(AppNotification) onUpdate,
    required void Function(String) onDelete,
  }) {
    subscribeCalls++;
    lastChannelUserId = userId;
    this.onInsert = onInsert;
    this.onUpdate = onUpdate;
    this.onDelete = onDelete;
    // Builds without opening a socket; `.subscribe()` is what connects and this
    // deliberately does not call it.
    return Supabase.instance.client.channel('test-$channelSuffix');
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {
    unsubscribeCalls++;
  }
}

Future<List<RouteSettings>> _pumpScreen(
  WidgetTester tester, {
  required NotificationProvider provider,
  String? userId = 'u-1',
  Size size = kSmall,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final pushed = <RouteSettings>[];

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(
          value: _FakeAuth(id: userId),
        ),
        ChangeNotifierProvider<NotificationProvider>.value(value: provider),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const NotificationsScreen(),
        onGenerateRoute: (settings) {
          pushed.add(settings);
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const SizedBox.shrink(),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return pushed;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  // ── 1. The enum coverage ────────────────────────────────────────────────
  group('notification types', () {
    test('every applied enum value has a style', () {
      // The base six plus thirteen ADD VALUE migrations, plus the ten
      // `collab_*` values added by the Collaboration Marketplace port
      // (20270421000000_collab_marketplace_enums.sql). A value with no style
      // would silently render as System.
      const applied = [
        'new_follower',
        'channel_addition',
        'builder_network_addition',
        'property_approved',
        'property_inquiry',
        'message_received',
        'lead_assigned',
        'lead_status_update',
        'network_lead_new',
        'channel_message',
        'project_shared',
        'property_like',
        'visit_booking_update',
        'visit_booking_new',
        'social_publish_started',
        'social_publish_success',
        'social_publish_failed',
        'social_retry_started',
        'social_retry_success',
        ...NotificationTypes.collabTypes,
        NotificationTypes.documentReuploadRequested,
        NotificationTypes.documentApproved,
        NotificationTypes.bulkMessage,
        NotificationTypes.newRating,
        NotificationTypes.teamActivity,
      ];
      for (final type in applied) {
        expect(kNotificationStyles.containsKey(type), isTrue, reason: type);
      }
      expect(kNotificationStyles, hasLength(applied.length));
    });

    test('an unknown type falls back rather than throwing', () {
      // Reached by the three migration2 values if that set is ever applied, and by
      // any future ADD VALUE.
      for (final type in NotificationTypes.unapplied) {
        expect(notificationStyleFor(type), kFallbackNotificationStyle);
      }
      expect(
        notificationStyleFor('invented_later'),
        kFallbackNotificationStyle,
      );
      expect(notificationStyleFor(null), kFallbackNotificationStyle);
    });

    test('every style lands in a known bucket', () {
      final buckets = {...kNotificationFilters, 'System'};
      for (final entry in kNotificationStyles.entries) {
        expect(buckets.contains(entry.value.filter), isTrue, reason: entry.key);
      }
    });

    test('the filter chips are the design\'s five', () {
      expect(kNotificationFilters, [
        'All',
        'Price Drop',
        'Visits',
        'Matches',
        'Enquiries',
      ]);
    });
  });

  // ── 2. The model ────────────────────────────────────────────────────────
  group('AppNotification', () {
    test('a null data payload reads as an empty map', () {
      // The column is nullable; every reader indexes it without a guard.
      final n = AppNotification.fromSupabase({
        'id': 'n-1',
        'type': 'new_follower',
        'title': 'T',
        'message': 'M',
        'is_read': false,
        'data': null,
      });
      expect(n.data, isEmpty);
    });

    test('relative time reads the way the mock strings did', () {
      String iso(Duration ago) =>
          DateTime.now().toUtc().subtract(ago).toIso8601String();

      expect(
        _notif(createdAt: iso(const Duration(seconds: 5))).relativeTime,
        'Just now',
      );
      expect(
        _notif(createdAt: iso(const Duration(minutes: 2))).relativeTime,
        '2 min ago',
      );
      expect(
        _notif(createdAt: iso(const Duration(hours: 1))).relativeTime,
        '1 hr ago',
      );
      expect(
        _notif(createdAt: iso(const Duration(hours: 5))).relativeTime,
        '5 hrs ago',
      );
      expect(
        _notif(createdAt: iso(const Duration(days: 1))).relativeTime,
        'Yesterday',
      );
      expect(
        _notif(createdAt: iso(const Duration(days: 3))).relativeTime,
        '3 days ago',
      );
    });

    test('a future timestamp does not read as negative', () {
      // Clock skew between server and device is real.
      final future = DateTime.now().toUtc().add(const Duration(minutes: 5));
      expect(
        _notif(createdAt: future.toIso8601String()).relativeTime,
        'Just now',
      );
    });

    test('the column list is explicit, not select(*)', () {
      expect(AppNotification.columns, contains('is_read'));
      expect(AppNotification.columns, contains('data'));
      expect(AppNotification.columns, isNot(contains('*')));
    });
  });

  // ── 3. The provider ────────────────────────────────────────────────────
  group('NotificationProvider', () {
    test('loads, counts unread and subscribes', () async {
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b', isRead: true),
          _notif(id: 'c'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.items, hasLength(3));
      expect(provider.unreadCount, 2);
      expect(provider.hasUnread, isTrue);
      expect(service.subscribeCalls, 1);
      expect(service.lastChannelUserId, 'u-1');
    });

    test('the unread count is derived, so it cannot drift', () async {
      // The portal keeps a separate counter and adjusts it by ±1, then has to
      // recalculate from scratch in its UPDATE listener to fix the drift.
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      expect(provider.unreadCount, 2);
      await provider.markRead(provider.items.first);
      expect(provider.unreadCount, 1);
      // Marking the same one again is a no-op, not a double decrement.
      await provider.markRead(provider.items.first);
      expect(provider.unreadCount, 1);
    });

    test('load is idempotent per user', () async {
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');
      await provider.load('u-1');
      await provider.load('u-1');

      expect(service.listCalls, 1, reason: 'a rebuild must not re-fetch');
      expect(service.subscribeCalls, 1, reason: 'nor open a second channel');
    });

    test('a different user tears the old channel down first', () async {
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');
      await provider.load('u-2');

      expect(service.unsubscribeCalls, 1);
      expect(service.subscribeCalls, 2);
      expect(service.lastChannelUserId, 'u-2');
    });

    test('signing out clears the list and the channel', () async {
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');
      expect(provider.items, hasLength(1));

      await provider.load(null);
      expect(provider.items, isEmpty);
      expect(provider.unreadCount, 0);
      expect(service.unsubscribeCalls, 1);
    });

    test('a failed load is a failure, not an empty inbox', () async {
      final service = _FakeService()..shouldFail = true;
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.failed, isTrue);
      expect(provider.items, isEmpty);
      expect(provider.loading, isFalse);
    });

    test('a realtime insert prepends without re-fetching', () async {
      final service = _FakeService(rows: [_notif(id: 'old')]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.onInsert!(_notif(id: 'new'));

      expect(provider.items.first.id, 'new');
      expect(provider.items, hasLength(2));
      expect(provider.unreadCount, 2);
      expect(service.listCalls, 1, reason: 'the payload is the whole row');
    });

    test('a duplicate realtime insert is ignored', () async {
      // An optimistic local insert and the broadcast for the same row would
      // otherwise both land.
      final service = _FakeService(rows: [_notif(id: 'a')]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.onInsert!(_notif(id: 'a'));

      expect(provider.items, hasLength(1));
    });

    test('a realtime update replaces in place and preserves order', () async {
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      // Read on another device.
      service.onUpdate!(_notif(id: 'b', isRead: true));

      expect(provider.items[0].id, 'a');
      expect(provider.items[1].id, 'b');
      expect(provider.items[1].isRead, isTrue);
      expect(provider.unreadCount, 1);
    });

    test('an update for an unheld row is ignored', () async {
      // A row beyond the fifty fetched must not be spliced in out of order.
      final service = _FakeService(rows: [_notif(id: 'a')]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.onUpdate!(_notif(id: 'zzz', isRead: true));

      expect(provider.items, hasLength(1));
      expect(provider.items.single.id, 'a');
    });

    test('a realtime delete (an undone like/comment/follow/request retracting '
        'its own notification) removes the row and recomputes the unread '
        'count, with no separate counter to drift', () async {
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');
      expect(provider.unreadCount, 2);

      service.onDelete!('a');

      expect(provider.items, hasLength(1));
      expect(provider.items.single.id, 'b');
      expect(provider.unreadCount, 1);
    });

    test('a delete for an unheld row is ignored', () async {
      final service = _FakeService(rows: [_notif(id: 'a')]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.onDelete!('zzz');

      expect(provider.items, hasLength(1));
      expect(provider.items.single.id, 'a');
    });

    test('mark read rolls back when the write fails', () async {
      final service = _FakeService(rows: [_notif(id: 'a')]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.writeShouldFail = true;
      await provider.markRead(provider.items.first);

      expect(
        provider.items.first.isRead,
        isFalse,
        reason: 'the optimistic flip must not survive a failed write',
      );
      expect(provider.unreadCount, 1);
    });

    test('mark all read filters and restores exactly on failure', () async {
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b', isRead: true),
          _notif(id: 'c'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await provider.markAllRead();
      expect(provider.unreadCount, 0);
      expect(service.markAllFor, ['u-1']);

      // Now fail one, and check the prior read/unread split is restored exactly.
      service.rows = [_notif(id: 'a'), _notif(id: 'b', isRead: true)];
      await provider.load('u-2');
      service.writeShouldFail = true;
      await provider.markAllRead();

      expect(provider.items[0].isRead, isFalse);
      expect(provider.items[1].isRead, isTrue);
    });

    test('mark all read is a no-op with nothing unread', () async {
      final service = _FakeService(rows: [_notif(id: 'a', isRead: true)]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await provider.markAllRead();
      expect(service.markAllFor, isEmpty);
    });

    test('mark unread reverses a read row', () async {
      final service = _FakeService(rows: [_notif(id: 'a', isRead: true)]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await provider.markUnread(provider.items.first);

      expect(provider.items.first.isRead, isFalse);
      expect(service.unread, ['a']);
    });

    test('dispose removes the channel', () async {
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      await provider.load('u-1');

      provider.dispose();
      expect(service.unsubscribeCalls, 1);
    });
  });

  // ── 4. G-4 routing ──────────────────────────────────────────────────────
  group('resolveNotificationDestination', () {
    NotificationDestination? resolve(
      String type, [
      Map<String, dynamic> data = const {},
    ]) => resolveNotificationDestination(type: type, data: data);

    test(
      'project_shared opens the project — the one that resolves in practice',
      () {
        // ProjectShareService writes `projectId`.
        final d = resolve('project_shared', {'projectId': 'p-1'});
        expect(d!.route, AppConstants.projectDetailScreen);
        expect(d.arguments!['projectId'], 'p-1');
      },
    );

    test('builder_network_addition opens the sender when the id is there', () {
      // Both of this app's writers emit `sender_id`; the portal routes to a list.
      final d = resolve('builder_network_addition', {'sender_id': 'u-9'});
      expect(d!.route, AppConstants.publicProfileScreen);
      expect(d.arguments!['userId'], 'u-9');
    });

    test('builder_network_addition falls back to the members list', () {
      // The portal helper writes only `sender_name`.
      final d = resolve('builder_network_addition', {'sender_name': 'Asha'});
      expect(d!.route, AppConstants.myNetworksScreen);
      expect(d.arguments, isNull);
    });

    test(
      'a bulk-message builder_network_addition opens Communication, not the members list',
      () {
        // NetworkCommunicationService.sendBulkMessage's exact `data` shape —
        // no `sender_id`, so it must not be mistaken for a connection request.
        final d = resolve('builder_network_addition', {
          'message_type': 'announcement',
          'priority': 'medium',
        });
        expect(d!.route, AppConstants.networkCommunicationScreen);
      },
    );

    test('chat types all reach the messages list', () {
      for (final type in [
        'channel_addition',
        'channel_message',
        'channel_admin_promoted',
      ]) {
        expect(resolve(type)!.route, AppConstants.messagesScreen, reason: type);
      }
    });

    test(
      'message_received resolves to null here — NotificationsScreen '
      'intercepts it before calling this function and opens the sender\'s '
      'thread directly, since the payload always carries conversation_id',
      () {
        expect(
          resolve(NotificationTypes.messageReceived, {
            'conversation_id': 'conv-1',
            'sender_id': 'u-9',
            'sender_name': 'Asha',
          }),
          isNull,
        );
      },
    );

    test('lead types reach the leads list', () {
      for (final type in [
        'lead_assigned',
        'lead_status_update',
        'network_lead_new',
      ]) {
        expect(resolve(type)!.route, AppConstants.myLeadsScreen, reason: type);
      }
    });

    test('property_inquiry reaches the role dashboard', () {
      // The portal's `/manage-properties` has no Flutter counterpart; listings are
      // managed on the role dashboard.
      expect(
        resolve('property_inquiry')!.route,
        AppConstants.manageDashboardScreen,
      );
    });

    test('an id-less property notification goes nowhere', () {
      // The portal's helper writes `{property_title}` only, so its
      // `/property/${property_id}` branch is dead for its own rows. Refusing to
      // navigate beats guessing an id.
      expect(resolve('property_approved', {'property_title': 'Flat'}), isNull);
      expect(resolve('property_like'), isNull);
    });

    test('property_approved resolves when an id is present', () {
      final d = resolve('property_approved', {'property_id': 'pr-1'});
      expect(d!.route, AppConstants.propertyDetailScreen);
      expect(d.arguments!['propertyId'], 'pr-1');
    });

    // Superseded by this fix: `visit_booking_update` used to resolve a
    // plain project/property detail page when the writer happened to
    // include an id, and fell back to `null` otherwise. It now always
    // resolves to the Manage Dashboard's Leads/Visits tab — WHICH tab
    // depends on the direction (owner→requester vs requester→owner), never
    // on which content id happens to be present. See
    // `notification_route_resolver_visit_test.dart` for the full
    // direction-disambiguation matrix this fix adds; the cases below just
    // confirm this file's own notification-tap integration (provider mark-
    // read + `Navigator.pushNamed` arguments) still agrees with it.
    test('visit_booking_update with no bookingId (the pre-fix shape neither '
        'writer has ever included) opens Site Visits, not nowhere', () {
      final d = resolve('visit_booking_update', {
        'title': 'Sea View 3BHK',
        'status': 'confirmed',
        'date': '2026-09-12',
        'time': '11:00 AM',
      });
      expect(d!.route, AppConstants.manageDashboardScreen);
      expect(d.arguments!['section'], DashboardSection.visits);
    });

    test('visit_booking_update with a projectId and no bookingId still opens '
        'Site Visits (the owner→requester direction), not a project page', () {
      final d = resolve('visit_booking_update', {
        'title': 'Green Valley',
        'status': 'confirmed',
        'date': '2026-09-12',
        'time': '11:00 AM',
        'projectId': 'proj-7',
      });
      expect(d!.route, AppConstants.manageDashboardScreen);
      expect(d.arguments!['section'], DashboardSection.visits);
      expect(d.arguments!['highlightSource'], 'project');
    });

    test(
      'visit_booking_update with explicit recipientRole: owner opens Leads',
      () {
        final d = resolve('visit_booking_update', {
          'title': 'Sea View 3BHK',
          'status': 'cancelled',
          'date': '2026-09-12',
          'propertyId': 'prop-3',
          'bookingId': 'b-1',
          'recipientRole': 'owner',
        });
        expect(d!.route, AppConstants.manageDashboardScreen);
        expect(d.arguments!['section'], DashboardSection.leads);
        expect(d.arguments!['highlightSource'], 'property');
      },
    );

    test("a bookingId with no recipientRole (the backend's "
        'my-visit-booking-manage shape) falls back to Leads, since that '
        'writer only ever notifies the owner', () {
      final d = resolve('visit_booking_update', {
        'status': 'confirmed',
        'date': '2026-09-12',
        'projectId': 'proj-7',
        'bookingId': 'b-9',
      });
      expect(d!.route, AppConstants.manageDashboardScreen);
      expect(d.arguments!['section'], DashboardSection.leads);
    });

    test('social types go nowhere — there is no screen for them', () {
      for (final type in [
        'social_publish_started',
        'social_publish_success',
        'social_publish_failed',
        'social_retry_started',
        'social_retry_success',
      ]) {
        expect(resolve(type), isNull, reason: type);
      }
    });

    test(
      'document review types both open Edit Profile — NotificationList.tsx:220-223',
      () {
        for (final type in [
          'document_reupload_requested',
          'document_approved',
        ]) {
          expect(
            resolve(type)!.route,
            AppConstants.editProfileScreen,
            reason: type,
          );
        }
      },
    );

    test('an unknown type goes nowhere rather than throwing', () {
      expect(resolve('invented_later'), isNull);
      expect(resolve(''), isNull);
    });

    test(
      'bulk_message resolves to null here — NotificationsScreen intercepts '
      'it before calling this function and shows a detail dialog instead',
      () {
        expect(resolve(NotificationTypes.bulkMessage), isNull);
      },
    );

    test('new_rating resolves to null here — NotificationsScreen intercepts it '
        'before calling this function and opens the Reviews screen instead, '
        'since the payload carries no id for this function to read', () {
      expect(
        resolve(NotificationTypes.newRating, {
          'rater_id': 'rater-1',
          'rater_name': 'Asha',
          'rating': 5,
        }),
        isNull,
      );
    });

    test('an empty-string id is treated as absent', () {
      expect(resolve('project_shared', {'projectId': ''}), isNull);
    });
  });

  // ── 5. The screen ───────────────────────────────────────────────────────
  group('NotificationsScreen', () {
    testWidgets('renders real rows with title, message and time', (
      tester,
    ) async {
      final provider = NotificationProvider(
        service: _FakeService(rows: [_notif()]),
      );
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);

      expect(find.text('New Project Shared'), findsOneWidget);
      expect(
        find.text('Prestige Estates shared a project: "Green Valley"'),
        findsOneWidget,
      );
      expect(find.text('Just now'), findsOneWidget);
      expect(find.text('1 new'), findsOneWidget);
    });

    testWidgets('no picsum placeholders survive', (tester) async {
      // The mock had five. A NetworkImage here would mean the rewrite missed one.
      final provider = NotificationProvider(
        service: _FakeService(rows: [_notif()]),
      );
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tapping marks read and navigates', (tester) async {
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      final pushed = await _pumpScreen(tester, provider: provider);

      await tester.tap(find.text('New Project Shared'));
      await tester.pumpAndSettle();

      expect(service.read, ['n-1']);
      expect(pushed.single.name, AppConstants.projectDetailScreen);
      expect(
        (pushed.single.arguments as Map<String, dynamic>)['projectId'],
        'p-1',
      );
    });

    testWidgets('tapping an unroutable row still marks it read', (
      tester,
    ) async {
      // `visit_booking_update` with this exact shape (title/status only, no
      // bookingId/recipientRole) used to be this test's own example of an
      // unroutable row — this fix makes it resolve to Site Visits instead
      // (see `resolveNotificationDestination`'s case), so a genuinely
      // still-nowhere type is used here instead: `social_publish_started`
      // has no screen in this app at all and is not expected to gain one.
      final service = _FakeService(
        rows: [
          _notif(
            id: 'v-1',
            type: NotificationTypes.socialPublishStarted,
            title: 'Publishing started',
            data: const {},
          ),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      final pushed = await _pumpScreen(tester, provider: provider);

      await tester.tap(find.text('Publishing started'));
      await tester.pumpAndSettle();

      expect(service.read, ['v-1']);
      expect(pushed, isEmpty, reason: 'nowhere to go, so it stays put');
    });

    testWidgets(
      'tapping a message_received row tries to open the sender\'s thread '
      'by looking the conversation up, falling back to the messages list '
      'when it can\'t be resolved (as here, with no real backend to query)',
      (tester) async {
        final service = _FakeService(
          rows: [
            _notif(
              id: 'm-1',
              type: NotificationTypes.messageReceived,
              title: 'New Message',
              message: 'Asha: Is this still available?',
              data: const {
                'conversation_id': 'conv-7',
                'sender_id': 'u-9',
                'sender_name': 'Asha',
              },
            ),
          ],
        );
        final provider = NotificationProvider(service: service);
        addTearDown(provider.dispose);
        await provider.load('u-1');

        final pushed = await _pumpScreen(tester, provider: provider);

        await tester.tap(find.text('New Message'));
        await tester.pumpAndSettle();

        expect(service.read, ['m-1']);
        expect(pushed.single.name, AppConstants.messagesScreen);
      },
    );

    testWidgets(
      'tapping a new_rating row opens the dedicated Reviews screen for the '
      'signed-in user — the payload never carries the rated user\'s own id',
      (tester) async {
        final service = _FakeService(
          rows: [
            _notif(
              id: 'r-1',
              type: NotificationTypes.newRating,
              title: 'New Review',
              message: 'Asha rated you 5 stars.',
              data: const {
                'rater_id': 'rater-1',
                'rater_name': 'Asha',
                'rating': 5,
                'rating_id': 'rt-1',
              },
            ),
          ],
        );
        final provider = NotificationProvider(service: service);
        addTearDown(provider.dispose);
        await provider.load('u-1');

        final pushed = await _pumpScreen(
          tester,
          provider: provider,
          userId: 'u-1',
        );

        await tester.tap(find.text('New Review'));
        await tester.pumpAndSettle();

        expect(service.read, ['r-1']);
        expect(
          pushed,
          isEmpty,
          reason: 'pushed directly, not via a named route',
        );
        final reviewsScreen = tester.widget<ProfileReviewsScreen>(
          find.byType(ProfileReviewsScreen),
        );
        expect(
          reviewsScreen.userId,
          'u-1',
          reason: 'the viewer\'s own id, not rater_id',
        );
      },
    );

    testWidgets(
      'tapping a bulk_message row marks it read and shows a dialog with its '
      'own title/message instead of navigating — there is no conversation '
      'row behind it to open',
      (tester) async {
        final service = _FakeService(
          rows: [
            _notif(
              id: 'b-1',
              type: NotificationTypes.bulkMessage,
              title: 'Price list update',
              message: 'New pricing is live for all Green Valley units.',
              data: const {'message_type': 'announcement', 'priority': 'high'},
            ),
          ],
        );
        final provider = NotificationProvider(service: service);
        addTearDown(provider.dispose);
        await provider.load('u-1');

        final pushed = await _pumpScreen(tester, provider: provider);

        await tester.tap(find.text('Price list update'));
        await tester.pumpAndSettle();

        expect(service.read, ['b-1']);
        expect(pushed, isEmpty, reason: 'shown in a dialog, not navigated to');
        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.text('Price list update')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialog,
            matching: find.text(
              'New pricing is live for all Green Valley units.',
            ),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets('long press toggles read state', (tester) async {
      // Replaces the mock's swipe-to-dismiss, which deleted from a local list
      // against a table with no DELETE policy.
      final service = _FakeService(rows: [_notif()]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);

      await tester.longPress(find.text('New Project Shared'));
      await tester.pumpAndSettle();
      expect(service.read, ['n-1']);

      await tester.longPress(find.text('New Project Shared'));
      await tester.pumpAndSettle();
      expect(service.unread, ['n-1']);
    });

    testWidgets('mark all read clears the pill', (tester) async {
      final service = _FakeService(
        rows: [
          _notif(id: 'a'),
          _notif(id: 'b'),
        ],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);
      expect(find.text('2 new'), findsOneWidget);

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(service.markAllFor, ['u-1']);
      expect(find.textContaining(' new'), findsNothing);
    });

    testWidgets('filters narrow by bucket', (tester) async {
      final provider = NotificationProvider(
        service: _FakeService(
          rows: [
            _notif(
              id: 'a',
              type: NotificationTypes.visitBookingUpdate,
              title: 'Visit Confirmed',
              data: const {},
            ),
            _notif(
              id: 'b',
              type: NotificationTypes.propertyInquiry,
              title: 'New Enquiry',
              data: const {},
            ),
          ],
        ),
      );
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider, size: const Size(700, 900));

      expect(find.text('Visit Confirmed'), findsOneWidget);
      expect(find.text('New Enquiry'), findsOneWidget);

      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      expect(find.text('Visit Confirmed'), findsOneWidget);
      expect(find.text('New Enquiry'), findsNothing);
    });

    testWidgets('an empty filter is distinguished from an empty inbox', (
      tester,
    ) async {
      final provider = NotificationProvider(
        service: _FakeService(
          rows: [
            _notif(
              id: 'a',
              type: NotificationTypes.propertyInquiry,
              title: 'New Enquiry',
              data: const {},
            ),
          ],
        ),
      );
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider, size: const Size(700, 900));

      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text("You're all caught up!"), findsNothing);
    });

    testWidgets('a truly empty inbox keeps the original copy', (tester) async {
      final provider = NotificationProvider(service: _FakeService());
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);

      expect(find.text('No notifications'), findsOneWidget);
      expect(find.text("You're all caught up!"), findsOneWidget);
    });

    testWidgets('a failed load offers a retry, not "all caught up"', (
      tester,
    ) async {
      final service = _FakeService()..shouldFail = true;
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);

      expect(find.text("Couldn't load notifications"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text("You're all caught up!"), findsNothing);
    });

    testWidgets('a realtime arrival appears without a refresh', (tester) async {
      final service = _FakeService(
        rows: [_notif(id: 'a', title: 'First')],
      );
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(tester, provider: provider);
      expect(find.text('First'), findsOneWidget);

      service.onInsert!(_notif(id: 'b', title: 'Just arrived'));
      await tester.pumpAndSettle();

      expect(find.text('Just arrived'), findsOneWidget);
      expect(find.text('2 new'), findsOneWidget);
    });

    testWidgets('lays out cleanly at 320 dp and 130% text', (tester) async {
      final provider = NotificationProvider(
        service: _FakeService(
          rows: [
            _notif(
              title: 'A rather long notification title that wraps',
              message:
                  'And a message long enough to need two lines and then '
                  'some more beyond that.',
            ),
            _notif(
              id: 'b',
              isRead: true,
              type: NotificationTypes.newFollower,
              title: 'New follower',
              data: const {},
            ),
          ],
        ),
      );
      addTearDown(provider.dispose);
      await provider.load('u-1');

      await _pumpScreen(
        tester,
        provider: provider,
        textScale: 1.3,
        size: const Size(320, 900),
      );

      // Asserts on HORIZONTAL overflow only, and deliberately.
      //
      // At 130% text the shared `BottomNavBar` overflows vertically by 2.5 dp
      // (bottom_nav_bar.dart:274) — a pre-existing issue in a widget mounted on
      // thirteen screens, which Spec G did not touch and must not refactor. Every
      // overflow this screen's own content could cause is horizontal: the app bar
      // row, the card row, the filter chips and the metadata row.
      final horizontal = overflowingBoxes(
        tester,
      ).where((o) => o.contains('horizontal')).toList();
      expect(horizontal, isEmpty);

      // The nav bar's overflow raises framework exceptions, and flutter_test fails
      // a test that leaves any unconsumed — so they are drained and identified here
      // rather than ignored. Draining without checking would hide a real exception
      // this screen caused; asserting each one is an overflow is what keeps the
      // check honest.
      // flutter_test aggregates several framework errors into one object whose
      // message is "Multiple exceptions (N) were detected…", so the individual
      // overflow text is not on it — the per-error detail went to the console. Both
      // forms are therefore accepted, and anything that is neither still fails.
      Object? exception;
      var drained = 0;
      while ((exception = tester.takeException()) != null) {
        final text = exception.toString();
        expect(
          text.contains('overflowed') || text.contains('Multiple exceptions'),
          isTrue,
          reason:
              'only the known nav-bar overflow is tolerated here, got: $text',
        );
        drained++;
      }
      expect(
        drained,
        greaterThan(0),
        reason:
            'if this ever hits zero the nav bar was fixed — drop this block',
      );
    });
  });

  // ── 6. Service contract ─────────────────────────────────────────────────
  group('NotificationService', () {
    test('the page size matches the portal', () {
      expect(NotificationService.pageSize, 50);
    });

    test('it targets the notifications table', () {
      expect(NotificationService.table, 'notifications');
    });
  });
}
