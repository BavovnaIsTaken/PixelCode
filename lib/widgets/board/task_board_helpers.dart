/// Pure helpers carved out of `task_board_panel.dart` so they can be unit
/// tested without spinning up a full Flutter `WidgetTester`.
///
/// Everything here is `pure` — no `BuildContext`, no providers, no global
/// state. Adding tests for any new widget logic? Try to land it here first.
library;

import 'package:flutter/material.dart';

import '../../models/game_economy.dart';
import '../../models/task_board.dart';

// ─── Column adjacency (used by the mobile swipe card) ──────────────────────

/// Column reachable from `c` via a forward (start-to-end) swipe.
/// Returns `null` for the terminal `done` column.
TaskColumn? nextColumn(TaskColumn c) => switch (c) {
      TaskColumn.backlog => TaskColumn.inProgress,
      TaskColumn.inProgress => TaskColumn.testing,
      TaskColumn.testing => TaskColumn.done,
      TaskColumn.done => null,
    };

/// Column reachable from `c` via a backward (end-to-start) swipe.
/// Returns `null` for the initial `backlog` column.
TaskColumn? prevColumn(TaskColumn c) => switch (c) {
      TaskColumn.backlog => null,
      TaskColumn.inProgress => TaskColumn.backlog,
      TaskColumn.testing => TaskColumn.inProgress,
      TaskColumn.done => TaskColumn.testing,
    };

/// Allowed `Dismissible` direction for a card sitting in `column`.
DismissDirection allowedDismissDirection(TaskColumn column) {
  final hasNext = nextColumn(column) != null;
  final hasPrev = prevColumn(column) != null;
  if (hasNext && hasPrev) return DismissDirection.horizontal;
  if (hasNext) return DismissDirection.startToEnd;
  if (hasPrev) return DismissDirection.endToStart;
  return DismissDirection.none;
}

// ─── Drag-and-drop predicate ───────────────────────────────────────────────

/// `DragTarget.onWillAccept` predicate for the desktop board. A card may
/// only be dropped on a column other than its current one.
bool canDropOnColumn(TaskCard task, TaskColumn target) =>
    task.column != target;

// ─── Column iconography ────────────────────────────────────────────────────

IconData columnIcon(TaskColumn column) => switch (column) {
      TaskColumn.backlog => Icons.inbox_outlined,
      TaskColumn.inProgress => Icons.play_circle_outline,
      TaskColumn.testing => Icons.bug_report_outlined,
      TaskColumn.done => Icons.check_circle_outline,
    };

// ─── Difficulty badge data ─────────────────────────────────────────────────

/// Display tuple for the difficulty badge: a stars-prefixed label and an
/// associated colour. Falls through to `Easy` for any value outside `1..5`.
({String label, Color color}) difficultyChipData(int difficulty) =>
    switch (difficulty) {
      1 => (label: '· Trivial', color: const Color(0xFF78909C)),
      3 => (label: '··· Medium', color: const Color(0xFFFFA726)),
      4 => (label: '···· Hard', color: const Color(0xFFEF5350)),
      5 => (label: '····· Expert', color: const Color(0xFFAB47BC)),
      _ => (label: '·· Easy', color: const Color(0xFF66BB6A)),
    };

// ─── Requirement chip text ─────────────────────────────────────────────────

/// Human-readable role label for a card's `allowedRoles` list.
/// Single role → its catalog name; multiple → `"N ролей"`.
String roleLabelFor(TaskCard task) {
  if (task.allowedRoles.length == 1) {
    return roleCatalogFor(task.allowedRoles.first)?.role ??
        task.allowedRoles.first;
  }
  return '${task.allowedRoles.length} ролей';
}

/// Combined "Lv N+ · Role" chip text, including the bullseye prefix.
String requirementChipText(TaskCard task) =>
    '🎯 Lv ${task.requiredLevel}+ · ${roleLabelFor(task)}';

// ─── Attachment formatting ─────────────────────────────────────────────────

/// Human-readable byte count: `B`, `KB`, `MB`. Always one decimal for
/// non-byte units. Negative values are rendered as `0 B` to keep the chip
/// from showing a dash that looks like part of the filename.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// `true` when an upload exceeds the hard cap defined in `task_board.dart`.
bool isAttachmentOverCap(int bytes) => bytes > maxAttachmentBytes;

/// Best-effort MIME from a filename's extension. Defaults to
/// `application/octet-stream` for unknown types.
String mimeFromName(String name) {
  final parts = name.split('.');
  if (parts.length < 2) return 'application/octet-stream';
  final ext = parts.last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' || 'md' => 'text/plain',
    'json' => 'application/json',
    'zip' => 'application/zip',
    _ => 'application/octet-stream',
  };
}

// ─── Work-history duration formatting ──────────────────────────────────────

/// `"42 с"` or `"3хв 7с"` — used by the work-history list. Negative inputs
/// are clamped to 0 so a malformed log entry can't throw.
String formatWorkDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  if (s < 60) return '$s с';
  return '${s ~/ 60}хв ${s % 60}с';
}
