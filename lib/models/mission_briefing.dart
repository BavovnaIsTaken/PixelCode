/// MissionBriefing — Drill Sergeant facilitator output.
///
/// 1–3 missions per briefing. No acts, no narrative arcs, no side
/// quests. Every mission is an order to execute, mapped 1:1 to a
/// kanban card. Shape is intentionally minimal — Drill is terse.
///
/// See `docs/FACILITATOR_SYSTEM.md` §2 for style design.
library;

import 'dart:convert';

import 'facilitator_output.dart';
import 'quest_line.dart' show DevCategory, ScopeScore;
import 'task_board.dart';

// ─── Mission status ─────────────────────────────────────────────────────────

enum MissionStatus {
  standby,    // not yet active
  active,     // currently executing
  complete,   // mission accomplished
  scrubbed;   // cancelled / aborted (counts as done on the board)

  String get key => name;

  static MissionStatus fromKey(String key) => switch (key) {
        'active' => MissionStatus.active,
        'complete' => MissionStatus.complete,
        'scrubbed' => MissionStatus.scrubbed,
        _ => MissionStatus.standby,
      };
}

// ─── Mission ────────────────────────────────────────────────────────────────

class Mission {
  final String id;

  /// One-line order, brutal. Becomes the TaskCard title.
  /// ("Ship the auth flow. Now.")
  final String briefing;

  /// Optional one-line target — what success looks like.
  final String target;

  /// Dev category drives taskType mapping on kanban.
  final DevCategory category;

  final MissionStatus status;
  final int xp;
  final int estimatedMinutes;
  final DateTime? completedAt;

  const Mission({
    required this.id,
    required this.briefing,
    this.target = '',
    required this.category,
    this.status = MissionStatus.standby,
    required this.xp,
    required this.estimatedMinutes,
    this.completedAt,
  });

  Mission copyWith({
    MissionStatus? status,
    DateTime? completedAt,
    String? briefing,
    String? target,
  }) =>
      Mission(
        id: id,
        briefing: briefing ?? this.briefing,
        target: target ?? this.target,
        category: category,
        status: status ?? this.status,
        xp: xp,
        estimatedMinutes: estimatedMinutes,
        completedAt: completedAt ?? this.completedAt,
      );

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'] as String,
        briefing: json['briefing'] as String? ?? '',
        target: json['target'] as String? ?? '',
        category:
            DevCategory.fromKey(json['category'] as String? ?? 'data-model'),
        status: MissionStatus.fromKey(json['status'] as String? ?? 'standby'),
        xp: json['xp'] as int? ?? 0,
        estimatedMinutes: json['estimatedMinutes'] as int? ?? 0,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'briefing': briefing,
        if (target.isNotEmpty) 'target': target,
        'category': category.key,
        'status': status.key,
        'xp': xp,
        'estimatedMinutes': estimatedMinutes,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };
}

// ─── Mission Briefing ───────────────────────────────────────────────────────

class MissionBriefing implements FacilitatorOutput {
  final String id;
  final String projectPath;

  /// One-line mission objective ("Ship the auth flow by EOD.")
  final String objective;

  /// 1–3 missions. Drill caps the briefing — more than 3 is "out of scope,
  /// soldier, focus".
  final List<Mission> missions;

  final ScopeScore scoreBreakdown;
  final DateTime createdAt;
  final DateTime? completedAt;

  const MissionBriefing({
    required this.id,
    required this.projectPath,
    required this.objective,
    required this.missions,
    required this.scoreBreakdown,
    required this.createdAt,
    this.completedAt,
  });

  // ─── Derived ──────────────────────────────────────────────────────────────

  int get totalXp => missions.map((m) => m.xp).fold(0, (a, b) => a + b);

  int get earnedXp => missions
      .where((m) => m.status == MissionStatus.complete)
      .map((m) => m.xp)
      .fold(0, (a, b) => a + b);

  /// Scrubbed counts toward "done" on the board, mirroring QuestLine's
  /// treatment of `skipped`.
  bool get isComplete => missions.every((m) =>
      m.status == MissionStatus.complete ||
      m.status == MissionStatus.scrubbed);

  double get progress {
    if (missions.isEmpty) return 0;
    final done = missions
        .where((m) =>
            m.status == MissionStatus.complete ||
            m.status == MissionStatus.scrubbed)
        .length;
    return done / missions.length;
  }

  Mission? missionById(String id) {
    for (final m in missions) {
      if (m.id == id) return m;
    }
    return null;
  }

  MissionBriefing copyWith({
    List<Mission>? missions,
    DateTime? completedAt,
  }) =>
      MissionBriefing(
        id: id,
        projectPath: projectPath,
        objective: objective,
        missions: missions ?? this.missions,
        scoreBreakdown: scoreBreakdown,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  MissionBriefing withMissionUpdated(Mission updated) {
    final newList =
        missions.map((m) => m.id == updated.id ? updated : m).toList();
    return copyWith(missions: newList);
  }

  // ─── FacilitatorOutput contract ───────────────────────────────────────────

  @override
  OutputFormat get format => OutputFormat.missionBriefing;

  /// Each mission → one TaskCard. No hierarchy, no acts; that's the
  /// whole point of this style.
  @override
  List<TaskCard> toKanbanTasks() =>
      missions.map((m) => _missionToTaskCard(m)).toList();

  TaskCard _missionToTaskCard(Mission m) => TaskCard(
        id: m.id,
        title: m.briefing,
        description: m.target,
        column: _statusToColumn(m.status),
        // All missions wear the same uniform — Drill is uniform aggressive.
        // Orange reads as "warning / mission-critical" on the board.
        color: StickyColor.orange,
        difficulty: _minutesToDifficulty(m.estimatedMinutes),
        taskType: _categoryToTaskType(m.category),
        createdAt: createdAt,
        updatedAt: m.completedAt ?? createdAt,
      );

  @override
  ProgressView toCanonicalProgress() {
    final done = missions
        .where((m) =>
            m.status == MissionStatus.complete ||
            m.status == MissionStatus.scrubbed)
        .length;
    final total = missions.length;

    return ProgressView(
      fraction: progress,
      earnedXp: earnedXp,
      totalXp: totalXp,
      isComplete: isComplete,
      label: total == 0
          ? 'No missions assigned'
          : '$done of $total missions complete',
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
        'missions': missions.map((m) => m.toJson()).toList(),
        'scoreBreakdown': scoreBreakdown.toJson(),
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory MissionBriefing.fromJson(Map<String, dynamic> json) =>
      MissionBriefing(
        id: json['id'] as String,
        projectPath: json['projectPath'] as String,
        objective: json['objective'] as String? ?? '',
        missions: (json['missions'] as List?)
                ?.map((m) => Mission.fromJson(m as Map<String, dynamic>))
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

  factory MissionBriefing.decode(String raw) =>
      MissionBriefing.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

// ─── Mission → Kanban mapping helpers ───────────────────────────────────────
//
// Same shape and reasoning as the helpers in `quest_line.dart`. Keeping
// per-format helpers keeps each output shape self-contained and avoids
// a shared "facilitator_kanban_helpers.dart" with cross-format imports.

TaskColumn _statusToColumn(MissionStatus s) => switch (s) {
      MissionStatus.standby => TaskColumn.backlog,
      MissionStatus.active => TaskColumn.inProgress,
      MissionStatus.complete => TaskColumn.done,
      MissionStatus.scrubbed => TaskColumn.done,
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
