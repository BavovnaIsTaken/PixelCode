/// MilestoneTree — Marina (Amber) facilitator output.
///
/// A 2-level tree: project root → milestones → tasks. No deeper nesting
/// in MVP — Marina's value is *flat* readability, not arbitrary depth.
/// Dependencies live BETWEEN milestones (gantt-light). Tasks within a
/// milestone are flat siblings.
///
/// See `docs/FACILITATOR_SYSTEM.md` §2 for style design.
library;

import 'dart:convert';

import 'facilitator_output.dart';
import 'quest_line.dart' show DevCategory, ScopeScore;
import 'task_board.dart';

// ─── Status enums ───────────────────────────────────────────────────────────

enum MilestoneStatus {
  notStarted,
  inFlight,
  delivered,
  cancelled;

  String get key => switch (this) {
        MilestoneStatus.notStarted => 'not_started',
        MilestoneStatus.inFlight => 'in_flight',
        MilestoneStatus.delivered => 'delivered',
        MilestoneStatus.cancelled => 'cancelled',
      };

  static MilestoneStatus fromKey(String key) => switch (key) {
        'in_flight' => MilestoneStatus.inFlight,
        'delivered' => MilestoneStatus.delivered,
        'cancelled' => MilestoneStatus.cancelled,
        _ => MilestoneStatus.notStarted,
      };
}

enum MilestoneTaskStatus {
  pending,
  inFlight,
  delivered,
  cancelled;

  String get key => switch (this) {
        MilestoneTaskStatus.pending => 'pending',
        MilestoneTaskStatus.inFlight => 'in_flight',
        MilestoneTaskStatus.delivered => 'delivered',
        MilestoneTaskStatus.cancelled => 'cancelled',
      };

  static MilestoneTaskStatus fromKey(String key) => switch (key) {
        'in_flight' => MilestoneTaskStatus.inFlight,
        'delivered' => MilestoneTaskStatus.delivered,
        'cancelled' => MilestoneTaskStatus.cancelled,
        _ => MilestoneTaskStatus.pending,
      };
}

// ─── Milestone Task (leaf node) ─────────────────────────────────────────────

class MilestoneTask {
  final String id;
  final String milestoneId;
  final String title;
  final String description;
  final DevCategory category;
  final MilestoneTaskStatus status;
  final int xp;
  final int estimatedMinutes;
  final DateTime? completedAt;

  const MilestoneTask({
    required this.id,
    required this.milestoneId,
    required this.title,
    this.description = '',
    required this.category,
    this.status = MilestoneTaskStatus.pending,
    required this.xp,
    required this.estimatedMinutes,
    this.completedAt,
  });

  MilestoneTask copyWith({
    MilestoneTaskStatus? status,
    DateTime? completedAt,
  }) =>
      MilestoneTask(
        id: id,
        milestoneId: milestoneId,
        title: title,
        description: description,
        category: category,
        status: status ?? this.status,
        xp: xp,
        estimatedMinutes: estimatedMinutes,
        completedAt: completedAt ?? this.completedAt,
      );

  factory MilestoneTask.fromJson(Map<String, dynamic> json) => MilestoneTask(
        id: json['id'] as String,
        milestoneId: json['milestoneId'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        category:
            DevCategory.fromKey(json['category'] as String? ?? 'data-model'),
        status: MilestoneTaskStatus.fromKey(
            json['status'] as String? ?? 'pending'),
        xp: json['xp'] as int? ?? 0,
        estimatedMinutes: json['estimatedMinutes'] as int? ?? 0,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'milestoneId': milestoneId,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'category': category.key,
        'status': status.key,
        'xp': xp,
        'estimatedMinutes': estimatedMinutes,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };
}

// ─── Milestone (intermediate node) ──────────────────────────────────────────

class Milestone {
  final String id;
  final String name;
  final String? dueDate;        // ISO-8601 date string, optional
  /// Other milestone ids that must be `delivered` before this one can
  /// move past `notStarted`.
  final List<String> dependsOn;
  final MilestoneStatus status;
  final List<MilestoneTask> tasks;

  const Milestone({
    required this.id,
    required this.name,
    this.dueDate,
    this.dependsOn = const [],
    this.status = MilestoneStatus.notStarted,
    this.tasks = const [],
  });

  /// Milestone is "complete" when every non-cancelled task is delivered
  /// or cancelled. Cancelled tasks count as resolved (mirrors
  /// QuestLine.skipped / Mission.scrubbed).
  bool get isComplete => tasks.every((t) =>
      t.status == MilestoneTaskStatus.delivered ||
      t.status == MilestoneTaskStatus.cancelled);

  Milestone copyWith({
    MilestoneStatus? status,
    List<MilestoneTask>? tasks,
  }) =>
      Milestone(
        id: id,
        name: name,
        dueDate: dueDate,
        dependsOn: dependsOn,
        status: status ?? this.status,
        tasks: tasks ?? this.tasks,
      );

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        dueDate: json['dueDate'] as String?,
        dependsOn: (json['dependsOn'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        status: MilestoneStatus.fromKey(
            json['status'] as String? ?? 'not_started'),
        tasks: (json['tasks'] as List?)
                ?.map((t) => MilestoneTask.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (dueDate != null) 'dueDate': dueDate,
        if (dependsOn.isNotEmpty) 'dependsOn': dependsOn,
        'status': status.key,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };
}

// ─── Milestone Tree (root) ──────────────────────────────────────────────────

class MilestoneTree implements FacilitatorOutput {
  final String id;
  final String projectPath;
  final String objective;
  final List<Milestone> milestones;
  final ScopeScore scoreBreakdown;
  final DateTime createdAt;
  final DateTime? completedAt;

  const MilestoneTree({
    required this.id,
    required this.projectPath,
    required this.objective,
    required this.milestones,
    required this.scoreBreakdown,
    required this.createdAt,
    this.completedAt,
  });

  // ─── Derived ──────────────────────────────────────────────────────────────

  Iterable<MilestoneTask> get allTasks =>
      milestones.expand((m) => m.tasks);

  int get totalXp => allTasks.map((t) => t.xp).fold(0, (a, b) => a + b);

  int get earnedXp => allTasks
      .where((t) => t.status == MilestoneTaskStatus.delivered)
      .map((t) => t.xp)
      .fold(0, (a, b) => a + b);

  bool get isComplete => milestones.every((m) =>
      m.status == MilestoneStatus.delivered ||
      m.status == MilestoneStatus.cancelled);

  /// Progress = milestones delivered (+ cancelled) / total milestones.
  /// Tasks roll up under their milestone — Marina cares about
  /// milestones first, granular tasks second.
  double get progress {
    if (milestones.isEmpty) return 0;
    final done = milestones
        .where((m) =>
            m.status == MilestoneStatus.delivered ||
            m.status == MilestoneStatus.cancelled)
        .length;
    return done / milestones.length;
  }

  Milestone? milestoneById(String id) {
    for (final m in milestones) {
      if (m.id == id) return m;
    }
    return null;
  }

  MilestoneTask? taskById(String id) {
    for (final t in allTasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  MilestoneTree copyWith({
    List<Milestone>? milestones,
    DateTime? completedAt,
  }) =>
      MilestoneTree(
        id: id,
        projectPath: projectPath,
        objective: objective,
        milestones: milestones ?? this.milestones,
        scoreBreakdown: scoreBreakdown,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  // ─── FacilitatorOutput contract ───────────────────────────────────────────

  @override
  OutputFormat get format => OutputFormat.milestoneTree;

  /// Each LEAF task → one TaskCard. Milestones themselves don't get
  /// kanban cards (they're container nodes). This matches gantt
  /// semantics — milestone is a marker, not a unit of work.
  @override
  List<TaskCard> toKanbanTasks() {
    return [
      for (final m in milestones)
        for (final t in m.tasks) _taskToCard(m, t),
    ];
  }

  TaskCard _taskToCard(Milestone m, MilestoneTask t) => TaskCard(
        id: t.id,
        title: t.title,
        description: t.description.isNotEmpty
            ? t.description
            : 'Milestone: ${m.name}',
        column: _statusToColumn(t.status),
        // All Marina tasks wear blue — corporate, neutral, professional.
        color: StickyColor.blue,
        difficulty: _minutesToDifficulty(t.estimatedMinutes),
        taskType: _categoryToTaskType(t.category),
        createdAt: createdAt,
        updatedAt: t.completedAt ?? createdAt,
      );

  @override
  ProgressView toCanonicalProgress() {
    final delivered = milestones
        .where((m) =>
            m.status == MilestoneStatus.delivered ||
            m.status == MilestoneStatus.cancelled)
        .length;
    final total = milestones.length;
    return ProgressView(
      fraction: progress,
      earnedXp: earnedXp,
      totalXp: totalXp,
      isComplete: isComplete,
      label: total == 0
          ? 'No milestones planned'
          : '$delivered of $total milestones delivered',
    );
  }

  @override
  String serialize() => encode();

  // ─── Serde ────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'format': format.key,
        'id': id,
        'projectPath': projectPath,
        'objective': objective,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'scoreBreakdown': scoreBreakdown.toJson(),
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory MilestoneTree.fromJson(Map<String, dynamic> json) => MilestoneTree(
        id: json['id'] as String,
        projectPath: json['projectPath'] as String,
        objective: json['objective'] as String? ?? '',
        milestones: (json['milestones'] as List?)
                ?.map((m) => Milestone.fromJson(m as Map<String, dynamic>))
                .toList() ??
            const [],
        scoreBreakdown: ScopeScore.fromJson(
            json['scoreBreakdown'] as Map<String, dynamic>? ?? const {}),
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  String encode() => jsonEncode(toJson());

  factory MilestoneTree.decode(String raw) =>
      MilestoneTree.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

// ─── Mapping helpers ────────────────────────────────────────────────────────

TaskColumn _statusToColumn(MilestoneTaskStatus s) => switch (s) {
      MilestoneTaskStatus.pending => TaskColumn.backlog,
      MilestoneTaskStatus.inFlight => TaskColumn.inProgress,
      MilestoneTaskStatus.delivered => TaskColumn.done,
      MilestoneTaskStatus.cancelled => TaskColumn.done,
    };

int _minutesToDifficulty(int minutes) {
  if (minutes <= 15) return 1;
  if (minutes <= 30) return 2;
  if (minutes <= 45) return 3;
  if (minutes <= 60) return 4;
  return 5;
}

String _categoryToTaskType(DevCategory c) => switch (c) {
      DevCategory.testing => 'testing',
      DevCategory.deploy => 'deploy',
      _ => 'coding',
    };
