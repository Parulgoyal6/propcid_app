import 'intent.dart';
import 'agent_response.dart';

class WorkflowState {
  final Intent? activeIntent;
  final Map<String, dynamic> collectedParams;
  final List<String> missingFields;
  final bool pendingConfirmation;
  final AgentResponse? confirmationPayload;

  const WorkflowState({
    this.activeIntent,
    required this.collectedParams,
    required this.missingFields,
    required this.pendingConfirmation,
    this.confirmationPayload,
  });

  WorkflowState copyWith({
    Intent? activeIntent,
    Map<String, dynamic>? collectedParams,
    List<String>? missingFields,
    bool? pendingConfirmation,
    AgentResponse? confirmationPayload,
    bool clearConfirmationPayload = false,
    bool clearActiveIntent = false,
  }) {
    return WorkflowState(
      activeIntent: clearActiveIntent
          ? null
          : (activeIntent ?? this.activeIntent),
      collectedParams: collectedParams ?? this.collectedParams,
      missingFields: missingFields ?? this.missingFields,
      pendingConfirmation: pendingConfirmation ?? this.pendingConfirmation,
      confirmationPayload: clearConfirmationPayload
          ? null
          : (confirmationPayload ?? this.confirmationPayload),
    );
  }
}

const WorkflowState initialWorkflowState = WorkflowState(
  activeIntent: null,
  collectedParams: {},
  missingFields: [],
  pendingConfirmation: false,
  confirmationPayload: null,
);
