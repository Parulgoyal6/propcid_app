// Regression guard: a just-created channel has no messages yet, so
// `lastMessageAt` is null — `MessagingService.listChannels`'s sort used to
// treat that as "always sorts last", which put a brand-new channel at the
// BOTTOM of the Messages > Channels list instead of the top. The fix falls
// back to the channel's own `created_at` (now parsed into
// `ChannelSummary.createdAt`, previously fetched but never read) so a
// channel's most-recent-activity timestamp is always either its last
// message or its own creation — whichever exists.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/channel_summary.dart';
import 'package:propcid_app/services/messaging_service.dart';

ChannelSummary _channel({
  required String id,
  required String name,
  DateTime? lastMessageAt,
  DateTime? createdAt,
}) => ChannelSummary(
  id: id,
  name: name,
  lastMessageAt: lastMessageAt,
  createdAt: createdAt,
);

void main() {
  group('ChannelSummary.fromSupabase', () {
    test('parses created_at', () {
      final channel = ChannelSummary.fromSupabase({
        'id': 'c-1',
        'name': 'General',
        'created_at': '2026-10-01T10:00:00Z',
      });
      expect(channel.createdAt, DateTime.parse('2026-10-01T10:00:00Z'));
    });

    test('a missing created_at parses to null rather than throwing', () {
      final channel = ChannelSummary.fromSupabase({
        'id': 'c-1',
        'name': 'General',
      });
      expect(channel.createdAt, isNull);
    });
  });

  group('MessagingService.compareChannelsByRecentActivity', () {
    test('a brand-new channel (no messages yet) sorts to the TOP, ahead of an '
        'older channel with a less-recent message', () {
      final brandNew = _channel(
        id: 'new',
        name: 'New Channel',
        createdAt: DateTime(2026, 10, 12, 9),
      );
      final older = _channel(
        id: 'old',
        name: 'Old Channel',
        lastMessageAt: DateTime(2026, 10, 10),
      );

      final list = [older, brandNew]
        ..sort(MessagingService.compareChannelsByRecentActivity);

      expect(list.first.id, 'new');
    });

    test('a channel with a recent message still outranks a channel merely '
        'created earlier with no messages', () {
      final activeOld = _channel(
        id: 'active',
        name: 'Active',
        createdAt: DateTime(2026, 1, 1),
        lastMessageAt: DateTime(2026, 10, 12),
      );
      final quietNewer = _channel(
        id: 'quiet',
        name: 'Quiet',
        createdAt: DateTime(2026, 10, 11),
      );

      final list = [quietNewer, activeOld]
        ..sort(MessagingService.compareChannelsByRecentActivity);

      expect(list.first.id, 'active');
    });

    test(
      'two channels with neither a message nor a createdAt fall back to name',
      () {
        final b = _channel(id: 'b', name: 'Bravo');
        final a = _channel(id: 'a', name: 'Alpha');

        final list = [b, a]
          ..sort(MessagingService.compareChannelsByRecentActivity);

        expect(list.first.id, 'a');
      },
    );
  });
}
