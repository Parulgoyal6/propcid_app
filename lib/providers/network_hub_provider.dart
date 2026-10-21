import 'package:flutter/foundation.dart';

import '../models/network_relationship.dart';
import '../models/network_stats.dart';
import '../services/network_relationship_service.dart';
import '../services/network_service.dart';
import '../services/ratings_service.dart';

/// Loads the Network hub's four KPIs.
///
/// Mirrors [MessagingProvider]'s shape, but the "networks" and "referrals"
/// tiles are no longer a straight pass-through of [NetworkService.
/// getNetworkStats] — see [load]'s own comment for why.
class NetworkHubProvider extends ChangeNotifier {
  NetworkHubProvider({
    NetworkService? service,
    NetworkRelationshipService? relationshipService,
    RatingsService? ratingsService,
  }) : _service = service,
       _relationshipService = relationshipService,
       _ratingsService = ratingsService;

  /// Constructed lazily rather than in a field initialiser: [NetworkService]
  /// resolves `Supabase.instance.client` on construction, and this provider is
  /// created during `build`, before a widget test has any reason to have
  /// initialised Supabase.
  NetworkService? _service;
  NetworkService get _network => _service ??= NetworkService();

  NetworkRelationshipService? _relationshipService;
  NetworkRelationshipService get _relationships =>
      _relationshipService ??= NetworkRelationshipService();

  RatingsService? _ratingsService;
  RatingsService get _ratings => _ratingsService ??= RatingsService();

  NetworkStats _stats = NetworkStats.empty;
  bool _loading = true;
  bool _failed = false;
  bool _disposed = false;
  String? _userId;

  NetworkStats get stats => _stats;
  bool get loading => _loading;
  bool get failed => _failed;
  bool get isBuilder => _isBuilder;

  /// [NetworkService.getNetworkStats] answers "networks" with a raw
  /// `builder_networks` accepted-count on whichever side [isBuilder] picks —
  /// which, because that table's RLS is fully symmetric and shared with the
  /// generic profile "Connect" flow, can include peer connections that are
  /// not genuine network memberships (see `network_relationship.dart`'s
  /// header). This re-derives that one number from [NetworkRelationshipService
  /// .listRelationships]'s classification instead, and also replaces the
  /// portal-inherited hardcoded `totalReferrals: 0` with a real count — every
  /// other figure ([NetworkService.getNetworkStats]'s leads/commissions) is
  /// unchanged and still comes from there.
  ///
  /// Also populates the Performance Summary card's three figures
  /// ([NetworkStats.successRatePercent], [NetworkStats.avgResponseTimeHours],
  /// [NetworkStats.networkRating]) — none of which the portal ever computed
  /// for real either (see [NetworkService.getPerformanceMetrics]'s own
  /// comment).
  ///
  /// That fetch is deliberately kept out of the [Future.wait] below rather
  /// than added as a fourth/fifth entry: the four KPI tiles are the whole
  /// point of this screen, and folding two more queries into the same
  /// `Future.wait` would mean a `network_leads` read failing (or this user
  /// simply having no ratings yet in a way [RatingsService] doesn't already
  /// treat as empty) took the KPI tiles down with it too — a strictly worse
  /// outcome than the Performance Summary card alone falling back to its own
  /// em dashes while the rest of the hub loads normally.
  Future<void> load(String userId, {required bool isBuilder}) async {
    _userId = userId;
    _isBuilder = isBuilder;
    _loading = true;
    _failed = false;
    _safeNotify();

    try {
      final results = await Future.wait([
        _network.getNetworkStats(userId, isBuilder: isBuilder),
        _relationships.listRelationships(userId),
        _relationships.countReferralsMade(userId),
      ]);
      final baseStats = results[0] as NetworkStats;
      final relationships = results[1] as List<NetworkRelationship>;
      final referralsMade = results[2] as int;

      // "My Networks" (my_networks_screen.dart) renders all three active-
      // membership kinds as separate sections — Current Network Members
      // (ownedNetworkMember), Networks Joined (joinedBuilderNetwork) and
      // Peer Connections (peerConnection) — regardless of the viewer's
      // role. Counting only one kind here under-reported the hub tile
      // against what that screen actually shows once opened.
      final networksCount = relationships
          .where((r) => isActiveMembershipKind(r.kind))
          .length;

      final performance = await _loadPerformanceSummary(
        userId,
        isBuilder: isBuilder,
      );

      _stats = NetworkStats(
        totalNetworks: networksCount,
        activeLeads: baseStats.activeLeads,
        totalReferrals: referralsMade,
        monthlyCommissions: baseStats.monthlyCommissions,
        successRatePercent: performance.successRate,
        avgResponseTimeHours: performance.avgResponseTimeHours,
        networkRating: performance.networkRating,
      );
      _failed = false;
    } catch (_) {
      // The hub renders an em dash per tile rather than a zero, so a failed
      // query is never mistaken for "you have no networks".
      _stats = NetworkStats.empty;
      _failed = true;
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// The Performance Summary card's three figures, best-effort.
  ///
  /// A failure here (RLS denying `network_leads` to this role, a transient
  /// network error, anything) degrades to "no data" — the same null the card
  /// already renders as an em dash for a user who simply has no leads or
  /// ratings yet — rather than failing [load] itself.
  Future<
    ({double? successRate, double? avgResponseTimeHours, double? networkRating})
  >
  _loadPerformanceSummary(String userId, {required bool isBuilder}) async {
    try {
      final results = await Future.wait([
        _network.getPerformanceMetrics(userId, isBuilder: isBuilder),
        _ratings.getRatingSummary(userId),
      ]);
      final performance =
          results[0] as ({double? successRate, double? avgResponseTimeHours});
      final ratingSummary = results[1] as ({int count, double average});

      return (
        successRate: performance.successRate,
        avgResponseTimeHours: performance.avgResponseTimeHours,
        networkRating: ratingSummary.count == 0 ? null : ratingSummary.average,
      );
    } catch (_) {
      return (
        successRate: null,
        avgResponseTimeHours: null,
        networkRating: null,
      );
    }
  }

  bool _isBuilder = false;

  /// Re-runs [load] for the already-known user, reusing whichever `isBuilder`
  /// the last [load] call was given.
  ///
  /// This is *not* a re-derivation of the role from `AuthProvider` — this
  /// provider has no context to read it from. A caller that has since learned
  /// a fresher `isBuilder` (e.g. role resolution completed after this
  /// provider's first load, or the caller is reacting to a mutation whose
  /// outcome could change it) must call [load] directly with that value
  /// instead of this method, or the stale cached role will silently persist
  /// across the "refresh". See `network_hub_screen.dart`'s own
  /// `onNetworkChanged` wiring for the pattern.
  Future<void> refresh() {
    final userId = _userId;
    if (userId == null) return Future.value();
    return load(userId, isBuilder: _isBuilder);
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
