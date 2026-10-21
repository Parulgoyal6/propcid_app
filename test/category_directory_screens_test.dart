// The four "browse all" screens the Popular Categories role/project tiles
// open (role_directory_screen.dart, latest_projects_screen.dart) — layout
// smoke tests plus the tap-through-to-detail wiring. Not exhaustive; mirrors
// the shallow coverage the rest of this app's screen tests use.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/project_model.dart';
import 'package:propcid_app/models/user_profile.dart';
import 'package:propcid_app/screens/network/role_directory_screen.dart';
import 'package:propcid_app/screens/project/latest_projects_screen.dart';
import 'package:propcid_app/services/project_service.dart';

class _FakeProjectService extends ProjectService {
  _FakeProjectService(this._projects);
  final List<ProjectModel> _projects;

  @override
  Future<List<ProjectModel>> listLatestActive({int limit = 8}) async =>
      _projects;
}

ProjectModel _project(String id, String title) => ProjectModel(
      id: id,
      builderId: 'b-1',
      title: title,
      description: '',
      projectType: 'Residential',
      location: 'Noida, Sector 150',
      status: 'active',
      approvalStatus: 'approved',
      totalUnits: 0,
      availableUnits: 0,
      priceRangeMin: 0,
      priceRangeMax: 0,
      areaSqftMin: 0,
      areaSqftMax: 0,
      reraNumber: '',
      websiteUrl: '',
      contactNumber: '',
      logoUrl: '',
      brochureUrl: '',
      masterLayoutUrl: '',
      mapImages: const [],
      otherImages: const [],
      mediaUrls: const [],
      videosUrls: const [],
      amenities: const [],
      likes: 0,
      views: 0,
      latitude: 0,
      longitude: 0,
    );

UserProfile _profile(String id, String name) => UserProfile.fromMap({
      'user_id': id,
      'display_name': name,
      'user_type': 'broker',
      'approval_status': 'approved',
    });

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

  group('LatestProjectsScreen', () {
    testWidgets('renders the fetched projects without overflowing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LatestProjectsScreen(
            service: _FakeProjectService([
              _project('p-1', 'Skyline Residency'),
              _project('p-2', 'Green Meadows'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Skyline Residency'), findsOneWidget);
      expect(find.text('Green Meadows'), findsOneWidget);
    });

    testWidgets('tapping a project opens the project detail route',
        (tester) async {
      final pushed = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LatestProjectsScreen(
            service: _FakeProjectService([_project('p-1', 'Skyline Residency')]),
          ),
          onGenerateRoute: (settings) {
            pushed.add(settings.name);
            return MaterialPageRoute(builder: (_) => const SizedBox());
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(pushed, contains(AppConstants.projectDetailScreen));
    });

    testWidgets('the search box filters by title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LatestProjectsScreen(
            service: _FakeProjectService([
              _project('p-1', 'Skyline Residency'),
              _project('p-2', 'Green Meadows'),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'skyline');
      await tester.pumpAndSettle();

      expect(find.text('Skyline Residency'), findsOneWidget);
      expect(find.text('Green Meadows'), findsNothing);
    });
  });

  group('RoleDirectoryScreen', () {
    testWidgets('renders the loaded profiles without overflowing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoleDirectoryScreen(
            userType: 'broker',
            title: 'Verified Brokers',
            loader: () async => [
              _profile('u-1', 'Alice Broker'),
              _profile('u-2', 'Bob Agent'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Alice Broker'), findsOneWidget);
      expect(find.text('Bob Agent'), findsOneWidget);
    });

    testWidgets('a failed load shows a retryable error, not a crash',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoleDirectoryScreen(
            userType: 'builder',
            title: 'Builders',
            loader: () async => throw Exception('network down'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("Couldn't load this list"), findsOneWidget);
    });

    testWidgets('the search box filters by name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RoleDirectoryScreen(
            userType: 'influencer',
            title: 'Influencers',
            loader: () async => [
              _profile('u-1', 'Alice Broker'),
              _profile('u-2', 'Bob Agent'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();

      expect(find.text('Alice Broker'), findsOneWidget);
      expect(find.text('Bob Agent'), findsNothing);
    });
  });
}
