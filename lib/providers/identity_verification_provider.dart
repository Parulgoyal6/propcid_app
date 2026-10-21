import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/identity_status.dart';
import '../services/identity_verification_service.dart';

/// The post-verify session step [IdentityVerificationProvider] needs —
/// extracted so tests can drive [IdentityVerificationProvider.verifyCode]
/// with a fake signed-in user id instead of a live Supabase session, the
/// same way `AuthServiceBase` lets `AuthProvider` be tested without one.
abstract class IdentitySessionGuard {
  /// The locally cached signed-in user id, read fresh (not cached) so a
  /// just-completed [refreshSession] call's effect is visible immediately.
  String? get currentUserId;

  /// Refreshes the session so updated email/phone claims propagate. Must
  /// not throw in a way that aborts the caller's own success handling — a
  /// refresh hiccup after an already-consumed OTP is not a failed
  /// verification.
  Future<void> refreshSession();
}

class _SupabaseIdentitySessionGuard implements IdentitySessionGuard {
  @override
  String? get currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  Future<void> refreshSession() =>
      Supabase.instance.client.auth.refreshSession();
}

/// Holds the signed-in user's identity-verification status (email/phone
/// linking) and drives send/verify requests against `verify-identifier`.
///
/// Scoped by user id via [syncUser] — called from the app's provider
/// composition (see `main.dart`'s `ChangeNotifierProxyProvider<AuthProvider,
/// IdentityVerificationProvider>`) whenever `AuthProvider` notifies, mirroring
/// the existing `NotificationProvider`/`RecentSearchesProvider` pattern of
/// resetting/reloading on an auth change rather than caching across accounts.
/// Every async method captures the user id it was called for and discards
/// its result if that id no longer matches by the time the request
/// completes — a previous account's late-arriving response can never be
/// applied to whichever account is current by then.
class IdentityVerificationProvider extends ChangeNotifier {
  IdentityVerificationProvider({
    IdentityVerificationService? service,
    IdentitySessionGuard? sessionGuard,
  }) : _service = service ?? IdentityVerificationService(),
       _sessionGuard = sessionGuard ?? _SupabaseIdentitySessionGuard();

  final IdentityVerificationService _service;
  final IdentitySessionGuard _sessionGuard;

  String? _userId;
  IdentityStatus? _status;
  bool _loading = false;
  IdentityVerificationFailure? _loadError;

  final Map<IdentityChannel, bool> _sending = {};
  final Map<IdentityChannel, bool> _verifying = {};
  final Map<IdentityChannel, IdentitySendResult> _lastSend = {};
  final Map<IdentityChannel, String> _pendingTarget = {};

  String? get userId => _userId;
  IdentityStatus? get status => _status;
  bool get isLoading => _loading;
  IdentityVerificationFailure? get loadError => _loadError;

  bool isSending(IdentityChannel channel) => _sending[channel] ?? false;
  bool isVerifying(IdentityChannel channel) => _verifying[channel] ?? false;
  IdentitySendResult? lastSend(IdentityChannel channel) =>
      _lastSend[channel];

  /// The exact target the most recent code for [channel] was sent to.
  /// Verification must bind to this, not to whatever the input currently
  /// shows — callers should clear it (via [clearPending]) the moment the
  /// user edits the target after a send.
  String? pendingTarget(IdentityChannel channel) => _pendingTarget[channel];

  /// Resets all cached identity state the moment the signed-in user changes
  /// (including to signed-out, `newUserId == null`), so a previous
  /// account's status or pending-send state can never leak into the next
  /// one. Idempotent for repeated calls with the same [newUserId] — safe to
  /// call from every `update:` rebuild.
  void syncUser(String? newUserId) {
    if (newUserId == _userId) return;
    _userId = newUserId;
    _status = null;
    _loadError = null;
    _loading = false;
    _sending.clear();
    _verifying.clear();
    _lastSend.clear();
    _pendingTarget.clear();
    notifyListeners();
  }

  /// Fetches status if not already loaded for the current user (or if
  /// [force] is true). Safe to call from multiple screens' `initState`.
  Future<void> ensureLoaded({bool force = false}) async {
    if (_userId == null) return;
    if (_status != null && !force) return;
    await _loadStatus();
  }

  Future<void> refresh() => _loadStatus();

  Future<void> _loadStatus() async {
    final requestedUserId = _userId;
    if (requestedUserId == null) return;
    // `ensureLoaded()` is explicitly documented as safe to call from
    // `initState()`, and every consuming screen does exactly that. Without
    // this deferral, the `notifyListeners()` three lines down would fire
    // SYNCHRONOUSLY within that same `initState()` call — i.e. while
    // Flutter is still in the middle of that widget's own first build —
    // which throws "setState() or markNeedsBuild() called during build" in
    // debug mode. One microtask is enough to land after the current build
    // phase's synchronous call stack has fully unwound, the same reason
    // `Future.microtask(...)` / `addPostFrameCallback` are the standard fix
    // for "notify from initState" in Flutter generally. Harmless for the
    // other callers (`refresh()`, button-triggered reloads) too.
    await Future<void>.microtask(() {});
    if (requestedUserId != _userId) return;

    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final result = await _service.status();
      if (requestedUserId != _userId) return;
      _status = result;
    } on IdentityVerificationFailure catch (e) {
      if (requestedUserId != _userId) return;
      _loadError = e;
    } catch (_) {
      if (requestedUserId != _userId) return;
      _loadError = const IdentityVerificationFailure(code: 'network_error');
    } finally {
      if (requestedUserId == _userId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Sends a code to [target] over [channel]. Throws
  /// [IdentityVerificationFailure] on failure — callers display it inline
  /// rather than this provider deciding how.
  Future<void> sendCode({
    required IdentityChannel channel,
    required String target,
  }) async {
    final requestedUserId = _userId;
    _sending[channel] = true;
    notifyListeners();
    try {
      final result = await _service.send(channel: channel, target: target);
      if (requestedUserId != _userId) return;
      _lastSend[channel] = result;
      _pendingTarget[channel] = target;
    } finally {
      if (requestedUserId == _userId) {
        _sending[channel] = false;
        notifyListeners();
      }
    }
  }

  /// Verifies [otp] for [channel]/[target]. On success: refreshes the
  /// Supabase session (so updated email/phone claims propagate), confirms
  /// the signed-in user id has not changed, and adopts the canonical status
  /// the server returned — re-fetching it if the server's own inline status
  /// lookup failed, rather than assuming success verified both identifiers.
  ///
  /// Deliberately calls `Supabase.instance.client.auth.refreshSession()`
  /// directly rather than routing through `AuthProvider`: that composes
  /// safely with `AuthProvider`'s existing same-user event coalescing
  /// (repeated `tokenRefreshed` events for an already-resolved user do not
  /// re-navigate — see `auth_navigation_test.dart`), so no change to
  /// `AuthProvider` itself is needed to pick this up safely.
  Future<void> verifyCode({
    required IdentityChannel channel,
    required String target,
    required String otp,
  }) async {
    final requestedUserId = _userId;
    if (requestedUserId == null) {
      throw const IdentityVerificationFailure(
        code: 'Not authenticated.',
        status: 401,
      );
    }
    _verifying[channel] = true;
    notifyListeners();
    try {
      final result = await _service.verify(
        channel: channel,
        target: target,
        otp: otp,
      );

      try {
        await _sessionGuard.refreshSession();
      } catch (e) {
        // The OTP was already consumed server-side — a refresh hiccup here
        // must not be reported as a failed verification.
        debugPrint('IdentityVerificationProvider: session refresh failed: $e');
      }

      if (_sessionGuard.currentUserId != requestedUserId) {
        // The signed-in account changed mid-request (e.g. a concurrent
        // logout/login) — never apply this result to whichever account is
        // current now.
        return;
      }
      if (requestedUserId != _userId) return;

      if (result != null) {
        _status = result;
      } else {
        // The server's own inline status lookup failed — retry rather than
        // assume success verified both identifiers.
        await _loadStatus();
      }
      _pendingTarget.remove(channel);
      _lastSend.remove(channel);
    } finally {
      if (requestedUserId == _userId) {
        _verifying[channel] = false;
        notifyListeners();
      }
    }
  }

  /// Clears pending send/verify state for [channel] — call the moment the
  /// user edits the target after a code was already sent, so a code typed
  /// for the old target can never be applied to the new one.
  void clearPending(IdentityChannel channel) {
    if (_pendingTarget[channel] == null && _lastSend[channel] == null) return;
    _pendingTarget.remove(channel);
    _lastSend.remove(channel);
    notifyListeners();
  }
}
