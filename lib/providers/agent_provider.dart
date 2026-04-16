/// Riverpod providers for agent state management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/agent_trait.dart';
import '../services/agent_ws_service.dart';
import '../services/chat_persistence_service.dart';
import '../services/server_process_service.dart';
import 'settings_provider.dart';

// ─── Server Process ─────────────────────────────────────────────────────────

final serverProcessProvider = Provider<ServerProcessService>((ref) {
  throw UnimplementedError('Must be overridden in ProviderScope');
});

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

// ─── Working directory ───────────────────────────────────────────────────

class WorkingDirectoryNotifier extends Notifier<String?> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  String? build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return null;
  }

  void _onMessage(ServerMessage msg) {
    if (msg is InitMessage && msg.workingDirectory != null) {
      state = msg.workingDirectory;
    }
  }
}

final workingDirectoryProvider =
    NotifierProvider<WorkingDirectoryNotifier, String?>(
  WorkingDirectoryNotifier.new,
);

// ─── Selected agent ──────────────────────────────────────────────────────

final selectedAgentProvider = StateProvider<String>((ref) => 'manager');

// ─── Bypass permissions toggle ───────────────────────────────────────────

final bypassPermissionsProvider = StateProvider<bool>((ref) => false);

// ─── Chat sync state ────────────────────────────────────────────────────────

enum ChatSyncState { syncing, ready }

final chatSyncStateProvider = StateProvider<ChatSyncState>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final sessionId = ChatPersistenceService.loadSessionId(prefs);
  return sessionId != null ? ChatSyncState.syncing : ChatSyncState.ready;
});

// ─── Chat messages ───────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<List<ChatMessage>> {
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<bool>? _connSub;
  Timer? _saveTimer;

  /// All messages across all agents.
  Map<String, List<ChatMessage>> _allMessages = {};

  /// The agent whose responses are currently being streamed.
  String? _activeStreamAgent;

  @override
  List<ChatMessage> build() {
    final ws = ref.watch(wsServiceProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() {
      _sub?.cancel();
      _connSub?.cancel();
      _saveTimer?.cancel();
    });

    // Restore persisted messages for all agents
    final prefs = ref.read(sharedPrefsProvider);
    _allMessages = ChatPersistenceService.loadAllMessages(prefs);

    // Resume server session if we have a stored session ID
    final sessionId = ChatPersistenceService.loadSessionId(prefs);
    if (sessionId != null) {
      _connSub?.cancel();
      if (ws.isConnected) {
        ws.resumeSession(sessionId);
      } else {
        _connSub = ws.connectionStatus.listen((connected) {
          if (connected) {
            _connSub?.cancel();
            ws.resumeSession(sessionId);
          }
        });
      }
    }

    return _allMessages[selectedAgent] ?? [];
  }

  String get _selectedAgent => ref.read(selectedAgentProvider);

  List<ChatMessage> _agentMessages(String agentId) =>
      _allMessages[agentId] ?? [];

  void _setAgentMessages(String agentId, List<ChatMessage> messages) {
    _allMessages = {..._allMessages, agentId: messages};
    // Only update state if this is the currently viewed agent
    if (agentId == _selectedAgent) {
      state = messages;
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
      final prefs = ref.read(sharedPrefsProvider);
      ChatPersistenceService.saveAllMessages(prefs, _allMessages);
    });
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case InitMessage(:final sessionId):
        if (sessionId != 'pending') {
          final prefs = ref.read(sharedPrefsProvider);
          ChatPersistenceService.saveSessionId(prefs, sessionId);
        }

      case ChatHistoryMessage(:final messages):
        // Replace local history with the authoritative server history
        final grouped = <String, List<ChatMessage>>{};
        for (final m in messages) {
          (grouped[m.agentId] ??= []).add(m);
        }
        _allMessages = grouped;
        state = _allMessages[_selectedAgent] ?? [];
        _scheduleSave();
        ref.read(chatSyncStateProvider.notifier).state = ChatSyncState.ready;

      case AssistantTextMessage(:final text, :final agentId):
        final messages = [..._agentMessages(agentId)];
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
            agentId: agentId,
            isStreaming: true,
          ));
        }
        _setAgentMessages(agentId, messages);

      case AssistantDoneMessage(:final text, :final agentId):
        final messages = [..._agentMessages(agentId)];
        if (messages.isNotEmpty &&
            messages.last.role == ChatRole.assistant &&
            messages.last.isStreaming) {
          messages[messages.length - 1] = messages.last.copyWith(
            text: text,
            isStreaming: false,
          );
        } else {
          messages.add(ChatMessage(
            role: ChatRole.assistant,
            text: text,
            agentId: agentId,
          ));
        }
        _setAgentMessages(agentId, messages);
        _activeStreamAgent = null;
        _scheduleSave();

      case ErrorMessage(:final message):
        final agentId = _activeStreamAgent ?? _selectedAgent;
        _setAgentMessages(agentId, [
          ..._agentMessages(agentId),
          ChatMessage(
            role: ChatRole.assistant,
            text: '⚠️ $message',
            agentId: agentId,
          ),
        ]);
        _activeStreamAgent = null;
        _scheduleSave();

      default:
        break;
    }
  }

  void sendMessage(String text, {List<Uint8List> images = const []}) {
    final agentId = _selectedAgent;
    _activeStreamAgent = agentId;
    final imageBase64s = images.map((b) => base64Encode(b)).toList();
    _setAgentMessages(agentId, [
      ..._agentMessages(agentId),
      ChatMessage(
        role: ChatRole.user,
        text: text,
        agentId: agentId,
        imageBase64s: imageBase64s,
      ),
    ]);
    ref.read(wsServiceProvider).sendMessage(
          text,
          agentId: agentId,
          images: imageBase64s.isNotEmpty ? imageBase64s : null,
        );
    _scheduleSave();
  }

  void newChat() {
    final agentId = _selectedAgent;
    _allMessages = {..._allMessages, agentId: []};
    state = [];
    final prefs = ref.read(sharedPrefsProvider);
    ChatPersistenceService.saveAllMessages(prefs, _allMessages);
    ref.read(chatSyncStateProvider.notifier).state = ChatSyncState.ready;
    ref.read(activityLogProvider.notifier).clear();
    ref.read(debugLogProvider.notifier).clear();
    ref.read(wsServiceProvider).newChat();
  }
}

// ─── Remote input text (live typing sync) ───────────────────────────────────

class _RemoteInputTextNotifier extends Notifier<String> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  String build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is InputTextMessage) {
        state = msg.text;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return '';
  }

  void clear() => state = '';
}

final remoteInputTextProvider =
    NotifierProvider<_RemoteInputTextNotifier, String>(
  _RemoteInputTextNotifier.new,
);

// ─── Remote input images (live attachment sync) ─────────────────────────────

class _RemoteInputImagesNotifier extends Notifier<List<String>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<String> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is InputImagesMessage) {
        state = msg.images;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void clear() => state = [];
}

final remoteInputImagesProvider =
    NotifierProvider<_RemoteInputImagesNotifier, List<String>>(
  _RemoteInputImagesNotifier.new,
);

final chatProvider = NotifierProvider<ChatNotifier, List<ChatMessage>>(
  ChatNotifier.new,
);

// ─── Agent statuses ──────────────────────────────────────────────────────────

class AgentState {
  final AgentInfo info;
  final AgentStatus status;
  final List<ToolActivity> activeTools;
  final String? currentTask;
  final DateTime? activeSince;
  final String? lastToolDescription;

  const AgentState({
    required this.info,
    this.status = AgentStatus.idle,
    this.activeTools = const [],
    this.currentTask,
    this.activeSince,
    this.lastToolDescription,
  });

  bool get isActive => status != AgentStatus.idle;

  AgentState copyWith({
    AgentStatus? status,
    List<ToolActivity>? activeTools,
    String? currentTask,
    DateTime? activeSince,
    String? lastToolDescription,
  }) =>
      AgentState(
        info: info,
        status: status ?? this.status,
        activeTools: activeTools ?? this.activeTools,
        currentTask: currentTask ?? this.currentTask,
        activeSince: activeSince ?? this.activeSince,
        lastToolDescription: lastToolDescription ?? this.lastToolDescription,
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
          final wasIdle = current.status == AgentStatus.idle;
          state = {
            ...state,
            agentId: current.copyWith(
              status: status,
              activeTools: tools,
              activeSince: wasIdle && status != AgentStatus.idle
                  ? DateTime.now()
                  : null,
            ),
          };
        }

      case SubagentStartMessage(:final agentType, :final task):
        // Map sub-agent type to our team agents
        final agentId = _resolveAgentId(agentType);
        final current = state[agentId];
        if (current != null) {
          final wasIdle = current.status == AgentStatus.idle;
          state = {
            ...state,
            agentId: current.copyWith(
              status: AgentStatus.running,
              currentTask: task,
              activeSince: wasIdle ? DateTime.now() : null,
            ),
          };
        }

      case SubagentStopMessage(:final agentId):
        final resolved = _resolveAgentId(agentId);
        final current = state[resolved];
        if (current != null) {
          state = {
            ...state,
            resolved: AgentState(
              info: current.info,
              status: AgentStatus.idle,
              activeTools: const [],
            ),
          };
        }

      case ToolUseMessage(:final agentId, :final toolName, :final status):
        final resolved = _resolveAgentId(agentId);
        final current = state[resolved];
        if (current != null) {
          final wasIdle = current.status == AgentStatus.idle;
          final newStatus = _toolNameToStatus(toolName);
          state = {
            ...state,
            resolved: current.copyWith(
              status: newStatus,
              lastToolDescription: status,
              activeSince: wasIdle ? DateTime.now() : null,
            ),
          };
        }

      case ResultMessage():
        // Reset all to idle
        state = {
          for (final entry in state.entries)
            entry.key: AgentState(info: entry.value.info),
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

// ─── Team metrics ───────────────────────────────────────────────────────────

class MetricsNotifier extends Notifier<Map<String, AgentMetrics>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  Map<String, AgentMetrics> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return {};
  }

  void _onMessage(ServerMessage msg) {
    if (msg is TeamMetricsMessage) {
      state = msg.metrics;
    }
  }
}

final metricsProvider =
    NotifierProvider<MetricsNotifier, Map<String, AgentMetrics>>(
  MetricsNotifier.new,
);

// ─── Activity log ───────────────────────────────────────────────────────────

class ActivityLogNotifier extends Notifier<List<ActivityEventMessage>> {
  static const _maxEvents = 200;
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<ActivityEventMessage> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _onMessage(ServerMessage msg) {
    if (msg is ActivityEventMessage) {
      final updated = [...state, msg];
      // Keep only the last N events
      state = updated.length > _maxEvents
          ? updated.sublist(updated.length - _maxEvents)
          : updated;
    }
  }

  void clear() => state = [];
}

final activityLogProvider =
    NotifierProvider<ActivityLogNotifier, List<ActivityEventMessage>>(
  ActivityLogNotifier.new,
);

// ─── Communication graph ────────────────────────────────────────────────────

class CommGraphNotifier extends Notifier<List<CommEvent>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<CommEvent> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _onMessage(ServerMessage msg) {
    if (msg is CommGraphMessage) {
      state = msg.events;
    }
  }
}

final commGraphProvider =
    NotifierProvider<CommGraphNotifier, List<CommEvent>>(
  CommGraphNotifier.new,
);

// ─── Debug console ──────────────────────────────────────────────────────────

class DebugLogNotifier extends Notifier<List<DebugLogMessage>> {
  static const _maxEntries = 500;
  StreamSubscription<ServerMessage>? _wsSub;
  StreamSubscription<ServerProcessLog>? _procSub;

  @override
  List<DebugLogMessage> build() {
    final ws = ref.watch(wsServiceProvider);
    _wsSub?.cancel();
    _wsSub = ws.messages.listen(_onMessage);

    final proc = ref.watch(serverProcessProvider);
    _procSub?.cancel();
    _procSub = proc.logs.listen(_onProcessLog);

    ref.onDispose(() {
      _wsSub?.cancel();
      _procSub?.cancel();
    });
    return [];
  }

  void _onMessage(ServerMessage msg) {
    if (msg is DebugLogMessage) {
      _add(msg);
    }
  }

  void _onProcessLog(ServerProcessLog log) {
    _add(DebugLogMessage(
      timestamp: log.timestamp,
      level: log.level,
      category: 'process',
      message: log.message,
    ));
  }

  void _add(DebugLogMessage msg) {
    final updated = [...state, msg];
    state = updated.length > _maxEntries
        ? updated.sublist(updated.length - _maxEntries)
        : updated;
  }

  void clear() => state = [];
}

final debugLogProvider =
    NotifierProvider<DebugLogNotifier, List<DebugLogMessage>>(
  DebugLogNotifier.new,
);

// ─── Agent traits ──────────────────────────────────────────────────────────

class TraitsNotifier extends Notifier<List<AgentTrait>> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  List<AgentTrait> build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return [];
  }

  void _onMessage(ServerMessage msg) {
    if (msg is AgentTraitsMessage) {
      state = msg.traits;
    }
  }

  /// Get traits for a specific agent, sorted by frequency descending.
  List<AgentTrait> forAgent(String agentId) {
    return state
        .where((t) => t.agentId == agentId)
        .toList()
      ..sort((a, b) => b.frequency.compareTo(a.frequency));
  }

  /// Get only weaknesses for an agent.
  List<AgentTrait> weaknessesFor(String agentId) {
    return forAgent(agentId)
        .where((t) => t.type == TraitType.weakness)
        .toList();
  }

  /// Get only strengths for an agent.
  List<AgentTrait> strengthsFor(String agentId) {
    return forAgent(agentId)
        .where((t) => t.type == TraitType.strength)
        .toList();
  }

  /// Record a lesson via WebSocket.
  void recordLesson({
    required String agentId,
    required TraitType type,
    required String category,
    required String tag,
    required String lesson,
  }) {
    ref.read(wsServiceProvider).recordLesson(
          agentId: agentId,
          lessonType: type == TraitType.strength ? 'strength' : 'weakness',
          category: category,
          tag: tag,
          lesson: lesson,
        );
  }

  /// Remove a lesson via WebSocket.
  void removeLesson(String lessonId) {
    ref.read(wsServiceProvider).removeLesson(lessonId);
  }
}

final traitsProvider = NotifierProvider<TraitsNotifier, List<AgentTrait>>(
  TraitsNotifier.new,
);
