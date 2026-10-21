import 'dart:async';

import 'package:flutter/widgets.dart';

import 'messaging_service.dart';

/// Keeps `profiles.is_online`/`last_seen_at` fresh (via the `update_own_presence`
/// RPC — the only legal write path, see MessagingService.updateOwnPresence)
/// while any messaging screen is open: a 30-second heartbeat in the
/// foreground, plus an immediate update on foreground/background transitions.
///
/// Scoped to the messaging module — started by [MessagingProvider] and
/// [ChatThreadProvider], not wired into the app's root widget — so presence
/// is live whenever the user is actually looking at chats, without touching
/// main.dart's bootstrap, which is outside this module's remit. Multiple
/// screens can [attach]/[detach] concurrently; only the first attach starts
/// the observer/timer and only the last detach stops them.
class PresenceService with WidgetsBindingObserver {
  PresenceService._(this._service);
  static PresenceService? _instance;

  factory PresenceService() =>
      _instance ??= PresenceService._(MessagingService());

  final MessagingService _service;
  Timer? _heartbeat;
  int _refCount = 0;

  void attach() {
    _refCount++;
    if (_refCount > 1) return;
    WidgetsBinding.instance.addObserver(this);
    _goOnline();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _goOnline(),
    );
  }

  void detach() {
    if (_refCount == 0) return;
    _refCount--;
    if (_refCount > 0) return;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _goOnline() => _service.updateOwnPresence(true);
  void _goOffline() => _service.updateOwnPresence(false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _goOnline();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _goOffline();
    }
  }
}
