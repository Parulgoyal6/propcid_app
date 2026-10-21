// Unit tests for ChannelParticipantDetail.fromJson — the shape returned by
// the `channel-participants-list` edge function, consumed by
// ChannelSettingsScreen's Members tab. Pure parsing, no widget/network setup
// needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/channel_summary.dart';

Map<String, dynamic> row({
  String id = 'p1',
  String userId = 'u1',
  String? role,
  String? joinedAt,
  String? blockedAt,
  Map<String, dynamic>? profile,
}) => {
  'id': id,
  'user_id': userId,
  if (role != null) 'role': role,
  if (joinedAt != null) 'joined_at': joinedAt,
  'blocked_at': blockedAt,
  if (profile != null) 'user_profile': profile,
};

void main() {
  group('ChannelParticipantDetail.fromJson', () {
    test('parses a full admin row', () {
      final p = ChannelParticipantDetail.fromJson(
        row(
          id: 'row-1',
          userId: 'user-1',
          role: 'admin',
          joinedAt: '2026-01-01T00:00:00Z',
          profile: {'display_name': 'Abhishek', 'avatar_url': 'a.png'},
        ),
      );

      expect(p.id, 'row-1');
      expect(p.userId, 'user-1');
      expect(p.role, 'admin');
      expect(p.joinedAt, DateTime.parse('2026-01-01T00:00:00Z'));
      expect(p.blockedAt, isNull);
      expect(p.displayName, 'Abhishek');
      expect(p.avatarUrl, 'a.png');
      expect(p.initial, 'A');
    });

    test('defaults role to member when absent', () {
      final p = ChannelParticipantDetail.fromJson(row());
      expect(p.role, 'member');
    });

    test('parses a non-null blocked_at', () {
      final p = ChannelParticipantDetail.fromJson(
        row(blockedAt: '2026-02-01T00:00:00Z'),
      );
      expect(p.blockedAt, DateTime.parse('2026-02-01T00:00:00Z'));
    });

    test('falls back to "Unknown User" when no profile is resolved', () {
      final p = ChannelParticipantDetail.fromJson(row());
      expect(p.displayName, 'Unknown User');
      expect(p.avatarUrl, isNull);
      expect(p.initial, 'U');
    });

    test('falls back to "Unknown User" when display_name is blank', () {
      final p = ChannelParticipantDetail.fromJson(
        row(profile: {'display_name': '   ', 'avatar_url': null}),
      );
      expect(p.displayName, 'Unknown User');
    });
  });
}
