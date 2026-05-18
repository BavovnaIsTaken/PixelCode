/// Task board models — Kanban-style sticky notes for agent work tracking.
library;

import 'dart:convert';

import '../services/task_outcome.dart';

// ─── Task Column ────────────────────────────────────────────────────────────

enum TaskColumn {
  backlog,
  inProgress,
  testing,
  done;

  String get label => switch (this) {
        backlog => 'Нові',
        inProgress => 'Виконується',
        testing => 'Тестування',
        done => 'Завершено',
      };

  String get key => switch (this) {
        backlog => 'backlog',
        inProgress => 'in_progress',
        testing => 'testing',
        done => 'done',
      };

  static TaskColumn fromKey(String key) => switch (key) {
        'in_progress' => TaskColumn.inProgress,
        'testing' => TaskColumn.testing,
        'done' => TaskColumn.done,
        _ => TaskColumn.backlog,
      };
}

// ─── Task Priority ──────────────────────────────────────────────────────────

enum TaskPriority {
  low,
  normal,
  high,
  urgent;

  String get label => switch (this) {
        low => 'Низький',
        normal => 'Звичайний',
        high => 'Високий',
        urgent => 'Терміново',
      };

  String get key => name;

  static TaskPriority fromKey(String key) => switch (key) {
        'low' => TaskPriority.low,
        'high' => TaskPriority.high,
        'urgent' => TaskPriority.urgent,
        _ => TaskPriority.normal,
      };
}

// ─── Sticky Note Color ──────────────────────────────────────────────────────

enum StickyColor {
  yellow,
  pink,
  blue,
  green,
  orange,
  purple;

  String get key => name;

  static StickyColor fromKey(String key) => switch (key) {
        'pink' => StickyColor.pink,
        'blue' => StickyColor.blue,
        'green' => StickyColor.green,
        'orange' => StickyColor.orange,
        'purple' => StickyColor.purple,
        _ => StickyColor.yellow,
      };
}

// ─── Task Card ──────────────────────────────────────────────────────────────

// ─── Task Difficulty ────────────────────────────────────────────────────────

/// Task difficulty level (1-5).
/// 1=Trivial, 2=Easy, 3=Medium, 4=Hard, 5=Expert.
///
/// Gating is level-based (see `requiredLevelFor`) + role-based (see
/// [TaskCard.allowedRoles]); skills are a soft modifier, not a gate.
extension TaskDifficultyExt on int {
  String get difficultyLabel => switch (this) {
        1 => 'Trivial',
        2 => 'Easy',
        3 => 'Medium',
        4 => 'Hard',
        5 => 'Expert',
        _ => 'Easy',
      };

  String get difficultyStars => switch (this) {
        1 => '·',
        2 => '··',
        3 => '···',
        4 => '····',
        5 => '·····',
        _ => '··',
      };
}

/// Minimum agent level required to take a task of the given difficulty.
/// Logarithmic curve — Expert stays a real challenge.
int requiredLevelFor(int difficulty) {
  final d = difficulty.clamp(1, 5);
  return const [0, 1, 2, 4, 7, 11][d];
}

// ─── Task Attachment ────────────────────────────────────────────────────────

/// Per-card file attachment, stored inline as base64 (server keeps the board
/// in memory). Keep payloads small — see [maxAttachmentBytes].
class TaskAttachment {
  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String dataBase64;
  final DateTime uploadedAt;

  const TaskAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.dataBase64,
    required this.uploadedAt,
  });

  bool get isImage => mimeType.startsWith('image/');

  factory TaskAttachment.fromJson(Map<String, dynamic> json) => TaskAttachment(
        id: json['id'] as String,
        name: json['name'] as String,
        mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        dataBase64: json['dataBase64'] as String? ?? '',
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'dataBase64': dataBase64,
        'uploadedAt': uploadedAt.toIso8601String(),
      };
}

/// Hard cap to keep WebSocket frames manageable. Larger files are rejected
/// client-side before upload.
const int maxAttachmentBytes = 5 * 1024 * 1024; // 5 MB

// ─── Task Card ──────────────────────────────────────────────────────────────

class TaskCard {
  final String id;
  final String title;
  final String description;
  final TaskColumn column;
  final TaskPriority priority;
  final StickyColor color;
  final List<String> assignedAgents;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Difficulty level 1-5. Default 2 (Easy).
  final int difficulty;

  /// Role types eligible to take this task. Default `['coder']`.
  /// Schema v5+.
  final List<String> allowedRoles;

  /// Task-type identifier, e.g. `'coding'`, `'review'`, `'testing'`.
  /// Used by the server to align system prompt. Default `'coding'`.
  /// Schema v5+.
  final String taskType;

  final List<TaskAttachment> attachments;

  /// Server-rolled outcome of the most recent `testing → ?` transition.
  /// Null until the card finishes testing at least once. Reflects the
  /// authoritative server roll (C.2 — server as single writer); the client
  /// never assigns this value locally.
  final TaskOutcome? outcome;

  const TaskCard({
    required this.id,
    required this.title,
    this.description = '',
    this.column = TaskColumn.backlog,
    this.priority = TaskPriority.normal,
    this.color = StickyColor.yellow,
    this.assignedAgents = const [],
    required this.createdAt,
    required this.updatedAt,
    this.difficulty = 2,
    this.allowedRoles = const ['coder'],
    this.taskType = 'coding',
    this.attachments = const [],
    this.outcome,
  });

  /// Derived: minimum agent level required to take this task.
  int get requiredLevel => requiredLevelFor(difficulty);

  TaskCard copyWith({
    String? title,
    String? description,
    TaskColumn? column,
    TaskPriority? priority,
    StickyColor? color,
    List<String>? assignedAgents,
    DateTime? updatedAt,
    int? difficulty,
    List<String>? allowedRoles,
    String? taskType,
    List<TaskAttachment>? attachments,
    Object? outcome = _kUnset,
  }) =>
      TaskCard(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        column: column ?? this.column,
        priority: priority ?? this.priority,
        color: color ?? this.color,
        assignedAgents: assignedAgents ?? this.assignedAgents,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        difficulty: difficulty ?? this.difficulty,
        allowedRoles: allowedRoles ?? this.allowedRoles,
        taskType: taskType ?? this.taskType,
        attachments: attachments ?? this.attachments,
        outcome: identical(outcome, _kUnset)
            ? this.outcome
            : outcome as TaskOutcome?,
      );

  factory TaskCard.fromJson(Map<String, dynamic> json) => TaskCard(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        column: TaskColumn.fromKey(json['column'] as String? ?? 'backlog'),
        priority:
            TaskPriority.fromKey(json['priority'] as String? ?? 'normal'),
        color: StickyColor.fromKey(json['color'] as String? ?? 'yellow'),
        assignedAgents: (json['assignedAgents'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        difficulty: json['difficulty'] as int? ?? 2,
        allowedRoles: (json['allowedRoles'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const ['coder'],
        taskType: json['taskType'] as String? ?? 'coding',
        attachments: (json['attachments'] as List?)
                ?.map((a) => TaskAttachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        outcome: TaskOutcome.fromKey(json['outcome'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'column': column.key,
        'priority': priority.key,
        'color': color.key,
        'assignedAgents': assignedAgents,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'difficulty': difficulty,
        'allowedRoles': allowedRoles,
        'taskType': taskType,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        if (outcome != null) 'outcome': outcome!.key,
      };
}

/// Sentinel that lets [TaskCard.copyWith] distinguish "leave outcome alone"
/// from "explicitly clear outcome to null" (e.g. when a bug bounce re-enters
/// the testing column and we want to drop the previous roll).
const Object _kUnset = Object();

// ─── Board State ────────────────────────────────────────────────────────────

class BoardState {
  final List<TaskCard> tasks;

  const BoardState({this.tasks = const []});

  List<TaskCard> tasksInColumn(TaskColumn column) =>
      tasks.where((t) => t.column == column).toList();

  factory BoardState.fromJson(Map<String, dynamic> json) => BoardState(
        tasks: (json['tasks'] as List?)
                ?.map((t) => TaskCard.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  factory BoardState.decode(String raw) =>
      BoardState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
