// Smoke test: the app's widget tree builds without throwing.
//
// Phase 11 repair. This test had been failing since the provider tree grew:
// it supplied four providers while `PropertyApp` also needs AuthProvider,
// ReelsProvider, AvailableLocationsProvider and VoiceAgentProvider — the last
// reached through `FloatingAiOrb`, which the app injects over every screen. It
// threw `ProviderNotFoundException` on every run.
//
// Several of those providers resolve `Supabase.instance` when constructed, so
// the harness initialises an in-memory client first. Nothing here touches the
// network: the URL is a loopback placeholder, token refresh is off, and session
// storage is the empty implementation, so no platform channel is needed.
//
// App code is unchanged — this is a harness fix only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/app.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/available_locations_provider.dart';
import 'package:propcid_app/providers/compare_provider.dart';
import 'package:propcid_app/providers/filter_provider.dart';
import 'package:propcid_app/providers/navigation_provider.dart';
import 'package:propcid_app/providers/notification_provider.dart';
import 'package:propcid_app/providers/projects_provider.dart';
import 'package:propcid_app/providers/property_provider.dart';
import 'package:propcid_app/providers/recent_searches_provider.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/providers/shortlist_provider.dart';
import 'package:propcid_app/voice_agent/providers/voice_agent_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Supabase.initialize builds its PKCE store on SharedPreferences
    // regardless of the auth localStorage above, so the plugin needs an
    // in-memory backing store here.
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

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        // The same set `main.dart` installs, so the test exercises the real
        // tree rather than a reduced one that cannot represent it.
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NavigationProvider()),
          ChangeNotifierProvider(create: (_) => PropertyProvider()),
          ChangeNotifierProvider(create: (_) => FilterProvider()),
          ChangeNotifierProvider(create: (_) => ShortlistProvider()),
          ChangeNotifierProvider(create: (_) => CompareProvider()),
          ChangeNotifierProvider(create: (_) => ReelsProvider()),
          ChangeNotifierProvider(create: (_) => ProjectsProvider()),
          ChangeNotifierProvider(create: (_) => AvailableLocationsProvider()),
          ChangeNotifierProxyProvider<AuthProvider, RecentSearchesProvider>(
            create: (ctx) => RecentSearchesProvider(ctx.read<AuthProvider>()),
            update: (ctx, auth, prev) => prev!..updateAuth(auth),
          ),
          ChangeNotifierProxyProvider<AuthProvider, VoiceAgentProvider>(
            create: (ctx) => VoiceAgentProvider(ctx.read<AuthProvider>()),
            update: (ctx, auth, prev) => prev!..updateAuth(auth),
          ),
          ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
            create: (_) => NotificationProvider(),
            update: (ctx, auth, prev) =>
                (prev ?? NotificationProvider())..load(auth.userId),
          ),
        ],
        child: const PropertyApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);

    // The splash screen schedules a 500 ms and a 3 s timer in initState. The
    // test binding fails a test that ends with timers outstanding, so they are
    // pumped out here rather than left pending.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
