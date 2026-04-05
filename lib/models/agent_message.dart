/// Messages exchanged between Flutter UI and the Node.js agent server.
library;

import 'dart:convert';

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
      'error' => ErrorMessage.fromJson(json),
      _ => ErrorMessage(message: 'Unknown message type: ${json['type']}'),
    };
  }
}

class InitMessage implements ServerMessage {
  final String sessionId;
  final List<AgentInfo> agents;
  InitMessage({required this.sessionId, required this.agents});
  factory InitMessage.fromJson(Map<String, dynamic> json) => InitMessage(
        sessionId: json['sessionId'] as String,
        agents: (json['agents'] as List)
            .map((a) => AgentInfo.fromJson(a as Map<String, dynamic>))
            .toList(),
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

class ErrorMessage implements ServerMessage {
  final String message;
  ErrorMessage({required this.message});
  factory ErrorMessage.fromJson(Map<String, dynamic> json) =>
      ErrorMessage(message: json['message'] as String);
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
}
