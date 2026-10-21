// screens/messaging/widgets/collab_action_panel.dart
//
// The status-stepper + per-status action panel rendered above the composer
// in a collaboration's DM thread — a phone-first port of
// `CollabActionPanel.tsx`'s status -> action -> role table (see the research
// transcript this was built from: 6-step stepper, per-status action list,
// dispute gating). Every action calls [CollaborationThreadController], which
// only ever calls RPCs/Edge Functions — nothing here writes collab state
// directly or predicts the next status locally.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../../config/launch_features.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/collaboration.dart';
import '../../../providers/collaboration_thread_controller.dart';
import '../../../services/collaboration_exceptions.dart';
import '../../../services/location_service.dart';
import '../../../services/razorpay_checkout_session.dart';
import 'collab_dispute_sheet.dart';

/// Bounded so a checkout the user opened and then abandoned (backgrounded
/// the app, lost connectivity mid-flow) cannot leave the caller's Future
/// pending forever — Razorpay's own callbacks are the fast path; this is
/// only the ceiling.
const Duration _kCheckoutTimeout = Duration(minutes: 5);

const List<({String status, String label})> kCollabSteps = [
  (status: CollabStatuses.accepted, label: 'Agreement'),
  (status: CollabStatuses.agreementPending, label: 'Advance (25%)'),
  (status: CollabStatuses.inProgress, label: 'In progress'),
  (status: CollabStatuses.deliverablePending, label: 'Final (75%)'),
  (status: CollabStatuses.delivered, label: 'Delivered'),
  (status: CollabStatuses.completed, label: 'Completed'),
];

/// `CollabActionPanel.tsx`'s `stepIndex` — folds the two statuses that are
/// declared in the enum but never actually stored (`advance_paid`,
/// `final_paid`) into their displayed step.
int collabStepIndex(String status) {
  final idx = kCollabSteps.indexWhere((s) => s.status == status);
  if (idx >= 0) return idx;
  if (status == CollabStatuses.advancePaid) return 2;
  if (status == CollabStatuses.finalPaid) return 3;
  return 0;
}

const Set<String> _kStepperHiddenStatuses = {
  CollabStatuses.declined,
  CollabStatuses.disputed,
  CollabStatuses.cancelled,
};

const Set<String> _kWorkStatuses = {
  CollabStatuses.advancePaid,
  CollabStatuses.inProgress,
};

const Set<String> _kDeliverableStatuses = {
  CollabStatuses.finalPaid,
  CollabStatuses.deliverablePending,
};

const Set<String> _kDisputableStatuses = {
  CollabStatuses.advancePaid,
  CollabStatuses.inProgress,
  CollabStatuses.deliverablePending,
  CollabStatuses.delivered,
};

/// `CollabActionPanel.tsx`'s `canCancel` — either participant, only while
/// `accepted` or still-unpaid `agreement_pending`.
const Set<String> _kCancellableStatuses = {
  CollabStatuses.accepted,
  CollabStatuses.agreementPending,
};

class CollabActionPanel extends StatefulWidget {
  final CollaborationThreadController controller;

  /// Called after any action that inserted a new message (sample/deliverable
  /// upload, location share/request) so the caller's message list refetches
  /// — mirrors `onMessagesChanged` in `CollabActionPanel.tsx`. The realtime
  /// subscription usually gets there first; this is the same belt-and-
  /// suspenders `await refresh()` pattern already used elsewhere in this app.
  final VoidCallback? onMessagesChanged;

  const CollabActionPanel({
    super.key,
    required this.controller,
    this.onMessagesChanged,
  });

  @override
  State<CollabActionPanel> createState() => _CollabActionPanelState();
}

class _CollabActionPanelState extends State<CollabActionPanel> {
  final _imagePicker = ImagePicker();
  final _locationService = LocationService();
  bool _localBusy = false;

  CollaborationThreadController get controller => widget.controller;

  bool get _busy => _localBusy || controller.busy;

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _localBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens the propose/counter dialog. `CollabActionPanel.tsx`'s title is
  /// "Counter offer" when responding to the other party's live offer, else
  /// "Propose amount"; same copy, same "final offer" checkbox either way.
  Future<void> _proposeOffer({required bool isCounter}) async {
    final amountController = TextEditingController();
    var isFinal = false;
    final result = await showDialog<(int, bool)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isCounter ? 'Counter offer' : 'Propose amount'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Total amount in INR. 25% is due as an advance, 75% on '
                'final delivery.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  hintText: 'Total amount',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: isFinal,
                onChanged: (v) => setDialogState(() => isFinal = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text(
                  'Send as a final offer (the other party can only accept '
                  'it or cancel — no further counters)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = double.tryParse(amountController.text.trim());
                if (value == null || value <= 0) return;
                Navigator.of(
                  dialogContext,
                ).pop(((value * 100).round(), isFinal));
              },
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final (amountMinor, isFinalOffer) = result;
    await _guard(() async {
      final error = await controller.proposeOffer(
        amountMinor: amountMinor,
        isFinal: isFinalOffer,
      );
      if (error != null) {
        _snack(error);
      } else {
        _snack(isFinalOffer ? 'Final offer sent' : 'Offer sent');
      }
    });
  }

  Future<void> _acceptOffer() async {
    await _guard(() async {
      final error = await controller.acceptOffer();
      if (error != null) {
        _snack(error);
      } else {
        _snack('Offer accepted — agreement set');
      }
    });
  }

  Future<void> _cancelCollaboration() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this collaboration?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This ends the collaboration for both parties. No payment '
              'has been made yet, so nothing needs to be refunded.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 3,
              // Matches CollaborationService.maxDisputeReasonLength — the
              // server's own cap on `cancel`'s optional reason, same as the
              // dispute reason.
              maxLength: 1000,
              decoration: const InputDecoration(hintText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Keep collaboration'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(reasonController.text),
            child: const Text(
              'Yes, cancel',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == null || !mounted) return;
    await _guard(() async {
      final trimmed = confirmed.trim();
      final error = await controller.cancelCollaboration(
        reason: trimmed.isEmpty ? null : trimmed,
      );
      if (error != null) {
        _snack(error);
      } else {
        _snack('Collaboration cancelled');
      }
    });
  }

  Future<void> _downloadAgreement() async {
    await _guard(() async {
      final (url, error) = await controller.fetchAgreementUrl();
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else if (error != null) {
        _snack(error);
      }
    });
  }

  Future<void> _pay(String milestone) async {
    // Defence-in-depth: this panel is never mounted at all while paid
    // collaborations are disabled (see `ChatThreadScreen.build`), but a
    // checkout must never proceed here either way.
    if (!LaunchFeatures.paidCollaborations) return;
    await _guard(() async {
      Map<String, dynamic> order;
      try {
        order = await controller.createPaymentOrder(milestone);
      } catch (e) {
        _snack('Could not start payment. Please try again.');
        return;
      }
      final keyId = order['keyId'] as String?;
      final orderId = order['orderId'] as String?;
      final amount = order['amount'];
      final currency = (order['currency'] as String?) ?? 'INR';
      if (keyId == null ||
          keyId.isEmpty ||
          orderId == null ||
          orderId.isEmpty ||
          amount == null) {
        _snack('Failed to create payment order.');
        return;
      }

      final session = RazorpayCheckoutSession();
      try {
        final result = await session
            .open(
              keyId: keyId,
              amountMinor: amount is int
                  ? amount
                  : int.tryParse('$amount') ?? 0,
              currency: currency,
              orderId: orderId,
              name: 'PropCid',
              description: milestone == CollabMilestones.advance
                  ? 'Collaboration advance (25%)'
                  : 'Collaboration final payment (75%)',
              customerId: order['customerId'] as String?,
              prefill: (order['prefill'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            )
            .timeout(
              _kCheckoutTimeout,
              onTimeout: () => const CheckoutFailed(
                'The payment window timed out. If you completed payment, '
                'it will be reconciled automatically.',
              ),
            );

        if (result is CheckoutSuccess) {
          try {
            await controller.verifyPayment(
              razorpayOrderId: result.orderId,
              razorpayPaymentId: result.paymentId,
              razorpaySignature: result.signature,
            );
            // Collab state advances server-side only — never predicted
            // locally. The realtime subscription (or this belt-and-
            // suspenders refresh) picks up the new status.
            await controller.refresh();
            _snack('Payment successful.');
          } catch (e) {
            _snack(
              e is CollaborationException
                  ? e.message
                  : 'Payment could not be verified. If you were charged, '
                        'webhook reconciliation may still complete it — '
                        'we will not create another order automatically.',
            );
          }
        } else if (result is CheckoutCancelled) {
          _snack('Payment cancelled.');
        } else if (result is CheckoutFailed) {
          _snack(result.message);
        }
      } finally {
        session.dispose();
      }
    });
  }

  /// `CollabActionPanel.tsx`'s sample flow, in order: instructions ->
  /// pick file -> stage in a preview dialog -> explicit "Send?" confirm ->
  /// upload. Previously this skipped straight from picking a file to
  /// uploading it, with none of the portal's confirmation steps.
  Future<void> _sendSample() async {
    final proceed = await _showSampleInstructions();
    if (proceed != true || !mounted) return;

    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;

    final confirmed = await _showSamplePreview(File(picked.path));
    if (confirmed != true || !mounted) return;

    await _guard(() async {
      final error = await controller.uploadSample(File(picked.path));
      if (error != null) {
        _snack(error);
      } else {
        _snack('Sample sent (view once)');
        widget.onMessagesChanged?.call();
      }
    });
  }

  Future<bool?> _showSampleInstructions() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send a one-time sample'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BulletLine('MP4 video, 10-15 seconds long.'),
            SizedBox(height: 8),
            _BulletLine(
              "The client can watch it only once — it's gone for good the "
              'moment they close the player.',
            ),
            SizedBox(height: 8),
            _BulletLine(
              "You'll see a preview and confirm before it's actually sent.",
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Choose video'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showSamplePreview(File file) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Send this sample?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _LocalVideoPreview(file: file),
            ),
            const SizedBox(height: 12),
            const Text(
              'Once sent, the client can view this video only once — '
              "there's no way to undo this.",
              style: TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDeliverable() async {
    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await _guard(() async {
      final error = await controller.uploadDeliverable(File(picked.path));
      if (error != null) {
        _snack(error);
      } else {
        widget.onMessagesChanged?.call();
      }
    });
  }

  Future<void> _requestLocation() async {
    await _guard(() async {
      final error = await controller.requestLocation();
      if (error != null) {
        _snack(error);
      } else {
        widget.onMessagesChanged?.call();
      }
    });
  }

  Future<void> _shareLocation() async {
    await _guard(() async {
      final result = await _locationService.getCurrentPosition();
      if (!result.isSuccess) {
        _snack(_locationFailureMessage(result.failureReason));
        return;
      }
      final error = await controller.sendLocation(
        latitude: result.latitude!,
        longitude: result.longitude!,
      );
      if (error != null) {
        _snack(error);
      } else {
        widget.onMessagesChanged?.call();
      }
    });
  }

  String _locationFailureMessage(LocationFailureReason? reason) {
    switch (reason) {
      case LocationFailureReason.servicesDisabled:
        return 'Turn on location services to share your location.';
      case LocationFailureReason.permissionDenied:
        return 'Location permission is required to share your location.';
      case LocationFailureReason.permissionDeniedForever:
        return 'Location access is turned off for this app. Enable it in Settings.';
      case LocationFailureReason.unknown:
      case null:
        return "Couldn't get your location. Please try again.";
    }
  }

  Future<void> _confirmPayFinal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pay final amount?'),
        content: Text(
          'This pays the remaining ${formatCollabAmount(controller.finalPayment?.amountMinor ?? controller.collaboration?.finalAmountMinor)} '
          'to complete the collaboration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, pay now'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _pay(CollabMilestones.finalMilestone);
  }

  Future<void> _raiseDispute() async {
    final reason = await showCollabDisputeSheet(context);
    if (reason == null || !mounted) return;
    await _guard(() async {
      final error = await controller.raiseDispute(reason);
      if (error != null) _snack(error);
    });
  }

  Future<void> _downloadInvoice(CollabInvoice invoice) async {
    await _guard(() async {
      final (url, error) = await controller.fetchInvoiceUrl(invoice.id);
      if (url != null) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else if (error != null) {
        _snack(error);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final collab = controller.collaboration;
    if (collab == null) {
      if (controller.loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      // Previously fell through to an empty SizedBox here, silently hiding
      // the whole panel on a load failure with no way to recover short of
      // leaving and reopening the thread.
      if (controller.failed) {
        return Container(
          color: AppColors.cardBackground,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Column(
            children: [
              Text(
                "Couldn't load this collaboration.",
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final status = collab.status;
    // Capped and scrollable so the stepper/actions/summary stack can never
    // squeeze the message list off a small screen.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_kStepperHiddenStatuses.contains(status))
              _buildStepper(status),
            const SizedBox(height: 12),
            ..._buildStatusActions(collab, status),
            if (controller.invoices.isNotEmpty) _buildInvoices(),
            const SizedBox(height: 4),
            _buildSummary(collab),
          ],
        ),
      ),
    );
  }

  /// Display-only 5-step grouping of [kCollabSteps] for the stepper card —
  /// "Advance (25%)" and "In progress" read as one "In progress (25%)"
  /// stage. [collabStepIndex] itself is unchanged.
  static const List<String> _kDisplaySteps = [
    'Agreement',
    'In progress\n(25%)',
    'Final\n(75%)',
    'Delivered',
    'Completed',
  ];

  int _displayStepIndex(String status) {
    final i = collabStepIndex(status);
    if (i <= 0) return 0;
    if (i <= 2) return 1;
    return i - 1;
  }

  Widget _buildStepper(String status) {
    final activeIndex = _displayStepIndex(status);
    final completedAll = status == CollabStatuses.completed;
    return _panelCard(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(_kDisplaySteps.length, (i) {
          final done = i < activeIndex || (completedAll && i == activeIndex);
          final active = i == activeIndex && !completedAll;
          final last = i == _kDisplaySteps.length - 1;
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: i == 0
                          ? const SizedBox.shrink()
                          : _connector(i <= activeIndex),
                    ),
                    _stepDot(i, done: done, active: active),
                    Expanded(
                      child: last
                          ? const SizedBox.shrink()
                          : _connector(i < activeIndex),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _kDisplaySteps[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: 9.5,
                    height: 1.25,
                    fontWeight: done || active
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: done || active
                        ? AppColors.primary
                        : AppColors.textHint,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _connector(bool reached) => Container(
    height: 2.5,
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: reached ? AppColors.primary : const Color(0xFFEDEDF2),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _stepDot(int i, {required bool done, required bool active}) {
    const size = 28.0;
    if (done) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AppColors.primaryGradient,
          boxShadow: AppColors.primaryGlow,
        ),
        child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
      );
    }
    if (active) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: AppColors.primary, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Color(0x40F97316), blurRadius: 10),
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceMuted,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        '${i + 1}',
        style: AppTextStyles.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textHint,
        ),
      ),
    );
  }

  /// White floating card used by the stepper and the summary.
  Widget _panelCard({required Widget child, EdgeInsetsGeometry? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFEDD5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14F97316),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );

  Widget _buildSummary(Collaboration collab) {
    final agreed = collab.agreedAmountMinor;
    final amount = agreed ?? collab.pendingOfferAmountMinor;
    final started = collab.createdAt;
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _tileIcon(Icons.assignment_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Collaboration Summary',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  icon: Icons.radio_button_checked,
                  iconColor: _statusColor(collab.status),
                  label: 'Status',
                  value: _statusLabel(collab.status),
                ),
              ),
              Expanded(
                child: _summaryTile(
                  icon: Icons.currency_rupee_rounded,
                  label: agreed != null ? 'Agreed amount' : 'Proposed amount',
                  value: amount != null
                      ? formatCollabAmount(amount, currency: collab.currency)
                      : 'Not set yet',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _summaryTile(
                  icon: Icons.calendar_today_outlined,
                  label: 'Started on',
                  value: started != null ? _formatDate(started) : '—',
                ),
              ),
              Expanded(
                child: _summaryTile(
                  icon: Icons.people_outline_rounded,
                  label: 'Participants',
                  value: '2 people',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tileIcon(IconData icon, {Color color = AppColors.primary}) =>
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: color),
      );

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
    Color iconColor = AppColors.primary,
  }) {
    return Row(
      children: [
        _tileIcon(icon, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(fontSize: 10.5),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case CollabStatuses.accepted:
        return 'Agreement';
      case CollabStatuses.agreementPending:
        return 'Advance pending';
      case CollabStatuses.advancePaid:
      case CollabStatuses.inProgress:
        return 'In progress';
      case CollabStatuses.finalPaid:
      case CollabStatuses.deliverablePending:
        return 'Awaiting delivery';
      case CollabStatuses.delivered:
        return 'Delivered';
      case CollabStatuses.completed:
        return 'Completed';
      case CollabStatuses.disputed:
        return 'Disputed';
      case CollabStatuses.cancelled:
        return 'Cancelled';
      case CollabStatuses.declined:
        return 'Declined';
      default:
        return 'Requested';
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case CollabStatuses.completed:
      case CollabStatuses.delivered:
      case CollabStatuses.advancePaid:
      case CollabStatuses.inProgress:
        return AppColors.success;
      case CollabStatuses.disputed:
      case CollabStatuses.cancelled:
      case CollabStatuses.declined:
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  static const List<String> _kMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_kMonths[l.month - 1]} ${l.year}';
  }

  List<Widget> _buildStatusActions(Collaboration collab, String status) {
    final actions = <Widget>[];

    if (status == CollabStatuses.accepted) {
      actions.addAll(_buildOfferActions(collab));
    }

    if (status == CollabStatuses.agreementPending) {
      actions.add(
        _infoLine(
          'Total ${formatCollabAmount(collab.agreedAmountMinor)} · '
          'Advance ${formatCollabAmount(collab.advanceAmountMinor)} · '
          'Final ${formatCollabAmount(collab.finalAmountMinor)}',
        ),
      );
      actions.add(
        _actionButton(
          'Agreement PDF',
          Icons.description_outlined,
          _downloadAgreement,
          outlined: true,
        ),
      );
      if (controller.isClient) {
        actions.add(
          _actionButton(
            'Pay advance (25%) — ${formatCollabAmount(controller.advancePayment?.amountMinor)}',
            Icons.payment_outlined,
            () => _pay(CollabMilestones.advance),
          ),
        );
      }
    }

    if (_kWorkStatuses.contains(status)) {
      if (controller.isInfluencer) {
        actions.add(
          _actionButton(
            'Send sample (view once)',
            Icons.videocam_outlined,
            _sendSample,
            outlined: true,
          ),
        );
        actions.add(
          _actionButton(
            'Request site location',
            Icons.location_searching,
            _requestLocation,
            outlined: true,
          ),
        );
      }
      if (controller.isClient) {
        actions.add(
          _actionButton(
            'Share my location',
            Icons.my_location_outlined,
            _shareLocation,
            outlined: true,
          ),
        );
        actions.add(
          _actionButton(
            'Confirm & pay final (75%) — ${formatCollabAmount(controller.finalPayment?.amountMinor ?? collab.finalAmountMinor)}',
            Icons.payment_outlined,
            _confirmPayFinal,
          ),
        );
      }
    }

    if (_kDeliverableStatuses.contains(status) && controller.isInfluencer) {
      actions.add(
        _actionButton(
          'Upload final deliverable',
          Icons.upload_file_outlined,
          _sendDeliverable,
        ),
      );
    }

    if (status == CollabStatuses.delivered) {
      if (controller.isClient) {
        actions.add(
          _infoLine(
            'Download the deliverable from the chat below — it expires 7 days after delivery.',
          ),
        );
      }
      if (controller.isInfluencer) {
        actions.add(
          _actionButton(
            'Send corrected deliverable',
            Icons.upload_file_outlined,
            _sendDeliverable,
            outlined: true,
          ),
        );
      }
    }

    if (status == CollabStatuses.completed) {
      actions.add(
        _infoLine(
          'Collaboration completed. Payout to the influencer is scheduled within 30 days.',
        ),
      );
    }

    if (status == CollabStatuses.disputed) {
      actions.add(_disputeBanner(collab.disputeReason));
    }

    if (status == CollabStatuses.cancelled) {
      actions.add(_infoLine('This collaboration was cancelled.'));
    }

    if (_kDisputableStatuses.contains(status)) {
      actions.add(
        _dangerLink('Raise a dispute', Icons.flag_outlined, _raiseDispute),
      );
    }

    // `CollabActionPanel.tsx`'s `canCancel`: either participant, only while
    // `accepted` or `agreement_pending` — and the latter only stays that
    // status while genuinely unpaid, since a paid advance moves it on to
    // `advance_paid`/`in_progress` server-side, so no extra payment check is
    // needed here beyond the status itself.
    if (_kCancellableStatuses.contains(status)) {
      actions.add(
        _dangerLink(
          'Cancel collaboration',
          Icons.cancel_outlined,
          _cancelCollaboration,
        ),
      );
    }

    return actions
        .map(
          (w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w),
        )
        .toList();
  }

  /// The `accepted`-status negotiation block — propose/counter/accept/wait,
  /// same block regardless of role, matching `CollabActionPanel.tsx`'s
  /// `accepted` case exactly.
  List<Widget> _buildOfferActions(Collaboration collab) {
    if (!collab.hasPendingOffer) {
      return [
        _actionButton(
          'Propose amount',
          Icons.payments_outlined,
          () => _proposeOffer(isCounter: false),
        ),
      ];
    }

    final amountText = formatCollabAmount(collab.pendingOfferAmountMinor);
    final mine = collab.proposedPendingOfferBy(controller.userId);

    if (mine) {
      return [
        _infoLine(
          'Waiting for the other party to respond to your offer of '
          '$amountText'
          '${collab.pendingOfferIsFinal ? ' (final offer)' : ''}.',
        ),
      ];
    }

    return [
      _infoLine(
        '${collab.pendingOfferIsFinal ? 'Final offer' : 'Offer'}: $amountText',
      ),
      _actionButton('Accept', Icons.check_circle_outline, _acceptOffer),
      if (!collab.pendingOfferIsFinal)
        _actionButton(
          'Counter',
          Icons.sync_alt,
          () => _proposeOffer(isCounter: true),
          outlined: true,
        ),
    ];
  }

  Widget _buildInvoices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: controller.invoices
          .map(
            (invoice) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _actionButton(
                '${invoice.milestone == CollabMilestones.advance ? 'Advance' : 'Final'} invoice',
                Icons.receipt_long_outlined,
                () => _downloadInvoice(invoice),
                outlined: true,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool outlined = false,
  }) {
    final fg = outlined ? AppColors.primary : Colors.white;
    final radius = BorderRadius.circular(16);
    return Opacity(
      opacity: _busy ? 0.7 : 1,
      child: Container(
        height: outlined ? 50 : 56,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: outlined ? null : AppColors.primaryGradient,
          color: outlined ? Colors.white : null,
          border: outlined
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.45))
              : null,
          boxShadow: outlined ? null : AppColors.primaryGlow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: _busy ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: outlined ? 32 : 36,
                    height: outlined ? 32 : 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: outlined
                          ? AppColors.primaryLight
                          : Colors.white.withValues(alpha: 0.22),
                    ),
                    alignment: Alignment.center,
                    child: _busy
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: fg,
                            ),
                          )
                        : Icon(icon, size: 18, color: fg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: AppTextStyles.body.copyWith(
                        color: fg,
                        fontSize: outlined ? 13.5 : 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, size: 20, color: fg),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Red icon + text link (Cancel collaboration / Raise a dispute).
  Widget _dangerLink(String label, IconData icon, VoidCallback onTap) => Align(
    alignment: Alignment.centerLeft,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.error),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _infoLine(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFEDD5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.caption.copyWith(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _disputeBanner(String? reason) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEE2E2),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      'Disputed${reason != null && reason.isNotEmpty ? ': $reason' : ''} — payout is frozen pending admin review.',
      style: AppTextStyles.caption.copyWith(
        fontSize: 12,
        color: const Color(0xFFB91C1C),
      ),
    ),
  );
}

/// One "•" bullet line for the sample-instructions dialog.
class _BulletLine extends StatelessWidget {
  final String text;
  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: TextStyle(fontSize: 12.5)),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
      ],
    );
  }
}

/// Local-file video preview for the "stage before sending" sample dialog —
/// first frame only, no playback controls needed for a quick confirm step.
class _LocalVideoPreview extends StatefulWidget {
  final File file;
  const _LocalVideoPreview({required this.file});

  @override
  State<_LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<_LocalVideoPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(widget.file);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      debugPrint('CollabActionPanel: sample preview init failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: ColoredBox(
        color: Colors.black87,
        child: _failed
            ? const Center(child: Icon(Icons.videocam_off, color: Colors.white))
            : controller == null
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              )
            : FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: controller.value.size.width,
                  height: controller.value.size.height,
                  child: VideoPlayer(controller),
                ),
              ),
      ),
    );
  }
}
