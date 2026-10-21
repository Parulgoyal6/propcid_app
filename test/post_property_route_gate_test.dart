// Central role gates for the three creation wizards.
//
// The audit found eleven navigations to `/post-property`, six of them reachable
// by a builder with no role check — three via shared, role-blind components (the
// bottom-nav "+" FAB on thirteen screens, Home's quick action, the Profile
// tiles). Gating at the route covers all of them at once, so what these tests
// pin is the gate's decision table rather than any one button.
//
// The four cases that matter per gate:
//   * edit mode  -> never gated, any role
//   * role still resolving -> wait, do not decide
//   * wrong role -> the other wizard, no error
//   * right role -> straight through
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:propcid_app/core/navigation/post_property_route_gate.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/providers/auth_provider.dart';
import 'package:propcid_app/screens/add_project/add_project_screen.dart';
import 'package:propcid_app/screens/influencer/influencer_video_form_screen.dart';
import 'package:propcid_app/screens/post_property/post_property_screen.dart';
import 'package:propcid_app/services/property_service.dart'
    show PropertyEditBundle;
import 'package:propcid_app/voice_agent/rag/route_index.dart';
import 'package:propcid_app/voice_agent/tools/permissions.dart';

/// An AuthProvider whose role can be set directly.
///
/// `userType` is normally filled asynchronously from `profiles`; overriding the
/// getters is what lets a test hold it at null to exercise the race the gate
/// guards.
class _FakeAuth extends AuthProvider {
  _FakeAuth({this.type, this.loggedIn = true});

  final String? type;
  final bool loggedIn;

  @override
  String? get userType => type;

  @override
  bool get isLoggedIn => loggedIn;
}

/// [settle] drains the mounted wizard's entry animation. Pass false when the
/// gate is expected to show the spinner instead: a `CircularProgressIndicator`
/// animates indefinitely, so `pumpAndSettle` would never return.
Future<void> _pump(
  WidgetTester tester,
  Widget gate,
  _FakeAuth auth, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: auth,
      child: MaterialApp(home: gate),
    ),
  );
  // Both wizards open with a finite `.animate().fadeIn()`, which schedules a
  // timer. Leaving it pending trips the binding's `!timersPending` assertion at
  // teardown, so it is drained here — only which wizard mounted is under test.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    dotenv.loadFromString(envString: 'GOOGLE_MAPS_API_KEY=');

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

  // ── The rule the gates delegate to ─────────────────────────────────────
  group('canCreate', () {
    test('only a builder is refused a property listing', () {
      expect(canCreate(CreatableContent.property, 'builder'), isFalse);
      for (final role in [
        'broker',
        'influencer',
        'individual',
        'seller',
        'dealer',
      ]) {
        expect(
          canCreate(CreatableContent.property, role),
          isTrue,
          reason: '$role may list a property',
        );
      }
    });

    test('only a builder may create a project', () {
      expect(canCreate(CreatableContent.project, 'builder'), isTrue);
      for (final role in ['broker', 'influencer', 'individual']) {
        expect(canCreate(CreatableContent.project, role), isFalse);
      }
    });

    test('only an influencer may create a video', () {
      expect(canCreate(CreatableContent.video, 'influencer'), isTrue);
      for (final role in ['broker', 'builder', 'individual', 'dealer']) {
        expect(canCreate(CreatableContent.video, role), isFalse);
      }
    });

    test('an influencer may still list a property', () {
      // Spec A repointed the influencer dashboard's create affordances at the
      // video form, but it did NOT take listings away: CreateContent.tsx:379-402
      // gives an influencer three create buttons (video, property, article) where
      // every other role gets two, and the influencer Content tab renders
      // MyListingsSection. The shared "+" / "Post Property" / "Add Property"
      // surfaces are deliberately untouched.
      expect(canCreate(CreatableContent.property, 'influencer'), isTrue);
      expect(canCreate(CreatableContent.article, 'influencer'), isTrue);
    });

    test('an unresolved role reads as allowed — which is why the gate waits', () {
      // `null != 'builder'` is true. If the gate decided on a null role, a
      // builder tapping "+" before their profile loaded would reach the listing
      // wizard.
      expect(canCreate(CreatableContent.property, null), isTrue);
      expect(canCreate(CreatableContent.project, null), isFalse);
      expect(canCreate(CreatableContent.video, null), isFalse);
    });
  });

  // ── /post-property ─────────────────────────────────────────────────────
  group('PostPropertyRouteGate', () {
    testWidgets('a builder gets the project wizard instead', (tester) async {
      await _pump(
        tester,
        const PostPropertyRouteGate(),
        _FakeAuth(type: 'builder'),
      );

      expect(find.byType(AddProjectScreen), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
      // Redirected, not refused — no error surface at all.
      expect(find.textContaining('not allowed'), findsNothing);
      expect(find.textContaining('cannot'), findsNothing);
    });

    testWidgets('every other role gets the listing wizard', (tester) async {
      for (final role in ['broker', 'influencer', 'individual']) {
        await _pump(
          tester,
          const PostPropertyRouteGate(),
          _FakeAuth(type: role),
        );
        expect(
          find.byType(PostPropertyScreen),
          findsOneWidget,
          reason: '$role should reach the listing wizard',
        );
        expect(find.byType(AddProjectScreen), findsNothing);
      }
    });

    testWidgets('waits while the role is still resolving', (tester) async {
      // Signed in, userType not yet loaded — neither wizard may mount.
      await _pump(
        tester,
        const PostPropertyRouteGate(),
        _FakeAuth(type: null),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
      expect(find.byType(AddProjectScreen), findsNothing);
    });

    testWidgets('a signed-out visitor is not held at the spinner', (
      tester,
    ) async {
      // Nothing to wait for: there is no role coming.
      await _pump(
        tester,
        const PostPropertyRouteGate(),
        _FakeAuth(type: null, loggedIn: false),
      );

      expect(find.byType(PostPropertyScreen), findsOneWidget);
    });

    testWidgets('edit mode opens the listing wizard even for a builder', (
      tester,
    ) async {
      // A builder with legacy `properties` rows must keep being able to edit
      // them. This is the only branch that skips the role read entirely.
      await _pump(
        tester,
        PostPropertyRouteGate(
          editPropertyId: 'p-1',
          editBundle: const PropertyEditBundle(
            propertyRow: {'id': 'p-1', 'title': 'A legacy listing'},
          ),
        ),
        _FakeAuth(type: 'builder'),
      );

      expect(find.byType(PostPropertyScreen), findsOneWidget);
      expect(find.byType(AddProjectScreen), findsNothing);
    });

    testWidgets('an id without a bundle is not edit mode, so the gate applies', (
      tester,
    ) async {
      // `PostPropertyScreen` only enters edit mode with both, so a half-supplied
      // argument must not be treated as an edit and slip past the role check.
      await _pump(
        tester,
        const PostPropertyRouteGate(editPropertyId: 'p-1'),
        _FakeAuth(type: 'builder'),
      );

      expect(find.byType(AddProjectScreen), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
    });
  });

  // ── /add-project — the mirror ──────────────────────────────────────────
  group('AddProjectRouteGate', () {
    testWidgets('a builder gets the project wizard', (tester) async {
      await _pump(
        tester,
        const AddProjectRouteGate(),
        _FakeAuth(type: 'builder'),
      );

      expect(find.byType(AddProjectScreen), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
    });

    testWidgets('a non-builder is sent to the listing wizard', (tester) async {
      // The hole this closes: the voice route index resolves "create a project"
      // for any authenticated user, AddProjectScreen has no role check, and
      // `builder_projects` INSERT is WITH CHECK (builder_id = auth.uid()) — so a
      // broker inserting their own id would satisfy RLS.
      for (final role in ['broker', 'influencer', 'individual']) {
        await _pump(tester, const AddProjectRouteGate(), _FakeAuth(type: role));
        expect(
          find.byType(PostPropertyScreen),
          findsOneWidget,
          reason: '$role must not reach the project wizard',
        );
        expect(find.byType(AddProjectScreen), findsNothing);
      }
    });

    testWidgets('waits while the role is still resolving', (tester) async {
      await _pump(
        tester,
        const AddProjectRouteGate(),
        _FakeAuth(type: null),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AddProjectScreen), findsNothing);
    });

    testWidgets('editing a project is never gated', (tester) async {
      final project = ProjectModel.fromSupabase({
        'id': 'p-9',
        'builder_id': 'b-1',
        'title': 'Existing',
      });

      // Even as a broker — the row's own RLS decides whether the update lands,
      // and a gate here would only break a legitimate owner whose role read is
      // stale.
      await _pump(
        tester,
        AddProjectRouteGate(editingProject: project),
        _FakeAuth(type: 'broker'),
      );

      expect(find.byType(AddProjectScreen), findsOneWidget);
    });
  });

  // ── /influencer-video ──────────────────────────────────────────────────
  group('InfluencerVideoRouteGate', () {
    testWidgets('an influencer gets the video form', (tester) async {
      await _pump(
        tester,
        const InfluencerVideoRouteGate(),
        _FakeAuth(type: 'influencer'),
      );

      expect(find.byType(InfluencerVideoFormScreen), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
    });

    testWidgets('a broker gets the listing wizard instead', (tester) async {
      // Redirected to what they can create, exactly as the other two gates do.
      await _pump(
        tester,
        const InfluencerVideoRouteGate(),
        _FakeAuth(type: 'broker'),
      );

      expect(find.byType(PostPropertyScreen), findsOneWidget);
      expect(find.byType(InfluencerVideoFormScreen), findsNothing);
    });

    testWidgets('a builder gets the project wizard, not the listing one', (
      tester,
    ) async {
      // The fallback has to branch: canCreate(property, 'builder') is false, so
      // sending a builder to PostPropertyScreen would land them on a wizard they
      // are barred from.
      await _pump(
        tester,
        const InfluencerVideoRouteGate(),
        _FakeAuth(type: 'builder'),
      );

      expect(find.byType(AddProjectScreen), findsOneWidget);
      expect(find.byType(PostPropertyScreen), findsNothing);
    });

    testWidgets('an unresolved role waits rather than deciding', (
      tester,
    ) async {
      await _pump(
        tester,
        const InfluencerVideoRouteGate(),
        _FakeAuth(type: null),
        settle: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(InfluencerVideoFormScreen), findsNothing);
      expect(find.byType(PostPropertyScreen), findsNothing);
    });

    testWidgets('a logged-out visitor is not held at the spinner', (
      tester,
    ) async {
      // isLoggedIn false means userType will never arrive; waiting would hang.
      await _pump(
        tester,
        const InfluencerVideoRouteGate(),
        _FakeAuth(type: null, loggedIn: false),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ── The voice agent can now reach the project wizard ───────────────────
  group('voice route index', () {
    test('"create a project" resolves to /add-project', () {
      // Before this entry existed the concept had no destination, so a builder
      // asking by voice had nowhere correct to go.
      for (final phrase in ['add project', 'create project', 'new project']) {
        final route = resolveConcept(phrase, 'authenticated');
        expect(route?.path, '/add-project', reason: 'for "$phrase"');
      }
    });

    test('"post property" still resolves to /post-property', () {
      // The new entry shares the words "add" and "create"; the existing one must
      // not lose its own phrases to it.
      for (final phrase in [
        'post property',
        'create listing',
        'add property',
      ]) {
        final route = resolveConcept(phrase, 'authenticated');
        expect(route?.path, '/post-property', reason: 'for "$phrase"');
      }
    });

    test('"upload a video" resolves to /influencer-video', () {
      // post_content(video) used to navigate to /reels — the consumer feed — so
      // an influencer who asked to post a video landed in a viewer.
      for (final phrase in ['upload video', 'create video', 'post video']) {
        final route = resolveConcept(phrase, 'authenticated');
        expect(route?.path, '/influencer-video', reason: 'for "$phrase"');
      }
    });

    test("the video entry does not steal the other two wizards' phrases", () {
      // All three share "create", "add", "new" and "post".
      expect(
        resolveConcept('post property', 'authenticated')?.path,
        '/post-property',
      );
      expect(
        resolveConcept('create project', 'authenticated')?.path,
        '/add-project',
      );
    });

    test('the video entry is not reachable by a logged-out visitor', () {
      // Same ladder trap as the project entry: an 'influencer' tier would give
      // indexOf == -1 and make the entry public.
      expect(
        resolveConcept('upload video', 'public')?.path,
        isNot('/influencer-video'),
      );
    });

    test('the project entry is not reachable by a logged-out visitor', () {
      // Why its tier is 'authenticated' and not 'builder': _canAccess compares
      // ladder positions, so an unrecognised tier gives indexOf == -1 and
      // `userIdx >= -1` is always true — 'builder' would make it PUBLIC.
      expect(
        resolveConcept('create project', 'public')?.path,
        isNot('/add-project'),
      );
    });
  });
}
