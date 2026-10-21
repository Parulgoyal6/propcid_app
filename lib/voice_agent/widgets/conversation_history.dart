import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation_turn.dart';
import '../providers/voice_agent_provider.dart';

class ConversationHistory extends StatefulWidget {
  const ConversationHistory({super.key});

  @override
  State<ConversationHistory> createState() => _ConversationHistoryState();
}

class _ConversationHistoryState extends State<ConversationHistory> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceAgentProvider>(
      builder: (context, provider, _) {
        final turns = provider.conversation;
        _scrollToBottom();

        if (turns.isEmpty) {
          return Center(
            child: Text(
              'Ask me anything about properties…',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: turns.length,
          itemBuilder: (context, index) => _TurnBubble(turn: turns[index]),
        );
      },
    );
  }
}

class _TurnBubble extends StatelessWidget {
  final ConversationTurn turn;

  const _TurnBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                turn.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isUser ? colorScheme.onPrimary : colorScheme.onSurface,
                ),
              ),
            ),
            if (!isUser && turn.intent != null) ...[
              const SizedBox(height: 4),
              _IntentBadge(
                intentName: turn.intent!.name,
                toolExecuted: turn.toolExecuted,
                toolSuccess: turn.toolSuccess,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntentBadge extends StatelessWidget {
  final String intentName;
  final String? toolExecuted;
  final bool? toolSuccess;

  const _IntentBadge({
    required this.intentName,
    this.toolExecuted,
    this.toolSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showTool = toolExecuted != null;
    final succeeded = toolSuccess ?? true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            intentName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
        if (showTool) ...[
          const SizedBox(width: 4),
          Icon(
            succeeded ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: succeeded ? Colors.green.shade600 : Colors.red.shade400,
          ),
        ],
      ],
    );
  }
}
