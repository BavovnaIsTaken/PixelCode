/// Riverpod providers for agent state management.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/agent_trait.dart';
import '../models/game_economy.dart';
import '../services/agent_ws_service.dart';
import '../services/chat_persistence_service.dart';
import 'game_economy_provider.dart';
import 'settings_provider.dart';

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

/// Short status token (≤5 chars) for the in-flight connection terminal widget.
/// `null` = connected/idle (terminal hides itself).
final connectionPhaseProvider = StreamProvider<String?>((ref) {
  return ref.watch(wsServiceProvider).phaseStatus;
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

// ─── Server info (connection details, tunnel URL) ──────────────────────────

class ServerInfoNotifier extends Notifier<ServerInfoMessage?> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  ServerInfoMessage? build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen((msg) {
      if (msg is ServerInfoMessage) {
        state = msg;
      }
    });
    ref.onDispose(() => _sub?.cancel());
    // Seed from buffered value (message may have arrived before we subscribed)
    return ws.lastServerInfo;
  }
}

final serverInfoProvider = NotifierProvider<ServerInfoNotifier, ServerInfoMessage?>(
  ServerInfoNotifier.new,
);

/// Convenience: tunnel URL from server info.
final tunnelUrlProvider = Provider<String?>((ref) {
  return ref.watch(serverInfoProvider)?.tunnelUrl;
});

// ─── Selected agent ──────────────────────────────────────────────────────

/// The instanceId currently focused in the chat UI.
///
/// Default picks the first hired manager instance so the user always starts
/// pointed at their coordinator. Falls back to `'manager#1'` for the very
/// first launch before any state is seeded.
final selectedAgentProvider = StateProvider<String>((ref) {
  final agents = ref.watch(gameEconomyProvider.select((g) => g.agents));
  for (final a in agents.values) {
    if (a.roleType == 'manager') return a.instanceId;
  }
  return 'manager#1';
});

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
      _saveTimer?.cancel();
    });

    // Restore persisted messages for all agents
    final prefs = ref.read(sharedPrefsProvider);
    _allMessages = ChatPersistenceService.loadAllMessages(prefs);

    // Seed from buffered chat_history that may have arrived before we
    // subscribed (race condition on localhost where response is instant).
    final buffered = ws.lastChatHistory;
    if (buffered != null) {
      _allMessages = _mergeHistory(_allMessages, buffered.messages);
      _scheduleSave();
      ref.read(chatSyncStateProvider.notifier).state = ChatSyncState.ready;
    }

    // Server is the source of truth for the shared SDK sessionId — it
    // auto-resumes on every query and broadcasts updates via InitMessage.
    // We just record the latest id locally for diagnostics.

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

  /// Merge server-authoritative history with local per-agent messages.
  ///
  /// Preserves any local message that is either still streaming or has a
  /// timestamp newer than the server's latest for that agent — otherwise a
  /// `chat_history` snapshot taken before the current stream finalized would
  /// wipe captain responses visible mid-flight.
  static Map<String, List<ChatMessage>> _mergeHistory(
    Map<String, List<ChatMessage>> local,
    List<ChatMessage> serverMessages,
  ) {
    final serverGrouped = <String, List<ChatMessage>>{};
    for (final m in serverMessages) {
      (serverGrouped[m.agentId] ??= []).add(m);
    }
    final merged = <String, List<ChatMessage>>{};
    final agentIds = {...local.keys, ...serverGrouped.keys};
    for (final agentId in agentIds) {
      final serverList = serverGrouped[agentId] ?? const <ChatMessage>[];
      final localList = local[agentId] ?? const <ChatMessage>[];
      if (serverList.isEmpty) {
        merged[agentId] = List.of(localList);
        continue;
      }
      final serverLatest = serverList
          .map((m) => m.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final tail = localList.where(
        (m) => m.isStreaming || m.timestamp.isAfter(serverLatest),
      );
      merged[agentId] = [...serverList, ...tail];
    }
    return merged;
  }

  void _scheduleSave() {
    final prefs = ref.read(sharedPrefsProvider);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () {
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
        _allMessages = _mergeHistory(_allMessages, messages);
        state = _allMessages[_selectedAgent] ?? [];
        _scheduleSave();
        ref.read(chatSyncStateProvider.notifier).state = ChatSyncState.ready;

      case AssistantTextMessage(:final text, :final agentId, :final threadId):
        final messages = [..._agentMessages(agentId)];
        if (messages.isNotEmpty &&
            messages.last.role == ChatRole.assistant &&
            messages.last.isStreaming &&
            messages.last.threadId == threadId) {
          messages[messages.length - 1] = messages.last.copyWith(
            text: messages.last.text + text,
          );
        } else {
          messages.add(ChatMessage(
            role: ChatRole.assistant,
            text: text,
            agentId: agentId,
            isStreaming: true,
            threadId: threadId,
          ));
        }
        _setAgentMessages(agentId, messages);

      case AssistantDoneMessage(:final text, :final agentId, :final threadId):
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
            threadId: threadId,
          ));
        }
        _setAgentMessages(agentId, messages);
        _activeStreamAgent = null;
        _scheduleSave();

      case ToolUseMessage(:final agentId, :final status, :final threadId)
          when threadId != null:
        _setAgentMessages(agentId, [
          ..._agentMessages(agentId),
          ChatMessage(
            role: ChatRole.assistant,
            agentId: agentId,
            text: status,
            category: MessageCategory.status,
            threadId: threadId,
          ),
        ]);

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

  /// Injects a local-only message into the chat (never sent to the server).
  /// Used for synthetic notifications like board-task-added confirmations.
  void addLocalMessage(ChatMessage msg) {
    final agentId = msg.agentId.isNotEmpty ? msg.agentId : _selectedAgent;
    _setAgentMessages(agentId, [..._agentMessages(agentId), msg]);
    _scheduleSave();
  }

  void sendMessage(
    String text, {
    List<Uint8List> images = const [],
  }) {
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
    final ws = ref.read(wsServiceProvider);
    ws.lastChatHistory = null; // Clear buffer so stale history isn't re-seeded
    ws.newChat();
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

  AgentBusyState get busyState =>
      status == AgentStatus.idle ? AgentBusyState.idle : AgentBusyState.busy;

  bool get isBusy => busyState == AgentBusyState.busy;

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

    // Derive the hired roster from the local game state — it's the source of
    // truth for who's on the team. Server messages then layer status on top.
    final gameAgents = ref.watch(gameEconomyProvider.select((g) => g.agents));

    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());

    final initial = <String, AgentState>{};
    for (final a in gameAgents.values) {
      final role = roleCatalogFor(a.roleType);
      initial[a.instanceId] = AgentState(
        info: AgentInfo(
          id: a.instanceId,
          name: a.nickname,
          role: role?.role ?? a.roleType,
          model: 'auto',
          roleType: a.roleType,
        ),
      );
    }
    return initial;
  }

  void _onMessage(ServerMessage msg) {
    switch (msg) {
      case InitMessage(:final agents):
        // Server-side init is informational now — only adopt entries that
        // aren't already in state (game state drives the roster).
        final merged = {...state};
        for (final a in agents) {
          merged.putIfAbsent(a.id, () => AgentState(info: a));
        }
        state = merged;

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

      case TaskDispatchedMessage(:final agentId, :final task):
        // Agent was dispatched — set it to running with the task description
        final current = state[agentId];
        if (current != null) {
          state = {
            ...state,
            agentId: current.copyWith(
              status: AgentStatus.running,
              currentTask: task,
              activeSince: DateTime.now(),
            ),
          };
        }

      case SubagentResultMessage(:final agentId):
        // Agent completed — set back to idle
        final current = state[agentId];
        if (current != null) {
          state = {
            ...state,
            agentId: AgentState(info: current.info),
          };
        }

      case ResultMessage():
        // Manager's query finished — only reset the manager to idle
        // (sub-agents may still be running independently)
        final manager = state['manager'];
        if (manager != null) {
          state = {
            ...state,
            'manager': AgentState(info: manager.info),
          };
        }

      default:
        break;
    }
  }

  String _resolveAgentId(String raw) {
    // Exact instanceId match wins.
    if (state.containsKey(raw)) return raw;

    // If [raw] looks like a bare roleType, return the first hired instance of
    // that role. Handles server messages that use roleType (e.g. SDK sub-agent
    // launches) rather than a concrete instanceId.
    for (final entry in state.entries) {
      if (entry.value.info.roleType == raw) return entry.key;
    }

    // Fuzzy fallback: substring match on keys.
    final lower = raw.toLowerCase();
    for (final key in state.keys) {
      final keyLower = key.toLowerCase();
      if (lower.contains(keyLower) || keyLower.contains(lower)) {
        return key;
      }
    }

    // Last resort — first tech-lead instance, or just [raw].
    for (final entry in state.entries) {
      if (entry.value.info.roleType == 'tech-lead') return entry.key;
    }
    return raw;
  }

  AgentStatus _toolNameToStatus(String toolName) => switch (toolName) {
        'Read' || 'Grep' || 'Glob' => AgentStatus.reading,
        'Edit' || 'Write' => AgentStatus.typing,
        'Bash' => AgentStatus.running,
        'Agent' || 'Task' => AgentStatus.thinking,
        'mcp__dispatch__dispatch' => AgentStatus.thinking,
        'mcp__dispatch__team_status' => AgentStatus.thinking,
        'mcp__dispatch__cancel_task' => AgentStatus.running,
        _ => AgentStatus.running,
      };
}

final agentsProvider = NotifierProvider<AgentsNotifier, Map<String, AgentState>>(
  AgentsNotifier.new,
);

/// Binary busy/idle availability map for all hired agents.
///
/// Derived from [agentsProvider] — use when routing or badge logic only needs
/// to know if an agent is occupied, not what it is specifically doing.
/// Expected consumer: team-dispatch (section D prerequisite) and roster badge.
final agentBusyProvider = Provider<Map<String, AgentBusyState>>((ref) =>
    ref
        .watch(agentsProvider)
        .map((id, s) => MapEntry(id, s.busyState)));

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
  StreamSubscription<String>? _connSub;

  @override
  List<DebugLogMessage> build() {
    final ws = ref.watch(wsServiceProvider);
    _wsSub?.cancel();
    _wsSub = ws.messages.listen(_onMessage);

    _connSub?.cancel();
    _connSub = ws.connectionLog.listen(_onConnLog);

    ref.onDispose(() {
      _wsSub?.cancel();
      _connSub?.cancel();
    });
    // Preserve existing logs across reconnections (state may not exist on first build)
    try { return state; } catch (_) { return []; }
  }

  void _onMessage(ServerMessage msg) {
    if (msg is DebugLogMessage) {
      _add(msg);
    }
  }

  void _onConnLog(String line) {
    _add(DebugLogMessage(
      timestamp: DateTime.now(),
      level: 'info',
      category: 'ws',
      message: line,
    ));
  }

  void _add(DebugLogMessage msg) {
    // Skip duplicates (early logs replayed on every reconnect)
    if (state.isNotEmpty &&
        state.last.timestamp == msg.timestamp &&
        state.last.message == msg.message) { return; }
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

// ─── Queue status ──────────────────────────────────────────────────────────

class QueueStatusNotifier extends Notifier<QueueStatusMessage> {
  StreamSubscription<ServerMessage>? _sub;

  @override
  QueueStatusMessage build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    return QueueStatusMessage(pending: 0, running: const []);
  }

  void _onMessage(ServerMessage msg) {
    if (msg is QueueStatusMessage) {
      state = msg;
    }
  }
}

final queueStatusProvider =
    NotifierProvider<QueueStatusNotifier, QueueStatusMessage>(
  QueueStatusNotifier.new,
);
