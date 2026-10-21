// services/session_service.dart
//
// Generates (once per app install) and persists a random anonymous session
// id used for property view-tracking dedup via the track_property_view RPC.
//
// Deliberately NOT rotated per-launch the way the website's sessionStorage
// id rotates per browser tab — the RPC's own 30-minute server-side dedupe
// window is what actually decides whether a view counts as new, and a
// stable per-install id is simpler to reason about than inventing an
// inactivity cutoff for a mobile app (backgrounding != closing, unlike a
// browser tab).
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _prefsKey = 'propcid_session_id';
  static String? _cached;

  static Future<String> getSessionId() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString(_prefsKey);
    if (id == null) {
      id = _generateId();
      await prefs.setString(_prefsKey, id);
    }
    _cached = id;
    return id;
  }

  static String _generateId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
