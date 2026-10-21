/// Read-only models for the Subscription & Billing surface.
///
/// Field names and semantics mirror `src/contexts/PaymentContext.tsx`, which is
/// the React portal's single source of billing state. Column names come from
/// the live `subscriptions`, `billing_profiles`, `payments`, `invoices` and
/// `refunds` tables — nothing here is inferred.
///
/// Money: the backend stores every amount as an integer in the smallest
/// currency unit (paise for INR), because that is what Razorpay expects.
/// React converts once in `mapBackendBillingItem` via its `toRupees` helper;
/// [BillingHistoryItem.fromJson] does the same, so every amount exposed by
/// these models is already in rupees.
library;

double? _paiseToRupees(dynamic paise) {
  if (paise == null) return null;
  final value = num.tryParse('$paise');
  return value == null ? null : value / 100;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}

/// One row of the `billing-history` Edge Function's `items` array.
///
/// That function joins `payments` with its nested `invoices` and `refunds` and
/// derives the GST/refund fields. It is invoked rather than reimplemented: the
/// join and the status mapping are business logic that already exists and must
/// not be duplicated.
class BillingHistoryItem {
  final String id;
  final DateTime? date;
  final String plan;

  /// Invoice subtotal, in rupees.
  final double amount;
  final String billingCycle;
  final String paymentStatus;
  final String refundStatus;
  final String transactionId;
  final String? invoiceUrl;
  final String? invoiceId;
  final String? invoiceNumber;
  final double? gstAmount;
  final double? finalAmount;
  final double? originalAmount;
  final double? refundAmount;

  const BillingHistoryItem({
    required this.id,
    required this.plan,
    required this.amount,
    required this.billingCycle,
    required this.paymentStatus,
    required this.refundStatus,
    required this.transactionId,
    this.date,
    this.invoiceUrl,
    this.invoiceId,
    this.invoiceNumber,
    this.gstAmount,
    this.finalAmount,
    this.originalAmount,
    this.refundAmount,
  });

  factory BillingHistoryItem.fromJson(Map<String, dynamic> json) {
    return BillingHistoryItem(
      id: '${json['id'] ?? ''}',
      date: _parseDate(json['date']),
      plan: '${json['plan'] ?? 'free'}',
      amount: _paiseToRupees(json['amount']) ?? 0,
      billingCycle: '${json['billingCycle'] ?? 'monthly'}',
      paymentStatus: '${json['paymentStatus'] ?? 'pending'}',
      refundStatus: '${json['refundStatus'] ?? 'none'}',
      transactionId: '${json['transactionId'] ?? ''}',
      invoiceUrl: json['invoiceUrl'] as String?,
      invoiceId: json['invoiceId'] as String?,
      invoiceNumber: json['invoiceNumber'] as String?,
      gstAmount: _paiseToRupees(json['gstAmount']),
      finalAmount: _paiseToRupees(json['finalAmount']),
      originalAmount: _paiseToRupees(json['originalAmount']),
      refundAmount: _paiseToRupees(json['refundAmount']),
    );
  }

  bool get hasRefund => refundStatus != 'none';
}

/// The caller's `billing_profiles` row — the details printed on invoices.
class BillingProfile {
  final String? companyName;
  final String? gstNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? country;
  final String? postalCode;
  final String? phone;
  final String? email;

  const BillingProfile({
    this.companyName,
    this.gstNumber,
    this.address,
    this.city,
    this.state,
    this.country,
    this.postalCode,
    this.phone,
    this.email,
  });

  factory BillingProfile.fromJson(Map<String, dynamic> json) {
    return BillingProfile(
      companyName: json['company_name'] as String?,
      gstNumber: json['gst_number'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
    );
  }
}

/// The caller's most recent `subscriptions` row, with React's defaults applied.
///
/// React falls back to `free` / `active` / `monthly` when no row exists, which
/// is the correct reading: a user who has never paid is on the free tier.
class SubscriptionSummary {
  final String plan;
  final String status;
  final String billingCycle;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final bool autoRenew;
  final bool cancelAtPeriodEnd;

  /// False when no `subscriptions` row exists at all — the user is on the
  /// implicit free tier rather than an explicitly recorded one.
  final bool isRecorded;

  const SubscriptionSummary({
    this.plan = 'free',
    this.status = 'active',
    this.billingCycle = 'monthly',
    this.startsAt,
    this.expiresAt,
    this.autoRenew = false,
    this.cancelAtPeriodEnd = false,
    this.isRecorded = false,
  });

  /// The state React renders before any query returns, and the state a user
  /// with no subscription row stays in.
  static const SubscriptionSummary free = SubscriptionSummary();

  factory SubscriptionSummary.fromJson(Map<String, dynamic> json) {
    return SubscriptionSummary(
      plan: '${json['plan'] ?? 'free'}',
      status: '${json['status'] ?? 'active'}',
      billingCycle: '${json['billing_cycle'] ?? 'monthly'}',
      startsAt: _parseDate(json['starts_at']),
      expiresAt: _parseDate(json['expires_at']),
      autoRenew: json['auto_renew'] == true,
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      isRecorded: true,
    );
  }

  bool get isFree => plan.toLowerCase() == 'free';

  /// `free` → `Free Plan`. The stored value is a plan id, not display copy.
  String get planLabel {
    if (plan.isEmpty) return 'Free Plan';
    final pretty = plan[0].toUpperCase() + plan.substring(1).toLowerCase();
    return '$pretty Plan';
  }

  /// `Sep 02, 2026`, matching the design's renewal format. Null when there is
  /// no renewal date to show.
  String? get renewalLabel {
    final date = expiresAt;
    if (date == null) return null;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final day = date.day.toString().padLeft(2, '0');
    return '${months[date.month - 1]} $day, ${date.year}';
  }
}
