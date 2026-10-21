// Pins `resolveNotificationDestination`'s `team_activity` case against the
// four exact payload shapes `notify_team_member_change`/
// `notify_team_activity_log` (propcid-main's
// `20271007040100_notify_team_activity.sql`) actually write. Before this
// fix the type had no case at all (fell through to `default: return null`),
// which is the literal "tapping the notification does nothing" bug — the
// row's own `data.route` is what the backend already uses to tell apart
// its four events, so this reads that instead of re-deriving one from
// `data.event` or the display title.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/core/navigation/dashboard_section.dart';
import 'package:propcid_app/core/navigation/notification_route_resolver.dart';
import 'package:propcid_app/models/app_notification.dart';

void main() {
  test('member_added opens this account\'s own Team Workspace', () {
    // Exact shape the trigger inserts for the newly-added member.
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: {
        'event': 'member_added',
        'builder_id': 'builder-9',
        'route': '/team-workspace',
      },
    );

    expect(destination, isNotNull);
    expect(destination!.route, AppConstants.teamWorkspaceScreen);
    expect(destination.arguments?['builderId'], 'builder-9');
  });

  test('access_changed also opens Team Workspace, scoped to that builder', () {
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: {
        'event': 'access_changed',
        'builder_id': 'builder-4',
        'route': '/team-workspace',
      },
    );

    expect(destination!.route, AppConstants.teamWorkspaceScreen);
    expect(destination.arguments?['builderId'], 'builder-4');
  });

  test('invite_accepted opens the builder\'s own dashboard on the Team tab', () {
    // Exact shape the trigger inserts for the team owner.
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: {
        'event': 'invite_accepted',
        'member_user_id': 'member-1',
        'route': '/manage-builder-dashboard',
      },
    );

    expect(destination, isNotNull);
    expect(destination!.route, AppConstants.manageDashboardScreen);
    expect(destination.arguments?['section'], DashboardSection.team);
  });

  test(
    'a coalesced team-activity log entry also opens the Team tab',
    () {
      // Exact shape `notify_team_activity_log` inserts/updates.
      final destination = resolveNotificationDestination(
        type: NotificationTypes.teamActivity,
        data: {
          'actor_user_id': 'member-1',
          'entity_type': 'inventory',
          'entity_id': 'unit-1',
          'action': 'insert',
          'count': 3,
          'route': '/manage-builder-dashboard',
        },
      );

      expect(destination!.route, AppConstants.manageDashboardScreen);
      expect(destination.arguments?['section'], DashboardSection.team);
    },
  );

  test('member_removed has nowhere to open — the row is the whole story', () {
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: {
        'event': 'member_removed',
        'builder_id': 'builder-9',
        'route': '/notifications',
      },
    );

    expect(destination, isNull);
  });

  test('a team_activity row with no recognised route resolves to null', () {
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: const {},
    );

    expect(destination, isNull);
  });

  test('missing builder_id still opens Team Workspace, just unscoped', () {
    final destination = resolveNotificationDestination(
      type: NotificationTypes.teamActivity,
      data: const {'route': '/team-workspace'},
    );

    expect(destination!.route, AppConstants.teamWorkspaceScreen);
    expect(destination.arguments?.containsKey('builderId'), isFalse);
  });
}
