// config/launch_features.dart
//
// Compile-time launch feature flags. Every payment-taking, subscription,
// paid-collaboration and Meta-publishing surface in this app is gated by one
// of these three booleans — none of their implementation (screens,
// providers, services, models, Razorpay, Meta OAuth) is deleted; only their
// entry points, automatic prompts, notification handling and optional data
// loading are gated, all reversibly.
//
// FAIL CLOSED, ON PURPOSE
// ------------------------
// Every flag has `defaultValue: false`. A build that forgets to pass
// `--dart-define-from-file` — including a plain `flutter run` — gets every
// gated feature HIDDEN, never silently enabled. To turn a feature back on,
// build with the matching JSON file:
//
//   flutter build appbundle --release \
//     --dart-define-from-file=config/features/play_release.json   # all off — Play launch
//   flutter run \
//     --dart-define-from-file=config/features/full_development.json # all on — local/dev
//
// Neither JSON file holds a secret — they are three booleans each, safe to
// commit.
import '../core/constants/app_constants.dart';

class LaunchFeatures {
  LaunchFeatures._();

  /// Subscriptions, plan upgrades and the Razorpay-backed payment/billing
  /// screens (Upgrade, Subscription & Billing, Payment Method, the one-time
  /// launch-offer prompt).
  static const bool subscriptions = bool.fromEnvironment(
    'FEATURE_SUBSCRIPTIONS',
    defaultValue: false,
  );

  /// The Collaboration Marketplace's paid side — sending/accepting a paid
  /// collaboration request and its Razorpay advance/final payments. Plain
  /// Chats and Channels are unaffected either way.
  static const bool paidCollaborations = bool.fromEnvironment(
    'FEATURE_PAID_COLLABORATIONS',
    defaultValue: false,
  );

  /// Meta (Facebook/Instagram) publishing — the Social hub, connecting a
  /// Meta account, and the automatic "Publish Everywhere"/"Boost on Meta"
  /// prompts after creating a property, article or reel. Plain Feed, Reels
  /// and the generic Facebook "share" sheets are unaffected either way.
  static const bool metaPublishing = bool.fromEnvironment(
    'FEATURE_META_PUBLISHING',
    defaultValue: false,
  );

  /// Controls the floating AI Assistant, authentication help assistant,
  /// voice-agent provider and AI tool registration.
  static const bool voiceAssistant = bool.fromEnvironment(
    'FEATURE_VOICE_ASSISTANT',
    defaultValue: false,
  );

  /// Every named route a disabled feature must block. Route names outside
  /// these sets are always enabled — this only ever returns false for a
  /// route that belongs to a currently-disabled feature.
  static bool routeEnabled(String? route) {
    if (route == null) return true;
    if (!subscriptions && _subscriptionRoutes.contains(route)) return false;
    if (!metaPublishing && _metaRoutes.contains(route)) return false;
    return true;
  }

  static const Set<String> _subscriptionRoutes = {
    AppConstants.upgradeScreen,
    AppConstants.subscriptionBillingScreen,
    AppConstants.paymentMethodScreen,
  };

  static const Set<String> _metaRoutes = {
    AppConstants.socialScreen,
    AppConstants.socialAccountsScreen,
    AppConstants.socialCampaignsScreen,
    AppConstants.socialLeadsScreen,
    AppConstants.socialPreferencesScreen,
    AppConstants.socialActivityScreen,
    AppConstants.socialAnalyticsScreen,
  };
}
