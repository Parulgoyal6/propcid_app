import 'package:flutter/foundation.dart';

import '../models/subscription_summary.dart';
import '../services/subscription_service.dart';

/// State for the Subscription & Billing screen.
///
/// Loads the three read-only sources in parallel, exactly as
/// `PaymentContext.refreshBillingData` does, and tracks failure per source so a
/// broken Edge Function does not blank out the plan card that loaded fine.
class SubscriptionProvider extends ChangeNotifier {
  /// Constructed lazily: this provider is created during `build`, before a
  /// widget test has any reason to have initialised Supabase.
  SubscriptionService? _service;
  SubscriptionService get _billing => _service ??= SubscriptionService();

  SubscriptionSummary _subscription = SubscriptionSummary.free;
  BillingProfile? _billingProfile;
  List<BillingHistoryItem> _history = const [];

  bool _loading = true;
  bool _subscriptionFailed = false;
  bool _historyFailed = false;
  bool _disposed = false;
  String? _userId;

  SubscriptionSummary get subscription => _subscription;
  BillingProfile? get billingProfile => _billingProfile;
  List<BillingHistoryItem> get history => List.unmodifiable(_history);

  bool get loading => _loading;

  /// True when the `subscriptions` read itself failed — the plan card shows em
  /// dashes rather than implying the user is on the free tier.
  bool get subscriptionFailed => _subscriptionFailed;

  /// True when `billing-history` failed. Distinct from an empty history: the
  /// design's "No payments yet" copy is only honest when the query succeeded.
  bool get historyFailed => _historyFailed;

  /// Completed payments only, newest first — what the Payments and Invoices
  /// tabs list.
  List<BillingHistoryItem> get completedPayments => List.unmodifiable(
    _history.where((i) => i.paymentStatus == 'completed').toList(),
  );

  List<BillingHistoryItem> get refunds =>
      List.unmodifiable(_history.where((i) => i.hasRefund).toList());

  /// Total billed across all completed payments, in rupees.
  double get totalBilled => completedPayments.fold<double>(
    0,
    (sum, item) => sum + (item.finalAmount ?? item.amount),
  );

  Future<void> load(String userId) async {
    _userId = userId;
    _loading = true;
    _subscriptionFailed = false;
    _historyFailed = false;
    _safeNotify();

    // Parallel, like React — and independently guarded, so one failure does not
    // discard the other two results.
    await Future.wait([
      _loadSubscription(userId),
      _loadHistory(),
      _loadProfile(userId),
    ]);

    _loading = false;
    _safeNotify();
  }

  Future<void> _loadSubscription(String userId) async {
    try {
      _subscription = await _billing.getSubscription(userId);
      _subscriptionFailed = false;
    } catch (_) {
      _subscription = SubscriptionSummary.free;
      _subscriptionFailed = true;
    }
  }

  Future<void> _loadHistory() async {
    try {
      _history = await _billing.getBillingHistory();
      _historyFailed = false;
    } catch (_) {
      _history = const [];
      _historyFailed = true;
    }
  }

  Future<void> _loadProfile(String userId) async {
    try {
      _billingProfile = await _billing.getBillingProfile(userId);
    } catch (_) {
      // A missing billing profile and an unreadable one look the same to the
      // user — both render the design's empty field placeholders — so this does
      // not get its own failure flag.
      _billingProfile = null;
    }
  }

  Future<void> refresh() {
    final userId = _userId;
    if (userId == null) return Future.value();
    return load(userId);
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
