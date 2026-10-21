import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around the deployed payment Supabase Edge Functions.
///
/// Never creates, edits or redeploys a function — this only calls the ones already
/// deployed for the shared backend (the same functions the website uses):
/// `create-order`, `verify-payment`, `manage-subscription`, `refund-payment`,
/// `download-invoice` and `update-billing-profile`.
///
/// `payment-webhook` is deliberately absent: Razorpay calls it server-to-server, and
/// it is what makes a payment durable if the client dies between checkout and
/// verification. A client has no business invoking it.
///
/// WRITE-ONLY BY DESIGN
/// --------------------
/// Reads stay with `SubscriptionService`, which owns `billing-history` and the
/// `subscriptions` / billing-profile queries. This service performs the mutations and
/// then the caller asks `SubscriptionProvider.refresh()` to re-read — so there is one
/// reader and one writer rather than two of each.
///
/// THE CLIENT NEVER SENDS AN AMOUNT
/// -------------------------------
/// [createOrder] sends `planId`, `billingCycle`, `currency` and an idempotency key.
/// `create-order` resolves the charge itself via `resolvePriceInr(role, planId,
/// cycle)`, reading the caller's own `profiles.user_type`. A client-supplied amount
/// would be a client-controlled price.
class PaymentService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// TEMPORARY payment tracing. Debug builds only; remove once the flow is
  /// confirmed on device. Logs function names and status, never a body — these
  /// payloads carry order ids and billing state.
  void _log(String message) {
    if (kDebugMode) debugPrint('[payments] $message');
  }

  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — surface the server's own message rather than a generic one.
  Future<Map<String, dynamic>> _invoke(
    String function, {
    required Map<String, dynamic> body,
  }) async {
    _log('→ $function');
    try {
      // Bounded so a socket that connects and then goes silent surfaces as an
      // error the caller already handles rather than an await that never
      // returns. Not a business rule — the functions themselves time out well
      // inside this, so reaching it means the transport is the problem.
      final response = await _supabase.functions
          .invoke(function, body: body)
          .timeout(const Duration(seconds: 45));
      final data = response.data;
      _log(
        '← $function status=${response.status} '
        'data=${data.runtimeType} keys=${data is Map ? data.keys.toList() : '-'}',
      );
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      // The transport hands back `Map<String, dynamic>` for a JSON object, but a
      // cast is not safe on a decoded nested map — take the keys as they come.
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    } on FunctionException catch (e) {
      _log(
        '✗ $function FunctionException status=${e.status} details=${e.details}',
      );
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ??
          'Could not reach the server. Please try again.';
    } on TimeoutException {
      _log('✗ $function timed out');
      throw 'The server took too long to respond. Please try again.';
    } catch (e) {
      _log('✗ $function threw ${e.runtimeType}: $e');
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  /// A fresh RFC-4122 v4 idempotency key.
  ///
  /// One per checkout **attempt**. `create-order` keys its dedupe on this, so a
  /// double-tap with the same key returns the first order rather than opening a
  /// second one — and a genuine retry after a cancellation must get a new key or it
  /// would resurrect the abandoned order.
  ///
  /// Hand-rolled rather than adding the `uuid` package: the server needs uniqueness,
  /// not RFC ceremony, and `Random.secure()` gives 122 bits of it.
  static String newIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Version 4, variant 1 — the two fields a v4 UUID pins.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  // ── Checkout ──────────────────────────────────────────────────────────────

  /// Creates a Razorpay order and returns what the checkout sheet needs.
  ///
  /// `PaymentContext.tsx:333-343`, body for body. The response carries `orderId`,
  /// `amount` (in the smallest currency unit — paise for INR, which is what Razorpay
  /// expects), `currency` and `keyId`.
  ///
  /// [idempotencyKey] must be **regenerated per attempt**, not per screen: it is what
  /// stops a double-tap becoming two orders, and reusing it across a genuine retry
  /// after a cancellation would return the stale order.
  ///
  /// Throws when the function returns no `orderId`, which the portal treats the same
  /// way (`:341`) — a 200 with no order is still a failure.
  Future<PaymentOrder> createOrder({
    required String planId,
    required String billingCycle,
    required String idempotencyKey,
    String currency = 'INR',
  }) async {
    final data = await _invoke(
      'create-order',
      body: {
        'planId': planId,
        'billingCycle': billingCycle,
        'currency': currency,
        'idempotencyKey': idempotencyKey,
      },
    );

    final order = PaymentOrder.fromJson(data);
    if (order.orderId.isEmpty || order.keyId.isEmpty) {
      throw 'Failed to create payment order.';
    }
    return order;
  }

  /// Quotes what a checkout would charge, without creating a Razorpay order or
  /// a `payments` row.
  ///
  /// `create-order` supports a `preview: true` mode for exactly this
  /// (`create-order/index.ts:90-95,196-208`) — the same subtotal/tax/proration
  /// arithmetic [createOrder] would charge, computed server-side so the
  /// checkout review screen never has to reproduce `computeOrderAmount`'s GST
  /// and proration rules on the client and risk drifting from them. Read-only:
  /// no row is written, so calling this on every plan-card tap (before the user
  /// has committed to paying) is safe, unlike [createOrder] itself.
  Future<PaymentQuote> previewOrder({
    required String planId,
    required String billingCycle,
    String currency = 'INR',
  }) async {
    final data = await _invoke(
      'create-order',
      body: {
        'planId': planId,
        'billingCycle': billingCycle,
        'currency': currency,
        'preview': true,
      },
    );
    return PaymentQuote.fromJson(data);
  }

  /// Verifies a completed Razorpay payment and activates the subscription.
  ///
  /// `PaymentContext.tsx:362-374`. The signature is checked server-side against the
  /// order — this is the step that makes the payment real, so a success callback from
  /// Razorpay that fails here has **not** bought anything.
  ///
  /// Throws unless the response carries `success: true`, matching the portal's own
  /// check (`:372`).
  Future<Map<String, dynamic>> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final data = await _invoke(
      'verify-payment',
      body: {
        'razorpayOrderId': razorpayOrderId,
        'razorpayPaymentId': razorpayPaymentId,
        'razorpaySignature': razorpaySignature,
      },
    );

    if (data['success'] != true) {
      throw 'Payment verification failed.';
    }
    return data;
  }

  // ── Subscription lifecycle (`manage-subscription`) ────────────────────────

  /// Cancels at period end. `PaymentContext.tsx:442-443`.
  Future<Map<String, dynamic>> cancelSubscription() =>
      _invoke('manage-subscription', body: {'action': 'cancel'});

  /// Undoes a pending cancellation. `:465-466`.
  Future<Map<String, dynamic>> resumeSubscription() =>
      _invoke('manage-subscription', body: {'action': 'resume'});

  /// Switches plan, in either direction. `:491-492`.
  ///
  /// The server validates the move against `PLAN_TIER` and recomputes the charge, so
  /// an upgrade and a downgrade go through this same call — the naming follows the
  /// portal's `change_plan` rather than splitting it.
  ///
  /// [billingCycle] is optional because the portal's `changePlan(planId,
  /// billingCycle?)` is: omitting it keeps the subscription's current cycle.
  Future<Map<String, dynamic>> changePlan({
    required String planId,
    String? billingCycle,
  }) => _invoke(
    'manage-subscription',
    body: {
      'action': 'change_plan',
      'planId': planId,
      // Null-aware value: a null cycle omits the key entirely, which is
      // what keeps the subscription's current cycle server-side.
      'billingCycle': ?billingCycle,
    },
  );

  // ── Refunds, invoices, billing profile ────────────────────────────────────

  /// Requests a refund against one payment record. `:521-522`.
  ///
  /// [paymentId] is the `payments` row id — `BillingHistoryItem`'s
  /// `paymentRecordId`, not the Razorpay payment id.
  Future<Map<String, dynamic>> requestRefund({
    required String paymentId,
    required String reason,
  }) => _invoke(
    'refund-payment',
    body: {'paymentId': paymentId, 'reason': reason},
  );

  /// Fetches one invoice. `:543-544`.
  ///
  /// Returns the function's payload as-is rather than writing a file: what comes back
  /// is a URL or an encoded document depending on how the invoice was generated, and
  /// deciding that here would put a download policy in a service.
  Future<Map<String, dynamic>> downloadInvoice(String invoiceId) =>
      _invoke('download-invoice', body: {'invoiceId': invoiceId});

  /// Updates the billing profile. `:574`.
  ///
  /// Takes the fields as a map because the portal passes a partial — only the keys
  /// the user edited — and sending an unedited field back as null would clear it.
  Future<Map<String, dynamic>> updateBillingProfile(
    Map<String, dynamic> fields,
  ) => _invoke('update-billing-profile', body: fields);
}

/// What `create-order` returns.
class PaymentOrder {
  const PaymentOrder({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.keyId,
  });

  /// Razorpay's order id, passed straight to the checkout sheet.
  final String orderId;

  /// In the **smallest currency unit** — paise for INR. This is what Razorpay
  /// expects, and it is why the portal divides by 100 before displaying it
  /// (`PaymentContext.tsx:404`).
  final int amount;

  final String currency;

  /// The publishable Razorpay key. Returned by the function rather than shipped in
  /// the app, so a key rotation does not need a release.
  final String keyId;

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    return PaymentOrder(
      orderId: '${json['orderId'] ?? ''}',
      amount: _asInt(json['amount']),
      currency: '${json['currency'] ?? 'INR'}',
      keyId: '${json['keyId'] ?? ''}',
    );
  }

  /// The amount in whole currency units, for display only.
  double get displayAmount => amount / 100;

  static int _asInt(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };
}

/// What `create-order`'s `preview: true` mode returns — the same figures
/// [PaymentOrder] would be charged, before any order or payment row exists.
///
/// All money fields are in the **smallest currency unit**, same as
/// [PaymentOrder.amount] — divide by 100 for display.
class PaymentQuote {
  const PaymentQuote({
    required this.months,
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.currency,
  });

  /// Billing periods covered — 1 for monthly, 12 for yearly.
  final int months;

  /// Pre-tax plan charge for [months], before any proration credit.
  final int subtotal;

  /// GST, INR only — zero for every other currency (`computeOrderAmount`).
  final int tax;

  /// Unused-time credit from an active subscription, applied against this
  /// charge. Zero for a first purchase or a same-currency lapse.
  final int discount;

  /// What would actually be charged: `subtotal + tax - discount`.
  final int total;

  final String currency;

  double get displaySubtotal => subtotal / 100;
  double get displayTax => tax / 100;
  double get displayDiscount => discount / 100;
  double get displayTotal => total / 100;

  factory PaymentQuote.fromJson(Map<String, dynamic> json) {
    return PaymentQuote(
      months: PaymentOrder._asInt(json['months']),
      subtotal: PaymentOrder._asInt(json['subtotal']),
      tax: PaymentOrder._asInt(json['tax']),
      discount: PaymentOrder._asInt(json['discount']),
      total: PaymentOrder._asInt(json['total']),
      currency: '${json['currency'] ?? 'INR'}',
    );
  }
}
