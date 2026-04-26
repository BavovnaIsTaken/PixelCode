/// Quest System models — the Game Master facilitator's output shape.
///
/// `QuestLine` is one of several `FacilitatorOutput` implementations
/// (alongside `MissionBriefing`, `MilestoneTree`, etc). It maps an app
/// idea to a narrative sequence of dev tasks the player completes to
/// ship the app.
///
/// See `docs/FACILITATOR_GAMEMASTER.md` for the Game Master mode design,
/// and `docs/FACILITATOR_SYSTEM.md` for how it slots into the broader
/// Facilitator System.
library;

import 'dart:convert';

import 'facilitator_output.dart';
import 'task_board.dart';

// ─── Tier ───────────────────────────────────────────────────────────────────

enum QuestTier {
  micro,
  small,
  medium,
  large;

  String get key => name;

  String get label => switch (this) {
        QuestTier.micro => 'Micro',
        QuestTier.small => 'Small',
        QuestTier.medium => 'Medium',
        QuestTier.large => 'Large',
      };

  /// Quest count window for this tier.
  ({int min, int max}) get questCountRange => switch (this) {
        QuestTier.micro => (min: 3, max: 4),
        QuestTier.small => (min: 5, max: 7),
        QuestTier.medium => (min: 8, max: 13),
        QuestTier.large => (min: 14, max: 20),
      };

  static QuestTier fromKey(String key) => switch (key) {
        'small' => QuestTier.small,
        'medium' => QuestTier.medium,
        'large' => QuestTier.large,
        _ => QuestTier.micro,
      };

  /// Map a total scope score (0–18) to a tier.
  static QuestTier fromScore(int total) {
    if (total <= 4) return QuestTier.micro;
    if (total <= 8) return QuestTier.small;
    if (total <= 12) return QuestTier.medium;
    return QuestTier.large;
  }
}

// ─── Scope Score ────────────────────────────────────────────────────────────

class ScopeScore {
  /// Number of distinct data models. 0–4.
  final int entityCount;

  /// Screens × interaction types. 0–4.
  final int interactionSurface;

  /// None=0, accounts=2, roles/permissions=3.
  final int auth;

  /// +1 per external service (push, maps, payments, camera, etc). 0–4.
  final int integrations;

  /// Static=0, sync=1, websocket=2, multi-user live=3.
  final int realtime;

  const ScopeScore({
    required this.entityCount,
    required this.interactionSurface,
    required this.auth,
    required this.integrations,
    required this.realtime,
  });

  const ScopeScore.empty()
      : entityCount = 0,
        interactionSurface = 0,
        auth = 0,
        integrations = 0,
        realtime = 0;

  int get total =>
      entityCount + interactionSurface + auth + integrations + realtime;

  QuestTier get tier => QuestTier.fromScore(total);

  ScopeScore copyWith({
    int? entityCount,
    int? interactionSurface,
    int? auth,
    int? integrations,
    int? realtime,
  }) =>
      ScopeScore(
        entityCount: entityCount ?? this.entityCount,
        interactionSurface: interactionSurface ?? this.interactionSurface,
        auth: auth ?? this.auth,
        integrations: integrations ?? this.integrations,
        realtime: realtime ?? this.realtime,
      );

  factory ScopeScore.fromJson(Map<String, dynamic> json) => ScopeScore(
        entityCount: json['entityCount'] as int? ?? 0,
        interactionSurface: json['interactionSurface'] as int? ?? 0,
        auth: json['auth'] as int? ?? 0,
        integrations: json['integrations'] as int? ?? 0,
        realtime: json['realtime'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'entityCount': entityCount,
        'interactionSurface': interactionSurface,
        'auth': auth,
        'integrations': integrations,
        'realtime': realtime,
      };
}

// ─── Act ────────────────────────────────────────────────────────────────────

enum ActArchetype {
  foundation,
  interfaceAct,
  logic,
  connection,
  polish,
  launch;

  String get key => switch (this) {
        ActArchetype.foundation => 'foundation',
        ActArchetype.interfaceAct => 'interface',
        ActArchetype.logic => 'logic',
        ActArchetype.connection => 'connection',
        ActArchetype.polish => 'polish',
        ActArchetype.launch => 'launch',
      };

  String get label => switch (this) {
        ActArchetype.foundation => 'Foundation',
        ActArchetype.interfaceAct => 'Interface',
        ActArchetype.logic => 'Logic',
        ActArchetype.connection => 'Connection',
        ActArchetype.polish => 'Polish',
        ActArchetype.launch => 'Launch',
      };

  static ActArchetype fromKey(String key) => switch (key) {
        'interface' => ActArchetype.interfaceAct,
        'logic' => ActArchetype.logic,
        'connection' => ActArchetype.connection,
        'polish' => ActArchetype.polish,
        'launch' => ActArchetype.launch,
        _ => ActArchetype.foundation,
      };
}

// ─── Quest ──────────────────────────────────────────────────────────────────

enum QuestStatus {
  locked,
  available,
  active,
  completed,
  skipped;

  String get key => name;

  static QuestStatus fromKey(String key) => switch (key) {
        'available' => QuestStatus.available,
        'active' => QuestStatus.active,
        'completed' => QuestStatus.completed,
        'skipped' => QuestStatus.skipped,
        _ => QuestStatus.locked,
      };
}

enum QuestType {
  main,
  side;

  String get key => name;

  static QuestType fromKey(String key) =>
      key == 'side' ? QuestType.side : QuestType.main;
}

enum DevCategory {
  dataModel,
  uiScreen,
  uiComponent,
  apiRoute,
  auth,
  integration,
  realtime,
  testing,
  deploy;

  String get key => switch (this) {
        DevCategory.dataModel => 'data-model',
        DevCategory.uiScreen => 'ui-screen',
        DevCategory.uiComponent => 'ui-component',
        DevCategory.apiRoute => 'api-route',
        DevCategory.auth => 'auth',
        DevCategory.integration => 'integration',
        DevCategory.realtime => 'realtime',
        DevCategory.testing => 'testing',
        DevCategory.deploy => 'deploy',
      };

  static DevCategory fromKey(String key) => switch (key) {
        'ui-screen' => DevCategory.uiScreen,
        'ui-component' => DevCategory.uiComponent,
        'api-route' => DevCategory.apiRoute,
        'auth' => DevCategory.auth,
        'integration' => DevCategory.integration,
        'realtime' => DevCategory.realtime,
        'testing' => DevCategory.testing,
        'deploy' => DevCategory.deploy,
        _ => DevCategory.dataModel,
      };
}

class DevTask {
  final DevCategory category;
  final String description;
  final List<String> acceptanceCriteria;
  final List<String> files;

  const DevTask({
    required this.category,
    required this.description,
    this.acceptanceCriteria = const [],
    this.files = const [],
  });

  factory DevTask.fromJson(Map<String, dynamic> json) => DevTask(
        category: DevCategory.fromKey(json['category'] as String? ?? 'data-model'),
        description: json['description'] as String? ?? '',
        acceptanceCriteria: (json['acceptanceCriteria'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        files: (json['files'] as List?)?.map((e) => e as String).toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'category': category.key,
        'description': description,
        'acceptanceCriteria': acceptanceCriteria,
        'files': files,
      };
}

class Quest {
  final String id;
  final String actId;
  final String title;       // narrative ("Forge the Task Vault")
  final String subtitle;    // dev one-liner
  final String description; // 2–4 sentence framing
  final String? payoffLine; // shown on completion
  final DevTask devTask;
  final QuestStatus status;
  final QuestType type;
  final List<String> dependsOn;
  final List<String> unlocks;
  final int xp;
  final int estimatedMinutes;
  final DateTime? completedAt;

  const Quest({
    required this.id,
    required this.actId,
    required this.title,
    required this.subtitle,
    required this.description,
    this.payoffLine,
    required this.devTask,
    this.status = QuestStatus.locked,
    this.type = QuestType.main,
    this.dependsOn = const [],
    this.unlocks = const [],
    required this.xp,
    required this.estimatedMinutes,
    this.completedAt,
  });

  Quest copyWith({
    QuestStatus? status,
    DateTime? completedAt,
    String? title,
    String? description,
    String? payoffLine,
  }) =>
      Quest(
        id: id,
        actId: actId,
        title: title ?? this.title,
        subtitle: subtitle,
        description: description ?? this.description,
        payoffLine: payoffLine ?? this.payoffLine,
        devTask: devTask,
        status: status ?? this.status,
        type: type,
        dependsOn: dependsOn,
        unlocks: unlocks,
        xp: xp,
        estimatedMinutes: estimatedMinutes,
        completedAt: completedAt ?? this.completedAt,
      );

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
        id: json['id'] as String,
        actId: json['actId'] as String,
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        description: json['description'] as String? ?? '',
        payoffLine: json['payoffLine'] as String?,
        devTask: DevTask.fromJson(json['devTask'] as Map<String, dynamic>),
        status: QuestStatus.fromKey(json['status'] as String? ?? 'locked'),
        type: QuestType.fromKey(json['type'] as String? ?? 'main'),
        dependsOn:
            (json['dependsOn'] as List?)?.map((e) => e as String).toList() ??
                const [],
        unlocks:
            (json['unlocks'] as List?)?.map((e) => e as String).toList() ??
                const [],
        xp: json['xp'] as int? ?? 0,
        estimatedMinutes: json['estimatedMinutes'] as int? ?? 0,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'actId': actId,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        if (payoffLine != null) 'payoffLine': payoffLine,
        'devTask': devTask.toJson(),
        'status': status.key,
        'type': type.key,
        'dependsOn': dependsOn,
        'unlocks': unlocks,
        'xp': xp,
        'estimatedMinutes': estimatedMinutes,
        if (completedAt != null)
          'completedAt': completedAt!.toIso8601String(),
      };
}

class Act {
  final String id;
  final String name;
  final ActArchetype archetype;
  final List<Quest> quests;

  const Act({
    required this.id,
    required this.name,
    required this.archetype,
    this.quests = const [],
  });

  Act copyWith({String? name, List<Quest>? quests}) => Act(
        id: id,
        name: name ?? this.name,
        archetype: archetype,
        quests: quests ?? this.quests,
      );

  bool get isCompleted =>
      quests.where((q) => q.type == QuestType.main).every(
            (q) => q.status == QuestStatus.completed ||
                q.status == QuestStatus.skipped,
          );

  factory Act.fromJson(Map<String, dynamic> json) => Act(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        archetype: ActArchetype.fromKey(
            json['archetype'] as String? ?? 'foundation'),
        quests: (json['quests'] as List?)
                ?.map((q) => Quest.fromJson(q as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'archetype': archetype.key,
        'quests': quests.map((q) => q.toJson()).toList(),
      };
}

// ─── Quest Line ─────────────────────────────────────────────────────────────

class QuestLine implements FacilitatorOutput {
  final String id;
  final String projectPath;
  final String appSummary;
  final QuestTier tier;
  final ScopeScore scoreBreakdown;
  final List<Act> acts;
  /// Counter of transformative scope changes; at threshold (3) inject a
  /// "Break the Curse" refactor quest before the next act can advance.
  final int transformativeChanges;
  final String? finalScreenshotPath;
  final DateTime createdAt;
  final DateTime? completedAt;

  const QuestLine({
    required this.id,
    required this.projectPath,
    required this.appSummary,
    required this.tier,
    required this.scoreBreakdown,
    required this.acts,
    this.transformativeChanges = 0,
    this.finalScreenshotPath,
    required this.createdAt,
    this.completedAt,
  });

  // ─── Derived ──────────────────────────────────────────────────────────────

  Iterable<Quest> get allQuests => acts.expand((a) => a.quests);

  Iterable<Quest> get mainQuests =>
      allQuests.where((q) => q.type == QuestType.main);

  int get totalXp => allQuests.map((q) => q.xp).fold(0, (a, b) => a + b);

  int get earnedXp => allQuests
      .where((q) => q.status == QuestStatus.completed)
      .map((q) => q.xp)
      .fold(0, (a, b) => a + b);

  /// Percent of MAIN quests done (side quests don't gate completion).
  double get progress {
    final mains = mainQuests.toList();
    if (mains.isEmpty) return 0;
    final done = mains
        .where((q) =>
            q.status == QuestStatus.completed ||
            q.status == QuestStatus.skipped)
        .length;
    return done / mains.length;
  }

  bool get isCompleted =>
      mainQuests.every((q) =>
          q.status == QuestStatus.completed ||
          q.status == QuestStatus.skipped);

  Quest? questById(String id) {
    for (final a in acts) {
      for (final q in a.quests) {
        if (q.id == id) return q;
      }
    }
    return null;
  }

  // ─── Mutation helpers ─────────────────────────────────────────────────────

  QuestLine copyWith({
    List<Act>? acts,
    int? transformativeChanges,
    String? finalScreenshotPath,
    DateTime? completedAt,
  }) =>
      QuestLine(
        id: id,
        projectPath: projectPath,
        appSummary: appSummary,
        tier: tier,
        scoreBreakdown: scoreBreakdown,
        acts: acts ?? this.acts,
        transformativeChanges:
            transformativeChanges ?? this.transformativeChanges,
        finalScreenshotPath: finalScreenshotPath ?? this.finalScreenshotPath,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
      );

  /// Replace a single quest by id. Recalculates downstream lock states.
  QuestLine withQuestUpdated(Quest updated) {
    final newActs = acts
        .map((a) => a.copyWith(
              quests: a.quests
                  .map((q) => q.id == updated.id ? updated : q)
                  .toList(),
            ))
        .toList();
    return copyWith(acts: newActs).recomputeAvailability();
  }

  /// Walks the DAG and promotes `locked` quests to `available` when all
  /// their dependencies are completed/skipped. Idempotent.
  QuestLine recomputeAvailability() {
    final byId = {for (final q in allQuests) q.id: q};

    bool depsSatisfied(Quest q) => q.dependsOn.every((id) {
          final dep = byId[id];
          if (dep == null) return true;
          return dep.status == QuestStatus.completed ||
              dep.status == QuestStatus.skipped;
        });

    final newActs = acts.map((a) {
      final newQuests = a.quests.map((q) {
        if (q.status == QuestStatus.locked && depsSatisfied(q)) {
          return q.copyWith(status: QuestStatus.available);
        }
        return q;
      }).toList();
      return a.copyWith(quests: newQuests);
    }).toList();

    return copyWith(acts: newActs);
  }

  // ─── FacilitatorOutput contract ───────────────────────────────────────────

  @override
  OutputFormat get format => OutputFormat.questLine;

  /// Quest → TaskCard. Lossy by design: hierarchy (acts), dependencies,
  /// XP, narrative `description` / `payoffLine`, and `estimatedMinutes`
  /// stay on the QuestLine; only the working-set fields land on the
  /// kanban. Side quests come through as kanban cards too — the board
  /// doesn't differentiate; the `QuestLine` does.
  @override
  List<TaskCard> toKanbanTasks() {
    return allQuests.map((q) => _questToTaskCard(q)).toList();
  }

  TaskCard _questToTaskCard(Quest q) {
    final actArchetype = acts
        .firstWhere(
          (a) => a.id == q.actId,
          orElse: () => Act(
            id: q.actId,
            name: '',
            archetype: ActArchetype.foundation,
          ),
        )
        .archetype;

    return TaskCard(
      id: q.id,
      title: q.title,
      description: q.subtitle.isNotEmpty ? q.subtitle : q.description,
      column: _statusToColumn(q.status),
      color: _archetypeToColor(actArchetype),
      difficulty: _minutesToDifficulty(q.estimatedMinutes),
      taskType: _categoryToTaskType(q.devTask.category),
      createdAt: createdAt,
      updatedAt: q.completedAt ?? createdAt,
    );
  }

  @override
  ProgressView toCanonicalProgress() {
    final mains = mainQuests.toList();
    final mainsTotal = mains.length;
    final mainsDone = mains
        .where((q) =>
            q.status == QuestStatus.completed ||
            q.status == QuestStatus.skipped)
        .length;

    return ProgressView(
      fraction: progress,
      earnedXp: earnedXp,
      totalXp: totalXp,
      isComplete: isCompleted,
      label: mainsTotal == 0
          ? 'No quests yet'
          : '$mainsDone of $mainsTotal quests forged',
    );
  }

  @override
  String serialize() => encode();

  // ─── Serde ────────────────────────────────────────────────────────────────

  factory QuestLine.fromJson(Map<String, dynamic> json) => QuestLine(
        id: json['id'] as String,
        projectPath: json['projectPath'] as String,
        appSummary: json['appSummary'] as String? ?? '',
        tier: QuestTier.fromKey(json['tier'] as String? ?? 'micro'),
        scoreBreakdown: ScopeScore.fromJson(
            json['scoreBreakdown'] as Map<String, dynamic>? ?? const {}),
        acts: (json['acts'] as List?)
                ?.map((a) => Act.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        transformativeChanges: json['transformativeChanges'] as int? ?? 0,
        finalScreenshotPath: json['finalScreenshotPath'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        // Discriminator for FacilitatorOutput routing (marketplace,
        // generic persistence). Always present so loaders can pick the
        // right `fromJson` without sniffing.
        'format': format.key,
        'id': id,
        'projectPath': projectPath,
        'appSummary': appSummary,
        'tier': tier.key,
        'scoreBreakdown': scoreBreakdown.toJson(),
        'acts': acts.map((a) => a.toJson()).toList(),
        'transformativeChanges': transformativeChanges,
        if (finalScreenshotPath != null)
          'finalScreenshotPath': finalScreenshotPath,
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  factory QuestLine.decode(String raw) =>
      QuestLine.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

// ─── Quest → Kanban mapping helpers ─────────────────────────────────────────
//
// These keep the Quest→TaskCard projection in one place. Mappings are
// intentionally simple — kanban is a working-set view, not a perfect
// mirror of the QuestLine.

TaskColumn _statusToColumn(QuestStatus s) => switch (s) {
      QuestStatus.locked => TaskColumn.backlog,
      QuestStatus.available => TaskColumn.backlog,
      QuestStatus.active => TaskColumn.inProgress,
      QuestStatus.completed => TaskColumn.done,
      QuestStatus.skipped => TaskColumn.done,
    };

StickyColor _archetypeToColor(ActArchetype a) => switch (a) {
      ActArchetype.foundation => StickyColor.green,
      ActArchetype.interfaceAct => StickyColor.blue,
      ActArchetype.logic => StickyColor.yellow,
      ActArchetype.connection => StickyColor.purple,
      ActArchetype.polish => StickyColor.pink,
      ActArchetype.launch => StickyColor.orange,
    };

/// Bucket estimated minutes into the 1–5 difficulty scale used by the
/// kanban. The thresholds match agent-level skill-cap gating in
/// [TaskCard.requiredLevel].
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
