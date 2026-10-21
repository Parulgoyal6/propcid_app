import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../config/role_plan_config.dart';
import '../../core/animations/page_transitions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/scale_tap.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/payment_service.dart';
import '../../widgets/shared/section_header_back_button.dart';
import '../../widgets/shared/toggle_row.dart';
import 'billing_policies_screen.dart';
// Only the saving-pill copy is still taken from the old catalogue; the plan
// ladder itself now comes from `role_plan_config.dart`. Shown rather than
// imported wholesale because both files export a `PlanDefinition`.
import 'plan_catalogue.dart' show PlanCatalogue;

/// Upgrade Your Plan — the plan ladder with a monthly/yearly switch.
///
/// Design: the `isSubscription` screen. Functionally this is React's
/// `PlanUpgradeSection` + `UpgradePlanCard` pair over `getPlansForRole`.
///
/// WHAT CHANGED, AND WHAT DID NOT
/// ------------------------------
/// Layout, colours, spacing, card and badge styling are exactly as they were.
/// Three things behind them changed:
///
///   * the ladder comes from [plansForRole] against `AuthProvider.userType`, so a
///     broker sees Broker Pro at ₹29 instead of the individual ladder. That
///     mattered: the old hardcoded list quoted individual prices to every role
///     while `create-order` charges from the caller's real `user_type`, so the
///     screen and the invoice disagreed for three roles out of four;
///   * "Current Plan" is read from `SubscriptionProvider.subscription.plan`
///     rather than Free being hardcoded as current;
///   * the CTAs run the real flow — `create-order` → Razorpay → `verify-payment`
///     for a paid plan, `manage-subscription` for the drop back to Free —
///     replacing the placeholder screen.
///
/// THE YEARLY PRICE IS THE WHOLE ANNUAL CHARGE
/// -------------------------------------------
/// `₹7/year` means ₹7 for the year, not ₹7/month billed annually. The old
/// catalogue modelled it the other way and printed a "Billed annually (₹84/year)"
/// note under the price; that note is gone, because under the deployed pricing
/// table it contradicts both the headline figure and what is actually charged.
/// See `config/role_plan_config.dart`.
///
/// THE CLIENT NEVER SENDS AN AMOUNT
/// -------------------------------
/// Every price here is display only. `create-order` recomputes the charge from
/// `planId` + `billingCycle` + the caller's own `profiles.user_type`.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Its own provider, because this is a top-level named route
    // (`app.dart:220`) and not a child of the billing screen — there is no
    // ancestor to inherit one from. Same create-and-load shape as
    // `SubscriptionBillingScreen`.
    return ChangeNotifierProvider(
      create: (_) => SubscriptionProvider(),
      child: const _UpgradeView(),
    );
  }
}

class _UpgradeView extends StatefulWidget {
  const _UpgradeView();

  @override
  State<_UpgradeView> createState() => _UpgradeViewState();
}

class _UpgradeViewState extends State<_UpgradeView> {
  bool _yearly = false;

  final PaymentService _payments = PaymentService();

  String? _loadedUserId;

  /// The plan whose checkout is in flight. Only its CTA spins, and every CTA is
  /// inert until it settles.
  PlanId? _busyPlan;

  /// Razorpay reports through callbacks rather than a Future, so a checkout is
  /// bridged onto [_attempt] and awaited like any other async step.
  Razorpay? _razorpay;
  _CheckoutAttempt? _attempt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfNeeded();
  }

  /// Reads the account's current plan so one card can be marked "Current Plan".
  ///
  /// Deferred to the end of the frame with the provider captured up front —
  /// `load()` notifies before its first `await` and this runs inside build. Same
  /// lifecycle handling as `_SubscriptionBillingViewState._loadIfNeeded`.
  void _loadIfNeeded() {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().userId;
    if (userId == null || userId == _loadedUserId) return;
    _loadedUserId = userId;

    final provider = context.read<SubscriptionProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.load(userId);
    });
  }

  @override
  void dispose() {
    // A checkout still in flight would otherwise leave its awaiting frame parked
    // forever; resolve it before tearing the plugin's channel down.
    _attempt?.complete(const _CheckoutCancelled());
    _razorpay?.clear();
    super.dispose();
  }

  // ── CTA dispatch ──────────────────────────────────────────────────────────

  /// What tapping [plan]'s button does, or null when it should not be tappable.
  ///
  /// `UpgradePlanCard.handleCTAClick` (`:46-60`) makes the same three-way split:
  /// the current plan does nothing, Free is a no-payment plan change, and every
  /// paid plan opens checkout — including one below the current tier, because a
  /// paid downgrade still bills.
  VoidCallback? _ctaFor(PlanDefinition plan, {required bool isCurrent}) {
    if (isCurrent || _busyPlan != null) return null;
    return plan.isFree
        ? () => _switchToFree(plan)
        : () => _openCheckoutReview(plan);
  }

  /// The review step the portal always shows before Razorpay: `PricingCard`
  /// and `UpgradePlanCard` both set `isCheckoutOpen = true` on this same tap
  /// (`PricingCard.tsx:89-114`), which mounts `CheckoutModal` — a price
  /// breakdown plus a Terms/Privacy/Refund gate — and only *that* modal's own
  /// "Pay Now" button calls `processPayment()`.
  ///
  /// This does the same job with the same two calls the rest of this screen
  /// already makes: [PaymentService.previewOrder] for the numbers
  /// (`CheckoutModal`'s `OrderSummary`, quoted server-side so the breakdown
  /// can never drift from what `create-order` would actually charge — see
  /// `previewOrder`'s doc comment), then, only once the user accepts, the
  /// unchanged [_startCheckout] for the real order + Razorpay + verification.
  Future<void> _openCheckoutReview(PlanDefinition plan) async {
    if (!_requireSignIn()) return;

    // Same guard as `_startCheckout` — failing here means the review sheet
    // never opens for a charge that could not happen anyway, rather than
    // opening it and only then discovering Razorpay has no web sheet to show.
    if (kIsWeb) {
      _toast(
        'Payments are only available in the PropCid mobile app. '
        'Use the web portal to change your plan in a browser.',
        isError: true,
      );
      return;
    }

    setState(() => _busyPlan = plan.id);
    PaymentQuote quote;
    try {
      quote = await _payments.previewOrder(
        planId: plan.id.wire,
        billingCycle: _yearly ? 'yearly' : 'monthly',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyPlan = null);
      _toast(
        _messageFor(e, fallback: 'Could not load pricing. Please try again.'),
        isError: true,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _busyPlan = null);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CheckoutReviewSheet(plan: plan, quote: quote, yearly: _yearly),
    );
    if (confirmed != true || !mounted) return;

    await _startCheckout(plan);
  }

  /// Drops to Free. No payment, so no checkout — `manage-subscription` alone.
  ///
  /// `UpgradePlanCard.tsx:51-56`: `await changePlan("free", "monthly")`. The
  /// cycle is pinned to monthly there and here; a free plan has no annual charge
  /// to prorate.
  Future<void> _switchToFree(PlanDefinition plan) async {
    if (!_requireSignIn()) return;

    final confirmed = await _confirm(
      title: 'Switch to Free?',
      message:
          'Your paid features stay available until the end of the current '
          'billing period, then the account moves to the Free plan.',
      confirmLabel: 'Switch to Free',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busyPlan = plan.id);
    try {
      await _payments.changePlan(
        planId: PlanId.free.wire,
        billingCycle: 'monthly',
      );
      if (!mounted) return;
      await context.read<SubscriptionProvider>().refresh();
      if (!mounted) return;
      setState(() => _busyPlan = null);
      _toast('You are now on the Free plan.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyPlan = null);
      _toast(
        _messageFor(e, fallback: 'Could not change your plan.'),
        isError: true,
      );
    }
  }

  /// The portal's sequence, step for step: create-order → checkout →
  /// verify-payment (`PaymentContext.processPayment`, `:324-420`).
  ///
  /// The one structural difference is the sheet: the portal injects `checkout.js`
  /// into the page, a phone opens the native SDK. Both hand back the same three
  /// fields, and the same Edge Function verifies them.
  Future<void> _startCheckout(PlanDefinition plan) async {
    _log('CTA tapped: ${plan.id.wire} (${_yearly ? 'yearly' : 'monthly'})');
    if (!_requireSignIn()) return;

    // `razorpay_flutter` declares `platforms: android, ios` and ships no web
    // implementation, so in a browser every call on its MethodChannel throws
    // MissingPluginException and no sheet can open. Stopped here rather than at
    // `open()`: `create-order` would otherwise leave a `payments` row parked in
    // 'created' for a checkout that cannot happen.
    //
    // The browser is the web portal's job — it loads Razorpay's `checkout.js`
    // directly (`PaymentContext.tsx:142-157`), which is a different integration
    // from this one, not a missing branch of it.
    if (kIsWeb) {
      _log('blocked: razorpay_flutter has no web implementation');
      _toast(
        'Payments are only available in the PropCid mobile app. '
        'Use the web portal to change your plan in a browser.',
        isError: true,
      );
      return;
    }

    setState(() => _busyPlan = plan.id);

    try {
      _log('→ createOrder…');
      final order = await _payments.createOrder(
        planId: plan.id.wire,
        billingCycle: _yearly ? 'yearly' : 'monthly',
        // Regenerated per attempt — see PaymentService.newIdempotencyKey.
        idempotencyKey: PaymentService.newIdempotencyKey(),
      );
      _log(
        '← createOrder ok: order=${order.orderId} amount=${order.amount} '
        '${order.currency} keyId=${order.keyId.isEmpty ? 'EMPTY' : 'set'}',
      );

      _log('→ openCheckout…');
      final result = await _openCheckout(plan: plan, order: order);
      _log('← openCheckout: ${result.runtimeType}');
      if (!mounted) return;

      // Dismissed or declined: nothing was bought, so nothing is verified and
      // the subscription is left exactly as it was.
      if (result is! _CheckoutSuccess) {
        setState(() => _busyPlan = null);
        _toast(
          result is _CheckoutCancelled
              ? 'Payment cancelled.'
              : (result as _CheckoutFailed).message,
          isError: true,
        );
        return;
      }

      // Razorpay's success callback is not proof of purchase — the signature is.
      // This is the call that activates the plan.
      _log('→ verifyPayment…');
      await _payments.verifyPayment(
        razorpayOrderId: result.orderId,
        razorpayPaymentId: result.paymentId,
        razorpaySignature: result.signature,
      );
      _log('← verifyPayment ok');

      if (!mounted) return;
      // Only now is the plan real. Re-reading `subscriptions` is what flips this
      // card to "Current Plan".
      _log('→ refresh…');
      await context.read<SubscriptionProvider>().refresh();
      _log('← refresh ok');
      if (!mounted) return;
      setState(() => _busyPlan = null);
      _toast('You are now on ${plan.name}.');
    } catch (e) {
      _log('✗ checkout threw: $e');
      if (!mounted) return;
      setState(() => _busyPlan = null);
      _toast(
        _messageFor(e, fallback: 'Payment failed. Please try again.'),
        isError: true,
      );
    }
  }

  /// Opens the native sheet and resolves once Razorpay reports an outcome.
  ///
  /// EVERY EXIT FROM THE SHEET MUST COMPLETE [_CheckoutAttempt]
  /// ----------------------------------------------------------
  /// This is the one await in the flow with no Future of its own behind it — it
  /// resolves only when a plugin callback fires. Two paths through
  /// `razorpay_flutter` 1.4.5 reach neither of the three callbacks below, and
  /// both of them park this Future forever, which is what leaves the CTA
  /// spinning with no sheet and no error:
  ///
  ///   1. `Razorpay._handleResult`'s `default:` branch emits the event name
  ///      `'error'` — not `EVENT_PAYMENT_ERROR` — for any platform response
  ///      whose `type` is not 0/1/2. Nothing listens to `'error'` unless it is
  ///      registered explicitly, so the emit goes nowhere.
  ///   2. `Razorpay.open` is declared `void open(...) async`. Its
  ///      `await _channel.invokeMethod('open', options)` and the
  ///      `_handleResult(response)` that follows can both throw — a
  ///      `PlatformException` from the native SDK, a `MissingPluginException`,
  ///      or a `NoSuchMethodError` if the platform hands back null. Because the
  ///      method returns `void` rather than a `Future`, those throws land in the
  ///      zone instead of in a caller's `try`, so `open()` looks like it
  ///      succeeded and no callback ever fires.
  ///
  /// Both are closed below. Nothing about the sequence changes.
  Future<_CheckoutResult> _openCheckout({
    required PlanDefinition plan,
    required PaymentOrder order,
  }) {
    final attempt = _CheckoutAttempt();
    _attempt = attempt;

    // Rebuilt per attempt: `on()` appends listeners rather than replacing them,
    // so reusing an instance would resolve a previous attempt's completer.
    _razorpay?.clear();
    final razorpay = Razorpay();
    _razorpay = razorpay;

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      _log('razorpay → SUCCESS payment=${r.paymentId} order=${r.orderId}');
      attempt.complete(
        _CheckoutSuccess(
          // `orderId` comes back from the SDK, but the order we created is the
          // authority on which order this is.
          orderId: order.orderId,
          paymentId: r.paymentId ?? '',
          signature: r.signature ?? '',
        ),
      );
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      _log('razorpay → ERROR code=${r.code} message=${r.message}');
      // A dismissed sheet arrives on the error channel too, so a cancellation is
      // told apart by its code rather than by a callback of its own.
      attempt.complete(
        r.code == Razorpay.PAYMENT_CANCELLED
            ? const _CheckoutCancelled()
            : _CheckoutFailed(
                (r.message?.isNotEmpty ?? false)
                    ? r.message!
                    : 'Payment failed.',
              ),
      );
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      _log('razorpay → EXTERNAL_WALLET ${r.walletName}');
      // The user left for a wallet app. `payment-webhook` is what will settle
      // this, so the screen must not claim success — it reports the handoff.
      attempt.complete(
        const _CheckoutFailed(
          'Complete the payment in your wallet app, then reopen this screen.',
        ),
      );
    });
    // (1) The plugin's unnamed fallback event. Without this listener an
    // unrecognised platform response is emitted into the void.
    razorpay.on('error', (dynamic r) {
      _log('razorpay → unnamed error event: $r');
      attempt.complete(
        const _CheckoutFailed('Payment could not be completed.'),
      );
    });

    final options = <String, dynamic>{
      'key': order.keyId,
      // Already in paise, as `create-order` returns it and Razorpay expects it.
      'amount': order.amount,
      'currency': order.currency,
      'order_id': order.orderId,
      'name': 'PropCid',
      'description': '${plan.name} — ${_yearly ? 'Yearly' : 'Monthly'}',
      // The portal's checkout theme (`PaymentContext.tsx:390`).
      'theme': {'color': '#F97316'},
    };
    _log(
      'razorpay.open() key=${order.keyId} order=${order.orderId} '
      'amount=${order.amount} ${order.currency}',
    );

    // (2) `open()` throws into the zone, not into a `try`, so this is the only
    // place those failures can be observed. Without it they are silent and the
    // await below never returns.
    runZonedGuarded(() => razorpay.open(options), (error, stack) {
      _log('razorpay.open() threw: $error');
      attempt.complete(
        _CheckoutFailed(
          error is PlatformException
              ? (error.message ?? 'Could not open checkout.')
              : 'Could not open checkout.',
        ),
      );
    });

    return attempt.future;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// TEMPORARY checkout tracing. Debug builds only; remove once the flow is
  /// confirmed on device. Prints no card data — only ids the server already logs.
  void _log(String message) {
    if (kDebugMode) debugPrint('[checkout] $message');
  }

  bool _requireSignIn() {
    if (context.read<AuthProvider>().userId != null) return true;
    _toast('Please sign in to change your plan.', isError: true);
    return false;
  }

  /// `PaymentService` throws the server's own message as a bare String; anything
  /// else is a bug or a transport failure the user cannot act on.
  String _messageFor(Object error, {required String fallback}) =>
      error is String ? error : fallback;

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          title,
          style: AppTextStyles.heading3.copyWith(fontSize: 16),
        ),
        content: Text(
          message,
          style: AppTextStyles.body.copyWith(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep current plan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: AppTextStyles.button.copyWith(
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// One card. A method rather than an inline expression because a collection-for
  /// has nowhere to put the two derived locals.
  Widget _card(
    PlanDefinition plan, {
    required PlanId? currentPlan,
    required bool resolving,
  }) {
    final isCurrent = plan.id == currentPlan;
    return _PlanCard(
      plan: plan,
      yearly: _yearly,
      isCurrent: isCurrent,
      busy: _busyPlan == plan.id,
      onTap: resolving ? null : _ctaFor(plan, isCurrent: isCurrent),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched, so the ladder follows the role as it resolves and the current-plan
    // marker follows the subscription as it loads or changes.
    final auth = context.watch<AuthProvider>();
    final billing = context.watch<SubscriptionProvider>();

    final plans = plansForRole(auth.userType);

    // Null until the account's plan is actually known. Marking Free as current
    // while the read is still in flight would be a guess, and it is the guess
    // that makes the Free card look inert to a paying user.
    final resolving = auth.userId != null && billing.loading;
    final currentPlan = resolving
        ? null
        : PlanId.fromWire(billing.subscription.plan);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DashboardHeaderBar(
                title: 'Upgrade Your Plan',
                subtitle: 'Unlock more features and grow faster on PropCid',
              ),
              const SizedBox(height: 18),
              _BillingPeriodSwitch(
                yearly: _yearly,
                onChanged: (value) => setState(() => _yearly = value),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < plans.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _card(plans[i], currentPlan: currentPlan, resolving: resolving),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Monthly · switch · Yearly" with a Save 20% pill once Yearly is selected.
class _BillingPeriodSwitch extends StatelessWidget {
  final bool yearly;
  final ValueChanged<bool> onChanged;

  const _BillingPeriodSwitch({required this.yearly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Billing period',
      value: yearly ? 'Yearly' : 'Monthly',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PeriodLabel(
            'Monthly',
            selected: !yearly,
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 10),
          // The design's larger 44×26 track, primary in both positions since
          // this selects between two periods rather than switching a setting
          // on and off.
          ExcludeSemantics(
            child: AppToggle(
              value: yearly,
              onChanged: onChanged,
              trackWidth: 44,
              trackHeight: 26,
              knobSize: 22,
              inactiveTrackColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          _PeriodLabel(
            'Yearly',
            selected: yearly,
            onTap: () => onChanged(true),
          ),
          if (yearly) ...[const SizedBox(width: 10), const _SavingPill()],
        ],
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodLabel(this.text, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        text,
        style: AppTextStyles.body.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? AppColors.textPrimary : AppColors.textHint,
        ),
      ),
    );
  }
}

/// `Save 20%` — 20 dp amber pill.
class _SavingPill extends StatelessWidget {
  const _SavingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3E2),
        borderRadius: BorderRadius.circular(AppConstants.pillRadius),
      ),
      child: Text(
        PlanCatalogue.yearlySavingLabel,
        style: AppTextStyles.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFB45309),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanDefinition plan;
  final bool yearly;

  /// The plan the account is on. Its CTA becomes an inert "Current Plan" label.
  final bool isCurrent;

  /// This plan's checkout is running.
  final bool busy;

  /// Null when the CTA should not respond — the current plan, or any card while
  /// another plan's checkout is in flight.
  final VoidCallback? onTap;

  const _PlanCard({
    required this.plan,
    required this.yearly,
    required this.isCurrent,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Yearly is the whole annual charge, so the figure stands on its own — there
    // is no monthly equivalent to explain underneath it.
    final price = plan.priceFor(yearly: yearly);

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        boxShadow: AppColors.surfaceCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 4 dp down, leaving room for the badge that overhangs the top edge.
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: plan.tintBackground,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(plan.icon, size: 20, color: plan.tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.name,
                      style: AppTextStyles.heading3.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      plan.description,
                      style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹$price',
                style: AppTextStyles.heading1.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                yearly ? '/year' : '/month',
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < plan.features.length; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            _FeatureRow(feature: plan.features[i]),
          ],
          const SizedBox(height: AppConstants.spacingL),
          _PlanCta(plan: plan, isCurrent: isCurrent, busy: busy, onTap: onTap),
        ],
      ),
    );

    if (plan.badge == null) return card;

    // The badge overhangs the card's top edge by 11 dp, so the stack is allowed
    // to paint outside its bounds and the row is padded to make room.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -11,
          left: AppConstants.spacingL,
          child: Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: plan.badgeColor ?? AppColors.primary,
              borderRadius: BorderRadius.circular(AppConstants.pillRadius),
            ),
            child: Text(
              plan.badge!,
              style: AppTextStyles.caption.copyWith(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final PlanFeatureLine feature;

  const _FeatureRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          feature.included ? Icons.check : Icons.close,
          size: 15,
          color: feature.included ? AppColors.success : const Color(0xFFD1D5DB),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            feature.label,
            style: AppTextStyles.caption.copyWith(
              fontSize: 12.5,
              color: feature.included
                  ? AppColors.textPrimary
                  : AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCta extends StatelessWidget {
  final PlanDefinition plan;
  final bool isCurrent;
  final bool busy;
  final VoidCallback? onTap;

  const _PlanCta({
    required this.plan,
    required this.isCurrent,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The three painted styles are unchanged; what picks between them is. The old
    // catalogue stored a `PlanCtaStyle` per plan — free was always `current` and
    // the badged plan was always `solid`. Free is no longer assumed to be the
    // account's plan, so `current` is now the live comparison, and `solid`
    // follows the badge, which reproduces the previous look exactly.
    final isSolid = !isCurrent && plan.badge != null;
    final isOutline = !isCurrent && !isSolid;

    final foreground = isCurrent
        ? AppColors.success
        : (isSolid ? Colors.white : AppColors.primary);

    final button = Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFFE7F8ED)
            : (isSolid ? AppColors.primary : AppColors.cardBackground),
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        border: isOutline
            ? Border.all(color: AppColors.primary, width: 1.5)
            : null,
        boxShadow: isSolid ? AppColors.primaryActionShadow : null,
      ),
      // Same 44 dp box either way, so the card does not resize mid-checkout.
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            )
          : Text(
              // The design labels the account's own plan; every other card keeps
              // the role's configured CTA copy.
              isCurrent ? 'Current Plan' : plan.cta,
              style: AppTextStyles.button.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
    );

    // The design gives the current plan no onClick, so it stays a label — as does
    // any card while another plan's checkout is running.
    if (onTap == null) return button;

    return Semantics(
      label: plan.cta,
      button: true,
      child: ScaleTap(onTap: onTap, child: button),
    );
  }
}

/// The portal's `CheckoutModal` (`CheckoutModal.tsx`): plan recap, the
/// `OrderSummary` price breakdown, and a required Terms/Privacy/Refund
/// checkbox gating a "Pay Now" button. Pops `true` on Pay Now, `false`/`null`
/// on cancel — [_UpgradeViewState._openCheckoutReview] is what turns a `true`
/// into the actual checkout.
///
/// Currency is not offered here — unlike the portal, this app only ever
/// charges INR (`PaymentService.createOrder`'s `currency` defaults to `'INR'`
/// and nothing in this screen changes it), so the portal's currency selector
/// has nothing to switch between here.
class _CheckoutReviewSheet extends StatefulWidget {
  const _CheckoutReviewSheet({
    required this.plan,
    required this.quote,
    required this.yearly,
  });

  final PlanDefinition plan;
  final PaymentQuote quote;
  final bool yearly;

  @override
  State<_CheckoutReviewSheet> createState() => _CheckoutReviewSheetState();
}

class _CheckoutReviewSheetState extends State<_CheckoutReviewSheet> {
  bool _termsAccepted = false;

  /// Whole rupees print bare (`₹499`); a non-zero paise remainder — possible
  /// on a prorated credit — keeps two decimals rather than silently rounding.
  String _money(double v) =>
      v == v.roundToDouble() ? '₹${v.round()}' : '₹${v.toStringAsFixed(2)}';

  void _openPolicies() {
    Navigator.of(
      context,
    ).push(PremiumPageRoute(builder: (_) => const BillingPoliciesScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final quote = widget.quote;

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textHint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Complete Your Purchase',
                      style: AppTextStyles.heading3.copyWith(fontSize: 17),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                    color: AppColors.textHint,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "You're upgrading to the ${plan.name} plan",
                style: AppTextStyles.caption.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 18),

              // Plan recap card.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppConstants.cardRadius),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: plan.tintBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(plan.icon, size: 18, color: plan.tint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        plan.name,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      widget.yearly ? 'Yearly billing' : 'Monthly billing',
                      style: AppTextStyles.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Order summary — the portal's `OrderSummary.tsx`.
              _SummaryRow(
                label: 'Subtotal',
                value: _money(quote.displaySubtotal),
              ),
              if (quote.tax > 0) ...[
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'GST (18%)',
                  value: _money(quote.displayTax),
                ),
              ],
              if (quote.discount > 0) ...[
                const SizedBox(height: 8),
                _SummaryRow(
                  label: 'Unused time credit',
                  value: '- ${_money(quote.displayDiscount)}',
                  valueColor: AppColors.success,
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _SummaryRow(
                label: 'Total',
                value: _money(quote.displayTotal),
                bold: true,
              ),
              const SizedBox(height: 4),
              Text(
                'Inclusive of all taxes',
                style: AppTextStyles.caption.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 16),

              // Secure-payment notice — `CheckoutModal.tsx:201-217`.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You'll be redirected to Razorpay's secure checkout "
                        'to complete this payment.',
                        style: AppTextStyles.caption.copyWith(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Terms gate — `CheckoutModal.tsx:252-320`.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _termsAccepted,
                        onChanged: (v) =>
                            setState(() => _termsAccepted = v ?? false),
                        activeColor: AppColors.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: RichText(
                          text: TextSpan(
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                            ),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text:
                                    'Terms of Service, Privacy Policy and '
                                    'Refund Policy',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = _openPolicies,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Pay Now — the single button that hands off to Razorpay.
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _termsAccepted
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.textHint.withValues(
                      alpha: 0.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.buttonRadius,
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Pay Now · ${_money(quote.displayTotal)}',
                    style: AppTextStyles.button.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppTextStyles.body.copyWith(fontSize: 15, fontWeight: FontWeight.w800)
        : AppTextStyles.body.copyWith(fontSize: 13);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style.copyWith(color: AppColors.textPrimary)),
        Text(value, style: style.copyWith(color: valueColor ?? style.color)),
      ],
    );
  }
}

// ── Checkout outcome ────────────────────────────────────────────────────────
//
// Razorpay reports through three separate callbacks. Collapsing them into one
// result type is what lets `_startCheckout` read as the linear sequence it is,
// instead of splitting the verify step across three handlers.

sealed class _CheckoutResult {
  const _CheckoutResult();
}

class _CheckoutSuccess extends _CheckoutResult {
  const _CheckoutSuccess({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;
}

/// The user dismissed the sheet. Not an error — nothing is said beyond
/// "cancelled", and nothing is refreshed.
class _CheckoutCancelled extends _CheckoutResult {
  const _CheckoutCancelled();
}

class _CheckoutFailed extends _CheckoutResult {
  const _CheckoutFailed(this.message);

  final String message;
}

/// One checkout, resolved once.
///
/// The plugin can emit more than once for a single sheet — its `resync` replays
/// a result the app missed — and completing a [Completer] twice throws.
class _CheckoutAttempt {
  final Completer<_CheckoutResult> _completer = Completer<_CheckoutResult>();

  Future<_CheckoutResult> get future => _completer.future;

  void complete(_CheckoutResult result) {
    if (_completer.isCompleted) return;
    _completer.complete(result);
  }
}
