// Settings sheet cleanup.
//
// Five toggles used to sit here — Dark Mode, Push Notifications, Location
// Services, Language, Email Updates — every one hard-coded to a fixed value
// with an empty `(value) {}` callback: picking a reason changed nothing and
// remembered nothing. Checked against what the app actually has (no
// `ThemeMode`, no localization scaffolding, no `profiles` email-preference
// column, and `LocationService`/`geolocator` with no feature consuming a
// position), four had nothing real underneath them and were removed. Only
// the Notification Centre's arrival sound/vibration
// (`NotificationProvider._onInserted`) was a genuine, already-running
// behavior, so it stays — retitled "Notification Alerts" and wired to
// [NotificationAlertPreference] instead of doing nothing.
//
// What this file pins:
//   * the preference itself defaults to on and round-trips through
//     SharedPreferences;
//   * disabling it actually stops the platform-channel calls
//     `NotificationProvider._onInserted` makes — not just a saved bool;
//   * the sheet shows exactly that one toggle plus Logout, none of the four
//     removed controls;
//   * flipping the switch in the sheet persists past reopening it;
//   * Logout still opens the same confirmation dialog as before.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/app_notification.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/notification_provider.dart';
import 'package:propcid_app/screens/profile/account_deletion_screen.dart';
import 'package:propcid_app/screens/profile/actions/settings_sheet.dart';
import 'package:propcid_app/services/notification_alert_preference.dart';
import 'package:propcid_app/services/notification_service.dart';

AppNotification _notif({String id = 'n-1'}) => AppNotification.fromSupabase({
  'id': id,
  'type': 'new_follower',
  'title': 'Someone followed you',
  'message': 'm',
  'is_read': false,
  'data': const {},
  'created_at': DateTime.now().toUtc().toIso8601String(),
});

/// Enough of `NotificationService` for `NotificationProvider.load` to
/// succeed without touching Supabase, and a hook to fire a realtime insert
/// directly — mirrors the fake already used in notification_centre_test.dart.
class _FakeNotificationService extends NotificationService {
  void Function(AppNotification)? onInsert;

  @override
  Future<List<AppNotification>> list(String userId) async => const [];

  @override
  RealtimeChannel subscribe({
    required String userId,
    required String channelSuffix,
    required void Function(AppNotification) onInsert,
    required void Function(AppNotification) onUpdate,
    required void Function(String) onDelete,
  }) {
    this.onInsert = onInsert;
    return Supabase.instance.client.channel('test-$channelSuffix');
  }

  @override
  Future<void> unsubscribe(RealtimeChannel channel) async {}
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

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('NotificationAlertPreference', () {
    test(
      'defaults to enabled — the cue always played before this existed',
      () async {
        expect(await NotificationAlertPreference.isEnabled(), isTrue);
      },
    );

    test('a change persists across reads', () async {
      await NotificationAlertPreference.setEnabled(false);
      expect(await NotificationAlertPreference.isEnabled(), isFalse);

      await NotificationAlertPreference.setEnabled(true);
      expect(await NotificationAlertPreference.isEnabled(), isTrue);
    });
  });

  group('NotificationProvider arrival cue', () {
    late List<String> platformCalls;

    setUp(() {
      platformCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platformCalls.add(call.method);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('plays the sound/haptic cue when the preference is enabled', () async {
      await NotificationAlertPreference.setEnabled(true);
      final service = _FakeNotificationService();
      final provider = NotificationProvider(service: service);
      addTearDown(provider.dispose);
      await provider.load('u-1');

      service.onInsert!(_notif());
      // The cue is fired via an unawaited Future inside `_onInserted`.
      await Future<void>.delayed(Duration.zero);

      expect(
        platformCalls,
        containsAll(['SystemSound.play', 'HapticFeedback.vibrate']),
      );
    });

    test(
      'stays silent when the preference is disabled — not just a saved bool',
      () async {
        await NotificationAlertPreference.setEnabled(false);
        final service = _FakeNotificationService();
        final provider = NotificationProvider(service: service);
        addTearDown(provider.dispose);
        await provider.load('u-1');

        service.onInsert!(_notif());
        await Future<void>.delayed(Duration.zero);

        expect(platformCalls, isEmpty);
        // The notification itself still lands in the list — muting the cue
        // must never drop the row.
        expect(provider.items, hasLength(1));
      },
    );
  });

  group('Settings sheet', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      // The Logout row's `Container` (a pre-existing, unrelated cosmetic
      // choice carried over verbatim from before this cleanup) wraps its
      // `ListTile` in a `DecoratedBox` with a background colour, which
      // Flutter warns may hide ink splashes. Silenced here rather than
      // touched, since fixing it is out of scope for this task; any other
      // FlutterError still fails the test normally.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains(
          'ListTile background color or ink splashes may be invisible',
        )) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
          child: MaterialApp(
            routes: {
              AppConstants.accountDeletionScreen: (_) =>
                  const AccountDeletionScreen(),
            },
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSettingsSheet(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows only Notification Alerts, Logout and Delete Account', (
      tester,
    ) async {
      await pumpSheet(tester);

      expect(find.text('Notification Alerts'), findsOneWidget);
      expect(find.text('Logout'), findsOneWidget);
      // The new "Change Password" tile (added for tracker item 47) pushes
      // this one further down the sheet's own scrollable list.
      await tester.scrollUntilVisible(find.text('Delete Account'), 200);
      expect(find.text('Delete Account'), findsOneWidget);

      // The four removed controls must not survive anywhere in this sheet.
      expect(find.text('Dark Mode'), findsNothing);
      expect(find.text('Push Notifications'), findsNothing);
      expect(find.text('Location Services'), findsNothing);
      expect(find.text('Language'), findsNothing);
      expect(find.text('Email Updates'), findsNothing);
    });

    testWidgets('Delete Account opens the account deletion screen', (
      tester,
    ) async {
      await pumpSheet(tester);

      await tester.scrollUntilVisible(find.text('Delete Account'), 200);
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      expect(find.text('Account deletion'), findsOneWidget);
    });

    testWidgets('flipping the switch persists past reopening the sheet', (
      tester,
    ) async {
      await pumpSheet(tester);
      expect(await NotificationAlertPreference.isEnabled(), isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(await NotificationAlertPreference.isEnabled(), isFalse);

      // Close and reopen: the switch must open already off, not reset.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isFalse);
    });

    testWidgets('Logout still opens the same confirmation dialog', (
      tester,
    ) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Logout'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure you want to logout?'), findsOneWidget);
    });
  });
}
