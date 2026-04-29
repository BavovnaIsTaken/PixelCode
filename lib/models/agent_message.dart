/// Messages exchanged between Flutter UI and the Node.js agent server.
library;

import 'dart:convert';

import 'agent_trait.dart';
import 'facilitator_output.dart';
import 'quest_line.dart' show ScopeScore;
import 'task_board.dart';

enum AgentProviderType {
  cloud,    // Anthropic / Vertex AI via Server
  local,    // Gemini CLI / Local Model
  ollama,   // Future: Ollama / MLX / llama.cpp
  deepseek, // DeepSeek API (cloud, API-key based)
  kimi,     // Kimi K2.6 (Moonshot AI, API-key based)
}

// ─── Agent Info ──────────────────────────────────────────────────────────────

/// Identity of an agent known to the UI.
///
/// In the instance-based model [id] is typically an instanceId
/// (e.g. `"coder#1"`), but may fall back to a bare role type during startup
/// before game state is synced. [roleType] carries the underlying role.
class AgentInfo {
  final String id;
  final String name;
  final String role;
  final String model;
  final String roleType;
  final AgentProviderType provider;

  const AgentInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.model,
    required this.roleType,
    this.provider = AgentProviderType.cloud,
  });

  factory AgentInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    // Derive roleType from the id prefix if the server didn't send it
    // explicitly (legacy payloads). `coder#1` → `coder`; bare `coder` → `coder`.
    String derivedRoleType = json['roleType'] as String? ?? '';
    if (derivedRoleType.isEmpty) {
      final hash = id.indexOf('#');
      derivedRoleType = hash > 0 ? id.substring(0, hash) : id;
    }
    return AgentInfo(
      id: id,
      name: json['name'] as String,
      role: json['role'] as String,
      model: json['model'] as String,
      roleType: derivedRoleType,
      provider: AgentProviderType.values[json['provider'] as int? ?? 0],
    );
  }
}

// ─── Agent Status ────────────────────────────────────────────────────────────

/// Fine-grained what-the-agent-is-doing-right-now status, driven by server events.
enum AgentStatus { idle, thinking, typing, reading, running, waiting }

/// Binary occupancy state — is this agent processing anything right now?
///
/// Derived from [AgentStatus]: any value except [AgentStatus.idle] maps to [busy].
/// Use this when you only care about availability, not what the agent is doing
/// (e.g. team-dispatch routing, roster badge, can-reassign guard).
enum AgentBusyState { idle, busy }

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
      'input_text' => InputTextMessage.fromJson(json),
      'input_images' => InputImagesMessage.fromJson(json),
      'ios_deploy_status' => IOSDeployStatusMessage.fromJson(json),
      'android_deploy_status' => AndroidDeployStatusMessage.fromJson(json),
      'screenshot_status' => ScreenshotStatusMessage.fromJson(json),
      'tailscale_log' => TailscaleLogMessage.fromJson(json),
      'health_check_result' => HealthCheckResultMessage.fromJson(json),
      'health_item_update' => HealthItemUpdateMessage.fromJson(json),
      'chat_history' => ChatHistoryMessage.fromJson(json),
      'game_state_sync' => GameStateSyncMessage.fromJson(json),
      'positions_sync' => PositionsSyncMessage.fromJson(json),
      'server_info' => ServerInfoMessage.fromJson(json),
      'task_dispatched' => TaskDispatchedMessage.fromJson(json),
      'subagent_result' => SubagentResultMessage.fromJson(json),
      'queue_status' => QueueStatusMessage.fromJson(json),
      'task_too_hard' => TaskTooHardMessage.fromJson(json),
      'dungeon_started' => DungeonStartedMessage.fromJson(json),
      'dungeon_complete' => DungeonCompleteMessage.fromJson(json),
      'dungeon_error' => DungeonErrorMessage.fromJson(json),
      'facilitator_seeded' => FacilitatorSeededMessage.fromJson(json),
      'facilitator_error' => FacilitatorErrorMessage.fromJson(json),
      'facilitator_output_sync' => FacilitatorOutputSyncMessage.fromJson(json),
      'session_status' => SessionStatusMessage.fromJson(json),
      'session_taken' => SessionTakenMessage.fromJson(json),
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
  final String agentId;
  final String? threadId;
  AssistantTextMessage({required this.text, required this.isPartial, this.agentId = 'manager', this.threadId});
  factory AssistantTextMessage.fromJson(Map<String, dynamic> json) =>
      AssistantTextMessage(
        text: json['text'] as String,
        isPartial: json['isPartial'] as bool,
        agentId: json['agentId'] as String? ?? 'manager',
        threadId: json['threadId'] as String?,
      );
}

class AssistantDoneMessage implements ServerMessage {
  final String messageId;
  final String text;
  final String agentId;
  final String? threadId;
  AssistantDoneMessage({required this.messageId, required this.text, this.agentId = 'manager', this.threadId});
  factory AssistantDoneMessage.fromJson(Map<String, dynamic> json) =>
      AssistantDoneMessage(
        messageId: json['messageId'] as String,
        text: json['text'] as String,
        agentId: json['agentId'] as String? ?? 'manager',
        threadId: json['threadId'] as String?,
      );
}

class ChatHistoryMessage implements ServerMessage {
  final List<ChatMessage> messages;
  ChatHistoryMessage({required this.messages});
  factory ChatHistoryMessage.fromJson(Map<String, dynamic> json) =>
      ChatHistoryMessage(
        messages: (json['messages'] as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
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
  final String? threadId;
  ToolUseMessage({
    required this.agentId,
    required this.toolUseId,
    required this.toolName,
    required this.status,
    this.threadId,
  });
  factory ToolUseMessage.fromJson(Map<String, dynamic> json) => ToolUseMessage(
        agentId: json['agentId'] as String,
        toolUseId: json['toolUseId'] as String,
        toolName: json['toolName'] as String,
        status: json['status'] as String,
        threadId: json['threadId'] as String?,
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

class GameStateSyncMessage implements ServerMessage {
  final String fullState;
  final int stateUpdatedAt;
  GameStateSyncMessage({required this.fullState, required this.stateUpdatedAt});
  factory GameStateSyncMessage.fromJson(Map<String, dynamic> json) =>
      GameStateSyncMessage(
        fullState: json['fullState'] as String? ?? '{}',
        stateUpdatedAt: (json['stateUpdatedAt'] as num?)?.toInt() ?? 0,
      );
}

class RemoteCharPosition {
  final int col;
  final int row;
  final String state;
  final String dir;
  final bool onSkateboard;
  const RemoteCharPosition({
    required this.col,
    required this.row,
    required this.state,
    required this.dir,
    this.onSkateboard = false,
  });
  factory RemoteCharPosition.fromJson(Map<String, dynamic> json) =>
      RemoteCharPosition(
        col: json['col'] as int? ?? 0,
        row: json['row'] as int? ?? 0,
        state: json['state'] as String? ?? 'idle',
        dir: json['dir'] as String? ?? 'down',
        onSkateboard: json['onSkateboard'] as bool? ?? false,
      );
}

class PositionsSyncMessage implements ServerMessage {
  final Map<String, RemoteCharPosition> positions;
  PositionsSyncMessage({required this.positions});
  factory PositionsSyncMessage.fromJson(Map<String, dynamic> json) {
    final raw = json['positions'] as Map<String, dynamic>? ?? {};
    return PositionsSyncMessage(
      positions: raw.map(
        (k, v) => MapEntry(k, RemoteCharPosition.fromJson(v as Map<String, dynamic>)),
      ),
    );
  }
}

class InputTextMessage implements ServerMessage {
  final String text;
  InputTextMessage({required this.text});
  factory InputTextMessage.fromJson(Map<String, dynamic> json) =>
      InputTextMessage(text: json['text'] as String? ?? '');
}

class InputImagesMessage implements ServerMessage {
  final List<String> images;
  InputImagesMessage({required this.images});
  factory InputImagesMessage.fromJson(Map<String, dynamic> json) =>
      InputImagesMessage(
        images: (json['images'] as List?)?.cast<String>() ?? const [],
      );
}

class IOSDeployStatusMessage implements ServerMessage {
  /// deps_result, log, error, install_ready, complete
  final String subtype;
  final bool? hasFlutter;
  final String? message;
  final String? installUrl;
  final bool? success;

  IOSDeployStatusMessage({
    required this.subtype,
    this.hasFlutter,
    this.message,
    this.installUrl,
    this.success,
  });

  factory IOSDeployStatusMessage.fromJson(Map<String, dynamic> json) {
    return IOSDeployStatusMessage(
      subtype: json['subtype'] as String,
      hasFlutter: json['hasFlutter'] as bool?,
      message: json['message'] as String?,
      installUrl: json['installUrl'] as String?,
      success: json['success'] as bool?,
    );
  }
}

class AndroidDevice {
  final String serial;
  final String model;
  final String state; // "device", "unauthorized", "offline", …

  const AndroidDevice({
    required this.serial,
    required this.model,
    required this.state,
  });

  bool get isReady => state == 'device';

  factory AndroidDevice.fromJson(Map<String, dynamic> json) => AndroidDevice(
        serial: json['serial'] as String? ?? '',
        model: json['model'] as String? ?? '',
        state: json['state'] as String? ?? 'unknown',
      );
}

class AndroidDeployStatusMessage implements ServerMessage {
  /// deps_result, log, error, install_ready, complete, devices_list
  final String subtype;
  final bool? hasFlutter;
  final String? message;
  final String? installUrl;
  final bool? success;
  final List<AndroidDevice>? devices;

  AndroidDeployStatusMessage({
    required this.subtype,
    this.hasFlutter,
    this.message,
    this.installUrl,
    this.success,
    this.devices,
  });

  factory AndroidDeployStatusMessage.fromJson(Map<String, dynamic> json) {
    return AndroidDeployStatusMessage(
      subtype: json['subtype'] as String,
      hasFlutter: json['hasFlutter'] as bool?,
      message: json['message'] as String?,
      installUrl: json['installUrl'] as String?,
      success: json['success'] as bool?,
      devices: (json['devices'] as List?)
          ?.map((e) => AndroidDevice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ScreenshotStatusMessage implements ServerMessage {
  /// ready, error
  final String subtype;
  /// android, ios
  final String platform;
  final String? url;
  final String? message;

  ScreenshotStatusMessage({
    required this.subtype,
    required this.platform,
    this.url,
    this.message,
  });

  factory ScreenshotStatusMessage.fromJson(Map<String, dynamic> json) =>
      ScreenshotStatusMessage(
        subtype: json['subtype'] as String,
        platform: json['platform'] as String? ?? 'android',
        url: json['url'] as String?,
        message: json['message'] as String?,
      );
}

class TailscaleLogMessage implements ServerMessage {
  final String message;
  const TailscaleLogMessage({required this.message});
  factory TailscaleLogMessage.fromJson(Map<String, dynamic> json) =>
      TailscaleLogMessage(message: json['message'] as String);
}

// ─── Network diagnostics ────────────────────────────────────────────────────

enum HealthItemId {
  tailscaleInstalled,
  tailscaleRunning,
  funnelActive,
  serverListening,
  clientConnected,
  iosSigning,
  xcodeTools,
  androidSdk,
  androidSigning,
  mdnsActive;

  static HealthItemId? fromWire(String raw) => switch (raw) {
        'tailscaleInstalled' => HealthItemId.tailscaleInstalled,
        'tailscaleRunning' => HealthItemId.tailscaleRunning,
        'funnelActive' => HealthItemId.funnelActive,
        'serverListening' => HealthItemId.serverListening,
        'clientConnected' => HealthItemId.clientConnected,
        'iosSigning' => HealthItemId.iosSigning,
        'xcodeTools' => HealthItemId.xcodeTools,
        'androidSdk' => HealthItemId.androidSdk,
        'androidSigning' => HealthItemId.androidSigning,
        'mdnsActive' => HealthItemId.mdnsActive,
        _ => null,
      };

  String get wire => switch (this) {
        HealthItemId.tailscaleInstalled => 'tailscaleInstalled',
        HealthItemId.tailscaleRunning => 'tailscaleRunning',
        HealthItemId.funnelActive => 'funnelActive',
        HealthItemId.serverListening => 'serverListening',
        HealthItemId.clientConnected => 'clientConnected',
        HealthItemId.iosSigning => 'iosSigning',
        HealthItemId.xcodeTools => 'xcodeTools',
        HealthItemId.androidSdk => 'androidSdk',
        HealthItemId.androidSigning => 'androidSigning',
        HealthItemId.mdnsActive => 'mdnsActive',
      };
}

enum HealthStatus { ok, fail, checking }

class HealthItem {
  final HealthItemId id;
  final HealthStatus status;
  final String? detail;
  final bool fixable;
  final String? instruction;

  const HealthItem({
    required this.id,
    required this.status,
    this.fixable = false,
    this.detail,
    this.instruction,
  });

  HealthItem copyWith({HealthStatus? status, String? detail, bool? fixable, String? instruction}) =>
      HealthItem(
        id: id,
        status: status ?? this.status,
        detail: detail ?? this.detail,
        fixable: fixable ?? this.fixable,
        instruction: instruction ?? this.instruction,
      );

  static HealthItem? fromJson(Map<String, dynamic> json) {
    final id = HealthItemId.fromWire(json['id'] as String? ?? '');
    if (id == null) return null;
    final statusRaw = json['status'] as String? ?? 'fail';
    return HealthItem(
      id: id,
      status: switch (statusRaw) {
        'ok' => HealthStatus.ok,
        'checking' => HealthStatus.checking,
        _ => HealthStatus.fail,
      },
      detail: json['detail'] as String?,
      fixable: json['fixable'] as bool? ?? false,
      instruction: json['instruction'] as String?,
    );
  }
}

class HealthCheckResultMessage implements ServerMessage {
  final List<HealthItem> items;
  const HealthCheckResultMessage({required this.items});
  factory HealthCheckResultMessage.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List?) ?? const [];
    final items = <HealthItem>[];
    for (final entry in raw) {
      final item = HealthItem.fromJson(entry as Map<String, dynamic>);
      if (item != null) items.add(item);
    }
    return HealthCheckResultMessage(items: items);
  }
}

class HealthItemUpdateMessage implements ServerMessage {
  final HealthItem? item;
  const HealthItemUpdateMessage({required this.item});
  factory HealthItemUpdateMessage.fromJson(Map<String, dynamic> json) =>
      HealthItemUpdateMessage(
        item: HealthItem.fromJson(json['item'] as Map<String, dynamic>? ?? const {}),
      );
}

class ServerInfoMessage implements ServerMessage {
  final String hostname;
  final List<String> localIps;
  final int port;
  final String? tunnelUrl;

  ServerInfoMessage({
    required this.hostname,
    required this.localIps,
    required this.port,
    this.tunnelUrl,
  });

  factory ServerInfoMessage.fromJson(Map<String, dynamic> json) =>
      ServerInfoMessage(
        hostname: json['hostname'] as String? ?? '',
        localIps: (json['localIps'] as List?)?.cast<String>() ?? const [],
        port: json['port'] as int? ?? 9720,
        tunnelUrl: json['tunnelUrl'] as String?,
      );
}

// ─── Task dispatch (non-blocking coordination) ───────────────────────────

class TaskDispatchedMessage implements ServerMessage {
  final String dispatchId;
  final String agentId;
  final String task;
  final String priority;

  TaskDispatchedMessage({
    required this.dispatchId,
    required this.agentId,
    required this.task,
    required this.priority,
  });

  factory TaskDispatchedMessage.fromJson(Map<String, dynamic> json) =>
      TaskDispatchedMessage(
        dispatchId: json['dispatchId'] as String? ?? '',
        agentId: json['agentId'] as String? ?? '',
        task: json['task'] as String? ?? '',
        priority: json['priority'] as String? ?? 'normal',
      );
}

class SubagentResultMessage implements ServerMessage {
  final String dispatchId;
  final String agentId;
  final String result;
  final double costUsd;
  final int durationMs;

  SubagentResultMessage({
    required this.dispatchId,
    required this.agentId,
    required this.result,
    required this.costUsd,
    required this.durationMs,
  });

  factory SubagentResultMessage.fromJson(Map<String, dynamic> json) =>
      SubagentResultMessage(
        dispatchId: json['dispatchId'] as String? ?? '',
        agentId: json['agentId'] as String? ?? '',
        result: json['result'] as String? ?? '',
        costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

class RunningAgentInfo {
  final String dispatchId;
  final String agentId;
  final String task;
  final int elapsedMs;

  const RunningAgentInfo({
    required this.dispatchId,
    required this.agentId,
    required this.task,
    required this.elapsedMs,
  });

  factory RunningAgentInfo.fromJson(Map<String, dynamic> json) =>
      RunningAgentInfo(
        dispatchId: json['dispatchId'] as String? ?? '',
        agentId: json['agentId'] as String? ?? '',
        task: json['task'] as String? ?? '',
        elapsedMs: json['elapsedMs'] as int? ?? 0,
      );
}

class QueueStatusMessage implements ServerMessage {
  final int pending;
  final List<RunningAgentInfo> running;

  QueueStatusMessage({required this.pending, required this.running});

  factory QueueStatusMessage.fromJson(Map<String, dynamic> json) =>
      QueueStatusMessage(
        pending: json['pending'] as int? ?? 0,
        running: (json['running'] as List?)
                ?.map((r) => RunningAgentInfo.fromJson(r as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

// ─── Dungeon & difficulty messages ─────────────────────────────────────────

class TaskTooHardMessage implements ServerMessage {
  final String agentId;
  final double required;
  final double current;
  TaskTooHardMessage({required this.agentId, required this.required, required this.current});
  factory TaskTooHardMessage.fromJson(Map<String, dynamic> json) => TaskTooHardMessage(
        agentId: json['agentId'] as String? ?? '',
        required: (json['required'] as num?)?.toDouble() ?? 1,
        current: (json['current'] as num?)?.toDouble() ?? 1,
      );
}

class DungeonStartedMessage implements ServerMessage {
  final String agentId;
  final int skillType;
  final int difficulty;
  final String challenge;
  DungeonStartedMessage({required this.agentId, required this.skillType, required this.difficulty, required this.challenge});
  factory DungeonStartedMessage.fromJson(Map<String, dynamic> json) => DungeonStartedMessage(
        agentId: json['agentId'] as String? ?? '',
        skillType: json['skillType'] as int? ?? 0,
        difficulty: json['difficulty'] as int? ?? 1,
        challenge: json['challenge'] as String? ?? '',
      );
}

class DungeonCompleteMessage implements ServerMessage {
  final String agentId;
  final int skillType;
  final int xpEarned;
  final int score;
  final String feedback;
  final bool passed;
  DungeonCompleteMessage({
    required this.agentId,
    required this.skillType,
    required this.xpEarned,
    required this.score,
    required this.feedback,
    required this.passed,
  });
  factory DungeonCompleteMessage.fromJson(Map<String, dynamic> json) => DungeonCompleteMessage(
        agentId: json['agentId'] as String? ?? '',
        skillType: json['skillType'] as int? ?? 0,
        xpEarned: json['xpEarned'] as int? ?? 0,
        score: json['score'] as int? ?? 0,
        feedback: json['feedback'] as String? ?? '',
        passed: json['passed'] as bool? ?? false,
      );
}

class DungeonErrorMessage implements ServerMessage {
  final String agentId;
  final String error;
  DungeonErrorMessage({required this.agentId, required this.error});
  factory DungeonErrorMessage.fromJson(Map<String, dynamic> json) => DungeonErrorMessage(
        agentId: json['agentId'] as String? ?? '',
        error: json['error'] as String? ?? '',
      );
}

// ─── Facilitator System ─────────────────────────────────────────────────────

/// Server signals a successful seed for a `facilitator_start` request.
/// Carries the serialized output JSON so the client can route it through
/// the persistence-service decoder registry (open/closed for new styles).
class FacilitatorSeededMessage implements ServerMessage {
  final String styleId;
  final ScopeScore finalScore;
  final OutputFormat outputFormat;
  final String outputJson;

  FacilitatorSeededMessage({
    required this.styleId,
    required this.finalScore,
    required this.outputFormat,
    required this.outputJson,
  });

  factory FacilitatorSeededMessage.fromJson(Map<String, dynamic> json) =>
      FacilitatorSeededMessage(
        styleId: json['styleId'] as String? ?? '',
        finalScore:
            ScopeScore.fromJson(json['finalScore'] as Map<String, dynamic>),
        outputFormat:
            OutputFormat.fromKey(json['outputFormat'] as String? ?? ''),
        outputJson: json['outputJson'] as String? ?? '',
      );
}

class FacilitatorErrorMessage implements ServerMessage {
  final String error;
  FacilitatorErrorMessage({required this.error});
  factory FacilitatorErrorMessage.fromJson(Map<String, dynamic> json) =>
      FacilitatorErrorMessage(error: json['error'] as String? ?? '');
}

/// Cross-device sync — same payload shape as [FacilitatorSeededMessage],
/// sent by the server to new clients on connect and broadcast to existing
/// clients when a fresh seed completes.
class FacilitatorOutputSyncMessage implements ServerMessage {
  final String styleId;
  final ScopeScore finalScore;
  final OutputFormat outputFormat;
  final String outputJson;

  FacilitatorOutputSyncMessage({
    required this.styleId,
    required this.finalScore,
    required this.outputFormat,
    required this.outputJson,
  });

  factory FacilitatorOutputSyncMessage.fromJson(Map<String, dynamic> json) {
    final rawScore = json['finalScore'];
    return FacilitatorOutputSyncMessage(
      styleId: json['styleId'] as String? ?? '',
      finalScore: rawScore is Map<String, dynamic>
          ? ScopeScore.fromJson(rawScore)
          : const ScopeScore.empty(),
      outputFormat: OutputFormat.fromKey(json['outputFormat'] as String? ?? ''),
      outputJson: json['outputJson'] as String? ?? '',
    );
  }
}

// ─── Session presence messages ──────────────────────────────────────────────

enum SessionMode { primary, viewer }

class SessionStatusMessage implements ServerMessage {
  final SessionMode mode;
  final String? primaryDevice;
  SessionStatusMessage({required this.mode, this.primaryDevice});
  factory SessionStatusMessage.fromJson(Map<String, dynamic> json) =>
      SessionStatusMessage(
        mode: (json['mode'] as String?) == 'primary'
            ? SessionMode.primary
            : SessionMode.viewer,
        primaryDevice: json['primaryDevice'] as String?,
      );
}

class SessionTakenMessage implements ServerMessage {
  final String byDevice;
  SessionTakenMessage({required this.byDevice});
  factory SessionTakenMessage.fromJson(Map<String, dynamic> json) =>
      SessionTakenMessage(
        byDevice: json['byDevice'] as String? ?? 'another device',
      );
}

// ─── Chat message model ─────────────────────────────────────────────────────

enum ChatRole { user, assistant }

/// Semantic category applied to a chat message for visual differentiation.
/// Null (default) means a regular assistant/user message with no special treatment.
enum MessageCategory {
  /// Agent is waiting for the user's response — rendered with cyan left border.
  awaitingReply,

  /// Pure technical noise: tool calls, delegation events, status updates.
  /// Rendered smaller, monospace, faded; consecutive runs collapse to "N дій".
  status,

  /// A board task was added — rendered as a board-linkage announcement row.
  taskLinked,
}

MessageCategory? _parseCategory(String? s) => switch (s) {
      'awaitingReply' => MessageCategory.awaitingReply,
      'status' => MessageCategory.status,
      'taskLinked' => MessageCategory.taskLinked,
      _ => null,
    };

class ChatMessage {
  final ChatRole role;
  final String text;
  final String agentId;
  final DateTime timestamp;
  final bool isStreaming;
  final List<String> imageBase64s;

  /// Groups this message into a thread. Null means the message is top-level.
  final String? threadId;

  /// Optional semantic category used to select visual treatment.
  final MessageCategory? category;

  ChatMessage({
    required this.role,
    required this.text,
    required this.agentId,
    DateTime? timestamp,
    this.isStreaming = false,
    this.imageBase64s = const [],
    this.threadId,
    this.category,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    bool? isStreaming,
    String? threadId,
    MessageCategory? category,
  }) =>
      ChatMessage(
        role: role,
        text: text ?? this.text,
        agentId: agentId,
        timestamp: timestamp,
        isStreaming: isStreaming ?? this.isStreaming,
        imageBase64s: imageBase64s,
        threadId: threadId ?? this.threadId,
        category: category ?? this.category,
      );

  Map<String, dynamic> toJson() => {
        'role': role == ChatRole.user ? 'user' : 'assistant',
        'text': text,
        'agentId': agentId,
        'timestamp': timestamp.toIso8601String(),
        if (imageBase64s.isNotEmpty) 'images': imageBase64s,
        if (threadId != null) 'threadId': threadId,
        if (category != null) 'category': category!.name,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] == 'user' ? ChatRole.user : ChatRole.assistant,
        text: json['text'] as String,
        agentId: json['agentId'] as String? ?? 'manager',
        timestamp: DateTime.parse(json['timestamp'] as String),
        imageBase64s: (json['images'] as List?)?.cast<String>() ?? const [],
        threadId: json['threadId'] as String?,
        category: _parseCategory(json['category'] as String?),
      );
}
