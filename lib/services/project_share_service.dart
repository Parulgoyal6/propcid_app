// services/project_share_service.dart
//
// "Share project" — notifies a builder's accepted network connections that a
// project has been published.
//
// A COMPANION, BY NECESSITY
// -------------------------
// `NetworkService` declares itself read-only in its own header — *"Every method
// is a `select`"* — and lists the network writes that stay with the web portal.
// Adding an insert there would falsify that contract. Its `listMemberships` is
// also the wrong shape for this: it does **not** filter `status`, so reusing it
// would notify pending and rejected connections too.
//
// WHAT IT PORTS
// -------------
// `BuilderProjectsManager.tsx:308-380` (`handleShareProject`) plus
// `utils/notificationHelpers.ts:174-187` (`notifyProjectShared`):
//
//   1. read the builder's company/display name for the message;
//   2. select `builder_networks` where `builder_id = me OR member_id = me` **and**
//      `status = 'accepted'`;
//   3. for each row take the *other* party — a builder can appear on either side;
//   4. dedupe, because two rows can name the same counterpart;
//   5. one `notifications` row each.
//
// `notifications` INSERT is `TO authenticated WITH CHECK (auth.uid() IS NOT
// NULL)`, so writing a row addressed to someone else is permitted — which is what
// makes this fan-out possible at all.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How the share attempt ended.
@immutable
class ProjectShareResult {
  const ProjectShareResult({
    required this.notified,
    required this.dropped,
    required this.hasNetwork,
  });

  /// Connections that received a notification.
  final int notified;

  /// Connections beyond [ProjectShareService.maxRecipients] that were skipped.
  ///
  /// Surfaced rather than swallowed: a builder who thinks all 800 of their
  /// contacts were told, when 300 were not, has been misled by the success
  /// message.
  final int dropped;

  /// False when the builder has no accepted connections at all — the portal
  /// refuses with a message instead of reporting a share of zero.
  final bool hasNetwork;

  bool get isEmpty => !hasNetwork;
}

class ProjectShareService {
  ProjectShareService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Ceiling on one fan-out.
  ///
  /// The portal has none — it fires a `Promise.all` over every connection, which
  /// for a large network means hundreds of concurrent inserts from a phone. These
  /// go sequentially and stop here; anything beyond is reported in
  /// [ProjectShareResult.dropped] rather than quietly dropped.
  static const int maxRecipients = 500;

  /// `notifications.type` for this event — `notifyProjectShared`'s value.
  static const String notificationType = 'project_shared';

  /// Notifies every accepted connection about [projectId].
  ///
  /// Throws only when the *network read* fails — the caller cannot report
  /// anything sensible without it. Individual notification inserts are allowed to
  /// fail quietly: the project is already published, and one undelivered
  /// notification must not present as a failed share.
  Future<ProjectShareResult> shareProject({
    required String builderId,
    required String projectId,
    required String projectTitle,
  }) async {
    final builderName = await _builderName(builderId);
    final recipients = await _acceptedCounterparts(builderId);

    if (recipients.isEmpty) {
      return const ProjectShareResult(
        notified: 0,
        dropped: 0,
        hasNetwork: false,
      );
    }

    final targets = recipients.take(maxRecipients).toList(growable: false);
    final dropped = recipients.length - targets.length;
    if (dropped > 0) {
      debugPrint(
        'ProjectShareService: network of ${recipients.length} exceeds the '
        '$maxRecipients cap; $dropped connection(s) were not notified for '
        'project $projectId.',
      );
    }

    var notified = 0;
    for (final userId in targets) {
      try {
        await _supabase.from('notifications').insert({
          'user_id': userId,
          'type': notificationType,
          'title': 'New Project Shared',
          'message': '$builderName shared a project: "$projectTitle"',
          'data': {
            'projectId': projectId,
            'projectTitle': projectTitle,
            'builderName': builderName,
          },
        });
        notified++;
      } catch (e) {
        // Logged, not rethrown — see the method doc.
        debugPrint('ProjectShareService: notify $userId failed: $e');
      }
    }

    return ProjectShareResult(
      notified: notified,
      dropped: dropped,
      hasNetwork: true,
    );
  }

  /// The name the message is signed with.
  ///
  /// `company_name || display_name || 'A builder'` — the portal's fallback chain
  /// (`BuilderProjectsManager.tsx:330-333`). A failed read is not fatal: the
  /// share still goes out signed generically.
  Future<String> _builderName(String builderId) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select('display_name, company_name')
          .eq('user_id', builderId)
          .maybeSingle();

      final company = row?['company_name']?.toString().trim() ?? '';
      if (company.isNotEmpty) return company;
      final display = row?['display_name']?.toString().trim() ?? '';
      if (display.isNotEmpty) return display;
    } catch (e) {
      debugPrint('ProjectShareService: builder name lookup failed: $e');
    }
    return 'A builder';
  }

  /// The other party in every accepted connection, deduplicated.
  ///
  /// A builder can sit on either side of `builder_networks`, so the counterpart
  /// is whichever column is not theirs. Self-references are dropped — a row where
  /// both ids are the builder would otherwise notify them about their own
  /// project.
  Future<List<String>> _acceptedCounterparts(String builderId) async {
    try {
      final rows = await _supabase
          .from('builder_networks')
          .select('builder_id, member_id')
          .or('builder_id.eq.$builderId,member_id.eq.$builderId')
          .eq('status', 'accepted');

      final seen = <String>{};
      for (final row in rows) {
        final rowBuilder = row['builder_id']?.toString() ?? '';
        final rowMember = row['member_id']?.toString() ?? '';
        final other = rowBuilder == builderId ? rowMember : rowBuilder;
        if (other.isEmpty || other == builderId) continue;
        seen.add(other);
      }
      return seen.toList(growable: false);
    } catch (e) {
      debugPrint('ProjectShareService: network read failed: $e');
      rethrow;
    }
  }
}
