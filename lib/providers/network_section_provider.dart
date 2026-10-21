import '../models/network_models.dart';
import '../services/network_service.dart';
import 'async_section.dart';

/// Loads one Network leaf screen's data.
///
/// Built on the shared [AsyncSection], which Phase 9 promoted out of the Social
/// module so both share one implementation of the value/loading/failed plumbing.
class NetworkSection<T> extends AsyncSection<T> {
  NetworkSection(super.value);

  /// Constructed lazily: these providers are created during `build`, before a
  /// widget test has any reason to have initialised Supabase.
  static NetworkService? _shared;
  static NetworkService get service => _shared ??= NetworkService();
}

/// My Networks — the caller's connections from either side.
class NetworkMembershipsSection
    extends NetworkSection<List<NetworkMembership>> {
  NetworkMembershipsSection() : super(const []);

  Future<void> loadFor(String userId) =>
      load(() => NetworkSection.service.listMemberships(userId));
}

/// My Leads — network leads plus their derived status counts.
class NetworkLeadsSection extends NetworkSection<List<NetworkLead>> {
  NetworkLeadsSection() : super(const []);

  Future<void> loadFor(String userId, {required bool isBuilder}) => load(
    () => NetworkSection.service.listLeads(userId, isBuilder: isBuilder),
  );

  LeadStatusCounts get counts => LeadStatusCounts.fromLeads(value);
}

/// My Referrals — referrals, commissions and scored periods together, since all
/// four sub-tabs read from the same three tables.
class NetworkReferralsSection extends NetworkSection<ReferralBundle> {
  NetworkReferralsSection() : super(ReferralBundle.empty);

  Future<void> loadFor(String userId, {required bool isBuilder}) => load(
    () =>
        NetworkSection.service.getReferralBundle(userId, isBuilder: isBuilder),
  );
}

/// Communication — the network's channels.
class NetworkChannelsSection extends NetworkSection<List<NetworkChannel>> {
  NetworkChannelsSection() : super(const []);

  Future<void> loadFor(String builderId) =>
      load(() => NetworkSection.service.listChannels(builderId));
}
