/// Observes server-rolled task outcomes on the kanban and folds them into
/// the local economy. Replaces the client-side roll that used to live in
/// `task_progress_provider.dart` (C.2 — server as single writer for board
/// transitions; outcome is now decided server-side and arrives on the
/// `TaskCard.outcome` field).
///
/// Strict reflector role:
///  - never mutates the board
///  - never rolls outcome itself
///  - idempotent per `taskId` via `GameState.rewardedTaskIds`
///
/// When economy moves to the server (B-full Roadmap entry) this provider
/// goes away — the server would broadcast canonical XP/spec/gold deltas
/// directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_board.dart';
import 'game_economy_provider.dart';
import 'task_board_provider.dart';

class TaskOutcomeReflectorNotifier extends Notifier<void> {
  @override
  void build() {
    ref.listen<BoardState>(taskBoardProvider, (prev, next) {
      _reflect(prev?.tasks ?? const [], next.tasks);
    });
    // Catch outcomes that landed before this provider was mounted (e.g. the
    // user opens the app while the server already has the final state in
    // the snapshot). Diff against `prev=[]` so every task with an unprocessed
    // outcome fires exactly once.
    _reflect(const [], ref.read(taskBoardProvider).tasks);
  }

  void _reflect(List<TaskCard> prev, List<TaskCard> next) {
    final notifier = ref.read(gameEconomyProvider.notifier);
    final rewarded = ref.read(gameEconomyProvider).rewardedTaskIds;

    final prevById = {for (final t in prev) t.id: t};

    for (final task in next) {
      final outcome = task.outcome;
      if (outcome == null) continue;
      if (rewarded.contains(task.id)) continue;

      // Decide which agent to credit. Prefer the most recent snapshot's
      // assignedAgents — server doesn't clear them on transition, so the
      // agent that did the work is still listed. Fall back to the prev
      // snapshot in case a future cleanup wipes the list.
      final assignees = task.assignedAgents.isNotEmpty
          ? task.assignedAgents
          : prevById[task.id]?.assignedAgents ?? const <String>[];
      if (assignees.isEmpty) {
        // No one to credit. Mark as processed so we don't keep checking on
        // every board push, but skip the reward payload.
        notifier.applyServerRolledOutcome(
          taskId: task.id,
          agentId: "",
          outcome: outcome,
          difficulty: task.difficulty,
          taskType: task.taskType,
        );
        continue;
      }

      notifier.applyServerRolledOutcome(
        taskId: task.id,
        agentId: assignees.first,
        outcome: outcome,
        difficulty: task.difficulty,
        taskType: task.taskType,
      );
    }
  }
}

final taskOutcomeReflectorProvider =
    NotifierProvider<TaskOutcomeReflectorNotifier, void>(
  TaskOutcomeReflectorNotifier.new,
);
