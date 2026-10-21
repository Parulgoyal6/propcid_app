// services/notification_alert_preference.dart
//
// A single, local, per-device preference: whether the Notification Centre's
// arrival cue — a short system sound plus a haptic tap, fired by
// `NotificationProvider._onInserted` whenever a row lands while the app is
// open (see that file) — plays at all.
//
// WHAT THIS IS NOT
// -----------------
// This is not an OS push-notification toggle: this app has no
// firebase_messaging/flutter_local_notifications wiring, so there is no
// notification-tray delivery to control, and flipping this never requests or
// changes the Android/iOS notification permission. It is also not a server
// preference — nothing on the backend reads this key. It only silences the
// in-app sound/vibration cue for whoever has this device signed in; the
// Notification Centre list itself is unaffected either way.
import 'package:shared_preferences/shared_preferences.dart';

class NotificationAlertPreference {
  NotificationAlertPreference._();

  static const String _key = 'settings_notification_alert_enabled';

  /// Defaults to enabled — the cue always played before this preference
  /// existed, so an unset key must not silently change that for anyone who
  /// never touches the setting.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
