import 'package:flutter/foundation.dart';

import 'async_section.dart';

import '../models/social_models.dart';
import '../services/social_service.dart';

/// Loads one Social screen's data.
///
/// The six leaf screens each fetch exactly one thing and share the same
/// loading/failed/dispose plumbing, which now lives in [AsyncSection] — Phase 9
/// promoted it so the Network leaves could reuse it instead of copying it. This
/// subclass adds the shared [SocialService] holder.
///
/// Typed aliases below give the Provider lookups a concrete type, since
/// `context.read<AsyncSection<List<AdLead>>>()` is both unwieldy and easy to
/// mismatch.
class SocialSection<T> extends AsyncSection<T> {
  SocialSection(super.value);

  /// Constructed lazily: these providers are created during `build`, before a
  /// widget test has any reason to have initialised Supabase.
  static SocialService? _shared;
  static SocialService get service => _shared ??= SocialService();

  /// Replaces the service for the duration of a test.
  @visibleForTesting
  static set service(SocialService value) => _shared = value;
}

/// Meta connection status — the Accounts screen.
class SocialAccountSection extends SocialSection<SocialAccount?> {
  SocialAccountSection() : super(null);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.getAccount(userId));
}

/// Share preferences — the Preferences screen.
class SocialPreferencesSection extends SocialSection<SocialPreferences> {
  SocialPreferencesSection() : super(SocialPreferences.defaults);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.getPreferences(userId));
}

/// The live publish queue — the Activity screen. Reads `social_share_queue`
/// (via [SocialService.listQueue]), not `social_share_logs`: the queue is the
/// only place a `queued` or `canceled` job is ever visible.
class SocialActivitySection extends SocialSection<List<ShareQueueItem>> {
  SocialActivitySection() : super(const []);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.listQueue(userId));
}

/// Publishing aggregate — the Analytics screen.
class SocialAnalyticsSection extends SocialSection<SocialAnalytics> {
  SocialAnalyticsSection() : super(SocialAnalytics.empty);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.getAnalytics(userId));
}

/// Ad campaigns — the Campaigns screen.
class SocialCampaignsSection extends SocialSection<List<AdCampaign>> {
  SocialCampaignsSection() : super(const []);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.listCampaigns(userId));
}

/// Lead-ad submissions — the Leads screen.
class SocialLeadsSection extends SocialSection<List<AdLead>> {
  SocialLeadsSection() : super(const []);

  Future<void> loadFor(String userId) =>
      load(() => SocialSection.service.listLeads(userId));
}
