// Builder Audience tab — "Most Liked Content" navigation.
//
// `builderCrossContentPushRoute` is the pure decision
// `BuilderDashboardScreen._openCrossContentItem` defers to. A builder's only
// cross-content type is `project` (via `builder-audience-insights`); the
// other three types are never actually returned by that function and exist
// on the switch purely for exhaustiveness — asserted here too, so a future
// change to the enum can't silently make this function stop compiling
// without a test noticing what changed.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/constants/app_constants.dart';
import 'package:propcid_app/models/dashboard_analytics.dart';
import 'package:propcid_app/screens/dashboard/builder_dashboard_screen.dart';

void main() {
  test('a project item routes to projectDetailScreen with projectId', () {
    const item = CrossContentItem(
      id: 'proj-9',
      type: CrossContentType.project,
      title: 'A project',
    );

    final route = builderCrossContentPushRoute(item);

    expect(route, isNotNull);
    expect(route!.name, AppConstants.projectDetailScreen);
    expect(route.arguments, {'projectId': 'proj-9'});
  });

  test(
    'the three types builder-audience-insights never returns all fall '
    'through to null',
    () {
      for (final type in [
        CrossContentType.property,
        CrossContentType.reel,
        CrossContentType.article,
      ]) {
        final item = CrossContentItem(id: 'x', type: type, title: 't');
        expect(
          builderCrossContentPushRoute(item),
          isNull,
          reason: type.name,
        );
      }
    },
  );
}
