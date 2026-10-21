// Pins `applyTeamWorkspaceOverride`: the redirect that sends a project-visit
// notification to the Team Workspace's Site Visits tab instead of the
// Manage Dashboard's Leads tab, for a viewer who only has *team* access to
// that project (an invited collaborator) rather than owning it themselves.
//
// `resolveNotificationDestination` itself is untouched and already pinned by
// `notification_route_resolver_visit_test.dart`; every case here feeds this
// function a `baseline` exactly as that resolver would have produced it,
// so a regression in either function's own logic shows up in the right file.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/navigation/dashboard_section.dart';
import 'package:propcid_app/core/navigation/notification_route_resolver.dart';
import 'package:propcid_app/models/builder_section_models.dart';

BuilderTeamMember _membership({
  String builderId = 'builder-1',
  List<String> modules = const ['site_visits'],
  List<String>? projectIds,
}) =>
    BuilderTeamMember(
      id: 'm-1',
      builderId: builderId,
      memberUserId: 'me',
      modules: modules,
      projectIds: projectIds,
    );

const _leadsBaseline = NotificationDestination(
  AppConstants.manageDashboardScreen,
  {'section': DashboardSection.leads, 'highlightSource': 'project'},
);

void main() {
  test('null baseline stays null', () {
    final result = applyTeamWorkspaceOverride(
      baseline: null,
      data: const {'projectId': 'proj-1'},
      activeTeamMemberships: [_membership(projectIds: const ['proj-1'])],
    );
    expect(result, isNull);
  });

  test('a destination outside the Manage Dashboard is untouched', () {
    const baseline = NotificationDestination(AppConstants.propertyDetailScreen, {
      'propertyId': 'p-1',
    });
    final result = applyTeamWorkspaceOverride(
      baseline: baseline,
      data: const {'propertyId': 'p-1'},
      activeTeamMemberships: [_membership(projectIds: const ['proj-1'])],
    );
    expect(result, same(baseline));
  });

  test('the dashboard\'s own default-tab fallback (no section) is untouched', () {
    const baseline = NotificationDestination(AppConstants.manageDashboardScreen);
    final result = applyTeamWorkspaceOverride(
      baseline: baseline,
      data: const {},
      activeTeamMemberships: [_membership(projectIds: const ['proj-1'])],
    );
    expect(result, same(baseline));
  });

  test('the requester\'s own Visits tab is never redirected', () {
    const baseline = NotificationDestination(AppConstants.manageDashboardScreen, {
      'section': DashboardSection.visits,
      'highlightSource': 'project',
    });
    final result = applyTeamWorkspaceOverride(
      baseline: baseline,
      data: const {'projectId': 'proj-1'},
      activeTeamMemberships: [_membership(projectIds: const ['proj-1'])],
    );
    expect(result, same(baseline));
  });

  test('a property/profile lead (no projectId) is untouched', () {
    final result = applyTeamWorkspaceOverride(
      baseline: _leadsBaseline,
      data: const {'propertyId': 'p-1'},
      activeTeamMemberships: [_membership(projectIds: const ['proj-1'])],
    );
    expect(result, same(_leadsBaseline));
  });

  test('no active team membership at all leaves the owner\'s Leads tab', () {
    final result = applyTeamWorkspaceOverride(
      baseline: _leadsBaseline,
      data: const {'projectId': 'proj-1'},
      activeTeamMemberships: const [],
    );
    expect(result, same(_leadsBaseline));
  });

  test(
    'a membership that does not cover this project leaves the owner\'s Leads tab',
    () {
      final result = applyTeamWorkspaceOverride(
        baseline: _leadsBaseline,
        data: const {'projectId': 'proj-1'},
        activeTeamMemberships: [
          _membership(projectIds: const ['some-other-project']),
        ],
      );
      expect(result, same(_leadsBaseline));
    },
  );

  test(
    'a membership without the site_visits module is skipped even if it covers the project',
    () {
      final result = applyTeamWorkspaceOverride(
        baseline: _leadsBaseline,
        data: const {'projectId': 'proj-1'},
        activeTeamMemberships: [
          _membership(modules: const ['leads'], projectIds: const ['proj-1']),
        ],
      );
      expect(result, same(_leadsBaseline));
    },
  );

  test(
    'a matching membership redirects to the Team Workspace\'s Site Visits tab',
    () {
      final result = applyTeamWorkspaceOverride(
        baseline: _leadsBaseline,
        data: const {'projectId': 'proj-1'},
        activeTeamMemberships: [
          _membership(builderId: 'builder-9', projectIds: const ['proj-1']),
        ],
      );
      expect(result, isNotNull);
      expect(result!.route, AppConstants.teamWorkspaceScreen);
      expect(result.arguments?['builderId'], 'builder-9');
      expect(result.arguments?['module'], 'site_visits');
    },
  );

  test('a null projectIds membership (every project) also matches', () {
    final result = applyTeamWorkspaceOverride(
      baseline: _leadsBaseline,
      data: const {'projectId': 'proj-1'},
      activeTeamMemberships: [_membership(builderId: 'builder-9')],
    );
    expect(result?.route, AppConstants.teamWorkspaceScreen);
    expect(result?.arguments?['builderId'], 'builder-9');
  });

  test('the first covering membership wins when several are active', () {
    final result = applyTeamWorkspaceOverride(
      baseline: _leadsBaseline,
      data: const {'projectId': 'proj-1'},
      activeTeamMemberships: [
        _membership(builderId: 'builder-a', projectIds: const ['other']),
        _membership(builderId: 'builder-b', projectIds: const ['proj-1']),
      ],
    );
    expect(result?.arguments?['builderId'], 'builder-b');
  });

  test('project_id (snake_case) is read the same as projectId', () {
    final result = applyTeamWorkspaceOverride(
      baseline: _leadsBaseline,
      data: const {'project_id': 'proj-1'},
      activeTeamMemberships: [
        _membership(builderId: 'builder-9', projectIds: const ['proj-1']),
      ],
    );
    expect(result?.route, AppConstants.teamWorkspaceScreen);
  });
}
