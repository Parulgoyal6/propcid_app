import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/subscription_summary.dart';

/// Read-only billing reads for the Subscription & Billing screen.
///
/// A direct port of `PaymentContext.refreshBillingData`, which fetches the same
/// three sources in parallel:
///   1. the caller's latest `subscriptions` row,
///   2. the `billing-history` Edge Function (payments ⨝ invoices ⨝ refunds),
///   3. the caller's `billing_profiles` row.
///
/// Nothing here writes. Every mutating billing path React has — `create-order`,
/// `verify-payment`, `refund-payment`, `manage-subscription`,
/// `update-billing-profile` — is deliberately untouched: those carry the money
/// movement and the Razorpay integration, and this phase is visibility only.
class SubscriptionService {
  /// Resolved lazily so the class can be referenced in tests without an
  /// initialised Supabase client.
  SupabaseClient get _supabase => Supabase.instance.client;

  /// The caller's current subscription, or [SubscriptionSummary.free] when no
  /// row exists — React's `?? "free"` fallback, made explicit.
  Future<SubscriptionSummary> getSubscription(String userId) async {
    try {
      final row = await _supabase
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return SubscriptionSummary.free;
      return SubscriptionSummary.fromJson(row);
    } catch (e) {
      debugPrint('SubscriptionService.getSubscription failed: $e');
      rethrow;
    }
  }

  /// The caller's billing profile, or null when they have never saved one.
  Future<BillingProfile?> getBillingProfile(String userId) async {
    try {
      final row = await _supabase
          .from('billing_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (row == null) return null;
      return BillingProfile.fromJson(row);
    } catch (e) {
      debugPrint('SubscriptionService.getBillingProfile failed: $e');
      rethrow;
    }
  }

  /// Payments + invoices + refunds, already joined and shaped by the existing
  /// `billing-history` function.
  ///
  /// Invoked rather than reimplemented on purpose. That function owns the
  /// payment/refund status mapping and the GST derivation; rebuilding the join
  /// in Dart would duplicate business logic and let the two portals drift. It
  /// authenticates the caller itself and only ever returns their own rows, so
  /// no user id is passed.
  Future<List<BillingHistoryItem>> getBillingHistory() async {
    try {
      final response = await _supabase.functions.invoke('billing-history');
      final data = response.data;
      if (data is! Map) return const [];

      final items = data['items'];
      if (items is! List) return const [];

      return items
          .whereType<Map>()
          .map(
            (item) =>
                BillingHistoryItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      debugPrint('SubscriptionService.getBillingHistory failed: $e');
      rethrow;
    }
  }
}
