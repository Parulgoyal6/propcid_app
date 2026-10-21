import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/update_ready_prompt.dart';
import 'update_check_client.dart';

/// Checks Google Play for a pending update and, if one exists, runs it
/// through the FLEXIBLE update flow — the download happens in the
/// background and the user is only interrupted once, after it finishes, to
/// offer a restart. Android-only; every other platform is a silent no-op.
/// Never an IMMEDIATE (blocking) update.
///
/// Mirrors `PremiumLaunchBottomSheet`'s session-gate pattern
/// (`LaunchOfferSessionGate`): [checkOnce] is safe to call unconditionally
/// from a post-frame callback and only ever does real work once per app run.
/// Every failure mode — no Play Store, `flutter run`, a sideloaded APK, no
/// connectivity, no update available, or the user declining/cancelling the
/// Play dialog — is swallowed silently so the caller never needs its own
/// error handling and the user can always keep using the app.
class InAppUpdateService {
  InAppUpdateService({UpdateCheckClient? client, bool Function()? isAndroid})
    : _client = client ?? const PlayInAppUpdateClient(),
      _isAndroid =
          isAndroid ?? (() => defaultTargetPlatform == TargetPlatform.android);

  final UpdateCheckClient _client;
  final bool Function() _isAndroid;

  static bool _checkedThisSession = false;

  /// Test-only: lets each test start from a fresh session.
  @visibleForTesting
  static void resetSessionGateForTest() => _checkedThisSession = false;

  /// Presents the "ready to restart" prompt at most once per app run.
  static Future<void> checkOnce(
    BuildContext context, {
    InAppUpdateService? service,
  }) {
    if (_checkedThisSession) return Future.value();
    _checkedThisSession = true;
    return (service ?? InAppUpdateService())._run(context);
  }

  Future<void> _run(BuildContext context) async {
    if (!_isAndroid()) return;

    final UpdateCheckResult result;
    try {
      result = await _client.checkForUpdate();
    } catch (_) {
      return;
    }
    if (!result.updateAvailable || !result.flexibleAllowed) return;

    final FlexibleUpdateOutcome outcome;
    try {
      outcome = await _client.runFlexibleUpdate();
    } catch (_) {
      // The user declined the Play dialog, or some other platform error —
      // either way, they keep using the current build.
      return;
    }
    if (outcome != FlexibleUpdateOutcome.downloaded || !context.mounted) {
      return;
    }

    showUpdateReadyPrompt(
      context,
      onRestart: () async {
        try {
          await _client.completeFlexibleUpdate();
        } catch (_) {
          // Nothing more to do — the user keeps using the current build.
        }
      },
    );
  }
}
