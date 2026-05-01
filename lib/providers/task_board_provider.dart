/// Riverpod provider for the task board (Kanban) state.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/game_economy.dart';
import '../models/task_board.dart';
import 'ws_provider.dart';

// ─── Assignment gating ─────────────────────────────────────────────────────

/// Checks whether [agent] can be assigned to [task]. Returns a human-readable
/// rejection reason in Ukrainian, or null if the assignment is allowed.
///
/// Gating:
/// * Role must be in `task.allowedRoles`.
/// * Agent level must be >= `task.requiredLevel`.
/// Skills are soft modifiers and never block assignment.
String? assignmentRejectionReason(TaskCard task, AgentGameData agent) {
  if (!task.allowedRoles.contains(agent.roleType)) {
    final labels = task.allowedRoles
        .map((r) => roleCatalogFor(r)?.role ?? r)
        .toSet()
        .join(', ');
    return 'Ця задача потребує роль: $labels.';
  }
  if (agent.level < task.requiredLevel) {
    return 'Потрібен Lv ${task.requiredLevel}+ (агент: Lv ${agent.level}).';
  }
  return null;
}

// ─── Pure helpers (testable without a provider container) ─────────────────

/// Apply an optimistic column move to a board snapshot. Pure function so
/// it can be unit-tested independently. Unknown taskIds are returned
/// unchanged (handler will show no flicker; the next broadcast wins).
BoardState applyOptimisticMove(
  BoardState board, {
  required String taskId,
  required TaskColumn column,
  DateTime? now,
}) {
  final stamp = now ?? DateTime.now();
  final tasks = board.tasks.map((t) {
    if (t.id != taskId) return t;
    return t.copyWith(column: column, updatedAt: stamp);
  }).toList();
  return BoardState(tasks: tasks);
}

// ─── Board state provider ──────────────────────────────────────────────────

class TaskBoardNotifier extends Notifier<BoardState> {
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<bool>? _connSub;

  /// Last server-side revision the client has acknowledged. Sent back
  /// via `board_get_state{since}` on reconnect so the server can reply
  /// with `board_state_unchanged` instead of re-shipping every task.
  /// `null` until the first revision-bearing broadcast lands.
  int? _appliedRevision;

  @visibleForTesting
  int? get debugAppliedRevision => _appliedRevision;

  @override
  BoardState build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();

    // onError defends against a malformed broadcast killing the
    // listener — without it, a single bad payload meant the board froze
    // until provider rebuild. We log and stay subscribed.
    _sub = ws.messages.listen(
      _onMessage,
      onError: (Object error, StackTrace stack) {
        debugPrint('[TaskBoard] message stream error (continuing): $error');
      },
    );

    // Request board state on every connection-up edge so a reconnect
    // after a transient drop also re-syncs. Sending `since` lets the
    // server short-circuit with `board_state_unchanged` when nothing
    // changed while we were away.
    _connSub?.cancel();
    if (ws.isConnected) {
      debugPrint('[TaskBoard] Already connected — requesting board state');
      ws.boardGetState(since: _appliedRevision);
    }
    _connSub = ws.connectionStatus.listen((connected) {
      if (connected) {
        debugPrint('[TaskBoard] Connected — requesting board state '
            '(since=$_appliedRevision)');
        ws.boardGetState(since: _appliedRevision);
      }
    });

    ref.onDispose(() {
      _sub?.cancel();
      _connSub?.cancel();
    });

    return const BoardState();
  }

  void _onMessage(ServerMessage msg) {
    if (msg is BoardStateMessage) {
      debugPrint('[TaskBoard] board_state: '
          '${msg.boardState.tasks.length} tasks (rev=${msg.revision})');
      state = msg.boardState;
      if (msg.revision != null) _appliedRevision = msg.revision;
    } else if (msg is BoardStateUnchangedMessage) {
      // Server confirmed our cached state is current; nothing to apply,
      // just update the marker so the next reconnect short-circuits too.
      debugPrint('[TaskBoard] board_state_unchanged (rev=${msg.revision})');
      _appliedRevision = msg.revision;
    } else if (msg is BoardSeedBatchResultMessage) {
      // Failed batches are surfaced via this provider's error stream so
      // UI can show a toast; the board state itself doesn't change.
      if (!msg.ok) {
        debugPrint('[TaskBoard] board_seed_batch failed: '
            '${msg.errors.length} error(s)');
      }
    }
  }

  bool createTask({
    required String title,
    String? description,
    String? color,
    String? priority,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
  }) {
    debugPrint('[TaskBoard] createTask: "$title"');
    final ws = ref.read(wsServiceProvider);
    if (!ws.isConnected) {
      debugPrint('[TaskBoard] WARNING: not connected, message will be dropped');
      return false;
    }
    ws.boardCreateTask(
      title: title,
      description: description,
      color: color,
      priority: priority,
      difficulty: difficulty,
      allowedRoles: allowedRoles,
      taskType: taskType,
    );
    return true;
  }

  /// Move a task to [column]. The change is applied to local state
  /// immediately for snappy drag-and-drop; the next `board_state`
  /// broadcast wins. If the server rejected the move, the broadcast
  /// reflects the server's view and the optimistic state is replaced.
  void moveTask({required String taskId, required TaskColumn column}) {
    state = applyOptimisticMove(state, taskId: taskId, column: column);
    ref.read(wsServiceProvider).boardMoveTask(
          taskId: taskId,
          column: column.key,
        );
  }

  void updateTask({
    required String taskId,
    required Map<String, dynamic> updates,
  }) {
    ref.read(wsServiceProvider).boardUpdateTask(
          taskId: taskId,
          updates: updates,
        );
  }

  void deleteTask({required String taskId}) {
    ref.read(wsServiceProvider).boardDeleteTask(taskId: taskId);
  }

  void assignAgent({
    required String taskId,
    required String agentId,
    required bool assign,
  }) {
    ref.read(wsServiceProvider).boardAssignAgent(
          taskId: taskId,
          agentId: agentId,
          assign: assign,
        );
  }

  void addAttachment({
    required String taskId,
    required String name,
    required String mimeType,
    required int sizeBytes,
    required String dataBase64,
  }) {
    ref.read(wsServiceProvider).boardAddAttachment(
          taskId: taskId,
          name: name,
          mimeType: mimeType,
          sizeBytes: sizeBytes,
          dataBase64: dataBase64,
        );
  }

  void removeAttachment({
    required String taskId,
    required String attachmentId,
  }) {
    ref.read(wsServiceProvider).boardRemoveAttachment(
          taskId: taskId,
          attachmentId: attachmentId,
        );
  }
}

final taskBoardProvider =
    NotifierProvider<TaskBoardNotifier, BoardState>(TaskBoardNotifier.new);
