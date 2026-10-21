// Regression guard for the channel-leave fix: `MessagingService.leaveChannel`
// used to delete the caller's own `channel_participants` row directly, which
// meant the channel could be left with no admin at all when the only admin
// left (no server-side admin-succession logic ran). It now goes through the
// same `channel-leave` Edge Function (→ `leave_channel_with_succession` SQL)
// every other channel-admin action in this service already uses, via the
// shared `_invokeChannelFn` helper.
//
// Against a bare, never-connected client (no backend reachable), that call
// fails over the network — this pins down that the failure surfaces as a
// typed, user-presentable [ChannelAdminError] (`_invokeChannelFn`'s own
// catch-all), not a raw/uncaught exception a direct table delete would never
// have produced.
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/services/messaging_exceptions.dart';
import 'package:propcid_app/services/messaging_service.dart';

SupabaseClient _testClient() => SupabaseClient(
  'http://localhost:54321',
  'test-anon-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('MessagingService.leaveChannel', () {
    test('surfaces a ChannelAdminError, not a raw error, when the function '
        'cannot be reached', () async {
      final service = MessagingService(client: _testClient());
      await expectLater(
        service.leaveChannel('channel-1', 'user-1'),
        throwsA(isA<ChannelAdminError>()),
      );
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
