// Smoke test proving the recoverSession-based fake-session seam actually
// sets `Supabase.instance.client.auth.currentUser` with no network call.
// Not a feature test — just validates the test infrastructure itself before
// it's relied on elsewhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_supabase_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
    );
  });

  tearDown(() async {
    await signOutFakeUser();
  });

  test('signInFakeUser sets currentUser with no network call', () async {
    expect(Supabase.instance.client.auth.currentUser, isNull);

    await signInFakeUser('user-aaaa', email: 'a@example.com');

    expect(Supabase.instance.client.auth.currentUser?.id, 'user-aaaa');
    expect(Supabase.instance.client.auth.currentUser?.email, 'a@example.com');
  });

  test('signOutFakeUser clears currentUser', () async {
    await signInFakeUser('user-bbbb');
    expect(Supabase.instance.client.auth.currentUser, isNotNull);

    await signOutFakeUser();
    expect(Supabase.instance.client.auth.currentUser, isNull);
  });
}
