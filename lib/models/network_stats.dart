/// The four KPIs the Network hub shows above its navigation cards.
///
/// Mirrors `NetworkStats` in `features/network/NetworkDashboard.tsx` field for
/// field. [totalReferrals] no longer mirrors the portal's own placeholder,
/// though: React hardcodes it to `0` with the comment "Temporarily disable
/// this query to fix TS error", but `network_referrals`/its RLS already
/// support a real `referrer_id`-scoped count (the same query
/// `NetworkService.getReferralBundle` already runs correctly), so
/// [NetworkHubProvider.load] now computes a genuine value via
/// `NetworkRelationshipService.countReferralsMade` instead of perpetuating a
/// gap the portal itself never actually needed to have.
class NetworkStats {
  final int totalNetworks;
  final int activeLeads;
  final int totalReferrals;
  final double monthlyCommissions;

  /// Percentage of this user's `network_leads` with `status = 'converted'`.
  ///
  /// Null means "no data" (no leads at all, or the query failed) — rendered
  /// as an em dash rather than `0%`, which would misreport "you have leads
  /// and none converted" when the truth is "you have no leads yet". See
  /// [NetworkService.getPerformanceMetrics] for where this and
  /// [avgResponseTimeHours] are computed from field for field.
  final double? successRatePercent;

  /// Average hours between `assigned_at` and `contacted_at`, over leads that
  /// reached at least `contacted` with both timestamps set. Null for the same
  /// "no data" reason as [successRatePercent].
  final double? avgResponseTimeHours;

  /// This user's average rating (1-5), the same figure
  /// `RatingsService.getRatingSummary` computes for the Profile screen's
  /// Reviews tile — reused here rather than re-derived, since "how is this
  /// person rated" does not change meaning between the two screens. Null when
  /// they have no ratings yet.
  final double? networkRating;

  const NetworkStats({
    this.totalNetworks = 0,
    this.activeLeads = 0,
    this.totalReferrals = 0,
    this.monthlyCommissions = 0,
    this.successRatePercent,
    this.avgResponseTimeHours,
    this.networkRating,
  });

  /// The zeroed state the provider starts in, so the hub can lay out its grid
  /// before the first query returns.
  static const NetworkStats empty = NetworkStats();

  /// `₹24,500` — Indian digit grouping (last three, then pairs), matching how
  /// the rest of the app renders rupee amounts.
  ///
  /// Not reusing `PropertyModel.formatIndianPrice`: that one abbreviates to
  /// `Cr`/`L` for listing prices and drops the separators below a lakh, which
  /// would render a commission of 24500 as `₹24500`.
  String get monthlyCommissionsDisplay {
    final whole = monthlyCommissions.round().abs();
    final digits = whole.toString();

    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final lastThree = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final pairs = <String>[];
      while (rest.length > 2) {
        pairs.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) pairs.insert(0, rest);
      grouped = '${pairs.join(',')},$lastThree';
    }

    final sign = monthlyCommissions < 0 ? '-' : '';
    return '$sign₹$grouped';
  }

  /// `85%`, or an em dash with no leads to compute from.
  String get successRateDisplay {
    final rate = successRatePercent;
    return rate == null ? '—' : '${rate.round()}%';
  }

  /// `2.3 hrs`, or an em dash with no contacted lead to compute from.
  String get avgResponseTimeDisplay {
    final hours = avgResponseTimeHours;
    return hours == null ? '—' : '${hours.toStringAsFixed(1)} hrs';
  }

  /// `4.8/5`, or an em dash with no ratings yet — matching
  /// `RatingSummaryCard`'s own "no ratings" treatment rather than showing
  /// `0.0/5`, which would read as a poor rating instead of an absent one.
  String get networkRatingDisplay {
    final rating = networkRating;
    return rating == null ? '—' : '${rating.toStringAsFixed(1)}/5';
  }
}
