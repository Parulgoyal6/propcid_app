/// Read-only models for Network ▸ Analytics — the builder-only screen the
/// portal renders as `features/analytics/NetworkAnalyticsDashboard.tsx`.
///
/// Every field here mirrors a real query that component runs; nothing is a
/// hardcoded placeholder — a `0` means the query genuinely returned nothing
/// for that builder yet, exactly as it does on the portal.
library;

import 'network_models.dart' show formatRupeeAmount;

double _double(dynamic value) =>
    value == null ? 0 : (double.tryParse('$value') ?? 0);

int _int(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;

/// The Analytics screen's four KPI tiles plus the Network Health card's two
/// progress bars. Mirrors `NetworkAnalyticsDashboard.tsx`'s parallel-fetched
/// `networkStats` exactly:
///
///   total_members      -> builder_networks, no status filter
///   active_members     -> builder_networks, status = 'accepted'
///   total_leads_distributed -> network_leads, no status filter
///   converted_leads     -> network_leads, status = 'converted' (used only
///                          to derive the conversion rate)
///   total_commissions_paid  -> sum(network_commissions.amount) where
///                          status = 'paid'
///   total_referrals     -> network_referrals, no status filter
///
/// [totalMembers] is deliberately not the same number as the Network hub's
/// "Network Members" tile — that one is accepted-only. This mirrors the
/// portal's own two independent queries rather than reusing one for both.
class NetworkAnalyticsStats {
  final int totalMembers;
  final int activeMembers;
  final int totalLeadsDistributed;
  final int convertedLeads;
  final double totalCommissionsPaid;
  final int totalReferrals;

  const NetworkAnalyticsStats({
    this.totalMembers = 0,
    this.activeMembers = 0,
    this.totalLeadsDistributed = 0,
    this.convertedLeads = 0,
    this.totalCommissionsPaid = 0,
    this.totalReferrals = 0,
  });

  static const NetworkAnalyticsStats empty = NetworkAnalyticsStats();

  /// `convertedLeads / totalLeadsDistributed * 100`, `0` with no leads yet —
  /// the exact guard `NetworkAnalyticsDashboard.tsx` uses
  /// (`totalLeads > 0 ? ... : 0`).
  double get averageConversionRate => totalLeadsDistributed > 0
      ? (convertedLeads / totalLeadsDistributed) * 100
      : 0;

  /// `activeMembers / totalMembers * 100`, guarded the same way — feeds the
  /// Network Health card's "Active Members" bar.
  double get activeMemberRate =>
      totalMembers > 0 ? (activeMembers / totalMembers) * 100 : 0;

  String get conversionRateDisplay =>
      '${averageConversionRate.toStringAsFixed(1)}%';

  String get commissionsPaidDisplay => formatRupeeAmount(totalCommissionsPaid);
}

/// One `network_performance` row on the Performance leaderboard, with the
/// member's public profile resolved. `network_performance`'s live schema
/// (verified against `20250914121741_...sql:65-84`): `member_id`,
/// `leads_received`, `leads_converted`, `referrals_made`,
/// `referrals_converted`, `conversion_rate`, `performance_score`,
/// `total_commission_earned`.
class NetworkPerformanceEntry {
  final String id;
  final String memberId;
  final int leadsReceived;
  final int leadsConverted;
  final int referralsMade;
  final int referralsConverted;
  final double conversionRate;
  final double performanceScore;
  final double totalCommissionEarned;
  final String? displayName;
  final String? avatarUrl;
  final String? userType;

  const NetworkPerformanceEntry({
    required this.id,
    required this.memberId,
    this.leadsReceived = 0,
    this.leadsConverted = 0,
    this.referralsMade = 0,
    this.referralsConverted = 0,
    this.conversionRate = 0,
    this.performanceScore = 0,
    this.totalCommissionEarned = 0,
    this.displayName,
    this.avatarUrl,
    this.userType,
  });

  factory NetworkPerformanceEntry.fromSupabase(
    Map<String, dynamic> json, {
    String? displayName,
    String? avatarUrl,
    String? userType,
  }) {
    return NetworkPerformanceEntry(
      id: '${json['id'] ?? ''}',
      memberId: '${json['member_id'] ?? ''}',
      leadsReceived: _int(json['leads_received']),
      leadsConverted: _int(json['leads_converted']),
      referralsMade: _int(json['referrals_made']),
      referralsConverted: _int(json['referrals_converted']),
      conversionRate: _double(json['conversion_rate']),
      performanceScore: _double(json['performance_score']),
      totalCommissionEarned: _double(json['total_commission_earned']),
      displayName: displayName,
      avatarUrl: avatarUrl,
      userType: userType,
    );
  }

  String get resolvedName => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : 'Unknown';

  String get initial =>
      resolvedName.isEmpty ? '?' : resolvedName[0].toUpperCase();

  /// `broker` -> `Broker`.
  String get roleLabel {
    final type = userType?.trim() ?? '';
    if (type.isEmpty) return 'Member';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  String get commissionEarnedDisplay =>
      formatRupeeAmount(totalCommissionEarned);

  String get conversionRateDisplay => '${conversionRate.toStringAsFixed(1)}%';
}
