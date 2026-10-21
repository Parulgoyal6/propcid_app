// services/registration_draft_store.dart
//
// Mirrors the portal's per-wizard draft persistence — e.g.
// `localStorage.setItem("builder_registration_draft", JSON.stringify({
//   formData, currentStep, timestamp, status: "draft" }))` in
// BuilderRegistration.tsx (and the equivalent `broker_registration_draft` /
// `influencer_registration_draft` keys in the other two wizards) — restored
// on mount if under 7 days old.
//
// Unlike the portal's raw `localStorage` key, this scopes the stored draft
// to the signed-in user's id. The portal's key has no such scoping (any
// browser profile sees whatever the last saved draft was); a shared mobile
// device makes that a real risk of leaking one person's half-filled
// registration into someone else's, so every key here is
// `{draftKeyBase}_{userId}`. A signed-out caller (no current user) simply
// cannot save or load — there is nothing meaningful to scope the draft to.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationDraftStore {
  RegistrationDraftStore(this.draftKeyBase);

  /// e.g. `'builder_registration_draft'` — matches the portal's own
  /// localStorage key name for the same wizard, purely for discoverability.
  final String draftKeyBase;

  static const Duration maxAge = Duration(days: 7);
  static const Duration _debounceDelay = Duration(seconds: 1);

  Timer? _debounce;

  String? get _prefsKey {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;
    return '${draftKeyBase}_$userId';
  }

  /// Debounces writes the same way the portal's `autoSave` does (1 second
  /// after the last change) so a fast-typing user isn't hitting disk on
  /// every keystroke. [buildPayload] is called once the debounce elapses,
  /// so it always serializes the *latest* form state, not the state at the
  /// moment this was called.
  void scheduleSave(Map<String, dynamic> Function() buildPayload) {
    final key = _prefsKey;
    if (key == null) return;

    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          key,
          jsonEncode({
            'formData': buildPayload(),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } catch (e) {
        debugPrint('RegistrationDraftStore.scheduleSave failed: $e');
      }
    });
  }

  /// Returns the saved `formData` map, or null when there is nothing to
  /// restore — no signed-in user, no saved draft, a draft older than
  /// [maxAge], or a corrupted entry (treated as absent rather than thrown).
  Future<Map<String, dynamic>?> load() async {
    final key = _prefsKey;
    if (key == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final timestamp = decoded['timestamp'] as int?;
      if (timestamp == null) return null;
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (age > maxAge.inMilliseconds) return null;

      final formData = decoded['formData'];
      return formData is Map<String, dynamic> ? formData : null;
    } catch (e) {
      debugPrint('RegistrationDraftStore.load failed: $e');
      return null;
    }
  }

  /// Removes the saved draft — call once the wizard actually submits.
  Future<void> clear() async {
    final key = _prefsKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (e) {
      debugPrint('RegistrationDraftStore.clear failed: $e');
    }
  }

  /// Cancels any pending debounced save. Call from the screen's `dispose()`
  /// so a save timer never fires against a disposed controller.
  void dispose() {
    _debounce?.cancel();
  }
}
