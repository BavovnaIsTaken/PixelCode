/// Riverpod providers for agent state management.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../services/agent_ws_service.dart';

// ─── WebSocket Service ───────────────────────────────────────────────────────

final wsServiceProvider = Provider<AgentWsService>((ref) {
  final service = AgentWsService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ─── Connection Status ───────────────────────────────────────────────────────

final connectionStatusProvider = StreamProvider<bool>((ref) {
  return ref.watch(wsServiceProvider).connectionStatus;
});

// ─── All server messages ─────────────────────────────────────────────────────

final serverMessagesProvider = StreamProvider<ServerMessage>((ref) {
  return ref.watch(wsServiceProvider).messages;
});

// ─── Chat messages ───────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<List<ChatMessage>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<ChatMessage> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case AssistantTextMessage(:final text):
        // Streaming text — append to last message or create new
        final messages = [...state];
        if (messages.isNotEmpty &&
            messages.last.role == ChatRole.assistant &&
            messages.last.isStreaming) {
          messages[messages.length - 1] = messages.last.copyWith(
            text: messages.last.text + text,
          );
        } else {
          messages.add(ChatMessage(
            role: ChatRole.assistant,
            text: text,
            isStreaming: true,
          ));
        }
        state = messages;

      case AssistantDoneMessage(:final text):
        // Finalize the streaming message
        final messages = [...state];
        if (messages.isNotEmpty &&
            messages.last.role == ChatRole.assistant &&
            messages.last.isStreaming) {
          messages[messages.length - 1] = messages.last.copyWith(
            text: text,
            isStreaming: false,
          );
        } else {
          messages.add(ChatMessage(role: ChatRole.assistant, text: text));
        }
        state = messages;

      case ErrorMessage(:final message):
        state = [
          ...state,
          ChatMessage(role: ChatRole.assistant, text: '⚠️ $message'),
        ];

      default:
        break;
    }
  }

  void sendMessage(String text) {
    state = [...state, ChatMessage(role: ChatRole.user, text: text)];
    ref.read(wsServiceProvider).sendMessage(text);
  }
}

final chatProvider = NotifierProvider<ChatNotifier, List<ChatMessage>>(
  ChatNotifier.new,
);

// ─── Agent statuses ──────────────────────────────────────────────────────────

class AgentState {
  final AgentInfo info;
  final AgentStatus status;
  final List<ToolActivity> activeTools;
  final String? currentTask;

  const AgentState({
    required this.info,
    this.status = AgentStatus.idle,
    this.activeTools = const [],
    this.currentTask,
  });

  AgentState copyWith({
    AgentStatus? status,
    List<ToolActivity>? activeTools,
    String? currentTask,
  }) =>
      AgentState(
        info: info,
        status: status ?? this.status,
        activeTools: activeTools ?? this.activeTools,
        currentTask: currentTask ?? this.currentTask,
      );
}

class AgentsNotifier extends Notifier<Map<String, AgentState>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  Map<String, AgentState> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return {};
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case InitMessage(:final agents):
        state = {
          for (final a in agents) a.id: AgentState(info: a),
        };

      case AgentStatusMessage(:final agentId, :final status, :final tools):
        final current = state[agentId];
        if (current != null) {
          state = {
            ...state,
            agentId: current.copyWith(status: status, activeTools: tools),
          };
        }

      case SubagentStartMessage(:final agentType, :final task):
        // Map sub-agent type to our team agents
        final agentId = _resolveAgentId(agentType);
        final current = state[agentId];
        if (current != null) {
          state = {
            ...state,
            agentId: current.copyWith(
              status: AgentStatus.running,
              currentTask: task,
            ),
          };
        }

      case SubagentStopMessage(:final agentId):
        final resolved = _resolveAgentId(agentId);
        final current = state[resolved];
        if (current != null) {
          state = {
            ...state,
            resolved: current.copyWith(
              status: AgentStatus.idle,
              activeTools: [],
              currentTask: null,
            ),
          };
        }

      case ToolUseMessage(:final agentId, :final toolName):
        // Determine which agent this tool belongs to based on tool name
        final resolved = _resolveAgentId(agentId);
        final current = state[resolved];
        if (current != null) {
          final newStatus = _toolNameToStatus(toolName);
          state = {
            ...state,
            resolved: current.copyWith(status: newStatus),
          };
        }

      case ResultMessage():
        // Reset all to idle
        state = {
          for (final entry in state.entries)
            entry.key: entry.value.copyWith(
              status: AgentStatus.idle,
              activeTools: [],
              currentTask: null,
            ),
        };

      default:
        break;
    }
  }

  String _resolveAgentId(String raw) {
    // Try exact match first
    if (state.containsKey(raw)) return raw;
    // Try fuzzy match
    final lower = raw.toLowerCase();
    for (final key in state.keys) {
      if (lower.contains(key) || key.contains(lower)) return key;
    }
    return 'tech-lead';
  }

  AgentStatus _toolNameToStatus(String toolName) => switch (toolName) {
        'Read' || 'Grep' || 'Glob' => AgentStatus.reading,
        'Edit' || 'Write' => AgentStatus.typing,
        'Bash' => AgentStatus.running,
        'Agent' || 'Task' => AgentStatus.thinking,
        _ => AgentStatus.running,
      };
}

final agentsProvider = NotifierProvider<AgentsNotifier, Map<String, AgentState>>(
  AgentsNotifier.new,
);
