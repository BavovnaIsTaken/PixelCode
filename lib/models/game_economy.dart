/// PixelCode game economy — currency, hiring, skills, office upgrades, donations.
///
/// Currency: "гримні" (₲). Start in a shabby garage with cheap laptops.
/// Progress by completing tasks, hiring agents, upgrading skills & hardware.
library;

import 'dart:convert';
import 'dart:math';

import 'agent_message.dart';
import 'app_theme.dart';

// ─── Office levels ─────────────────────────────────────────────────────────

/// One expansion step within a given office tier.
///
/// Each step grows the grid by [deltaCols] columns and/or [deltaRows] rows
/// and costs [cost] ₲. Steps are ordered — buying step N requires having
/// bought all prior steps at the current tier.
class OfficeExpansion {
  final int deltaCols;
  final int deltaRows;
  final int cost;

  const OfficeExpansion({
    this.deltaCols = 0,
    this.deltaRows = 0,
    required this.cost,
  });
}

enum OfficeLevel {
  garage,
  smallOffice,
  modernOffice,
  techHub,
  campus,
}

extension OfficeLevelExt on OfficeLevel {
  String get label => switch (this) {
        OfficeLevel.garage => 'Гараж',
        OfficeLevel.smallOffice => 'Маленький офіс',
        OfficeLevel.modernOffice => 'Модерн офіс',
        OfficeLevel.techHub => 'Тех-хаб',
        OfficeLevel.campus => 'Кампус',
      };

  String get description => switch (this) {
        OfficeLevel.garage =>
          'Обшарпаний гараж, тьмяне світло. Старт 5×3, розширення до 8×5 клітинок — забудовуй і перебудовуй як хочеш.',
        OfficeLevel.smallOffice =>
          'Скромний офіс з нормальним Wi-Fi. Старт 7×4, розширення до 11×8 клітинок — твоя розкладка від першої клітинки.',
        OfficeLevel.modernOffice =>
          'Сучасний офіс, ергономіка і швидкий інтернет. Старт 9×5, розширення до 14×10 клітинок — простір під будь-яку розкладку.',
        OfficeLevel.techHub =>
          'Тех-хаб з неоном і топовим залізом. Старт 10×7, розширення до 16×13 клітинок — є де розгулятися.',
        OfficeLevel.campus =>
          'Розкішний кампус. Старт 12×10, розширення до 20×16 клітинок — плануй від першої до останньої клітинки.',
      };

  String get emoji => switch (this) {
        OfficeLevel.garage => '🏚️',
        OfficeLevel.smallOffice => '🏢',
        OfficeLevel.modernOffice => '🏗️',
        OfficeLevel.techHub => '⚡',
        OfficeLevel.campus => '🏛️',
      };

  int get maxAgents => switch (this) {
        OfficeLevel.garage => 3,
        OfficeLevel.smallOffice => 6,
        OfficeLevel.modernOffice => 12,
        OfficeLevel.techHub => 25,
        OfficeLevel.campus => 100,
      };

  double get speedModifier => switch (this) {
        OfficeLevel.garage => 0.75,
        OfficeLevel.smallOffice => 1.0,
        OfficeLevel.modernOffice => 1.1,
        OfficeLevel.techHub => 1.25,
        OfficeLevel.campus => 1.5,
      };

  int get upgradeCost => switch (this) {
        OfficeLevel.garage => 0,
        OfficeLevel.smallOffice => 1000,
        OfficeLevel.modernOffice => 8000,
        OfficeLevel.techHub => 50000,
        OfficeLevel.campus => 500000,
      };

  /// Base grid dimensions at purchase time (before any expansions bought).
  /// Total grid includes a 1-tile wall on each side; playable inner area is
  /// `(baseCols-2) × (baseRows-2)`.
  int get baseCols => switch (this) {
        OfficeLevel.garage => 7,
        OfficeLevel.smallOffice => 9,
        OfficeLevel.modernOffice => 11,
        OfficeLevel.techHub => 12,
        OfficeLevel.campus => 14,
      };

  int get baseRows => switch (this) {
        OfficeLevel.garage => 5,
        OfficeLevel.smallOffice => 6,
        OfficeLevel.modernOffice => 7,
        OfficeLevel.techHub => 9,
        OfficeLevel.campus => 12,
      };

  /// Ordered expansion steps for this tier. Each step either adds a column
  /// or a row (usually not both) and costs the given ₲. Steps are bought
  /// sequentially — you must buy step N before step N+1.
  List<OfficeExpansion> get expansions => switch (this) {
        OfficeLevel.garage => const [
            // base 7×5 inner 5×3=15 → 10×7 inner 8×5=40
            OfficeExpansion(deltaCols: 1, cost: 80),   // 8×5 → 18
            OfficeExpansion(deltaCols: 1, cost: 140),  // 9×5 → 21
            OfficeExpansion(deltaRows: 1, cost: 200),  // 9×6 → 28
            OfficeExpansion(deltaCols: 1, cost: 280),  // 10×6 → 32
            OfficeExpansion(deltaRows: 1, cost: 380),  // 10×7 → 40
          ],
        OfficeLevel.smallOffice => const [
            // base 9×6 inner 7×4=28 → 13×10 inner 11×8=88
            OfficeExpansion(deltaCols: 1, cost: 350),  // 10×6 → 32
            OfficeExpansion(deltaRows: 1, cost: 500),  // 10×7 → 40
            OfficeExpansion(deltaCols: 1, cost: 700),  // 11×7 → 45
            OfficeExpansion(deltaRows: 1, cost: 950),  // 11×8 → 54
            OfficeExpansion(deltaCols: 1, cost: 1250), // 12×8 → 60
            OfficeExpansion(deltaRows: 1, cost: 1600), // 12×9 → 70
            OfficeExpansion(deltaCols: 1, cost: 2000), // 13×9 → 77
            OfficeExpansion(deltaRows: 1, cost: 2500), // 13×10 → 88
          ],
        OfficeLevel.modernOffice => const [
            // base 11×7 inner 9×5=45 → 16×12 inner 14×10=140
            OfficeExpansion(deltaCols: 1, cost: 2200), // 12×7 → 50
            OfficeExpansion(deltaRows: 1, cost: 3000), // 12×8 → 60
            OfficeExpansion(deltaCols: 1, cost: 4000), // 13×8 → 66
            OfficeExpansion(deltaRows: 1, cost: 5200), // 13×9 → 77
            OfficeExpansion(deltaCols: 1, cost: 6800), // 14×9 → 84
            OfficeExpansion(deltaRows: 1, cost: 8800), // 14×10 → 96
            OfficeExpansion(deltaCols: 1, cost: 11000),// 15×10 → 104
            OfficeExpansion(deltaRows: 1, cost: 13500),// 15×11 → 117
            OfficeExpansion(deltaCols: 1, cost: 16500),// 16×11 → 126
            OfficeExpansion(deltaRows: 1, cost: 20000),// 16×12 → 140
          ],
        OfficeLevel.techHub => const [
            // base 12×9 inner 10×7=70 → 18×15 inner 16×13=208
            OfficeExpansion(deltaCols: 1, cost: 12000), // 13×9 → 77
            OfficeExpansion(deltaRows: 1, cost: 15000), // 13×10 → 88
            OfficeExpansion(deltaCols: 1, cost: 18500), // 14×10 → 96
            OfficeExpansion(deltaRows: 1, cost: 23000), // 14×11 → 108
            OfficeExpansion(deltaCols: 1, cost: 28500), // 15×11 → 117
            OfficeExpansion(deltaRows: 1, cost: 35000), // 15×12 → 130
            OfficeExpansion(deltaCols: 1, cost: 43000), // 16×12 → 140
            OfficeExpansion(deltaRows: 1, cost: 52000), // 16×13 → 154
            OfficeExpansion(deltaCols: 1, cost: 63000), // 17×13 → 165
            OfficeExpansion(deltaRows: 1, cost: 76000), // 17×14 → 180
            OfficeExpansion(deltaCols: 1, cost: 92000), // 18×14 → 192
            OfficeExpansion(deltaRows: 1, cost: 110000),// 18×15 → 208
          ],
        OfficeLevel.campus => const [
            // base 14×12 inner 12×10=120 → 22×18 inner 20×16=320
            OfficeExpansion(deltaCols: 1, cost: 90000),
            OfficeExpansion(deltaRows: 1, cost: 110000),
            OfficeExpansion(deltaCols: 1, cost: 135000),
            OfficeExpansion(deltaRows: 1, cost: 165000),
            OfficeExpansion(deltaCols: 1, cost: 200000),
            OfficeExpansion(deltaRows: 1, cost: 240000),
            OfficeExpansion(deltaCols: 1, cost: 285000),
            OfficeExpansion(deltaRows: 1, cost: 340000),
            OfficeExpansion(deltaCols: 1, cost: 400000),
            OfficeExpansion(deltaRows: 1, cost: 470000),
            OfficeExpansion(deltaCols: 1, cost: 550000),
            OfficeExpansion(deltaRows: 1, cost: 640000),
            OfficeExpansion(deltaCols: 1, cost: 740000),
            OfficeExpansion(deltaRows: 1, cost: 850000),
            OfficeExpansion(deltaCols: 1, cost: 980000),
            OfficeExpansion(deltaRows: 1, cost: 1120000),
          ],
      };

  /// Effective grid columns after applying [expansionsBought] steps (clamped
  /// to `expansions.length`).
  int effectiveCols(int expansionsBought) {
    final n = expansionsBought.clamp(0, expansions.length);
    var cols = baseCols;
    for (var i = 0; i < n; i++) {
      cols += expansions[i].deltaCols;
    }
    return cols;
  }

  int effectiveRows(int expansionsBought) {
    final n = expansionsBought.clamp(0, expansions.length);
    var rows = baseRows;
    for (var i = 0; i < n; i++) {
      rows += expansions[i].deltaRows;
    }
    return rows;
  }

  /// Playable inner tiles at the given expansion count — excludes the
  /// 1-tile wall border. Used by the UI to show "X / Y клітинок" capacity.
  int playableTiles(int expansionsBought) =>
      (effectiveCols(expansionsBought) - 2) *
      (effectiveRows(expansionsBought) - 2);

  /// How many extra expansion steps (and what cost) are needed to grow the
  /// playable inner area to at least `neededInnerCols × neededInnerRows`.
  ///
  /// Returns a plan even when zero steps are needed (extraSteps == 0). When
  /// the target exceeds this tier's max expansion capacity, [reachable] is
  /// false and the caller should treat the ghost as invalid (tooltip:
  /// "Потрібен Tier Upgrade").
  PendingExpansionPlan computeExpansionPlan(
    int currentBought,
    int neededInnerCols,
    int neededInnerRows,
  ) {
    // Translate inner target → total grid target (inner + 2 walls).
    final neededTotalCols = neededInnerCols + 2;
    final neededTotalRows = neededInnerRows + 2;

    final maxBought = expansions.length;
    var bought = currentBought.clamp(0, maxBought);
    var cumulativeCost = 0;

    while (effectiveCols(bought) < neededTotalCols ||
        effectiveRows(bought) < neededTotalRows) {
      if (bought >= maxBought) {
        return PendingExpansionPlan(
          extraSteps: bought - currentBought,
          totalCost: cumulativeCost,
          resultCols: effectiveCols(bought),
          resultRows: effectiveRows(bought),
          reachable: false,
        );
      }
      cumulativeCost += expansions[bought].cost;
      bought++;
    }

    return PendingExpansionPlan(
      extraSteps: bought - currentBought,
      totalCost: cumulativeCost,
      resultCols: effectiveCols(bought),
      resultRows: effectiveRows(bought),
      reachable: true,
    );
  }

  /// Base/max playable tiles — used for shop labels.
  int get basePlayableTiles => playableTiles(0);
  int get maxPlayableTiles => playableTiles(expansions.length);

  /// Legacy grid dims — kept as aliases to base size for any stale readers.
  int get gridCols => baseCols;
  int get gridRows => baseRows;

  /// True for tiers that are gated behind "В розробці" — visible in the
  /// upgrade UI but not purchasable yet.
  bool get isWipComingSoon => this == OfficeLevel.campus;

  OfficeLevel? get nextLevel => switch (this) {
        OfficeLevel.garage => OfficeLevel.smallOffice,
        OfficeLevel.smallOffice => OfficeLevel.modernOffice,
        OfficeLevel.modernOffice => OfficeLevel.techHub,
        OfficeLevel.techHub => OfficeLevel.campus,
        OfficeLevel.campus => null,
      };
}

/// Result of `OfficeLevel.computeExpansionPlan`. When [extraSteps] is 0 the
/// ghost fits in the current owned grid — no expansion purchase needed.
/// When [reachable] is false the ghost is outside even the max expansion of
/// the current tier and the caller should treat placement as invalid.
class PendingExpansionPlan {
  final int extraSteps;
  final int totalCost;
  final int resultCols;
  final int resultRows;
  final bool reachable;

  const PendingExpansionPlan({
    required this.extraSteps,
    required this.totalCost,
    required this.resultCols,
    required this.resultRows,
    required this.reachable,
  });

  bool get fitsInOwned => extraSteps == 0;
}

// ─── Hardware tiers ────────────────────────────────────────────────────────

enum HardwareTier {
  oldLaptop,
  basicLaptop,
  desktopPC,
  gamingPC,
  workstation,
  serverRack,
}

extension HardwareTierExt on HardwareTier {
  String get label => switch (this) {
        HardwareTier.oldLaptop => 'Старий ноутбук',
        HardwareTier.basicLaptop => 'Базовий ноутбук',
        HardwareTier.desktopPC => 'Десктоп ПК',
        HardwareTier.gamingPC => 'Ігровий ПК',
        HardwareTier.workstation => 'Робоча станція',
        HardwareTier.serverRack => 'Серверна стійка',
      };

  String get shortLabel => switch (this) {
        HardwareTier.oldLaptop => '💻🔧',
        HardwareTier.basicLaptop => '💻',
        HardwareTier.desktopPC => '🖥️',
        HardwareTier.gamingPC => '🎮',
        HardwareTier.workstation => '⚙️',
        HardwareTier.serverRack => '🖧',
      };

  double get speedModifier => switch (this) {
        HardwareTier.oldLaptop => 0.5,
        HardwareTier.basicLaptop => 0.75,
        HardwareTier.desktopPC => 1.0,
        HardwareTier.gamingPC => 1.25,
        HardwareTier.workstation => 1.5,
        HardwareTier.serverRack => 2.0,
      };

  int get cost => switch (this) {
        HardwareTier.oldLaptop => 0,
        HardwareTier.basicLaptop => 200,
        HardwareTier.desktopPC => 500,
        HardwareTier.gamingPC => 1500,
        HardwareTier.workstation => 5000,
        HardwareTier.serverRack => 15000,
      };

  HardwareTier? get nextTier => switch (this) {
        HardwareTier.oldLaptop => HardwareTier.basicLaptop,
        HardwareTier.basicLaptop => HardwareTier.desktopPC,
        HardwareTier.desktopPC => HardwareTier.gamingPC,
        HardwareTier.gamingPC => HardwareTier.workstation,
        HardwareTier.workstation => HardwareTier.serverRack,
        HardwareTier.serverRack => null,
      };
}

// ─── Agent skills ──────────────────────────────────────────────────────────

/// Agent capability skills.
///
/// Each value maps to a measurable effect on task execution:
/// * [speed] — time per task (lower wall-clock).
/// * [precision] — fewer bugs (replaces old "quality").
/// * [creativity] — crit chance on divergent task types.
/// * [insight] — capability on hard tasks; tier-bias when picking the Claude
///   model (replaces old "problemSolving").
/// * [reliability] — chance the task completes without an `incomplete` roll.
enum SkillType {
  speed,
  precision,
  creativity,
  insight,
  reliability,
}

extension SkillTypeExt on SkillType {
  String get label => switch (this) {
        SkillType.speed => 'Швидкість',
        SkillType.precision => 'Точність',
        SkillType.creativity => 'Креативність',
        SkillType.insight => 'Проникливість',
        SkillType.reliability => 'Надійність',
      };

  String get icon => switch (this) {
        SkillType.speed => '⚡',
        SkillType.precision => '🎯',
        SkillType.creativity => '💡',
        SkillType.insight => '🔮',
        SkillType.reliability => '🔒',
      };

  int get baseCost => switch (this) {
        SkillType.speed => 100,
        SkillType.precision => 150,
        SkillType.creativity => 180,
        SkillType.insight => 200,
        SkillType.reliability => 130,
      };

  /// Cost to upgrade from current level to next.
  int upgradeCost(int currentLevel) => baseCost * (currentLevel + 1);
}

// ─── Agent game data ───────────────────────────────────────────────────────

/// A single hired agent *instance*.
///
/// Multiple instances of the same [roleType] can coexist (e.g. two coders).
/// Presence in [GameState.agents] implies "hired" — there is no separate flag.
const _agentSentinel = Object();

/// Whether an agent has a physical workstation assigned in the office.
///
/// [unassigned] — newly hired; no desk yet. Coding/testing/debugging tasks
/// suffer an increased incomplete chance until the player builds and assigns
/// a Workstation Room (Build System B.1).
/// [assigned] — has a canonical or extra desk; works at full efficiency.
enum WorkplaceStatus { unassigned, assigned }

class AgentGameData {
  /// Stable unique identifier, e.g. "coder#1", "coder#2". Used as the map key
  /// in [GameState.agents] and the address for chat/dispatch.
  final String instanceId;

  /// The role this instance belongs to (e.g. "coder", "reviewer"). Links to
  /// [roleCatalog] for behavior templates, salary, and passives.
  final String roleType;

  /// Player-visible display name (e.g. "Майстер", "Майстер 2"). Editable.
  final String nickname;

  final HardwareTier hardware;
  final Map<SkillType, int> skills;

  /// Agent level (1..maxAgentLevel). Gates tasks, caps skill upgrades,
  /// grows with XP. Schema v5+.
  final int level;

  /// Experience points accumulated towards the next level. Schema v5+.
  final int xp;

  /// The backend model provider for this agent.
  final AgentProviderType provider;

  /// Optional curated-roster character id (e.g. `"andriy_coder"`) when this
  /// agent was hired through Roster v1 instead of the abstract role flow.
  /// Null for legacy hires and seeded agents. Persisted across sessions.
  final String? characterId;

  /// Custom system prompt injected before the role template when this agent
  /// was created via Custom Agent Spawn. Null for standard / roster hires.
  final String? customSystemPrompt;

  /// Personality preset key used at spawn time (e.g. "speedster", "creative").
  /// Informational — the actual effect is encoded in [skills].
  final String? personalityPreset;

  /// Whether this agent has a workstation assigned in the office.
  /// Defaults to [WorkplaceStatus.assigned] for backward-compatible seeded
  /// agents; newly hired agents should be created with [WorkplaceStatus.unassigned].
  final WorkplaceStatus workplaceStatus;

  /// Per-`taskType` completion counters. Increments only on successful
  /// outcomes (`clean` / `crit`); bug/incomplete do not count. Used by the
  /// specialization unlock mechanic (C.1) — once a counter crosses
  /// [kSpecializationThreshold] for a task type, that type joins
  /// [specializations] and grants a crit-roll bonus on matching tasks.
  final Map<String, int> taskCompletionsByType;

  /// Set of `taskType` keys this agent is specialized in. Empty for fresh
  /// agents; populated lazily as completion counters cross the threshold.
  /// Each unlocked specialization adds [kSpecializationCritBonus] to the
  /// crit roll on tasks of that type, capped at [kMaxSpecializationCritBonus].
  final Set<String> specializations;

  const AgentGameData({
    required this.instanceId,
    required this.roleType,
    required this.nickname,
    this.hardware = HardwareTier.oldLaptop,
    this.skills = const {},
    this.level = 1,
    this.xp = 0,
    this.provider = AgentProviderType.cloud,
    this.characterId,
    this.customSystemPrompt,
    this.personalityPreset,
    this.workplaceStatus = WorkplaceStatus.assigned,
    this.taskCompletionsByType = const {},
    this.specializations = const {},
  });

  /// Average skill value — purely a cosmetic summary for UI.
  /// Not used for gating (see `level`) or capability (see server's
  /// `skillsToModel` which weights skills explicitly).
  int get avgSkill {
    if (skills.isEmpty) return 0;
    return (skills.values.reduce((a, b) => a + b) / skills.length).round();
  }

  double get totalSpeedModifier => hardware.speedModifier;

  AgentGameData copyWith({
    String? nickname,
    HardwareTier? hardware,
    Map<SkillType, int>? skills,
    int? level,
    int? xp,
    AgentProviderType? provider,
    String? characterId,
    Object? customSystemPrompt = _agentSentinel,
    Object? personalityPreset = _agentSentinel,
    WorkplaceStatus? workplaceStatus,
    Map<String, int>? taskCompletionsByType,
    Set<String>? specializations,
  }) =>
      AgentGameData(
        instanceId: instanceId,
        roleType: roleType,
        nickname: nickname ?? this.nickname,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
        level: level ?? this.level,
        xp: xp ?? this.xp,
        provider: provider ?? this.provider,
        characterId: characterId ?? this.characterId,
        customSystemPrompt: identical(customSystemPrompt, _agentSentinel)
            ? this.customSystemPrompt
            : customSystemPrompt as String?,
        personalityPreset: identical(personalityPreset, _agentSentinel)
            ? this.personalityPreset
            : personalityPreset as String?,
        workplaceStatus: workplaceStatus ?? this.workplaceStatus,
        taskCompletionsByType:
            taskCompletionsByType ?? this.taskCompletionsByType,
        specializations: specializations ?? this.specializations,
      );

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'roleType': roleType,
        'nickname': nickname,
        'hardware': hardware.index,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
        'level': level,
        'xp': xp,
        'provider': provider.index,
        if (characterId != null) 'characterId': characterId,
        if (customSystemPrompt != null) 'customSystemPrompt': customSystemPrompt,
        if (personalityPreset != null) 'personalityPreset': personalityPreset,
        if (workplaceStatus != WorkplaceStatus.assigned)
          'workplaceStatus': workplaceStatus.index,
        if (taskCompletionsByType.isNotEmpty)
          'taskCompletionsByType': taskCompletionsByType,
        if (specializations.isNotEmpty)
          'specializations': specializations.toList(),
      };

  factory AgentGameData.fromJson(Map<String, dynamic> json) => AgentGameData(
        instanceId: json['instanceId'] as String,
        roleType: json['roleType'] as String,
        nickname: json['nickname'] as String? ?? '',
        hardware: HardwareTier.values[json['hardware'] as int? ?? 0],
        skills: {
          for (final e
              in (json['skills'] as Map<String, dynamic>? ?? {}).entries)
            SkillType.values[int.parse(e.key)]: e.value as int,
        },
        level: json['level'] as int? ?? 1,
        xp: json['xp'] as int? ?? 0,
        provider: AgentProviderType.values[json['provider'] as int? ?? 0],
        characterId: json['characterId'] as String?,
        customSystemPrompt: json['customSystemPrompt'] as String?,
        personalityPreset: json['personalityPreset'] as String?,
        workplaceStatus: WorkplaceStatus.values[
            json['workplaceStatus'] as int? ?? WorkplaceStatus.assigned.index],
        taskCompletionsByType: {
          for (final e
              in (json['taskCompletionsByType'] as Map<String, dynamic>? ?? {})
                  .entries)
            e.key: (e.value as num).toInt(),
        },
        specializations: {
          for (final v in (json['specializations'] as List<dynamic>? ?? const []))
            v as String,
        },
      );
}

/// Number of successful task completions on a single `taskType` required
/// to unlock a specialization for that type. Tuned for the C.1 keystone
/// slice — high enough that fresh hires don't trivially earn it, low enough
/// that an active player feels the unlock within a session arc.
const int kSpecializationThreshold = 20;

/// Crit-chance bonus granted by a single matching specialization on a
/// divergent task. Capped at [kMaxSpecializationCritBonus] when summed
/// across multiple matching specializations (defensive — current design
/// has at most one match per task, but the cap protects future stacking).
const double kSpecializationCritBonus = 0.15;

/// Hard cap on aggregate specialization-driven crit bonus, per
/// [docs/ROADMAP.md](../../docs/ROADMAP.md) C.1 risk-watch ("cap on a
/// reasonable maximum, not 2×"). Keeps grown agents distinctly better
/// without trivializing the roll.
const double kMaxSpecializationCritBonus = 0.30;

/// Success-chance bonus granted per accumulated lesson on any task.
/// 0.5% per lesson → 20 lessons = +10% success (= −10% incomplete rate).
const double kLessonSuccessBonusPerLesson = 0.005;

/// Hard cap on the aggregate lesson-driven success bonus. Keeps the mechanic
/// visible without trivializing the roll for agents with hundreds of lessons.
const double kMaxLessonSuccessBonus = 0.10;

/// Crit-chance bonus granted per 5 completed tasks on architectural tasks.
/// 1% per 5 tasks → 75 tasks = +15% crit on architecture rolls.
const double kProjectMemoryBonusPerTasks = 0.01;

/// Number of tasks completed per 1% crit bonus increment on architecture rolls.
const int kProjectMemoryTasksPerStep = 5;

/// Hard cap on project memory depth bonus. Keeps the mechanic visible without
/// making aged agents trivial on architectural reasoning.
const double kMaxProjectMemoryBonus = 0.15;


// ─── Agent passives ───────────────────────────────────────────────────────

class AgentPassive {
  final String icon;
  final String name;
  final String nameUk;
  final String description;

  const AgentPassive({
    required this.icon,
    required this.name,
    required this.nameUk,
    required this.description,
  });
}

// ─── Role catalog ──────────────────────────────────────────────────────────

/// One entry per role type. Defines cost to hire a NEW instance of that role,
/// default nickname, passive trait, and the specialization blurb.
class RoleCatalogEntry {
  /// Role type identifier, e.g. "coder", "manager", "reviewer".
  final String roleType;

  /// Base display name — applied to the first instance (later instances get " 2", " 3"…).
  final String baseName;

  /// Ukrainian role label (e.g. "Розробник").
  final String role;

  /// Specialization — what this role is good at (Ukrainian blurb for UI).
  final String specialization;

  /// Weaknesses — what this role is bad at (Ukrainian blurb for UI).
  final String weakness;

  /// Cost (₲) to hire each new instance.
  final int hireCost;

  /// Salary per instance (currently informational).
  final int salary;

  /// Whether a single instance of this role is expected (manager is singleton).
  final bool singleton;

  /// Number of instances of this role seeded into a fresh game state.
  /// Defaults to 0; override for starter roles (manager, coder).
  final int defaultSeedCount;

  /// Default provider for newly hired instances (0=cloud/Claude, 1=local/Gemini).
  /// Defaults to 0 (Claude).
  final int defaultProvider;

  /// Ukrainian personal-name pool. New seeds / custom spawns pick a random name
  /// from here (excluding names already used on the team). Pool intentionally
  /// thematic per role (martial for security, lyrical for artist, etc.) so the
  /// generated team reads like a curated cast, not random noise.
  final List<String> nicknamePool;

  final AgentPassive passive;

  const RoleCatalogEntry({
    required this.roleType,
    required this.baseName,
    required this.role,
    required this.specialization,
    required this.weakness,
    required this.hireCost,
    required this.salary,
    required this.passive,
    this.nicknamePool = const [],
    this.singleton = false,
    this.defaultSeedCount = 0,
    this.defaultProvider = 0,
  });
}

const roleCatalog = <RoleCatalogEntry>[
  RoleCatalogEntry(
    roleType: 'manager',
    baseName: 'Капітан',
    role: 'Координатор',
    specialization: 'Координує команду, розбиває задачі, розподіляє роботу.',
    weakness: 'Не пише код сам — тільки делегує.',
    hireCost: 0,
    salary: 50,
    singleton: true,
    defaultSeedCount: 1,
    nicknamePool: ['Остап', 'Святослав', 'Орест', 'Левко'],
    passive: AgentPassive(
      icon: '🧠',
      name: 'Tactical Mind',
      nameUk: 'Тактичний розум',
      description:
          'Оптимально розподіляє задачі — команда працює швидше коли він на чолі.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'coder',
    baseName: 'Майстер',
    role: 'Розробник',
    specialization: 'Програмування — реалізація фіч, фікс багів, рефакторинг.',
    weakness: 'Дизайн UI/UX та глибокий security-аудит — не його коник.',
    hireCost: 0,
    salary: 40,
    defaultSeedCount: 1,
    nicknamePool: ['Юрій', 'Степан', 'Ярема', 'Влад'],
    passive: AgentPassive(
      icon: '⌨️',
      name: 'Speed Typing',
      nameUk: 'Швидкодрук',
      description:
          'Пише код з нелюдською швидкістю — менше помилок, більше фіч за раунд.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'tech-lead',
    baseName: 'Архітект',
    role: 'Технічний лідер',
    specialization: 'Системна архітектура, тех-рішення, вибір бібліотек.',
    weakness: 'Деталі low-level реалізації та pixel-perfect UI.',
    hireCost: 500,
    salary: 80,
    nicknamePool: ['Олег', 'Михайло', 'Ігор', 'Антін'],
    passive: AgentPassive(
      icon: '🏗️',
      name: 'System Vision',
      nameUk: 'Системне бачення',
      description:
          'Бачить повну картину проєкту — його архітектурні рішення економлять час.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'reviewer',
    baseName: 'Детектив',
    role: 'Рецензент',
    specialization: 'Ревʼю коду, пошук анти-патернів і прихованих багів.',
    weakness: 'Не пише й не змінює код — тільки оглядає.',
    hireCost: 300,
    salary: 40,
    nicknamePool: ['Тарас', 'Лука', 'Ілля', 'Захар'],
    passive: AgentPassive(
      icon: '🔍',
      name: 'Bug Radar',
      nameUk: 'Радар багів',
      description:
          'Інтуїтивно відчуває приховані баги — знаходить проблеми ще до тестування.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'tester',
    baseName: 'Крашер',
    role: 'Контроль якості',
    specialization: 'Юніт-, віджет- та інтеграційні тести, edge-кейси.',
    weakness: 'Архітектурні рішення й візуальний дизайн — поза зоною.',
    hireCost: 300,
    salary: 40,
    nicknamePool: ['Петро', 'Кирило', 'Гліб', 'Микита'],
    passive: AgentPassive(
      icon: '👆',
      name: 'Swipe Master',
      nameUk: 'Майстер свайпів',
      description:
          'Має особливий хист до тестування UI — свайпи, жести та анімації не вислизнуть.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'security',
    baseName: 'Страж',
    role: 'Безпека',
    specialization: 'Аудит безпеки — автентифікація, шифрування, валідація.',
    weakness: 'Не вміє в polish фіч та візуал.',
    hireCost: 800,
    salary: 60,
    nicknamePool: ['Роман', 'Євген', 'Володимир', 'Адам'],
    passive: AgentPassive(
      icon: '🛡️',
      name: 'Firewall',
      nameUk: 'Фаєрвол',
      description:
          'Невидимий щит — автоматично виявляє вразливості OWASP Top 10 у коді.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'ui-ux-designer',
    baseName: 'Піксельник',
    role: 'UI/UX',
    specialization: 'UI/UX — компоновки, юзабіліті, візуальна консистентність.',
    weakness: 'Бекенд-архітектура й алгоритми — не профіль.',
    hireCost: 400,
    salary: 45,
    nicknamePool: ['Маркіян', 'Северин', 'Юрко', 'Стах'],
    passive: AgentPassive(
      icon: '🎨',
      name: 'Pixel Perfect',
      nameUk: 'Ідеальний піксель',
      description:
          'Бачить кожен піксель — інтерфейси виходять бездоганними з першого разу.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'llm-specialist',
    baseName: 'Промптер',
    role: 'LLM-спеціаліст',
    specialization:
        'Claude Code та Claude Agent SDK — архітектура агентів, prompt engineering, tool use, prompt caching, MCP сервери, hooks та slash commands.',
    weakness: 'Без LLM-задач у беклозі простоює — звичайний CRUD не його профіль.',
    hireCost: 1200,
    salary: 100,
    nicknamePool: ['Артур', 'Платон', 'Серафим', 'Філіп'],
    passive: AgentPassive(
      icon: '🤖',
      name: 'Prompt Whisperer',
      nameUk: 'Шептун промптів',
      description:
          'Знає Claude SDK напамʼять — оптимізує токени, кеш та інструменти, скорочуючи цикли інтеграції AI-фіч.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'game-designer',
    baseName: 'Левелер',
    role: 'Геймдизайнер',
    specialization:
        'Дизайн механік, прогресії, економіки, F2P-петель та marketplace; балансування чисел і декомпозиція великих цілей на MVP/v1/v2.',
    weakness: 'Сам код не пише — здає спеки і дифи в roadmap, реалізацію передає coder/tech-lead.',
    hireCost: 600,
    salary: 70,
    nicknamePool: ['Денис', 'Влас', 'Тимко', 'Іларіон'],
    passive: AgentPassive(
      icon: '🎲',
      name: 'Game Sense',
      nameUk: 'Чуття гри',
      description:
          'Бачить, що в петлі залипає, а що дратує — підказує, які механіки скоротити чи відполірувати, поки вони не з’їли retention.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'strategy-keeper',
    baseName: 'Неповертайло',
    role: 'Стратег',
    specialization:
        'Reality-check проти drift — звіряє git-історію з ROADMAP, ставить Fermi-питання до оптимістичних дедлайнів, класифікує поза-планові ідеї (polish / off-plan / pivot) і аудитує сам план на невалідовані припущення.',
    weakness: 'Код не пише — здає вердикти зі scope і точкові дифи у STRATEGY/ROADMAP, які власник застосовує сам.',
    hireCost: 1000,
    salary: 90,
    nicknamePool: ['Богуслав', 'Аркадій', 'Лаврін', 'Гордій'],
    passive: AgentPassive(
      icon: '🧭',
      name: 'Reality Check',
      nameUk: 'Перевірка реальністю',
      description:
          'Тримає курс — раз на період звіряє останні коміти з roadmap і повідомляє, де доки розійшлися з реальністю, поки drift не став хронічним.',
    ),
  ),
  RoleCatalogEntry(
    roleType: 'character-artist',
    baseName: 'Піксельмейстер',
    role: 'Художник',
    specialization:
        'Створює нових персонажів з нуля — спрайти, скін-палітри, анімаційні сети, NPC. Працює із 7-колірною палітрою та 16×32 sprite sheet.',
    weakness:
        'Не дизайнить екрани і UI-флоу — це робота UI/UX дизайнера. Без задач на новий контент простоює.',
    hireCost: 500,
    salary: 55,
    nicknamePool: ['Лесь', 'Ярослав', 'Корній', 'Сава'],
    passive: AgentPassive(
      icon: '🎨',
      name: 'Color Soul',
      nameUk: 'Кольорова душа',
      description:
          'Відчуває характер персонажа через палітру — нові скіни і NPC народжуються з першого ескізу без переробок.',
    ),
  ),
];

RoleCatalogEntry? roleCatalogFor(String roleType) {
  for (final entry in roleCatalog) {
    if (entry.roleType == roleType) return entry;
  }
  return null;
}

// ─── Role-biased initial skills ───────────────────────────────────────────

/// Initial skill distribution for a newly hired agent.
///
/// Each role has its own bias so agents start differentiated instead of
/// uniform 1/1/1/1/1. Totals ~13 points (avg 2.6 per skill) — well below
/// `skillCap(1) == 12`, leaving room for gold-paid upgrades.
///
/// Unknown roleType falls back to a balanced 2-point baseline across all
/// skills.
Map<SkillType, int> initialSkillsForRole(String roleType) {
  return switch (roleType) {
    'coder' => const {
        SkillType.speed: 3,
        SkillType.precision: 3,
        SkillType.creativity: 2,
        SkillType.insight: 3,
        SkillType.reliability: 2,
      },
    'tech-lead' => const {
        SkillType.speed: 2,
        SkillType.precision: 3,
        SkillType.creativity: 3,
        SkillType.insight: 4,
        SkillType.reliability: 2,
      },
    'reviewer' => const {
        SkillType.speed: 1,
        SkillType.precision: 5,
        SkillType.creativity: 1,
        SkillType.insight: 4,
        SkillType.reliability: 3,
      },
    'tester' => const {
        SkillType.speed: 3,
        SkillType.precision: 2,
        SkillType.creativity: 1,
        SkillType.insight: 2,
        SkillType.reliability: 5,
      },
    'security' => const {
        SkillType.speed: 1,
        SkillType.precision: 4,
        SkillType.creativity: 2,
        SkillType.insight: 4,
        SkillType.reliability: 3,
      },
    'ui-ux-designer' => const {
        SkillType.speed: 2,
        SkillType.precision: 3,
        SkillType.creativity: 5,
        SkillType.insight: 1,
        SkillType.reliability: 1,
      },
    'manager' => const {
        SkillType.speed: 2,
        SkillType.precision: 2,
        SkillType.creativity: 2,
        SkillType.insight: 3,
        SkillType.reliability: 3,
      },
    'llm-specialist' => const {
        SkillType.speed: 2,
        SkillType.precision: 4,
        SkillType.creativity: 4,
        SkillType.insight: 5,
        SkillType.reliability: 3,
      },
    'game-designer' => const {
        SkillType.speed: 1,
        SkillType.precision: 2,
        SkillType.creativity: 4,
        SkillType.insight: 5,
        SkillType.reliability: 1,
      },
    'strategy-keeper' => const {
        SkillType.speed: 1,
        SkillType.precision: 4,
        SkillType.creativity: 1,
        SkillType.insight: 5,
        SkillType.reliability: 3,
      },
    'character-artist' => const {
        SkillType.speed: 1,
        SkillType.precision: 4,
        SkillType.creativity: 6,
        SkillType.insight: 1,
        SkillType.reliability: 1,
      },
    _ => const {
        SkillType.speed: 2,
        SkillType.precision: 2,
        SkillType.creativity: 2,
        SkillType.insight: 2,
        SkillType.reliability: 2,
      },
  };
}

// ─── Instance-ID helpers ──────────────────────────────────────────────────

/// Extract the role type from an instanceId like "coder#2" → "coder".
/// Returns the input unchanged if there's no "#".
String roleTypeFromInstanceId(String instanceId) {
  final hash = instanceId.indexOf('#');
  return hash > 0 ? instanceId.substring(0, hash) : instanceId;
}

/// Build the next available instanceId for [roleType] given the set of
/// currently used IDs. Numbering is stable and compact: picks the lowest
/// positive integer not already in use.
String nextInstanceId(String roleType, Iterable<String> existingIds) {
  final used = <int>{};
  for (final id in existingIds) {
    if (!id.startsWith('$roleType#')) continue;
    final suffix = id.substring(roleType.length + 1);
    final n = int.tryParse(suffix);
    if (n != null) used.add(n);
  }
  var n = 1;
  while (used.contains(n)) {
    n++;
  }
  return '$roleType#$n';
}

/// Default nickname for the Nth instance of a role (1-indexed).
/// First instance gets the bare [baseName], later ones get "baseName 2", "baseName 3"…
String defaultNicknameFor(RoleCatalogEntry role, int ordinal) {
  return ordinal <= 1 ? role.baseName : '${role.baseName} $ordinal';
}

/// Random Ukrainian personal name for a new instance of [roleType]. Picks
/// uniformly from the role's [RoleCatalogEntry.nicknamePool], excluding any
/// nicknames already used on the team so duplicates don't clutter the roster.
///
/// Falls back to [defaultNicknameFor] (class label) when the role is unknown
/// or the pool is empty / fully consumed by exclusions. Pass [seed] for
/// deterministic output in tests.
String pickRoleNickname(
  String roleType, {
  Iterable<String> excludeNicknames = const [],
  int? seed,
}) {
  final role = roleCatalogFor(roleType);
  if (role == null) return roleType;
  if (role.nicknamePool.isEmpty) return role.baseName;

  final usedLower = {for (final n in excludeNicknames) n.toLowerCase()};
  final available =
      role.nicknamePool.where((n) => !usedLower.contains(n.toLowerCase())).toList();
  final pool = available.isNotEmpty ? available : role.nicknamePool;
  final rng = seed != null ? Random(seed) : Random();
  return pool[rng.nextInt(pool.length)];
}

// ─── Donation packages ─────────────────────────────────────────────────────

class DonationPackage {
  final int grymni;
  final String price;
  final String label;
  final bool isBestValue;

  const DonationPackage({
    required this.grymni,
    required this.price,
    required this.label,
    this.isBestValue = false,
  });
}

const donationPackages = <DonationPackage>[
  DonationPackage(grymni: 100, price: '\$0.99', label: 'Жменька'),
  DonationPackage(grymni: 500, price: '\$3.99', label: 'Конверт'),
  DonationPackage(grymni: 1500, price: '\$9.99', label: 'Пачка', isBestValue: true),
  DonationPackage(grymni: 5000, price: '\$29.99', label: 'Чемодан'),
  DonationPackage(grymni: 15000, price: '\$79.99', label: 'Сейф'),
];

// ─── Nickname generation ──────────────────────────────────────────────────

const _nickPrefixes = [
  'Shadow', 'Cyber', 'Neo', 'Dark', 'Neon', 'Pixel', 'Byte', 'Code',
  'Stack', 'Debug', 'Null', 'Root', 'Admin', 'Ghost', 'Flux', 'Glitch',
  'Turbo', 'Hyper', 'Ultra', 'Mega', 'Crypto', 'Logic', 'Delta', 'Zero',
  'Alpha', 'Omega', 'Blaze', 'Storm', 'Frost', 'Volt',
];

const _nickSuffixes = [
  'Coder', 'Dev', 'Hacker', 'Master', 'Hunter', 'Wolf', 'Fox', 'Hawk',
  'Ninja', 'Blade', 'Storm', 'Viper', 'Ghost', 'Knight', 'Mage', 'Lord',
  'X', 'Prime', 'Core', 'Node', 'Bit', 'Hex', 'Forge', 'Craft',
  'Pulse', 'Wave', 'Dash', 'Link', 'Spark', 'Flux',
];

const _nickSeparators = ['_', '.', '-', 'x', 'X', ''];

String generateGameNickname(int seed) {
  final r = seed.abs();
  final prefix = _nickPrefixes[r % _nickPrefixes.length];
  final suffix = _nickSuffixes[(r ~/ 31) % _nickSuffixes.length];
  final sep = _nickSeparators[(r ~/ 97) % _nickSeparators.length];
  final num = (r % 100).toString().padLeft(2, '0');
  // Mix styles: sometimes xXNameXx, sometimes Name_42, sometimes just PrefixSuffix
  final style = (r ~/ 7) % 4;
  return switch (style) {
    0 => '$prefix$sep$suffix',
    1 => '$prefix$sep$suffix$num',
    2 => 'xX${prefix}_${suffix}Xx',
    _ => '$prefix$num',
  };
}

/// How many free nickname changes before grymni cost kicks in.
const freeNicknameChanges = 3;

/// Cost per nickname change after free ones are used up.
const nicknameChangeCost = 200;

// ─── Cosmetic items ───────────────────────────────────────────────────────

enum CosmeticType {
  skin,
  nicknameDecor,
  avatarFrame,
  titleBadge,
  sendButtonStyle,
}

extension CosmeticTypeExt on CosmeticType {
  String get label => switch (this) {
        CosmeticType.skin => 'Скіни',
        CosmeticType.nicknameDecor => 'Декор нікнейму',
        CosmeticType.avatarFrame => 'Рамки аватара',
        CosmeticType.titleBadge => 'Титули',
        CosmeticType.sendButtonStyle => 'Кнопка «Надіслати»',
      };

  String get icon => switch (this) {
        CosmeticType.skin => '👔',
        CosmeticType.nicknameDecor => '✏️',
        CosmeticType.avatarFrame => '🖼️',
        CosmeticType.titleBadge => '🏷️',
        CosmeticType.sendButtonStyle => '📮',
      };
}

class CosmeticItem {
  final String id;
  final CosmeticType type;
  final String name;
  final int cost;
  final String preview;

  const CosmeticItem({
    required this.id,
    required this.type,
    required this.name,
    required this.cost,
    required this.preview,
  });
}

/// Apply a nickname decoration to a name.
String applyNicknameDecor(String nickname, String? decorId) {
  if (decorId == null || nickname.isEmpty) return nickname;
  final decor = cosmeticCatalog
      .where((c) => c.id == decorId && c.type == CosmeticType.nicknameDecor)
      .firstOrNull;
  if (decor == null) return nickname;
  return decor.preview.replaceAll('{n}', nickname);
}

const cosmeticCatalog = <CosmeticItem>[
  // ── Skins ──
  CosmeticItem(id: 'skin_casual', type: CosmeticType.skin, name: 'Кежуал', cost: 500, preview: '👕'),
  CosmeticItem(id: 'skin_corporate', type: CosmeticType.skin, name: 'Корпоратив', cost: 800, preview: '👔'),
  CosmeticItem(id: 'skin_hacker', type: CosmeticType.skin, name: 'Хакер', cost: 1200, preview: '🥷'),
  CosmeticItem(id: 'skin_creative', type: CosmeticType.skin, name: 'Креатив', cost: 1000, preview: '🎨'),
  CosmeticItem(id: 'skin_retro', type: CosmeticType.skin, name: 'Ретро', cost: 1500, preview: '📼'),
  CosmeticItem(id: 'skin_cyberpunk', type: CosmeticType.skin, name: 'Кіберпанк', cost: 2000, preview: '🌃'),
  CosmeticItem(id: 'skin_cozy', type: CosmeticType.skin, name: 'Затишок', cost: 1000, preview: '🧶'),

  // ── Nickname decorations ──
  CosmeticItem(id: 'decor_stars', type: CosmeticType.nicknameDecor, name: 'Зірки', cost: 150, preview: '★ {n} ★'),
  CosmeticItem(id: 'decor_swords', type: CosmeticType.nicknameDecor, name: 'Мечі', cost: 200, preview: '⚔ {n} ⚔'),
  CosmeticItem(id: 'decor_angles', type: CosmeticType.nicknameDecor, name: 'Кутики', cost: 100, preview: '« {n} »'),
  CosmeticItem(id: 'decor_fire', type: CosmeticType.nicknameDecor, name: 'Вогонь', cost: 300, preview: '🔥 {n} 🔥'),
  CosmeticItem(id: 'decor_lightning', type: CosmeticType.nicknameDecor, name: 'Блискавка', cost: 250, preview: '⚡ {n} ⚡'),
  CosmeticItem(id: 'decor_diamonds', type: CosmeticType.nicknameDecor, name: 'Діаманти', cost: 400, preview: '💎 {n} 💎'),
  CosmeticItem(id: 'decor_crown', type: CosmeticType.nicknameDecor, name: 'Корона', cost: 500, preview: '👑 {n}'),
  CosmeticItem(id: 'decor_skull', type: CosmeticType.nicknameDecor, name: 'Череп', cost: 350, preview: '☠ {n} ☠'),
  CosmeticItem(id: 'decor_brackets', type: CosmeticType.nicknameDecor, name: 'Код', cost: 200, preview: '[ {n} ]'),
  CosmeticItem(id: 'decor_glitch', type: CosmeticType.nicknameDecor, name: 'Глітч', cost: 600, preview: '▓ {n} ▓'),

  // ── Avatar frames ──
  CosmeticItem(id: 'frame_neon', type: CosmeticType.avatarFrame, name: 'Неон', cost: 300, preview: '💠'),
  CosmeticItem(id: 'frame_gold', type: CosmeticType.avatarFrame, name: 'Золото', cost: 500, preview: '🥇'),
  CosmeticItem(id: 'frame_fire', type: CosmeticType.avatarFrame, name: 'Полумʼя', cost: 800, preview: '🔥'),
  CosmeticItem(id: 'frame_glitch', type: CosmeticType.avatarFrame, name: 'Глітч', cost: 1000, preview: '📺'),
  CosmeticItem(id: 'frame_pixel', type: CosmeticType.avatarFrame, name: 'Піксель', cost: 400, preview: '🟩'),
  CosmeticItem(id: 'frame_matrix', type: CosmeticType.avatarFrame, name: 'Матриця', cost: 700, preview: '🖥️'),

  // ── Title badges ──
  CosmeticItem(id: 'title_rookie', type: CosmeticType.titleBadge, name: 'Новачок', cost: 0, preview: '🌱 Новачок'),
  CosmeticItem(id: 'title_pro', type: CosmeticType.titleBadge, name: 'Про', cost: 500, preview: '⭐ Про'),
  CosmeticItem(id: 'title_hacker', type: CosmeticType.titleBadge, name: 'Хакер', cost: 800, preview: '💀 Хакер'),
  CosmeticItem(id: 'title_sensei', type: CosmeticType.titleBadge, name: 'Сенсей', cost: 1200, preview: '🥋 Сенсей'),
  CosmeticItem(id: 'title_legend', type: CosmeticType.titleBadge, name: 'Легенда', cost: 3000, preview: '🏆 Легенда'),
  CosmeticItem(id: 'title_glitch', type: CosmeticType.titleBadge, name: 'Глітч', cost: 2000, preview: '👾 Глітч'),
  CosmeticItem(id: 'title_ceo', type: CosmeticType.titleBadge, name: 'CEO', cost: 5000, preview: '💼 CEO'),
  CosmeticItem(id: 'title_pixel_god', type: CosmeticType.titleBadge, name: 'Pixel God', cost: 10000, preview: '✨ Pixel God'),

  // ── Send button styles ──
  // Hand-crafted variants for the chat "send" button. Free default +
  // three premium designs — the most expensive items in the catalog.
  CosmeticItem(id: 'send_classic', type: CosmeticType.sendButtonStyle, name: 'Класичний', cost: 0, preview: '➤'),
  CosmeticItem(id: 'send_neon_pulse', type: CosmeticType.sendButtonStyle, name: 'Неоновий Пульс', cost: 6000, preview: '✺'),
  CosmeticItem(id: 'send_gold_rocket', type: CosmeticType.sendButtonStyle, name: 'Золота Ракета', cost: 12000, preview: '🚀'),
  CosmeticItem(id: 'send_pixel_arcade', type: CosmeticType.sendButtonStyle, name: 'Піксельна Аркада', cost: 20000, preview: '▶'),
  CosmeticItem(id: 'send_liquid_glass', type: CosmeticType.sendButtonStyle, name: 'Рідке Скло', cost: 25000, preview: '🫧'),
  CosmeticItem(id: 'send_cloud_drift', type: CosmeticType.sendButtonStyle, name: 'Хмарний Дрейф', cost: 18000, preview: '🌬'),
];

CosmeticItem? cosmeticById(String id) {
  for (final item in cosmeticCatalog) {
    if (item.id == id) return item;
  }
  return null;
}

// ─── Furniture system ────────────────────────────────────────────────────

enum FurnitureType {
  coffeeTable,
  snackTable,
  decoration,
  storage,
  lounge,
}

extension FurnitureTypeExt on FurnitureType {
  String get label => switch (this) {
        FurnitureType.coffeeTable => 'Кавові столики',
        FurnitureType.snackTable => 'Столики з їжею',
        FurnitureType.decoration => 'Декор',
        FurnitureType.storage => 'Зберігання',
        FurnitureType.lounge => 'Зона відпочинку',
      };

  String get icon => switch (this) {
        FurnitureType.coffeeTable => '☕',
        FurnitureType.snackTable => '🍪',
        FurnitureType.decoration => '🌿',
        FurnitureType.storage => '📚',
        FurnitureType.lounge => '🛋️',
      };
}

class FurnitureItem {
  final String id;
  final FurnitureType type;
  final String name;
  final int cost;
  final String description;
  final int widthTiles;
  final int heightTiles;
  final bool blocksPath;

  const FurnitureItem({
    required this.id,
    required this.type,
    required this.name,
    required this.cost,
    required this.description,
    this.widthTiles = 1,
    this.heightTiles = 1,
    this.blocksPath = true,
  });
}

class FurniturePlacement {
  final String itemId;
  final int col;
  final int row;

  const FurniturePlacement({
    required this.itemId,
    required this.col,
    required this.row,
  });

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'col': col,
        'row': row,
      };

  factory FurniturePlacement.fromJson(Map<String, dynamic> json) =>
      FurniturePlacement(
        itemId: json['itemId'] as String,
        col: json['col'] as int,
        row: json['row'] as int,
      );
}

const furnitureCatalog = <FurnitureItem>[
  // ── Гаражний стартер ──
  // Free starter props seeded into a fresh garage so the office isn't empty
  // out of the gate. Remove via the furniture editor once real rooms replace
  // them.
  FurnitureItem(
    id: 'old_desk',
    type: FurnitureType.coffeeTable,
    name: 'Пошарпаний стіл',
    cost: 0,
    description: 'Хитається, але тримає ноутбук. З чогось треба починати.',
  ),
  FurnitureItem(
    id: 'stool',
    type: FurnitureType.lounge,
    name: 'Табуретка',
    cost: 0,
    description: 'Без спинки, без любові. Але працює.',
  ),
  FurnitureItem(
    id: 'cardboard_boxes',
    type: FurnitureType.storage,
    name: 'Коробки',
    cost: 0,
    description: 'Стопка картонних коробок. Щось у них напевно є.',
  ),

  // ── Кавові столики ──
  FurnitureItem(
    id: 'coffee_table_basic',
    type: FurnitureType.coffeeTable,
    name: 'Простий столик',
    cost: 300,
    description: 'Звичайний кавовий столик. Тримає чашку — і то добре.',
  ),
  FurnitureItem(
    id: 'coffee_table_premium',
    type: FurnitureType.coffeeTable,
    name: 'Преміум столик',
    cost: 800,
    description: 'Елегантний столик з підставкою для ноутбука.',
  ),
  FurnitureItem(
    id: 'coffee_table_designer',
    type: FurnitureType.coffeeTable,
    name: 'Дизайнерський столик',
    cost: 2000,
    description: 'Авторський столик з вбудованою бездротовою зарядкою.',
  ),

  // ── Столики з їжею ──
  FurnitureItem(
    id: 'snack_table_basic',
    type: FurnitureType.snackTable,
    name: 'Стіл з печивом',
    cost: 200,
    description: 'Простий стіл з печивом для команди. Мотивація +1.',
  ),
  FurnitureItem(
    id: 'snack_table_candy',
    type: FurnitureType.snackTable,
    name: 'Стіл з цукерками',
    cost: 500,
    description: 'Стіл повний різних цукерок. Цукровий рай.',
  ),
  FurnitureItem(
    id: 'snack_table_buffet',
    type: FurnitureType.snackTable,
    name: 'Шведський стіл',
    cost: 1500,
    description: 'Повноцінний шведський стіл — піца, суші, все що душа забажає.',
    widthTiles: 2,
  ),

  // ── Декор ──
  FurnitureItem(
    id: 'plant_small',
    type: FurnitureType.decoration,
    name: 'Невелика рослина',
    cost: 100,
    description: 'Маленький вазон на стіл. Додає затишку.',
    blocksPath: false,
  ),
  FurnitureItem(
    id: 'plant_large',
    type: FurnitureType.decoration,
    name: 'Велика рослина',
    cost: 300,
    description: 'Висока рослина в горщику. Очищає повітря та думки.',
  ),
  FurnitureItem(
    id: 'poster_motivational',
    type: FurnitureType.decoration,
    name: 'Мотиваційний постер',
    cost: 150,
    description: '«Keep calm and git push» — класика жанру.',
    blocksPath: false,
  ),
  FurnitureItem(
    id: 'poster_code',
    type: FurnitureType.decoration,
    name: 'Код-постер',
    cost: 200,
    description: 'Постер з красивим кодом. Натхнення для справжніх девів.',
    blocksPath: false,
  ),
  FurnitureItem(
    id: 'water_cooler',
    type: FurnitureType.decoration,
    name: 'Кулер з водою',
    cost: 250,
    description: 'Кулер з водою — місце для розмов та пліток.',
  ),

  // ── Зберігання ──
  FurnitureItem(
    id: 'bookshelf',
    type: FurnitureType.storage,
    name: 'Книжкова шафа',
    cost: 500,
    description: 'Шафа з технічною літературою. «Clean Code» на почесному місці.',
  ),
  FurnitureItem(
    id: 'filing_cabinet',
    type: FurnitureType.storage,
    name: 'Картотека',
    cost: 350,
    description: 'Старомодна картотека. Тут зберігаються секрети проєкту.',
  ),

  // ── Зона відпочинку ──
  FurnitureItem(
    id: 'beanbag',
    type: FurnitureType.lounge,
    name: 'Крісло-мішок',
    cost: 400,
    description: 'Мʼяке крісло-мішок. Ідеальне для брейнштормів.',
  ),
  FurnitureItem(
    id: 'couch_small',
    type: FurnitureType.lounge,
    name: 'Маленький диван',
    cost: 1000,
    description: 'Компактний диванчик для швидкого відпочинку між спринтами.',
    widthTiles: 2,
  ),
];

FurnitureItem? furnitureById(String id) {
  for (final item in furnitureCatalog) {
    if (item.id == id) return item;
  }
  return null;
}

// ─── Office rooms ──────────────────────────────────────────────────────────

/// Two structural classes that share the same `RoomType` enum but render and
/// validate differently:
///
/// - **Room** — enclosed unit with its own walls/border. Initiates and
///   receives adjacency pairs. Examples: workstation, openSpace, serverRoom.
/// - **Zone** — open feature area without walls (think gym floor, pool deck,
///   lounge corner). Renders with a dashed border instead of a solid one.
///   Only *receives* adjacency bonuses — never initiates a pair. Examples:
///   lounge, gym, pool, cinema, miniGolf.
///
/// The split is structural, not cosmetic — adjacency engine, ghost preview
/// and BuildMenu badge all branch on `category`.
enum RoomCategory { room, zone }

/// Room types share a single enum so their `.index` keeps a stable JSON
/// encoding across schema versions. New values MUST be appended to the end
/// to avoid renumbering historical saves.
enum RoomType {
  // ── Rooms (enclosed, own walls) ──
  workstation,
  breakRoom,
  meetingRoom,
  serverRoom,
  // ── Zones (open feature areas, no walls) ──
  lounge,
  gym,
  cinema,
  pool,
  miniGolf,
  // ── Appended in B.1 Stage 3b ──
  openSpace,
  // ── Appended in B.1 Stage 3b polish round (2026-05-11) ──
  teamFloor,
}

extension RoomTypeExt on RoomType {
  RoomCategory get category => switch (this) {
        RoomType.workstation ||
        RoomType.breakRoom ||
        RoomType.meetingRoom ||
        RoomType.serverRoom ||
        RoomType.openSpace ||
        RoomType.teamFloor =>
          RoomCategory.room,
        RoomType.lounge ||
        RoomType.gym ||
        RoomType.cinema ||
        RoomType.pool ||
        RoomType.miniGolf =>
          RoomCategory.zone,
      };

  String get nameUk => switch (this) {
        RoomType.workstation => 'Воркстейшн',
        RoomType.breakRoom => 'Кімната відпочинку',
        RoomType.meetingRoom => 'Переговорна',
        RoomType.serverRoom => 'Серверна',
        RoomType.openSpace => 'Опен-спейс',
        RoomType.teamFloor => 'Командний поверх',
        RoomType.lounge => 'Рекреація',
        RoomType.gym => 'Спортзал',
        RoomType.cinema => 'Кінозал',
        RoomType.pool => 'Басейн',
        RoomType.miniGolf => 'Міні-гольф',
      };

  String get description => switch (this) {
        RoomType.workstation =>
          'Один робочий стіл для агента без закріпленого місця.',
        RoomType.breakRoom =>
          'Агенти відновлюються довше — менше безцільного блукання офісом.',
        RoomType.meetingRoom =>
          'Координаційний центр менеджера. Поряд з воркстейшном — −10 % затримки dispatch.',
        RoomType.serverRoom =>
          'Все прискорюється на 10 %. Ефективна лише поряд з воркстейшнами.',
        RoomType.openSpace =>
          'Відкритий простір на 6 столів. Ефективніший за шість окремих воркстейшнів.',
        RoomType.teamFloor =>
          'Командний open-plan поверх на 12 столів. Кістяк продуктового офісу.',
        RoomType.lounge =>
          'Зона. Відкрита рекреаційна зона. Агенти прямують сюди у вільний час.',
        RoomType.gym => 'Зона. Морал-буст для всієї команди.',
        RoomType.cinema => 'Зона. Кіно-перегляди підвищують командний дух.',
        RoomType.pool => 'Зона. Найкращий spot відпочинку між спринтами.',
        RoomType.miniGolf => 'Зона. Невеликі змагання між колегами.',
      };

  String get icon => switch (this) {
        RoomType.workstation => '💻',
        RoomType.breakRoom => '🛋️',
        RoomType.meetingRoom => '🗣️',
        RoomType.serverRoom => '🖥️',
        RoomType.openSpace => '🏢',
        RoomType.teamFloor => '🏬',
        RoomType.lounge => '🛹',
        RoomType.gym => '🏋️',
        RoomType.cinema => '🎬',
        RoomType.pool => '🏊',
        RoomType.miniGolf => '⛳',
      };

  int get widthTiles => switch (this) {
        RoomType.workstation => 2,
        RoomType.breakRoom => 2,
        RoomType.meetingRoom => 3,
        RoomType.serverRoom => 2,
        RoomType.openSpace => 5,
        RoomType.teamFloor => 7,
        RoomType.lounge => 3,
        RoomType.gym => 4,
        RoomType.cinema => 5,
        RoomType.pool => 5,
        RoomType.miniGolf => 5,
      };

  int get heightTiles => switch (this) {
        RoomType.workstation => 2,
        RoomType.breakRoom => 2,
        RoomType.meetingRoom => 2,
        RoomType.serverRoom => 2,
        RoomType.openSpace => 4,
        RoomType.teamFloor => 5,
        RoomType.lounge => 2,
        RoomType.gym => 3,
        RoomType.cinema => 3,
        RoomType.pool => 4,
        RoomType.miniGolf => 3,
      };

  int get cost => switch (this) {
        RoomType.workstation => 400,
        RoomType.breakRoom => 500,
        RoomType.meetingRoom => 900,
        RoomType.serverRoom => 1500,
        RoomType.openSpace => 1800,
        RoomType.teamFloor => 4500,
        RoomType.lounge => 700,
        RoomType.gym => 2500,
        RoomType.cinema => 3500,
        RoomType.pool => 5000,
        RoomType.miniGolf => 4000,
      };

  int get maxPerOffice => switch (this) {
        RoomType.workstation => 8,
        RoomType.breakRoom => 4,
        RoomType.meetingRoom => 3,
        RoomType.serverRoom => 3,
        RoomType.openSpace => 3,
        RoomType.teamFloor => 2,
        RoomType.lounge => 3,
        RoomType.gym => 1,
        RoomType.cinema => 1,
        RoomType.pool => 1,
        RoomType.miniGolf => 1,
      };

  /// True for high-tier feature Zones (1-per-office signature pieces) gated
  /// behind office upgrades. Garage tier hides them in BuildMenu.
  bool get isLuxury => switch (this) {
        RoomType.gym ||
        RoomType.cinema ||
        RoomType.pool ||
        RoomType.miniGolf =>
          true,
        _ => false,
      };
}

/// 2D tile coordinate (col, row). Used for [PlacedRoom.closedDoors].
typedef DoorTile = ({int col, int row});

class PlacedRoom {
  final String id;
  final RoomType type;
  final int col;
  final int row;

  /// Rotation in degrees, 0/90/180/270. v6+.
  final int rotation;

  /// Optional override of the tier-default wall skin. Null inherits.
  final String? wallSkinId;

  /// Optional override of the tier-default floor skin. Null inherits.
  final String? floorSkinId;

  /// Tile coords on this room's border that the player has explicitly closed
  /// (sealed the auto-gap). Geometric doors form whenever two rooms share an
  /// edge; this set carves exceptions back out. Persists across reloads.
  final Set<DoorTile> closedDoors;

  const PlacedRoom({
    required this.id,
    required this.type,
    required this.col,
    required this.row,
    this.rotation = 0,
    this.wallSkinId,
    this.floorSkinId,
    this.closedDoors = const {},
  });

  /// Footprint width, accounting for 90°/270° rotation that swaps axes.
  int get footprintWidth =>
      (rotation == 90 || rotation == 270) ? type.heightTiles : type.widthTiles;

  /// Footprint height, accounting for rotation.
  int get footprintHeight =>
      (rotation == 90 || rotation == 270) ? type.widthTiles : type.heightTiles;

  int get right => col + footprintWidth;
  int get bottom => row + footprintHeight;

  PlacedRoom copyWith({
    int? col,
    int? row,
    int? rotation,
    String? wallSkinId,
    String? floorSkinId,
    Set<DoorTile>? closedDoors,
    bool clearWallSkin = false,
    bool clearFloorSkin = false,
  }) =>
      PlacedRoom(
        id: id,
        type: type,
        col: col ?? this.col,
        row: row ?? this.row,
        rotation: rotation ?? this.rotation,
        wallSkinId: clearWallSkin ? null : (wallSkinId ?? this.wallSkinId),
        floorSkinId: clearFloorSkin ? null : (floorSkinId ?? this.floorSkinId),
        closedDoors: closedDoors ?? this.closedDoors,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'col': col,
        'row': row,
        if (rotation != 0) 'rotation': rotation,
        if (wallSkinId != null) 'wallSkinId': wallSkinId,
        if (floorSkinId != null) 'floorSkinId': floorSkinId,
        if (closedDoors.isNotEmpty)
          'closedDoors': [
            for (final d in closedDoors) {'col': d.col, 'row': d.row},
          ],
      };

  factory PlacedRoom.fromJson(Map<String, dynamic> json) => PlacedRoom(
        id: json['id'] as String,
        type: RoomType.values[json['type'] as int],
        col: json['col'] as int,
        row: json['row'] as int,
        rotation: json['rotation'] as int? ?? 0,
        wallSkinId: json['wallSkinId'] as String?,
        floorSkinId: json['floorSkinId'] as String?,
        closedDoors: {
          for (final d in (json['closedDoors'] as List<dynamic>? ?? []))
            (
              col: (d as Map<String, dynamic>)['col'] as int,
              row: d['row'] as int,
            ),
        },
      );
}

/// A linear corridor segment — sequence of grid tiles agents walk through.
/// Modelled separately from [PlacedRoom] because corridors are 1-tile-wide
/// linear paths, not rectangular bounding boxes.
class PlacedCorridor {
  final String id;

  /// Ordered tiles forming the corridor. Each tile is `(col, row)`.
  final List<({int col, int row})> tiles;

  /// True for 2-tile-wide variant (gives a small agent speed bonus, costs more).
  final bool wide;

  /// Optional skin override; null inherits the tier theme.
  final String? skinId;

  const PlacedCorridor({
    required this.id,
    required this.tiles,
    this.wide = false,
    this.skinId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'tiles': [
          for (final t in tiles) {'col': t.col, 'row': t.row},
        ],
        if (wide) 'wide': true,
        if (skinId != null) 'skinId': skinId,
      };

  factory PlacedCorridor.fromJson(Map<String, dynamic> json) => PlacedCorridor(
        id: json['id'] as String,
        tiles: [
          for (final t in (json['tiles'] as List<dynamic>? ?? []))
            (
              col: (t as Map<String, dynamic>)['col'] as int,
              row: t['row'] as int,
            ),
        ],
        wide: json['wide'] as bool? ?? false,
        skinId: json['skinId'] as String?,
      );
}

// ─── Room templates (one room with pre-baked furniture, single price) ──────

/// A pre-furnished room template — ships a [baseRoom] together with a fixed
/// set of furniture items already laid out inside, sold as a bundle. Distinct
/// from the legacy `OfficePreset` which bundled multiple rooms.
class RoomTemplate {
  final String id;
  final String name;
  final String description;
  final RoomType baseRoom;

  /// Pre-baked furniture, positioned relative to the room's top-left corner.
  final List<TemplateFurnitureSlot> furniture;

  /// Bundle discount on top of the raw component sum, in percent (0–100).
  final int discountPercent;

  const RoomTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.baseRoom,
    required this.furniture,
    this.discountPercent = 8,
  });

  /// Sum of base room cost + each furniture item cost (without discount).
  int rawCost(List<FurnitureItem> catalog) {
    var total = baseRoom.cost;
    for (final slot in furniture) {
      final item = _findFurniture(catalog, slot.furnitureId);
      if (item != null) total += item.cost;
    }
    return total;
  }

  /// Final price after applying [discountPercent].
  int bundleCost(List<FurnitureItem> catalog) =>
      (rawCost(catalog) * (100 - discountPercent) / 100).round();
}

class TemplateFurnitureSlot {
  final String furnitureId;
  final int colOffset;
  final int rowOffset;

  const TemplateFurnitureSlot({
    required this.furnitureId,
    required this.colOffset,
    required this.rowOffset,
  });
}

FurnitureItem? _findFurniture(List<FurnitureItem> catalog, String id) {
  for (final item in catalog) {
    if (item.id == id) return item;
  }
  return null;
}

/// Pre-furnished room bundles. Each template ships a base [RoomType] with a
/// curated set of furniture pre-positioned inside, sold at a single price
/// with a small bundle discount. Picked from a section in BuildMenu and
/// placed onto the grid as one atomic transaction.
const roomTemplateCatalog = <RoomTemplate>[
  RoomTemplate(
    id: 'tpl_cozy_workstation',
    name: 'Затишне робоче місце',
    description: 'Базове робоче місце з кавовим столиком, рослиною і постером.',
    baseRoom: RoomType.workstation,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'coffee_table_basic', colOffset: 0, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_small', colOffset: 1, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'poster_motivational', colOffset: 0, rowOffset: 0),
    ],
  ),
  RoomTemplate(
    id: 'tpl_productive_pod',
    name: 'Продуктивний підрозділ',
    description: 'Робоче місце для глибокої роботи: преміум-стіл, шафа, велика рослина.',
    baseRoom: RoomType.workstation,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'coffee_table_premium', colOffset: 0, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'bookshelf', colOffset: 1, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_large', colOffset: 1, rowOffset: 0),
    ],
  ),
  RoomTemplate(
    id: 'tpl_snack_lounge',
    name: 'Снек-зона',
    description: 'Куток відпочинку зі смачним столом, кріслом-мішком і рослиною.',
    baseRoom: RoomType.breakRoom,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'snack_table_basic', colOffset: 0, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'beanbag', colOffset: 1, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_small', colOffset: 1, rowOffset: 0),
    ],
  ),
  RoomTemplate(
    id: 'tpl_boardroom_classic',
    name: 'Класична переговорна',
    description: 'Переговорний пункт із преміум-столом, постером і рослиною.',
    baseRoom: RoomType.meetingRoom,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'coffee_table_premium', colOffset: 1, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'poster_code', colOffset: 0, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'plant_large', colOffset: 2, rowOffset: 0),
    ],
  ),
  RoomTemplate(
    id: 'tpl_server_sanctuary',
    name: 'Серверне святилище',
    description: 'Серверна з картотекою для документації і коробками для запчастин.',
    baseRoom: RoomType.serverRoom,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'filing_cabinet', colOffset: 0, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'cardboard_boxes', colOffset: 1, rowOffset: 0),
    ],
  ),
  // ── Work-focused templates ─────────────────────────────────────────────
  // Richer work-room presets that ship with motivational/utility furniture
  // pre-laid out, so the player can drop in a "real" work room without
  // hand-placing every prop. Multi-workstation Open Space requires a model
  // extension (`RoomTemplate` currently holds one `baseRoom`) and is tracked
  // as Stage 3b in ROADMAP.md.
  RoomTemplate(
    id: 'tpl_starter_cube',
    name: 'Стартовий куб',
    description:
        'Робоче місце для новачка: мотиваційний постер, вазон і кулер з водою.',
    baseRoom: RoomType.workstation,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'poster_motivational', colOffset: 0, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'plant_small', colOffset: 1, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'water_cooler', colOffset: 1, rowOffset: 1),
    ],
  ),
  RoomTemplate(
    id: 'tpl_deep_focus',
    name: 'Глибокий фокус',
    description:
        'Преміум робоче місце: дизайнерський столик, шафа з технічкою, велика рослина.',
    baseRoom: RoomType.workstation,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'coffee_table_designer', colOffset: 0, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'bookshelf', colOffset: 1, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_large', colOffset: 1, rowOffset: 0),
    ],
    discountPercent: 12,
  ),
  RoomTemplate(
    id: 'tpl_team_hub',
    name: 'Команд-хаб',
    description:
        'Переговорна для командної роботи: шафа з документами, картотека, велика рослина.',
    baseRoom: RoomType.meetingRoom,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'bookshelf', colOffset: 0, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'filing_cabinet', colOffset: 1, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_large', colOffset: 2, rowOffset: 0),
      TemplateFurnitureSlot(
          furnitureId: 'poster_code', colOffset: 0, rowOffset: 0),
    ],
    discountPercent: 10,
  ),
  RoomTemplate(
    id: 'tpl_skater_lounge',
    name: 'Скейт-куток',
    description: 'Зона відпочинку з диваном, кріслом-мішком і рослиною.',
    baseRoom: RoomType.lounge,
    furniture: [
      TemplateFurnitureSlot(
          furnitureId: 'couch_small', colOffset: 0, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'beanbag', colOffset: 2, rowOffset: 1),
      TemplateFurnitureSlot(
          furnitureId: 'plant_small', colOffset: 2, rowOffset: 0),
    ],
  ),
];

RoomTemplate? roomTemplateById(String id) {
  for (final t in roomTemplateCatalog) {
    if (t.id == id) return t;
  }
  return null;
}

// ─── Adjacency engine ─────────────────────────────────────────────────────

/// True when [a] and [b] share at least one wall tile (bounding boxes touch
/// edge-to-edge, not corner-to-corner).
bool areRoomsAdjacent(PlacedRoom a, PlacedRoom b) {
  final xOverlap = a.col < b.right && b.col < a.right;
  final yOverlap = a.row < b.bottom && b.row < a.bottom;
  return (a.right == b.col || b.right == a.col) && yOverlap ||
      (a.bottom == b.row || b.bottom == a.row) && xOverlap;
}

/// Returns the net adjacency bonus [%] that placing [newType] at ([col],[row])
/// with [rotation] would earn from [existingRooms].
///
/// Positive = speed/morale boost, negative = penalty. Returns null when there
/// is no adjacency effect (callers can skip rendering the label).
///
/// Pairs (B.1 Stage 3b taxonomy):
/// - workstation  ↔ serverRoom   → +5 % speed
/// - workstation  ↔ meetingRoom  → +5 % efficiency
/// - workstation  ↔ openSpace    → +5 % efficiency
/// - openSpace    ↔ meetingRoom  → +5 % efficiency
/// - breakRoom    → lounge       → +5 % morale (one-way, lounge is a Zone)
/// - breakRoom    → gym          → +5 % morale (one-way, gym is a Zone)
/// - serverRoom placed >8 tiles from every workstation → −5 % penalty
///
/// Zones (lounge, gym, cinema, pool, miniGolf) only *receive* pairs — they
/// never initiate adjacency, by `category == zone` guard.
int? computeAdjacencyBonusPercent(
  RoomType newType,
  int col,
  int row,
  int rotation,
  List<PlacedRoom> existingRooms,
) {
  final ghost = PlacedRoom(
    id: '__ghost__',
    type: newType,
    col: col,
    row: row,
    rotation: rotation,
  );

  int bonus = 0;

  for (final existing in existingRooms) {
    if (!areRoomsAdjacent(ghost, existing)) continue;

    bonus += _adjacencyContribution(newType, existing.type);
  }

  // serverRoom far from every desk-hub → cable-cost penalty.
  if (newType == RoomType.serverRoom && existingRooms.isNotEmpty) {
    final ghostCx = col + ghost.footprintWidth / 2.0;
    final ghostCy = row + ghost.footprintHeight / 2.0;
    final hasNearbyHub = existingRooms.any((r) {
      if (r.type != RoomType.workstation &&
          r.type != RoomType.openSpace &&
          r.type != RoomType.teamFloor) {
        return false;
      }
      final rcx = r.col + r.footprintWidth / 2.0;
      final rcy = r.row + r.footprintHeight / 2.0;
      return (rcx - ghostCx).abs() + (rcy - ghostCy).abs() <= 8;
    });
    if (!hasNearbyHub) bonus -= 5;
  }

  return bonus == 0 ? null : bonus;
}

/// Single source of truth for adjacency-pair contributions. Returns the bonus
/// the *new* room earns from being adjacent to an *existing* room.
///
/// One-way receive: a Zone never initiates, so when [newType] is a Zone we
/// look up what pair-bonus would have applied if a Room *received* from it,
/// flipping the direction. The result is the same number, attributed once.
int _adjacencyContribution(RoomType newType, RoomType existing) {
  // Zones don't initiate adjacency pairs — they only receive. Flip the
  // direction so the Room side becomes the initiator. Guard against the
  // zone-to-zone case (no pair possible) to keep recursion finite.
  if (newType.category == RoomCategory.zone) {
    if (existing.category == RoomCategory.zone) return 0;
    return _adjacencyContribution(existing, newType);
  }

  // All desk-bearing rooms count as a "workstation hub" for adjacency.
  // teamFloor is the biggest and inherits every workstation/openSpace pair.
  const deskHubs = <RoomType>{
    RoomType.workstation,
    RoomType.openSpace,
    RoomType.teamFloor,
  };

  // Workstation / openSpace / teamFloor pairs (symmetric within the hub set).
  if (deskHubs.contains(newType)) {
    if (existing == RoomType.serverRoom) return 5;
    if (existing == RoomType.meetingRoom) return 5;
    // Adjacent desk-hubs reinforce each other (openSpace ↔ workstation, etc.)
    // — but a hub never pairs with itself (no double-counting of own type).
    if (newType != existing && deskHubs.contains(existing)) return 5;
    return 0;
  }

  // Server room pairs.
  if (newType == RoomType.serverRoom) {
    if (deskHubs.contains(existing)) return 5;
    return 0;
  }

  // Meeting room pairs.
  if (newType == RoomType.meetingRoom) {
    if (deskHubs.contains(existing)) return 5;
    return 0;
  }

  // Break room initiates one-way bonuses to Zones (lounge, gym).
  if (newType == RoomType.breakRoom) {
    if (existing == RoomType.lounge) return 5;
    if (existing == RoomType.gym) return 5;
    return 0;
  }

  return 0;
}

// ─── Wall / floor skin packs ───────────────────────────────────────────────

/// A purchasable cosmetic pack that overrides the tier-default wall colours
/// for a single placed room. Floors live in a parallel [FloorSkinPack] catalog.
class WallSkinPack {
  final String id;
  final String name;
  final String description;
  final int cost;

  /// Hex-encoded colour tokens. Painter consumes these in place of the tier
  /// theme's `wallBase` / `wallTop` / `wallInner`.
  final int wallBase;
  final int wallTop;
  final int wallInner;

  const WallSkinPack({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.wallBase,
    required this.wallTop,
    required this.wallInner,
  });
}

class FloorSkinPack {
  final String id;
  final String name;
  final String description;
  final int cost;

  final int floorDark;
  final int floorLight;
  final int floorGrid;

  const FloorSkinPack({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.floorDark,
    required this.floorLight,
    required this.floorGrid,
  });
}

/// Free "Classic" wall skin — matches each tier's default palette.
const kWallSkinFreeId = 'classic_wall';

/// Free "Classic" floor skin — matches each tier's default palette.
const kFloorSkinFreeId = 'classic_floor';

const wallSkinPackCatalog = <WallSkinPack>[
  WallSkinPack(
    id: 'classic_wall',
    name: 'Класик',
    description: 'Стандартне оздоблення стін вашого офісного рівня.',
    cost: 0,
    wallBase: 0xFF1A1A26,
    wallTop: 0xFF252538,
    wallInner: 0xFF161624,
  ),
  WallSkinPack(
    id: 'brick_wall',
    name: 'Цегляна кладка',
    description: 'Індустріальний стиль — оголена цегла з патиною.',
    cost: 500,
    wallBase: 0xFF3D1A0A,
    wallTop: 0xFF5C2B14,
    wallInner: 0xFF2A1008,
  ),
  WallSkinPack(
    id: 'concrete_wall',
    name: 'Бетон',
    description: 'Мінімалістичний raw-бетон — лофт-атмосфера.',
    cost: 700,
    wallBase: 0xFF2E2E2E,
    wallTop: 0xFF404040,
    wallInner: 0xFF1E1E1E,
  ),
  WallSkinPack(
    id: 'cyberpunk_wall',
    name: 'Кіберпанк',
    description: 'Неонові акцентні смуги на вугільно-чорній підлозі.',
    cost: 1000,
    wallBase: 0xFF0D0D1A,
    wallTop: 0xFF1A003A,
    wallInner: 0xFF060610,
  ),
];

const floorSkinPackCatalog = <FloorSkinPack>[
  FloorSkinPack(
    id: 'classic_floor',
    name: 'Класик',
    description: 'Стандартна підлога вашого офісного рівня.',
    cost: 0,
    floorDark: 0xFF131318,
    floorLight: 0xFF17171E,
    floorGrid: 0xFF1C1C26,
  ),
  FloorSkinPack(
    id: 'parquet_floor',
    name: 'Паркет',
    description: 'Тепле деревʼяне покриття — затишний стиль.',
    cost: 500,
    floorDark: 0xFF2A1A0A,
    floorLight: 0xFF3A2414,
    floorGrid: 0xFF1E1008,
  ),
  FloorSkinPack(
    id: 'marble_floor',
    name: 'Мармур',
    description: 'Елегантна мармурова плитка — преміум-відчуття.',
    cost: 800,
    floorDark: 0xFF1E2228,
    floorLight: 0xFF2A3038,
    floorGrid: 0xFF141820,
  ),
  FloorSkinPack(
    id: 'neon_floor',
    name: 'Неонова сітка',
    description: 'Матова підлога з яскравими неоновими лініями.',
    cost: 1100,
    floorDark: 0xFF080818,
    floorLight: 0xFF0C0C20,
    floorGrid: 0xFF001A40,
  ),
];

WallSkinPack? wallSkinPackById(String id) {
  for (final p in wallSkinPackCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

FloorSkinPack? floorSkinPackById(String id) {
  for (final p in floorSkinPackCatalog) {
    if (p.id == id) return p;
  }
  return null;
}

// ─── Game state ────────────────────────────────────────────────────────────

class GameState {
  /// Current on-disk schema version. Bump this constant whenever the
  /// serialised shape changes in a breaking way.
  ///
  /// v6 — adds Build System v2: PlacedRoom rotation + per-room skin overrides,
  /// PlacedCorridor list, owned wall/floor skin pack sets.
  static const int currentSchemaVersion = 6;

  /// The schema version this instance was created with (persisted in JSON).
  final int schemaVersion;

  final int grymni;
  final OfficeLevel officeLevel;

  /// Number of grid-expansion steps purchased at the current [officeLevel].
  /// Reset to 0 on tier upgrade. Clamped at runtime to
  /// `officeLevel.expansions.length`.
  final int officeExpansions;

  final Map<String, AgentGameData> agents;
  final int totalEarned;
  final int totalSpent;

  /// Player nickname (Latin, game-style).
  final String nickname;

  /// How many times the player has changed their nickname.
  final int nicknameChangesUsed;

  /// IDs of owned cosmetic items.
  final Set<String> ownedCosmetics;

  /// Currently equipped cosmetics: type index → cosmetic ID.
  final Map<int, String> equippedCosmetics;

  /// Theme ownership, active theme, and per-theme customisations.
  final ThemeState themeState;

  /// Purchased furniture items: itemId → total copies bought (not placed).
  /// Use [furnitureAvailable] to know how many are ready to place.
  final Map<String, int> furnitureInventory;

  /// IDs of furniture items the player owns at least one copy of.
  Set<String> get ownedFurniture =>
      furnitureInventory.entries
          .where((e) => e.value > 0)
          .map((e) => e.key)
          .toSet();

  /// How many copies of [itemId] are in inventory (bought but not yet placed).
  int furnitureAvailable(String itemId) {
    final total = furnitureInventory[itemId] ?? 0;
    final placed = placedFurniture.where((p) => p.itemId == itemId).length;
    return (total - placed).clamp(0, total);
  }

  /// Placed furniture items with their grid positions.
  final List<FurniturePlacement> placedFurniture;

  /// Placed office rooms (Build Mode).
  final List<PlacedRoom> placedRooms;

  /// Placed corridors connecting rooms (Build System v2). v6+.
  final List<PlacedCorridor> placedCorridors;

  /// IDs of purchased wall skin packs (Build System v2). v6+.
  final Set<String> ownedWallSkinPacks;

  /// IDs of purchased floor skin packs (Build System v2). v6+.
  final Set<String> ownedFloorSkinPacks;

  /// Epoch millis of the last local mutation. Drives last-write-wins sync
  /// between devices — the server only accepts state with a newer timestamp
  /// than what it already holds.
  final int updatedAt;

  const GameState({
    this.schemaVersion = currentSchemaVersion,
    this.grymni = 500,
    this.officeLevel = OfficeLevel.garage,
    this.officeExpansions = 0,
    this.agents = const {},
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.nickname = '',
    this.nicknameChangesUsed = 0,
    this.ownedCosmetics = const {},
    this.equippedCosmetics = const {},
    this.themeState = const ThemeState(),
    this.furnitureInventory = const {},
    this.placedFurniture = const [],
    this.placedRooms = const [],
    this.placedCorridors = const [],
    this.ownedWallSkinPacks = const {},
    this.ownedFloorSkinPacks = const {},
    this.updatedAt = 0,
  });

  /// Number of hired instances (presence in the map == hired).
  int get hiredCount => agents.length;

  /// Whether there is free room in the office for another instance.
  bool get canHireMore => hiredCount < officeLevel.maxAgents;

  /// Every hired instanceId (ordered by insertion).
  List<String> get hiredAgentIds => agents.keys.toList();

  /// Instances belonging to a given role type.
  List<AgentGameData> instancesOfRole(String roleType) => [
        for (final a in agents.values)
          if (a.roleType == roleType) a,
      ];

  /// How many instances of [roleType] are currently hired.
  int roleCount(String roleType) => instancesOfRole(roleType).length;

  /// Whether the next nickname change is free.
  bool get isNicknameChangeFree => nicknameChangesUsed < freeNicknameChanges;

  /// Cost of the next nickname change (0 if still free).
  int get nextNicknameChangeCost =>
      isNicknameChangeFree ? 0 : nicknameChangeCost;

  /// Get equipped cosmetic ID for a given type.
  String? equippedFor(CosmeticType type) => equippedCosmetics[type.index];

  /// Display nickname with decorations applied.
  String get displayNickname =>
      applyNicknameDecor(nickname, equippedFor(CosmeticType.nicknameDecor));

  /// Effective grid columns = base + expansions bought at current tier.
  int get gridCols => officeLevel.effectiveCols(officeExpansions);

  /// Effective grid rows = base + expansions bought at current tier.
  int get gridRows => officeLevel.effectiveRows(officeExpansions);

  /// Currently playable inner tile count.
  int get playableTiles => officeLevel.playableTiles(officeExpansions);

  /// Max playable tiles if every expansion for this tier is bought.
  int get maxPlayableTilesAtTier => officeLevel.maxPlayableTiles;

  /// The next expansion step to be bought at the current tier, or null if
  /// the tier is fully expanded.
  OfficeExpansion? get nextExpansion {
    final steps = officeLevel.expansions;
    return officeExpansions < steps.length ? steps[officeExpansions] : null;
  }

  /// Whether the current tier is fully expanded (no more steps to buy).
  bool get isOfficeFullyExpanded =>
      officeExpansions >= officeLevel.expansions.length;

  GameState copyWith({
    int? schemaVersion,
    int? grymni,
    OfficeLevel? officeLevel,
    int? officeExpansions,
    Map<String, AgentGameData>? agents,
    int? totalEarned,
    int? totalSpent,
    String? nickname,
    int? nicknameChangesUsed,
    Set<String>? ownedCosmetics,
    Map<int, String>? equippedCosmetics,
    ThemeState? themeState,
    Map<String, int>? furnitureInventory,
    List<FurniturePlacement>? placedFurniture,
    List<PlacedRoom>? placedRooms,
    List<PlacedCorridor>? placedCorridors,
    Set<String>? ownedWallSkinPacks,
    Set<String>? ownedFloorSkinPacks,
    int? updatedAt,
  }) =>
      GameState(
        schemaVersion: schemaVersion ?? this.schemaVersion,
        grymni: grymni ?? this.grymni,
        officeLevel: officeLevel ?? this.officeLevel,
        officeExpansions: officeExpansions ?? this.officeExpansions,
        agents: agents ?? this.agents,
        totalEarned: totalEarned ?? this.totalEarned,
        totalSpent: totalSpent ?? this.totalSpent,
        nickname: nickname ?? this.nickname,
        nicknameChangesUsed: nicknameChangesUsed ?? this.nicknameChangesUsed,
        ownedCosmetics: ownedCosmetics ?? this.ownedCosmetics,
        equippedCosmetics: equippedCosmetics ?? this.equippedCosmetics,
        themeState: themeState ?? this.themeState,
        furnitureInventory: furnitureInventory ?? this.furnitureInventory,
        placedFurniture: placedFurniture ?? this.placedFurniture,
        placedRooms: placedRooms ?? this.placedRooms,
        placedCorridors: placedCorridors ?? this.placedCorridors,
        ownedWallSkinPacks: ownedWallSkinPacks ?? this.ownedWallSkinPacks,
        ownedFloorSkinPacks: ownedFloorSkinPacks ?? this.ownedFloorSkinPacks,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  GameState removeCorridor(String corridorId) => copyWith(
    placedCorridors: placedCorridors.where((c) => c.id != corridorId).toList(),
  );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'grymni': grymni,
        'officeLevel': officeLevel.index,
        'officeExpansions': officeExpansions,
        'agents': {
          for (final e in agents.entries) e.key: e.value.toJson(),
        },
        'totalEarned': totalEarned,
        'totalSpent': totalSpent,
        'nickname': nickname,
        'nicknameChangesUsed': nicknameChangesUsed,
        'ownedCosmetics': ownedCosmetics.toList(),
        'equippedCosmetics': {
          for (final e in equippedCosmetics.entries)
            e.key.toString(): e.value,
        },
        'themeState': themeState.toJson(),
        'furnitureInventory': furnitureInventory,
        'placedFurniture': [
          for (final p in placedFurniture) p.toJson(),
        ],
        'placedRooms': [
          for (final r in placedRooms) r.toJson(),
        ],
        'placedCorridors': [
          for (final c in placedCorridors) c.toJson(),
        ],
        'ownedWallSkinPacks': ownedWallSkinPacks.toList(),
        'ownedFloorSkinPacks': ownedFloorSkinPacks.toList(),
        'updatedAt': updatedAt,
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    // Load raw then apply in-flight migrations before the real constructor.
    var level = OfficeLevel.values[json['officeLevel'] as int? ?? 0];
    var expansions = json['officeExpansions'] as int? ?? 0;
    var rooms = [
      for (final r in (json['placedRooms'] as List<dynamic>?) ?? [])
        PlacedRoom.fromJson(r as Map<String, dynamic>),
    ];
    var furniture = [
      for (final p in (json['placedFurniture'] as List<dynamic>?) ?? [])
        FurniturePlacement.fromJson(p as Map<String, dynamic>),
    ];
    var corridors = [
      for (final c in (json['placedCorridors'] as List<dynamic>?) ?? [])
        PlacedCorridor.fromJson(c as Map<String, dynamic>),
    ];

    // Clamp expansions to the number this tier actually supports.
    final maxSteps = level.expansions.length;
    if (expansions < 0) expansions = 0;
    if (expansions > maxSteps) expansions = maxSteps;

    // Drop rooms/furniture/corridors that no longer fit in the effective grid
    // (post migration — e.g. v3 → v4 grids may have shrunk).
    final gCols = level.effectiveCols(expansions);
    final gRows = level.effectiveRows(expansions);
    rooms = rooms
        .where((r) =>
            r.col >= 1 &&
            r.row >= 1 &&
            r.col + r.footprintWidth <= gCols - 1 &&
            r.row + r.footprintHeight <= gRows - 1)
        .toList();
    furniture = furniture
        .where((p) => p.col < gCols - 1 && p.row < gRows - 1)
        .toList();
    corridors = corridors
        .where((c) => c.tiles.every((t) =>
            t.col >= 1 &&
            t.row >= 1 &&
            t.col < gCols - 1 &&
            t.row < gRows - 1))
        .toList();

    return GameState(
        schemaVersion: json['schemaVersion'] as int? ?? 1,
        grymni: json['grymni'] as int? ?? 500,
        officeLevel: level,
        officeExpansions: expansions,
        agents: {
          for (final e
              in (json['agents'] as Map<String, dynamic>? ?? {}).entries)
            e.key: AgentGameData.fromJson(e.value as Map<String, dynamic>),
        },
        totalEarned: json['totalEarned'] as int? ?? 0,
        totalSpent: json['totalSpent'] as int? ?? 0,
        nickname: json['nickname'] as String? ?? '',
        nicknameChangesUsed: json['nicknameChangesUsed'] as int? ?? 0,
        ownedCosmetics: {
          for (final id in (json['ownedCosmetics'] as List<dynamic>?) ?? [])
            id as String,
        },
        equippedCosmetics: {
          for (final e
              in (json['equippedCosmetics'] as Map<String, dynamic>? ?? {})
                  .entries)
            int.parse(e.key): e.value as String,
        },
        themeState: json['themeState'] != null
            ? ThemeState.fromJson(json['themeState'] as Map<String, dynamic>)
            : const ThemeState(),
        furnitureInventory: () {
          // v7+: map format. Fallback: migrate old list → qty 1 each.
          final newFmt = json['furnitureInventory'] as Map<String, dynamic>?;
          if (newFmt != null) {
            return {for (final e in newFmt.entries) e.key: e.value as int};
          }
          return {
            for (final id in (json['ownedFurniture'] as List<dynamic>?) ?? [])
              id as String: 1,
          };
        }(),
        placedFurniture: furniture,
        placedRooms: rooms,
        placedCorridors: corridors,
        ownedWallSkinPacks: {
          for (final id
              in (json['ownedWallSkinPacks'] as List<dynamic>?) ?? [])
            id as String,
        },
        ownedFloorSkinPacks: {
          for (final id
              in (json['ownedFloorSkinPacks'] as List<dynamic>?) ?? [])
            id as String,
        },
        updatedAt: json['updatedAt'] as int? ?? 0,
      );
  }

  String encode() => jsonEncode(toJson());

  /// Decode a persisted game state. Saves from older schemas (without a
  /// [schemaVersion] key, or with a lower version) are rejected so the
  /// caller falls back to [GameState.initial] — the app currently makes
  /// no effort to migrate pre-v2 data.
  factory GameState.decode(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final version = json['schemaVersion'] as int? ?? 1;
    // Accept v2 (empty placedRooms), v3 (no officeExpansions), v4, v5 (no
    // FacilitatorStyle), and v6 (no corridors / skin packs / room rotation).
    // Reject older/unknown.
    if (version < 2 || version > currentSchemaVersion) {
      throw const FormatException('Incompatible game state schema');
    }
    final state = GameState.fromJson(json);
    // Silent-migration path: fromJson filled defaults for any missing fields,
    // so the in-memory state is semantically at the current schema. Normalize
    // schemaVersion so a server-sourced older state isn't re-persisted with a
    // stale version — otherwise load() would trigger the reset toast on every
    // subsequent launch.
    return state.schemaVersion == currentSchemaVersion
        ? state
        : state.copyWith(schemaVersion: currentSchemaVersion);
  }

  /// Create default starting state: seed instances per role defaultSeedCount.
  factory GameState.initial() {
    final agents = <String, AgentGameData>{};
    for (final role in roleCatalog) {
      for (var i = 1; i <= role.defaultSeedCount; i++) {
        final id = nextInstanceId(role.roleType, agents.keys);
        final used = agents.values.map((a) => a.nickname);
        agents[id] = AgentGameData(
          instanceId: id,
          roleType: role.roleType,
          nickname: pickRoleNickname(role.roleType, excludeNicknames: used),
          hardware: HardwareTier.oldLaptop,
          skills: initialSkillsForRole(role.roleType),
        );
      }
    }
    // Generate a random starter nickname
    final seed = DateTime.now().microsecondsSinceEpoch;
    return GameState(
      grymni: 500,
      officeLevel: OfficeLevel.garage,
      agents: agents,
      nickname: generateGameNickname(seed),
      ownedCosmetics: {'title_rookie'}, // Free starter title
      furnitureInventory: {'old_desk': 1, 'stool': 1, 'cardboard_boxes': 1},
      // Garage base grid is 7×5 (inner cols 1..5, rows 1..3). Pre-place the
      // starter props along the far row so the office reads "lived-in" but
      // the player can clear them out via the furniture editor.
      placedFurniture: [
        FurniturePlacement(itemId: 'old_desk', col: 2, row: 3),
        FurniturePlacement(itemId: 'stool', col: 3, row: 3),
        FurniturePlacement(itemId: 'cardboard_boxes', col: 5, row: 3),
      ],
      // 0 = never persisted / never synced. Bumped on first real mutation via
      // _scheduleSave(). The server treats ts=0 as "fresh client, don't let me
      // clobber authoritative state" — see set_game_state handler.
      updatedAt: 0,
    );
  }
}

