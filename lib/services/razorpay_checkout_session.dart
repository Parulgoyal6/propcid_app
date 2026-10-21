// services/razorpay_checkout_session.dart
//
// One Razorpay checkout attempt — extracted from the exact, already-proven
// lifecycle in `screens/subscription/upgrade_screen.dart` (`_openCheckout`)
// so the collaboration marketplace's advance/final payments don't
// reimplement its two documented failure-mode fixes rather than
// reproducing (and risking re-breaking) them a second time:
//
//   1. `Razorpay._handleResult`'s `default:` branch emits the unnamed event
//      name `'error'` for any platform response whose `type` isn't 0/1/2.
//      Nothing hears it unless a listener is registered explicitly, which
//      leaves the caller's Future parked forever.
//   2. `Razorpay.open` is declared `void open(...) async` — its internal
//      awaits (and the native-channel call itself) can throw into the
//      current zone instead of into a caller's `try`, silently leaving
//      `open()` looking like it succeeded with no callback ever firing.
//      `runZonedGuarded` is what actually observes that failure.
//
// `upgrade_screen.dart` itself is left untouched (its own subscription
// checkout keeps working exactly as before) — this is a new, separate call
// site reusing the same lifecycle, not a refactor of the existing one.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;
}

class CheckoutCancelled extends CheckoutResult {
  const CheckoutCancelled();
}

class CheckoutFailed extends CheckoutResult {
  const CheckoutFailed(this.message);
  final String message;
}

/// Resolved once per checkout attempt — a second callback/error after the
/// first is silently dropped (the plugin can emit more than once for a
/// single sheet close).
class _CheckoutAttempt {
  final Completer<CheckoutResult> _completer = Completer<CheckoutResult>();
  Future<CheckoutResult> get future => _completer.future;
  void complete(CheckoutResult result) {
    if (_completer.isCompleted) return;
    _completer.complete(result);
  }
}

/// Construct one per attempt — never reuse across attempts, since
/// `Razorpay.on()` appends listeners rather than replacing them, and reusing
/// an instance would resolve a previous attempt's completer. Call [dispose]
/// once the returned future completes (or the caller navigates away).
class RazorpayCheckoutSession {
  Razorpay? _razorpay;

  Future<CheckoutResult> open({
    required String keyId,
    required int amountMinor,
    required String currency,
    required String orderId,
    required String name,
    required String description,
    String? customerId,
    Map<String, String>? prefill,
  }) {
    final attempt = _CheckoutAttempt();

    _razorpay?.clear();
    final razorpay = Razorpay();
    _razorpay = razorpay;

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      attempt.complete(
        CheckoutSuccess(
          orderId: orderId,
          paymentId: r.paymentId ?? '',
          signature: r.signature ?? '',
        ),
      );
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      attempt.complete(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? const CheckoutCancelled()
            : CheckoutFailed(
                (r.message?.isNotEmpty ?? false)
                    ? r.message!
                    : 'Payment failed.',
              ),
      );
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      attempt.complete(
        const CheckoutFailed(
          'Complete the payment in your wallet app, then reopen this screen.',
        ),
      );
    });
    // Fix (1) — see file header.
    razorpay.on('error', (dynamic r) {
      attempt.complete(const CheckoutFailed('Payment could not be completed.'));
    });

    final options = <String, dynamic>{
      'key': keyId,
      // Already in the smallest currency unit (paise for INR), as
      // `collab-create-order` returns it and Razorpay expects it.
      'amount': amountMinor,
      'currency': currency,
      'order_id': orderId,
      'name': name,
      'description': description,
      'theme': {'color': '#F97316'},
      if (customerId != null) 'customer_id': customerId,
      if (customerId != null) 'remember_customer': true,
      if (prefill != null && prefill.isNotEmpty) 'prefill': prefill,
    };

    // Fix (2) — see file header.
    runZonedGuarded(() => razorpay.open(options), (error, stack) {
      attempt.complete(
        CheckoutFailed(
          error is PlatformException
              ? (error.message ?? 'Could not open checkout.')
              : 'Could not open checkout.',
        ),
      );
    });

    return attempt.future;
  }

  void dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}
