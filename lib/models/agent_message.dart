/// Messages exchanged between Flutter UI and the Node.js agent server.
library;

import 'dart:convert';

import 'agent_trait.dart';
import 'task_board.dart';

// ─── Agent Info ──────────────────────────────────────────────────────────────

class AgentInfo {
  final String id;
  final String name;
  final String role;
  final String model;

  const AgentInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.model,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) => AgentInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] as String,
        model: json['model'] as String,
      );
}

// ─── Agent Status ────────────────────────────────────────────────────────────

enum AgentStatus { idle, thinking, typing, reading, running, waiting }

AgentStatus parseAgentStatus(String s) => switch (s) {
      'thinking' => AgentStatus.thinking,
      'typing' => AgentStatus.typing,
      'reading' => AgentStatus.reading,
      'running' => AgentStatus.running,
      'waiting' => AgentStatus.waiting,
      _ => AgentStatus.idle,
    };

class ToolActivity {
  final String toolUseId;
  final String toolName;
  final String status;

  const ToolActivity({
    required this.toolUseId,
    required this.toolName,
    required this.status,
  });

  factory ToolActivity.fromJson(Map<String, dynamic> json) => ToolActivity(
        toolUseId: json['toolUseId'] as String,
        toolName: json['toolName'] as String,
        status: json['status'] as String,
      );
}

// ─── Server → Client messages ────────────────────────────────────────────────

sealed class ServerMessage {
  factory ServerMessage.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return switch (json['type'] as String) {
      'init' => InitMessage.fromJson(json),
      'assistant_text' => AssistantTextMessage.fromJson(json),
      'assistant_message_done' => AssistantDoneMessage.fromJson(json),
      'agent_status' => AgentStatusMessage.fromJson(json),
      'subagent_start' => SubagentStartMessage.fromJson(json),
      'subagent_stop' => SubagentStopMessage.fromJson(json),
      'tool_use' => ToolUseMessage.fromJson(json),
      'tool_done' => ToolDoneMessage.fromJson(json),
      'result' => ResultMessage.fromJson(json),
      'team_metrics' => TeamMetricsMessage.fromJson(json),
      'activity_event' => ActivityEventMessage.fromJson(json),
      'comm_graph' => CommGraphMessage.fromJson(json),
      'debug_log' => DebugLogMessage.fromJson(json),
      'error' => ErrorMessage.fromJson(json),
      'board_state' => BoardStateMessage.fromJson(json),
      'summary_result' => SummaryResultMessage.fromJson(json),
      'agent_traits' => AgentTraitsMessage.fromJson(json),
      _ => ErrorMessage(message: 'Unknown message type: ${json['type']}'),
    };
  }
}

class InitMessage implements ServerMessage {
  final String sessionId;
  final List<AgentInfo> agents;
  final String? workingDirectory;
  InitMessage({required this.sessionId, required this.agents, this.workingDirectory});
  factory InitMessage.fromJson(Map<String, dynamic> json) => InitMessage(
        sessionId: json['sessionId'] as String,
        agents: (json['agents'] as List)
            .map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
            .toList(),
        workingDirectory: json['workingDirectory'] as String?,
      );
}

class AssistantTextMessage implements ServerMessage {
  final String text;
  final bool isPartial;
  AssistantTextMessage({required this.text, required this.isPartial});
  factory AssistantTextMessage.fromJson(Map<String, dynamic> json) =>
      AssistantTextMessage(
        text: json['text'] as String,
        isPartial: json['isPartial'] as bool,
      );
}

class AssistantDoneMessage implements ServerMessage {
  final String messageId;
  final String text;
  AssistantDoneMessage({required this.messageId, required this.text});
  factory AssistantDoneMessage.fromJson(Map<String, dynamic> json) =>
      AssistantDoneMessage(
        messageId: json['messageId'] as String,
        text: json['text'] as String,
      );
}

class AgentStatusMessage implements ServerMessage {
  final String agentId;
  final AgentStatus status;
  final List<ToolActivity> tools;
  AgentStatusMessage({
    required this.agentId,
    required this.status,
    required this.tools,
  });
  factory AgentStatusMessage.fromJson(Map<String, dynamic> json) =>
      AgentStatusMessage(
        agentId: json['agentId'] as String,
        status: parseAgentStatus(json['status'] as String),
        tools: (json['tools'] as List)
            .map((t) => ToolActivity.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

class SubagentStartMessage implements ServerMessage {
  final String parentAgentId;
  final String agentId;
  final String agentType;
  final String task;
  SubagentStartMessage({
    required this.parentAgentId,
    required this.agentId,
    required this.agentType,
    required this.task,
  });
  factory SubagentStartMessage.fromJson(Map<String, dynamic> json) =>
      SubagentStartMessage(
        parentAgentId: json['parentAgentId'] as String,
        agentId: json['agentId'] as String,
        agentType: json['agentType'] as String,
        task: json['task'] as String,
      );
}

class SubagentStopMessage implements ServerMessage {
  final String agentId;
  SubagentStopMessage({required this.agentId});
  factory SubagentStopMessage.fromJson(Map<String, dynamic> json) =>
      SubagentStopMessage(agentId: json['agentId'] as String);
}

class ToolUseMessage implements ServerMessage {
  final String agentId;
  final String toolUseId;
  final String toolName;
  final String status;
  ToolUseMessage({
    required this.agentId,
    required this.toolUseId,
    required this.toolName,
    required this.status,
  });
  factory ToolUseMessage.fromJson(Map<String, dynamic> json) => ToolUseMessage(
        agentId: json['agentId'] as String,
        toolUseId: json['toolUseId'] as String,
        toolName: json['toolName'] as String,
        status: json['status'] as String,
      );
}

class ToolDoneMessage implements ServerMessage {
  final String agentId;
  final String toolUseId;
  ToolDoneMessage({required this.agentId, required this.toolUseId});
  factory ToolDoneMessage.fromJson(Map<String, dynamic> json) =>
      ToolDoneMessage(
        agentId: json['agentId'] as String,
        toolUseId: json['toolUseId'] as String,
      );
}

class ResultMessage implements ServerMessage {
  final String text;
  final double costUsd;
  final int durationMs;
  ResultMessage({
    required this.text,
    required this.costUsd,
    required this.durationMs,
  });
  factory ResultMessage.fromJson(Map<String, dynamic> json) => ResultMessage(
        text: json['text'] as String? ?? '',
        costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

class CommGraphMessage implements ServerMessage {
  final List<CommEvent> events;
  CommGraphMessage({required this.events});
  factory CommGraphMessage.fromJson(Map<String, dynamic> json) => CommGraphMessage(
        events: (json['events'] as List)
            .map((e) => CommEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CommEvent {
  final int timestamp; // ms since epoch
  final String from;
  final String to;
  const CommEvent({required this.timestamp, required this.from, required this.to});
  factory CommEvent.fromJson(Map<String, dynamic> json) => CommEvent(
        timestamp: json['timestamp'] as int,
        from: json['from'] as String,
        to: json['to'] as String,
      );
}

class DebugLogMessage implements ServerMessage {
  final DateTime timestamp;
  final String level; // debug, info, warn, error
  final String category;
  final String message;

  DebugLogMessage({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
  });

  factory DebugLogMessage.fromJson(Map<String, dynamic> json) => DebugLogMessage(
        timestamp: DateTime.parse(json['timestamp'] as String),
        level: json['level'] as String,
        category: json['category'] as String,
        message: json['message'] as String,
      );
}

class ActivityEventMessage implements ServerMessage {
  final DateTime timestamp;
  final String agentId;
  final String event; // started, tool_use, completed, delegated, error
  final String detail;

  ActivityEventMessage({
    required this.timestamp,
    required this.agentId,
    required this.event,
    required this.detail,
  });

  factory ActivityEventMessage.fromJson(Map<String, dynamic> json) =>
      ActivityEventMessage(
        timestamp: DateTime.parse(json['timestamp'] as String),
        agentId: json['agentId'] as String,
        event: json['event'] as String,
        detail: json['detail'] as String,
      );
}

class TeamMetricsMessage implements ServerMessage {
  final Map<String, AgentMetrics> metrics;
  TeamMetricsMessage({required this.metrics});
  factory TeamMetricsMessage.fromJson(Map<String, dynamic> json) {
    final raw = json['metrics'] as Map<String, dynamic>;
    return TeamMetricsMessage(
      metrics: raw.map(
        (k, v) => MapEntry(k, AgentMetrics.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

class AgentMetrics {
  final int tasksAssigned;
  final int tasksCompleted;
  final int reworkCount;

  const AgentMetrics({
    required this.tasksAssigned,
    required this.tasksCompleted,
    required this.reworkCount,
  });

  factory AgentMetrics.fromJson(Map<String, dynamic> json) => AgentMetrics(
        tasksAssigned: json['tasksAssigned'] as int? ?? 0,
        tasksCompleted: json['tasksCompleted'] as int? ?? 0,
        reworkCount: json['reworkCount'] as int? ?? 0,
      );
}

class ErrorMessage implements ServerMessage {
  final String message;
  ErrorMessage({required this.message});
  factory ErrorMessage.fromJson(Map<String, dynamic> json) =>
      ErrorMessage(message: json['message'] as String);
}

class BoardStateMessage implements ServerMessage {
  final BoardState boardState;
  BoardStateMessage({required this.boardState});
  factory BoardStateMessage.fromJson(Map<String, dynamic> json) =>
      BoardStateMessage(
        boardState: BoardState(
          tasks: (json['tasks'] as List?)
                  ?.map((t) => TaskCard.fromJson(t as Map<String, dynamic>))
                  .toList() ??
              [],
        ),
      );
}

class SummaryResultMessage implements ServerMessage {
  final String summary;
  SummaryResultMessage({required this.summary});
  factory SummaryResultMessage.fromJson(Map<String, dynamic> json) =>
      SummaryResultMessage(summary: json['summary'] as String? ?? '');
}

class AgentTraitsMessage implements ServerMessage {
  final List<AgentTrait> traits;
  AgentTraitsMessage({required this.traits});
  factory AgentTraitsMessage.fromJson(Map<String, dynamic> json) =>
      AgentTraitsMessage(
        traits: (json['traits'] as List?)
                ?.map((t) => AgentTrait.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ─── Chat message model ─────────────────────────────────────────────────────

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final bool isStreaming;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.isStreaming = false,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({String? text, bool? isStreaming}) => ChatMessage(
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
      );

  Map<String, dynamic> toJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}
