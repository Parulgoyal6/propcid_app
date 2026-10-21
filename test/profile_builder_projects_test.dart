// Profile → the content slot is role-dependent.
//
// A builder's work lives in `builder_projects`; `ProfileProvider.properties`
// only ever reads `properties`. So the All/Properties/Articles list could never
// show a builder anything — it sat on "No content yet" permanently, which reads
// as "you have nothing" rather than "this list cannot represent your work".
//
// The portal makes the same substitution rather than adding a fourth tab:
// `PROFILE_TYPE_CONFIG` marks builder as `content: "projects"` and
// `ProfileDashboardShell.tsx:3894-3900` swaps the whole My Content block for
// `BuilderProjectsManager`. Read from the reference repo at
// `c:\Users\USER\Desktop\Flutter\propcid`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/providers/compare_provider.dart';
import 'package:propcid_app/providers/navigation_provider.dart';
import 'package:propcid_app/providers/profile_provider.dart';
import 'package:propcid_app/providers/projects_provider.dart';
import 'package:propcid_app/providers/property_provider.dart';
import 'package:propcid_app/providers/reels_provider.dart';
import 'package:propcid_app/screens/dashboard/widgets/my_projects_section.dart';
import 'package:propcid_app/screens/profile/profile_screen.dart';
import 'package:propcid_app/screens/profile/widgets/my_content_section.dart';

class _FakeAuth extends AuthProvider {
  _FakeAuth({required this.type});

  final String? type;

  @override
  String? get userId => 'u-1';

  @override
  String? get userType => type;

  @override
  bool get isLoggedIn => true;

  @override
  String get userName => 'Test User';
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

  Future<void> pumpProfile(
    WidgetTester tester, {
    required String? userType,
  }) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(
            value: _FakeAuth(type: userType),
          ),
          ChangeNotifierProvider<ProfileProvider>(
            create: (_) => ProfileProvider(),
          ),
          ChangeNotifierProvider<NavigationProvider>(
            create: (_) => NavigationProvider(),
          ),
          ChangeNotifierProvider<PropertyProvider>(
            create: (_) => PropertyProvider(),
          ),
          ChangeNotifierProvider<CompareProvider>(
            create: (_) => CompareProvider(),
          ),
          ChangeNotifierProvider<ReelsProvider>(create: (_) => ReelsProvider()),
          ChangeNotifierProvider<ProjectsProvider>(
            create: (_) => ProjectsProvider(),
          ),
        ],
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    // Not pumpAndSettle: the screen runs staggered entry animations and its
    // sections self-fetch against a client that is not there. Which widget got
    // built is decided on the first frame, which is all this asserts.
    await tester.pump();
  }

  /// Tears the tree down and lets the staggered `.animate()` delay timers fire.
  ///
  /// Must run inside the test body — the framework asserts on pending timers
  /// before `addTearDown` callbacks get a turn.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('a builder gets the projects list, not All/Properties/Articles', (
    tester,
  ) async {
    await pumpProfile(tester, userType: 'builder');

    expect(find.byType(MyProjectsSection), findsOneWidget);
    expect(find.byType(MyContentSection), findsNothing);
    // `_SectionLabel` uppercases its text.
    expect(find.text('MY PROJECTS'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('every other role keeps the content list', (tester) async {
    for (final role in const ['individual', 'broker', 'influencer']) {
      await pumpProfile(tester, userType: role);

      expect(find.byType(MyContentSection), findsOneWidget, reason: role);
      expect(find.byType(MyProjectsSection), findsNothing, reason: role);
      expect(find.text('MY CONTENT'), findsOneWidget, reason: role);

      await teardown(tester);
    }
  });

  testWidgets('an unresolved role keeps the content list', (tester) async {
    // `userType` is null until the profile fetch lands. Guessing "builder" on
    // that would flash the wrong section for every user on every cold start.
    await pumpProfile(tester, userType: null);

    expect(find.byType(MyContentSection), findsOneWidget);
    expect(find.byType(MyProjectsSection), findsNothing);

    await teardown(tester);
  });

  testWidgets('the role match is case-insensitive', (tester) async {
    // `profiles.user_type` is free text, and the screen's existing `isBuilder`
    // check already lower-cases it — this must not diverge from it.
    await pumpProfile(tester, userType: 'Builder');

    expect(find.byType(MyProjectsSection), findsOneWidget);

    await teardown(tester);
  });
}
