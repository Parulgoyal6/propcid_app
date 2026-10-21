import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Maps a failed Meta API call to a "fix it there" link — a direct port of
/// `metaAdsService.ts`'s `isBillingError`/`isDevModeError`/`metaErrorAction`.
///
/// Some campaign-lifecycle failures can only be resolved outside the app (no
/// payment method on the ad account, the Meta app still in Development mode).
/// Surfacing a dead-end error message for those is worse than pointing the
/// user straight at Meta's own settings page.
class MetaErrorAction {
  final String label;
  final String url;
  const MetaErrorAction(this.label, this.url);
}

bool isMetaBillingError(String? message) => RegExp(
  r'payment|billing|funding|spend limit|payment method',
  caseSensitive: false,
).hasMatch(message ?? '');

bool isMetaDevModeError(String? message) => RegExp(
  r'development mode|must be in public|in public to create',
  caseSensitive: false,
).hasMatch(message ?? '');

/// Meta Ads Manager's billing page for a given ad account (`act_<id>` or
/// `<id>`).
String metaBillingUrl(String? adAccountId) {
  final id = (adAccountId ?? '').replaceFirst(RegExp(r'^act_'), '');
  return 'https://adsmanager.facebook.com/ads/manager/account_settings/'
      'account_billing/?act=$id';
}

/// The Meta app's dashboard, to switch it from Development to Live mode.
String metaAppDashboardUrl() {
  final appId = dotenv.env['META_APP_ID'];
  return (appId != null && appId.isNotEmpty)
      ? 'https://developers.facebook.com/apps/$appId/settings/basic/'
      : 'https://developers.facebook.com/apps/';
}

/// The action to offer alongside a failed-lifecycle error message, or null
/// when the message isn't one of the two fixable-outside-the-app cases.
MetaErrorAction? metaErrorAction(String message, {String? adAccountId}) {
  if (isMetaBillingError(message)) {
    return MetaErrorAction('Add payment method', metaBillingUrl(adAccountId));
  }
  if (isMetaDevModeError(message)) {
    return MetaErrorAction('Open app settings', metaAppDashboardUrl());
  }
  return null;
}
