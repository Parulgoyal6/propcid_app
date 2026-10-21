// Launch feature flags — the central gate for subscriptions, paid
// collaborations and Meta publishing.
//
// Every flag must default to false (fail closed): a build that forgets
// --dart-define-from-file must hide every gated feature, never show it.
// `flutter test` never passes a dart-define, so every assertion here runs
// against that exact default — the same configuration a plain `flutter run`
// or a forgotten build flag would produce.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/config/launch_features.dart';
import 'package:propcid_app/core/constants/app_constants.dart';

void main() {
  group('defaults', () {
    test('every flag is false with no dart-define passed', () {
      expect(LaunchFeatures.subscriptions, isFalse);
      expect(LaunchFeatures.paidCollaborations, isFalse);
      expect(LaunchFeatures.metaPublishing, isFalse);
    });
  });

  group('routeEnabled', () {
    test('blocks every subscription/payment route by default', () {
      for (final route in [
        AppConstants.upgradeScreen,
        AppConstants.subscriptionBillingScreen,
        AppConstants.paymentMethodScreen,
      ]) {
        expect(LaunchFeatures.routeEnabled(route), isFalse, reason: route);
      }
    });

    test('blocks every Social route by default', () {
      for (final route in [
        AppConstants.socialScreen,
        AppConstants.socialAccountsScreen,
        AppConstants.socialCampaignsScreen,
        AppConstants.socialLeadsScreen,
        AppConstants.socialPreferencesScreen,
        AppConstants.socialActivityScreen,
        AppConstants.socialAnalyticsScreen,
      ]) {
        expect(LaunchFeatures.routeEnabled(route), isFalse, reason: route);
      }
    });

    test('leaves every other route alone', () {
      for (final route in [
        '/',
        AppConstants.feedScreen,
        AppConstants.messagesScreen,
        AppConstants.networkScreen,
        AppConstants.publicProfileScreen,
        '/property-detail',
        '/reels',
      ]) {
        expect(LaunchFeatures.routeEnabled(route), isTrue, reason: route);
      }
    });

    test('a null route name is never treated as disabled', () {
      expect(LaunchFeatures.routeEnabled(null), isTrue);
    });
  });
}
