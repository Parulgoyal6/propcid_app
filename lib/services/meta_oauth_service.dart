import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/launch_features.dart';
import '../models/social_models.dart';

/// Mobile port of `src/services/social/metaOAuthService.ts`'s connect/select/
/// disconnect flow, calling the exact same Edge Functions the portal does
/// (`meta-oauth-exchange`, `meta-select-page`, `meta-disconnect`) — no new
/// backend, no secrets, no service-role key.
///
/// WHY THE REDIRECT MECHANISM DIFFERS FROM THE PORTAL
/// ----------------------------------------------------
/// React does a full-page `window.location.href` redirect to Facebook's OAuth
/// dialog and back to its own web origin. A mobile app has no "own origin" to
/// redirect back to, so the redirect target here is the custom URL scheme
/// `propcid://meta-callback` instead — registered in `AndroidManifest.xml`
/// and `Info.plist` alongside the app's two other proven external-browser
/// round trips (email magic-link's `com.propcid.app://login-callback` and
/// password reset's `propcid://reset-password`). `meta-oauth-exchange` itself
/// needs no change: it already takes `redirect_uri` as a parameter from the
/// caller rather than hardcoding the portal's origin, precisely so it can
/// exchange the code Meta issued against *whichever* redirect_uri the
/// authorize step actually used.
///
/// THE ONE THING THIS APP CANNOT DO ITSELF
/// -----------------------------------------
/// `propcid://meta-callback` must be added to the Meta App's own "Valid OAuth
/// Redirect URIs" list in the Facebook Developer dashboard — a one-time,
/// human, dashboard-side step. Until that's done, Facebook's authorize step
/// will reject the redirect_uri outright; nothing in this file can detect or
/// route around that ahead of time.
class MetaOAuthService {
  static const String oauthRedirectUri =
      'https://viboxyvkzntuealqcvze.supabase.co/functions/v1/meta-mobile-oauth-callback';

  static const String deepLinkRedirectUri = 'propcid://meta-callback';

  /// Same scope list as `metaOAuthService.ts`'s `META_SCOPES` — Pages +
  /// Instagram + Ads/Leads. Advanced-access scopes (ads_management,
  /// ads_read, pages_manage_ads, leads_retrieval) only actually grant once
  /// the Meta app is Live + Business Verified + App-Reviewed; until then the
  /// exchange still succeeds, just with `ads_capable=false`.
  static const List<String> _scopes = [
    'pages_show_list',
    'pages_manage_posts',
    'pages_read_engagement',
    'business_management',
    'instagram_basic',
    'instagram_content_publish',
    'ads_management',
    'ads_read',
    'pages_manage_ads',
    'leads_retrieval',
  ];

  SupabaseClient get _supabase => Supabase.instance.client;

  String? get _appId => dotenv.env['META_APP_ID'];

  /// Gates the Connect button off, the same way the portal's
  /// `isMetaConfigured()` does, when no App ID has been set.
  bool get isConfigured => (_appId ?? '').trim().isNotEmpty;

  String _generateState() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String _buildOAuthUrl(String state) {
    final params = {
      'client_id': _appId!,
      'redirect_uri': oauthRedirectUri,
      'response_type': 'code',
      'scope': _scopes.join(','),
      'state': state,
    };
    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return 'https://www.facebook.com/v21.0/dialog/oauth?$query';
  }

  /// A function that returns HTTP 200 with `{ error: '...' }` is still a
  /// failure — same unwrap `EdgeFunctionsService`/`edgeError.ts` already use.
  Future<Map<String, dynamic>> _invoke(
    String function, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await _supabase.functions.invoke(function, body: body);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw data['error'].toString();
      }
      return (data as Map<String, dynamic>?) ?? const <String, dynamic>{};
    } on FunctionException catch (e) {
      final message = e.details is Map ? e.details['error'] : null;
      throw message?.toString() ?? 'Could not reach Meta. Please try again.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'A network error occurred. Please try again.';
    }
  }

  /// Opens Facebook's OAuth dialog in the external browser, waits for the
  /// `propcid://meta-callback` redirect, validates the CSRF `state`, then
  /// exchanges the returned code — one call that does what the portal's
  /// button + query-param effect + `exchangeCode` do together, since a
  /// mobile app has no page-reload moment to split them across.
  ///
  /// Throws a plain [String] message on any failure (config missing, user
  /// cancelled/denied, state mismatch, or the exchange itself failing) —
  /// callers show it directly, matching this app's other Edge Function
  /// wrappers.
  Future<List<AvailablePage>> connect() async {
    if (!LaunchFeatures.metaPublishing) {
      throw 'Social connections are not available in this build.';
    }
    if (!isConfigured) {
      throw 'Social connections are not set up on this build yet.';
    }

    final state = _generateState();
    final appLinks = AppLinks();
    final completer = Completer<Uri>();
    late final StreamSubscription<Uri> sub;
    sub = appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'propcid' &&
          uri.host == 'meta-callback' &&
          !completer.isCompleted) {
        completer.complete(uri);
      }
    }, onError: (_) {});

    try {
      final launched = await launchUrl(
        Uri.parse(_buildOAuthUrl(state)),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw 'Could not open the Facebook login page.';

      final callback = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw 'Connection timed out — please try again.',
      );

      final error = callback.queryParameters['error'];
      if (error != null) {
        final description = callback.queryParameters['error_description'];
        throw description ?? 'Facebook login was cancelled.';
      }

      final returnedState = callback.queryParameters['state'];
      if (returnedState != state) {
        throw 'Could not verify the login response. Please try again.';
      }

      final code = callback.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw 'Facebook did not return a login code.';
      }

      final result = await _invoke(
        'meta-oauth-exchange',
        body: {'code': code, 'redirect_uri': oauthRedirectUri},
      );
      final pages = (result['pages'] as List? ?? const [])
          .whereType<Map>()
          .map((p) => AvailablePage.fromJson(Map<String, dynamic>.from(p)))
          .toList();
      return pages;
    } finally {
      await sub.cancel();
    }
  }

  /// Persists the chosen Facebook Page (and its linked Instagram Business
  /// account, if any) as the connected account — completes the connect flow.
  Future<void> selectPage(String pageId) =>
      _invoke('meta-select-page', body: {'page_id': pageId});

  Future<void> disconnect() => _invoke('meta-disconnect');
}
