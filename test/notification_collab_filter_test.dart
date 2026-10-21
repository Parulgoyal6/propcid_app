// NotificationProvider — collaboration notifications, with paid
// collaborations disabled (the default).
//
// A `collab_*` row must not affect the visible list or the unread badge —
// `_items` itself still holds it untouched (so re-enabling the feature
// needs no re-fetch), only what `items`/`unreadCount` expose is filtered.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/models/app_notification.dart';
import 'package:propcid_app/providers/notification_provider.dart';
import 'package:propcid_app/services/notification_service.dart';

AppNotification _notif({
  required String id,
  required String type,
  bool isRead = false,
}) => AppNotification.fromSupabase({
  'id': id,
  'type': type,
  'title': 'T',
  'message': 'M',
  'is_read': isRead,
  'data': const {},
  'created_at': DateTime.now().toUtc().toIso8601String(),
});

class _FakeService extends NotificationService {
  _FakeService(this.rows);

  final List<AppNotification> rows;

  @override
  Future<List<AppNotification>> list(String userId) async => rows;
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

  test(
    'collaboration rows are excluded from the list and the unread count',
    () async {
      final service = _FakeService([
        _notif(id: 'a', type: 'new_follower'),
        _notif(id: 'b', type: NotificationTypes.collabRequest),
        _notif(id: 'c', type: NotificationTypes.collabAccepted),
        _notif(id: 'd', type: 'property_inquiry'),
      ]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.items.map((n) => n.id), ['a', 'd']);
      expect(provider.unreadCount, 2);
      expect(provider.hasUnread, isTrue);
    },
  );

  test(
    'an all-collaboration inbox reads as empty, not just filtered',
    () async {
      final service = _FakeService([
        _notif(id: 'a', type: NotificationTypes.collabAdvancePaid),
        _notif(id: 'b', type: NotificationTypes.collabDeliverableReady),
      ]);
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);

      await provider.load('u-1');

      expect(provider.items, isEmpty);
      expect(provider.unreadCount, 0);
      expect(provider.hasUnread, isFalse);
    },
  );
}
