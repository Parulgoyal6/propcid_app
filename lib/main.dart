import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'config/launch_features.dart';
import 'core/navigation/invite_deep_link_handler.dart';
import 'providers/navigation_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/property_provider.dart';
import 'providers/filter_provider.dart';
import 'providers/shortlist_provider.dart';
import 'providers/compare_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/identity_verification_provider.dart';
import 'services/push_notification_service.dart';
import 'providers/reels_provider.dart';
import 'providers/projects_provider.dart';
import 'providers/available_locations_provider.dart';
import 'providers/recent_searches_provider.dart';
import 'voice_agent/providers/voice_agent_provider.dart';
import 'voice_agent/tools/navigation_tool.dart';
import 'voice_agent/tools/search_tools.dart';
import 'voice_agent/tools/property_tools.dart';
import 'voice_agent/tools/profile_tools.dart';
import 'voice_agent/tools/favorites_tool.dart';
import 'voice_agent/tools/utility_tools.dart';

void _registerVoiceAgentTools() {
  registerNavigationTool();
  registerSearchTools();
  registerPropertyTools();
  registerProfileTools();
  registerFavoritesTool();
  registerUtilityTools();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  if (LaunchFeatures.voiceAssistant) {
    _registerVoiceAgentTools();
  }

  // Constructed here rather than via the provider's own `create:` so
  // `InviteDeepLinkHandler` can read the exact same instance's
  // `isLoggedIn` — the provider tree isn't reachable from outside a
  // `BuildContext`, and this handler is not one.
  final authProvider = AuthProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => NavigationProvider()),
        ChangeNotifierProvider(create: (_) => PropertyProvider()),
        ChangeNotifierProvider(create: (_) => FilterProvider()),
        ChangeNotifierProvider(create: (_) => ShortlistProvider()),
        ChangeNotifierProvider(create: (_) => CompareProvider()),
        ChangeNotifierProvider(create: (_) => ReelsProvider()),
        ChangeNotifierProvider(create: (_) => ProjectsProvider()),
        ChangeNotifierProvider(create: (_) => AvailableLocationsProvider()),
        // Proxied on AuthProvider because recent searches live in
        // `ai_user_memory` for a signed-in user and in shared_preferences for
        // an anonymous one — the list has to reload when that identity changes.
        ChangeNotifierProxyProvider<AuthProvider, RecentSearchesProvider>(
          create: (ctx) => RecentSearchesProvider(ctx.read<AuthProvider>()),
          update: (ctx, auth, prev) => prev!..updateAuth(auth),
        ),
        if (LaunchFeatures.voiceAssistant)
          ChangeNotifierProxyProvider<AuthProvider, VoiceAgentProvider>(
            create: (ctx) => VoiceAgentProvider(ctx.read<AuthProvider>()),
            update: (ctx, auth, prev) => prev!..updateAuth(auth),
          ),
        // App-level, unlike every other feature provider in this app, because two
        // surfaces need the same unread count at once: the notifications screen and
        // the home header's badge. Two screen-scoped instances would open two
        // realtime channels and could disagree.
        //
        // Proxied on AuthProvider so a sign-in loads it and a sign-out tears the
        // channel down — `load(null)` clears the list. `load` is idempotent per user
        // id, so the repeated `update` calls a rebuild causes are no-ops.
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(),
          update: (ctx, auth, prev) =>
              (prev ?? NotificationProvider())..load(auth.userId),
        ),
        // Proxied on AuthProvider so identity-verification state (email/
        // phone linking status, pending sends) resets the moment the
        // signed-in user changes — see IdentityVerificationProvider.syncUser.
        // Does not eagerly fetch status; screens that need it call
        // ensureLoaded() themselves.
        ChangeNotifierProxyProvider<AuthProvider, IdentityVerificationProvider>(
          create: (_) => IdentityVerificationProvider(),
          update: (ctx, auth, prev) =>
              (prev ?? IdentityVerificationProvider())..syncUser(auth.userId),
        ),
      ],
      child: const PropertyApp(),
    ),
  );

  // Fire-and-forget: `start()` checks the link that launched a cold start,
  // then keeps listening. Runs after `runApp` so `appNavigatorKey` is
  // already attached if a link is already waiting.
  unawaited(InviteDeepLinkHandler(authProvider: authProvider).start());

  // Registers this device's FCM token for the signed-in user (and re-registers
  // on every sign-in / token refresh). Safe to run without Firebase config.
  unawaited(PushNotificationService.instance.start(authProvider));
}
