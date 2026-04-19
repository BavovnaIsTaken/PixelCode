/// Simulates agent work on tasks: auto-advances columns on a countdown timer
/// and accumulates a per-task work log so users can see who worked how long.
library;

import 'dart:async';

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

// ─── Per-task progress ────────────────────────────────────────────────────────

class _TaskProgress {
  double secondsRemaining;
  final double totalSeconds;
  final DateTime columnEnteredAt;

  _TaskProgress({
    required this.secondsRemaining,
    required this.totalSeconds,
    required this.columnEnteredAt,
  });
}

// ─── Task progress notifier ───────────────────────────────────────────────────

class TaskProgressNotifier extends Notifier<void> {
  final Map<String, _TaskProgress> _progress = {};
  Timer? _timer;

  @override
  void build() {
    ref.listen<BoardState>(taskBoardProvider, (prev, next) {
      _syncTasks(prev?.tasks ?? [], next.tasks);
    });
    // Also seed from current state immediately.
    _syncTasks([], ref.read(taskBoardProvider).tasks);

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    ref.onDispose(() {
      _timer?.cancel();
      _progress.clear();
    });
  }

  void _syncTasks(List<TaskCard> prev, List<TaskCard> next) {
    final prevMap = {for (final t in prev) t.id: t};
    final nextIds = {for (final t in next) t.id};

    // Remove stale entries.
    _progress.removeWhere((id, _) => !nextIds.contains(id));

    for (final task in next) {
      // Skip tasks with no assigned agents — nothing to simulate.
      if (task.assignedAgents.isEmpty) {
        _progress.remove(task.id);
        continue;
      }
      // Skip completed tasks.
      if (task.column == TaskColumn.done) {
        _progress.remove(task.id);
        continue;
      }

      final prevTask = prevMap[task.id];
      final columnChanged = prevTask != null && prevTask.column != task.column;
      final agentsChanged = prevTask != null &&
          prevTask.assignedAgents.toString() != task.assignedAgents.toString();
      final isNew = prevTask == null;

      if (isNew || columnChanged || agentsChanged || !_progress.containsKey(task.id)) {
        final seconds = _workSeconds(task);
        _progress[task.id] = _TaskProgress(
          secondsRemaining: seconds,
          totalSeconds: seconds,
          columnEnteredAt: DateTime.now(),
        );
      }
    }
  }

  double _workSeconds(TaskCard task) {
    final d = task.difficulty.clamp(1, 5);
    return switch (task.column) {
      TaskColumn.backlog => 10.0 + (d - 1) * 2, // 10–18 s to pick up
      TaskColumn.inProgress => d * 12.0,          // 12–60 s to implement
      TaskColumn.testing => d * 6.0,              // 6–30 s to test
      TaskColumn.done => 0,
    };
  }

  void _tick() {
    final board = ref.read(taskBoardProvider);
    final toAdvance = <String>[];

    for (final entry in _progress.entries) {
      final task = board.tasks.firstWhere(
        (t) => t.id == entry.key,
        orElse: () => TaskCard(
          id: entry.key,
          title: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      if (task.title.isEmpty) continue; // task was deleted
      if (task.assignedAgents.isEmpty) continue;

      entry.value.secondsRemaining -= 1;
      if (entry.value.secondsRemaining <= 0) {
        toAdvance.add(entry.key);
      }
    }

    for (final taskId in toAdvance) {
      _advance(taskId, board);
    }
  }

  void _advance(String taskId, BoardState board) {
    final task = board.tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => TaskCard(
        id: taskId,
        title: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    if (task.title.isEmpty) return;

    final nextColumn = switch (task.column) {
      TaskColumn.backlog => TaskColumn.inProgress,
      TaskColumn.inProgress => TaskColumn.testing,
      TaskColumn.testing => TaskColumn.done,
      TaskColumn.done => null,
    };
    if (nextColumn == null) {
      _progress.remove(taskId);
      return;
    }

    // Record a work log entry for each assigned agent.
    final progress = _progress[taskId];
    if (progress != null) {
      final elapsed = DateTime.now().difference(progress.columnEnteredAt);
      final entries = task.assignedAgents
          .map((agentId) => WorkLogEntry(
                agentId: agentId,
                startedAt: progress.columnEnteredAt,
                durationSeconds: elapsed.inSeconds,
              ))
          .toList();
      ref.read(workLogProvider.notifier).record(taskId, entries);
    }

    _progress.remove(taskId);
    ref.read(taskBoardProvider.notifier).moveTask(
          taskId: taskId,
          column: nextColumn,
        );
  }
}

final taskProgressProvider =
    NotifierProvider<TaskProgressNotifier, void>(TaskProgressNotifier.new);
