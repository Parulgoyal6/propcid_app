import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_navigator.dart';
import '../core/navigation/notification_route_resolver.dart';
import '../providers/auth_provider.dart';

/// Registers this device's Firebase Cloud Messaging token with the backend so
/// the `send-push` function can deliver every in-app notification as a push.
///
/// The backend stores the token in `push_tokens` via the `push-token-register`
/// edge function (the same one the website's FCM web push uses). Delivery while
/// the app is backgrounded or closed is handled by the OS from the FCM
/// `notification` payload; while the app is open, the in-app
/// `NotificationProvider` realtime channel already updates the badge/list.
/// Tapping a push opens the same screen the in-app notification list would
/// (the payload carries the notification's `type` + `data`, routed through
/// [resolveNotificationDestination]).
///
/// If Firebase isn't configured for this build (no google-services.json /
/// GoogleService-Info.plist) every method here is a harmless no-op.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _started = false;
  bool _firebaseReady = false;
  String? _registeredForUserId;
  AuthProvider? _auth;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> start(AuthProvider auth) async {
    if (_started) return;
    _started = true;

    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[push] Firebase not configured, push disabled: $e');
      return;
    }

    _auth = auth;
    auth.addListener(() => _syncWithAuth(auth));
    await _syncWithAuth(auth);

    // Tap on a push while the app is backgrounded.
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
    // Tap on a push that launched the app from a terminated state. Give the
    // splash/auth flow time to settle so the route isn't immediately replaced.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      Future<void>.delayed(const Duration(seconds: 2), () => _openFromMessage(initial));
    }

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final userId = auth.userId;
      if (userId != null) _registerToken(token);
    });
  }

  Future<void> _syncWithAuth(AuthProvider auth) async {
    if (!_firebaseReady) return;
    final userId = auth.userId;
    if (userId == null) {
      _registeredForUserId = null;
      return;
    }
    // Re-register only when the signed-in user changes; the backend reassigns
    // a token that moves to a different account.
    if (_registeredForUserId == userId) return;
    _registeredForUserId = userId;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] notification permission denied, skipping token registration');
        return;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      // Allow a retry on the next auth change.
      _registeredForUserId = null;
      debugPrint('[push] token registration failed: $e');
    }
  }

  void _openFromMessage(RemoteMessage message) {
    if (_auth?.userId == null) return; // signed out: nothing to open
    final type = message.data['type'];
    if (type == null || type.isEmpty) return;

    var data = <String, dynamic>{};
    final raw = message.data['data'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        // Malformed data: route by type alone.
      }
    }

    final destination = applyTeamWorkspaceOverride(
      baseline: resolveNotificationDestination(type: type, data: data),
      data: data,
      activeTeamMemberships: _auth?.activeTeamMemberships ?? const [],
    );
    if (destination == null) return;
    appNavigatorKey.currentState?.pushNamed(
      destination.route,
      arguments: destination.arguments,
    );
  }

  Future<void> _registerToken(String token) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'push-token-register',
        body: {'token': token, 'platform': Platform.isIOS ? 'ios' : 'android'},
      );
      debugPrint('[push] token registered (${Platform.isIOS ? 'ios' : 'android'})');
    } catch (e) {
      debugPrint('[push] push-token-register failed: $e');
    }
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _openedSub?.cancel();
  }
}
