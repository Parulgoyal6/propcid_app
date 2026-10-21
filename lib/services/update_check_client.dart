// Thin abstraction over the `in_app_update` plugin (Google Play In-App
// Updates / Play Core). `InAppUpdateService` depends only on this interface,
// never on the plugin's own types directly, so its branching logic can be
// unit-tested with a fake client — the plugin itself is a platform channel
// and cannot be exercised in a test environment (no real Play Services).
import 'dart:async';

import 'package:in_app_update/in_app_update.dart' as play;

/// Whether Play reports an update, and whether it can run as a FLEXIBLE
/// (background-download) update specifically — this app never offers an
/// IMMEDIATE (blocking) update, so `immediateUpdateAllowed` is deliberately
/// not surfaced here.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.updateAvailable,
    required this.flexibleAllowed,
  });

  final bool updateAvailable;
  final bool flexibleAllowed;
}

/// Terminal outcome of a flexible update attempt.
enum FlexibleUpdateOutcome { downloaded, declinedOrFailed }

abstract class UpdateCheckClient {
  Future<UpdateCheckResult> checkForUpdate();

  /// Starts the flexible download and resolves only once it's reached a
  /// terminal state — fully downloaded, or ended without completing
  /// (declined at the Play dialog, failed, or cancelled). A single
  /// Future-returning call rather than a stream the caller has to manage,
  /// deliberately — see [UpdateCheckClient]'s own doc comment.
  Future<FlexibleUpdateOutcome> runFlexibleUpdate();

  Future<void> completeFlexibleUpdate();
}

/// Real implementation — never constructed in a test.
class PlayInAppUpdateClient implements UpdateCheckClient {
  const PlayInAppUpdateClient();

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    final info = await play.InAppUpdate.checkForUpdate();
    return UpdateCheckResult(
      updateAvailable:
          info.updateAvailability == play.UpdateAvailability.updateAvailable,
      flexibleAllowed: info.flexibleUpdateAllowed,
    );
  }

  @override
  Future<FlexibleUpdateOutcome> runFlexibleUpdate() async {
    // Subscribed before starting the download so an early/fast completion
    // can't be missed between `startFlexibleUpdate` returning and the
    // listener being attached.
    final completer = Completer<FlexibleUpdateOutcome>();
    final sub = play.InAppUpdate.installUpdateListener.listen(
      (status) {
        if (completer.isCompleted) return;
        if (status == play.InstallStatus.downloaded) {
          completer.complete(FlexibleUpdateOutcome.downloaded);
        } else if (status == play.InstallStatus.failed ||
            status == play.InstallStatus.canceled) {
          completer.complete(FlexibleUpdateOutcome.declinedOrFailed);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(FlexibleUpdateOutcome.declinedOrFailed);
        }
      },
    );

    try {
      final result = await play.InAppUpdate.startFlexibleUpdate();
      if (result != play.AppUpdateResult.success) {
        await sub.cancel();
        return FlexibleUpdateOutcome.declinedOrFailed;
      }
    } catch (_) {
      await sub.cancel();
      return FlexibleUpdateOutcome.declinedOrFailed;
    }

    final outcome = await completer.future;
    await sub.cancel();
    return outcome;
  }

  @override
  Future<void> completeFlexibleUpdate() =>
      play.InAppUpdate.completeFlexibleUpdate();
}
