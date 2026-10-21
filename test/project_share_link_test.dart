// Project share links — `projectShareUrl` mirrors `propertyShareUrl` exactly
// (same id+slug shape as React's `projectPath` in `seoSlug.ts`), since the
// project detail screen previously had no share affordance of any kind and
// needed the same URL-building rule property/reel already have.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/utils/profile_link.dart';

void main() {
  group('projectShareUrl', () {
    test('includes the SEO slug when a title is given', () {
      expect(
        projectShareUrl('proj-1', title: 'Green Valley Heights'),
        'https://propcid.com/project/proj-1/green-valley-heights',
      );
    });

    test('falls back to a bare id when there is no title', () {
      expect(projectShareUrl('proj-1'), 'https://propcid.com/project/proj-1');
      expect(
        projectShareUrl('proj-1', title: ''),
        'https://propcid.com/project/proj-1',
      );
    });

    test('is always absolute', () {
      expect(
        projectShareUrl('proj-1', title: 'Green Valley Heights'),
        startsWith('https://'),
      );
    });

    test('is not the same path as propertyShareUrl', () {
      // A project and a property sharing the same id must never collide on
      // the same URL.
      expect(
        projectShareUrl('x-1', title: 'Same Title'),
        isNot(propertyShareUrl('x-1', title: 'Same Title')),
      );
    });
  });
}
