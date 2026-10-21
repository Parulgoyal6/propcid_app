import '../models/intent.dart';

class AiConfig {
  /// True by default. When true the provider forces complete:true after parsing,
  /// except for intents in [alwaysConfirmIntents] and [Intent.create_listing].
  /// Phase 2: read from flutter_dotenv when env flag is added.
  static bool get isAutonomous => true;

  /// Intents that still require user confirmation even in autonomous mode.
  static Set<Intent> get alwaysConfirmIntents => {
    Intent.delete_account,
    Intent.delete_listing,
    Intent.publish_listing,
    Intent.logout,
  };

  /// Phase 3: set true to enable RAG grounding calls to ai-knowledge Edge Function.
  static bool get isRagGroundingEnabled => false;
}
