// Pins `OutgoingVisitRequest`'s three factories against the EXACT response
// shape `my-visit-requests/index.ts` returns (confirmed by reading that
// function, not guessed) — a property/project row joined with its listing,
// and a profile row with `target_display_name`/`target_avatar_url` already
// attached by the function itself.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/models/outgoing_visit_request.dart';

void main() {
  group('OutgoingVisitRequest.fromPropertyRow', () {
    test('reads the joined properties object', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'preferred_date': '2026-11-01',
        'preferred_time': '10:00',
        'status': 'pending',
        'created_at': '2026-10-01T10:00:00Z',
        'properties': {
          'id': 'p-1',
          'title': 'Sea View Villa',
          'location': 'Bandra West',
          'media_urls': ['https://example.com/a.jpg'],
        },
      });

      expect(item.source, OutgoingVisitSource.property);
      expect(item.targetId, 'p-1');
      expect(item.title, 'Sea View Villa');
      expect(item.location, 'Bandra West');
      expect(item.imageUrl, 'https://example.com/a.jpg');
      expect(item.status, 'pending');
      expect(item.identity, 'property_b-1');
    });

    test('a deleted/missing property does not crash — empty title/target', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-2',
        'property_id': null,
        'preferred_date': '2026-11-01',
        'status': 'pending',
        'properties': null,
      });

      expect(item.targetId, '');
      expect(item.title, '');
      expect(item.imageUrl, isNull);
    });
  });

  group('OutgoingVisitRequest.fromProjectRow', () {
    test('reads the joined builder_projects object, falling back to '
        'master_layout_url when logo_url is absent', () {
      final item = OutgoingVisitRequest.fromProjectRow({
        'id': 'b-3',
        'project_id': 'proj-1',
        'preferred_date': '2026-11-05',
        'preferred_time': '09:00',
        'status': 'confirmed',
        'builder_projects': {
          'id': 'proj-1',
          'title': 'Skyline Towers',
          'location': 'Gachibowli',
          'logo_url': null,
          'master_layout_url': 'https://example.com/layout.jpg',
        },
      });

      expect(item.source, OutgoingVisitSource.project);
      expect(item.targetId, 'proj-1');
      expect(item.title, 'Skyline Towers');
      expect(item.imageUrl, 'https://example.com/layout.jpg');
      expect(item.identity, 'project_b-3');
    });
  });

  group('OutgoingVisitRequest.fromProfileRow', () {
    test('reads the attached target_display_name/target_avatar_url, '
        'and location is always empty', () {
      final item = OutgoingVisitRequest.fromProfileRow({
        'id': 'b-4',
        'target_user_id': 'u-owner',
        'preferred_date': '2026-11-06',
        'status': 'pending',
        'target_display_name': 'Priya Sharma',
        'target_avatar_url': 'https://example.com/avatar.jpg',
      });

      expect(item.source, OutgoingVisitSource.profile);
      expect(item.targetId, 'u-owner');
      expect(item.title, 'Priya Sharma');
      expect(item.location, '');
      expect(item.identity, 'profile_b-4');
    });
  });

  test('identity disambiguates same-id rows from different source tables', () {
    final property = OutgoingVisitRequest.fromPropertyRow({
      'id': 'same-id',
      'property_id': 'p-1',
      'preferred_date': '2026-11-01',
      'status': 'pending',
    });
    final project = OutgoingVisitRequest.fromProjectRow({
      'id': 'same-id',
      'project_id': 'proj-1',
      'preferred_date': '2026-11-01',
      'status': 'pending',
    });

    expect(property.id, project.id);
    expect(property.identity, isNot(project.identity));
  });

  group('isChangeable', () {
    test('a pending future-dated request is changeable', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'preferred_date': '2099-01-01',
        'preferred_time': '10:00',
        'status': 'pending',
      });
      expect(item.isChangeable, isTrue);
    });

    test('a completed request is not changeable regardless of date', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'preferred_date': '2099-01-01',
        'status': 'completed',
      });
      expect(item.isChangeable, isFalse);
    });

    test('a cancelled request is not changeable', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'preferred_date': '2099-01-01',
        'status': 'cancelled',
      });
      expect(item.isChangeable, isFalse);
    });

    test('a pending request whose slot has already passed is not '
        'changeable', () {
      final item = OutgoingVisitRequest.fromPropertyRow({
        'id': 'b-1',
        'property_id': 'p-1',
        'preferred_date': '2020-01-01',
        'preferred_time': '10:00',
        'status': 'pending',
      });
      expect(item.isChangeable, isFalse);
    });
  });
}
