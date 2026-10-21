// Workspace Drawer — launch feature gates.
//
// Upgrade, Subscription & Billing and Social used to always render. With the
// default (all-false) flags, none of the three may appear, while every
// ordinary destination (Home, Feed, Reels, Messages, Network, Settings,
// Logout) must still be there exactly as before.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/widgets/workspace_drawer.dart';

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

  Widget withAuth(Widget child) => ChangeNotifierProvider<AuthProvider>(
    create: (_) => AuthProvider(),
    child: MaterialApp(home: child),
  );

  group('WorkspaceDrawer', () {
    testWidgets('has no Upgrade, Subscription & Billing or Social row', (
      tester,
    ) async {
      await tester.pumpWidget(
        withAuth(const Scaffold(body: WorkspaceDrawer())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upgrade'), findsNothing);
      expect(find.text('Subscription & Billing'), findsNothing);
      expect(find.text('Social'), findsNothing);
    });

    testWidgets('every ordinary destination is untouched', (tester) async {
      await tester.pumpWidget(
        withAuth(const Scaffold(body: WorkspaceDrawer())),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'Home',
        'Manage Dashboard',
        'Feed',
        'Reels',
        'Messages',
        'Network',
        'Settings',
        'Logout',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });
}
