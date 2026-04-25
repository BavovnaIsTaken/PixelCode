/// Riverpod provider for the task board (Kanban) state.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_message.dart';
import '../models/game_economy.dart';
import '../models/task_board.dart';
import 'agent_provider.dart';

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

// ─── Board state provider ──────────────────────────────────────────────────

class TaskBoardNotifier extends Notifier<BoardState> {
  StreamSubscription<ServerMessage>? _sub;
  StreamSubscription<bool>? _connSub;

  @override
  BoardState build() {
    final ws = ref.watch(wsServiceProvider);
    _sub?.cancel();
    _sub = ws.messages.listen(_onMessage);

    // Request board state once connected (with proper cancellation)
    _connSub?.cancel();
    if (ws.isConnected) {
      debugPrint('[TaskBoard] Already connected — requesting board state');
      ws.boardGetState();
    } else {
      _connSub = ws.connectionStatus.listen((connected) {
        if (connected) {
          _connSub?.cancel();
          debugPrint('[TaskBoard] Connected — requesting board state');
          ws.boardGetState();
        }
      });
    }

    ref.onDispose(() {
      _sub?.cancel();
      _connSub?.cancel();
    });

    return const BoardState();
  }

  void _onMessage(ServerMessage msg) {
    if (msg is BoardStateMessage) {
      debugPrint('[TaskBoard] Received board_state: ${msg.boardState.tasks.length} tasks');
      state = msg.boardState;
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

  void moveTask({required String taskId, required TaskColumn column}) {
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
