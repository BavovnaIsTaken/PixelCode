/// Passive observer that records per-agent work-log entries when a task
/// transitions out of an active column. C.2 (server as single writer for
/// board transitions) demoted the original simulator: this provider no
/// longer drives column moves on a timer, rolls outcomes, or resets orphans
/// — those responsibilities all live server-side now. The kept piece is the
/// work-log capture, used by the board UI to show "who worked how long".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_board.dart';
import '../models/work_log_entry.dart';
import 'task_board_provider.dart';

// ─── Work-log provider ────────────────────────────────────────────────────────

class WorkLogNotifier extends Notifier<Map<String, List<WorkLogEntry>>> {
  @override
  Map<String, List<WorkLogEntry>> build() => {};

  void record(String taskId, List<WorkLogEntry> entries) {
    state = {
      ...state,
      taskId: [...(state[taskId] ?? []), ...entries],
    };
  }

  void removeTask(String taskId) {
    if (!state.containsKey(taskId)) return;
    final updated = Map<String, List<WorkLogEntry>>.from(state);
    updated.remove(taskId);
    state = updated;
  }
}

final workLogProvider =
    NotifierProvider<WorkLogNotifier, Map<String, List<WorkLogEntry>>>(
  WorkLogNotifier.new,
);

// ─── Column-stay tracker (reflector) ──────────────────────────────────────────

/// Lives only inside [TaskProgressNotifier] — tracks when a task entered its
/// current active column (in_progress / testing) on this client. Used to
/// derive `durationSeconds` for the work-log row when the server pushes the
/// column transition. Not exposed publicly; UI does not consume it.
class _ColumnEntry {
  final TaskColumn column;
  final DateTime enteredAt;
  const _ColumnEntry({required this.column, required this.enteredAt});
}

// ─── Task progress notifier ───────────────────────────────────────────────────

class TaskProgressNotifier extends Notifier<void> {
  final Map<String, _ColumnEntry> _activeAt = {};

  @override
  void build() {
    ref.listen<BoardState>(taskBoardProvider, (prev, next) {
      _reflect(prev?.tasks ?? const [], next.tasks);
    });
    // Seed from current state so a late-mounted listener still tracks
    // anything that's already active.
    _reflect(const [], ref.read(taskBoardProvider).tasks);
    ref.onDispose(_activeAt.clear);
  }

  /// Compares the previous board snapshot with the next one and, for each
  /// task whose column changed *out of* an active column, emits a work-log
  /// entry for every assignee covering the time spent in that column.
  void _reflect(List<TaskCard> prev, List<TaskCard> next) {
    final now = DateTime.now();
    final prevMap = {for (final t in prev) t.id: t};
    final nextIds = {for (final t in next) t.id};

    _activeAt.removeWhere((id, _) => !nextIds.contains(id));

    for (final task in next) {
      final prevTask = prevMap[task.id];
      final isActive = task.column == TaskColumn.inProgress ||
          task.column == TaskColumn.testing;
      final wasActive = prevTask?.column == TaskColumn.inProgress ||
          prevTask?.column == TaskColumn.testing;

      // 1. Task left an active column (anything → not the same active column):
      //    flush a work-log row per assignee using the prev snapshot's
      //    `assignedAgents`. Must run BEFORE the re-stamp below — otherwise
      //    a same-tick re-entry (inProgress → testing) overwrites the entry
      //    stamp and durations collapse to zero.
      if (wasActive && (!isActive || prevTask!.column != task.column)) {
        final entry = _activeAt.remove(task.id);
        if (entry != null) {
          final elapsed = now.difference(entry.enteredAt);
          final assignees = prevTask?.assignedAgents ?? const <String>[];
          if (assignees.isNotEmpty && elapsed.inSeconds > 0) {
            final logs = assignees
                .map((agentId) => WorkLogEntry(
                      agentId: agentId,
                      startedAt: entry.enteredAt,
                      durationSeconds: elapsed.inSeconds,
                    ))
                .toList();
            ref.read(workLogProvider.notifier).record(task.id, logs);
          }
        }
      }

      // 2. Task entered an active column: stamp the entry timestamp so the
      //    next leave can compute duration.
      if (isActive && (prevTask == null || prevTask.column != task.column)) {
        _activeAt[task.id] = _ColumnEntry(
          column: task.column,
          enteredAt: now,
        );
      }
    }
  }
}

final taskProgressProvider =
    NotifierProvider<TaskProgressNotifier, void>(TaskProgressNotifier.new);
