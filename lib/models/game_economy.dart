/// PixelCode game economy — currency, hiring, skills, office upgrades, donations.
///
/// Currency: "гримні" (₲). Start in a shabby garage with cheap laptops.
/// Progress by completing tasks, hiring agents, upgrading skills & hardware.
library;

import 'dart:convert';

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
        OfficeLevel.techHub => 'Тех хаб',
        OfficeLevel.campus => 'Кампус',
      };

  String get description => switch (this) {
        OfficeLevel.garage =>
          'Обшарпаний гараж з парою столів та тьмяним світлом. Повільно, але працює.',
        OfficeLevel.smallOffice =>
          'Невеликий офіс з базовими меблями та нормальним Wi-Fi.',
        OfficeLevel.modernOffice =>
          'Сучасний офіс з ергономічними кріслами та швидким інтернетом.',
        OfficeLevel.techHub =>
          'Стильний тех хаб з неоновим підсвічуванням та топовим залізом.',
        OfficeLevel.campus =>
          'Розкішний кампус з усіма зручностями. Мрія кожного розробника.',
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

  const AgentGameData({
    required this.instanceId,
    required this.roleType,
    required this.nickname,
    this.hardware = HardwareTier.oldLaptop,
    this.skills = const {},
    this.level = 1,
    this.xp = 0,
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
  }) =>
      AgentGameData(
        instanceId: instanceId,
        roleType: roleType,
        nickname: nickname ?? this.nickname,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
        level: level ?? this.level,
        xp: xp ?? this.xp,
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
      );
}

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
    this.singleton = false,
    this.defaultSeedCount = 0,
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
    passive: AgentPassive(
      icon: '🛡️',
      name: 'Firewall',
      nameUk: 'Фаєрвол',
      description:
          'Невидимий щит — автоматично виявляє вразливості OWASP Top 10 в коді.',
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
    passive: AgentPassive(
      icon: '🤖',
      name: 'Prompt Whisperer',
      nameUk: 'Шептун промптів',
      description:
          'Знає Claude SDK напамʼять — оптимізує токени, кеш та інструменти, скорочуючи цикли інтеграції AI-фіч.',
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

/// Room types split into two groups:
/// - compact rooms (2×2, 3×2) — dominant, placed in quantity
/// - luxury rooms (bigger) — 1 per office, each with a signature mechanic
enum RoomType {
  // ── Compact ──
  workstation,
  breakRoom,
  meetingRoom,
  serverRoom,
  lounge,
  // ── Luxury (1-2 per office) ──
  gym,
  cinema,
  pool,
  miniGolf,
}

extension RoomTypeExt on RoomType {
  String get nameUk => switch (this) {
        RoomType.workstation => 'Робоче місце',
        RoomType.breakRoom => 'Куток відпочинку',
        RoomType.meetingRoom => 'Переговорний пункт',
        RoomType.serverRoom => 'Сервер',
        RoomType.lounge => 'Скейт-куток',
        RoomType.gym => 'Спортзал',
        RoomType.cinema => 'Кінозал',
        RoomType.pool => 'Басейн',
        RoomType.miniGolf => 'Міні-гольф',
      };

  String get description => switch (this) {
        RoomType.workstation => 'Додаткове місце для агента без канонічного стола.',
        RoomType.breakRoom =>
          'Агенти сидять за столом на 50 % довше — менше блукають.',
        RoomType.meetingRoom =>
          'Координаційний пункт — покращує роботу менеджера.',
        RoomType.serverRoom => 'Всі агенти рухаються на 10 % швидше.',
        RoomType.lounge => 'Агенти частіше катаються скейтом саме сюди.',
        RoomType.gym => 'Люкс. Морал-буст для всієї команди.',
        RoomType.cinema => 'Люкс. Кіно-перегляди підвищують командний дух.',
        RoomType.pool => 'Люкс. Найкращий spot для відпочинку між спринтами.',
        RoomType.miniGolf => 'Люкс. Невеликі змагання між колегами.',
      };

  String get icon => switch (this) {
        RoomType.workstation => '💻',
        RoomType.breakRoom => '🛋️',
        RoomType.meetingRoom => '🗣️',
        RoomType.serverRoom => '🖥️',
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
        RoomType.lounge => 3,
        RoomType.gym => 1,
        RoomType.cinema => 1,
        RoomType.pool => 1,
        RoomType.miniGolf => 1,
      };

  /// Compact rooms are the "dominant" small-size group; luxury rooms are the
  /// signature 1-per-office feature pieces. UI groups them separately.
  bool get isLuxury => switch (this) {
        RoomType.gym ||
        RoomType.cinema ||
        RoomType.pool ||
        RoomType.miniGolf =>
          true,
        _ => false,
      };
}

class PlacedRoom {
  final String id;
  final RoomType type;
  final int col;
  final int row;

  const PlacedRoom({
    required this.id,
    required this.type,
    required this.col,
    required this.row,
  });

  int get right => col + type.widthTiles;
  int get bottom => row + type.heightTiles;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'col': col,
        'row': row,
      };

  factory PlacedRoom.fromJson(Map<String, dynamic> json) => PlacedRoom(
        id: json['id'] as String,
        type: RoomType.values[json['type'] as int],
        col: json['col'] as int,
        row: json['row'] as int,
      );
}

// ─── Game state ────────────────────────────────────────────────────────────

class GameState {
  /// Current on-disk schema version. Bump this constant whenever the
  /// serialised shape changes in a breaking way.
  static const int currentSchemaVersion = 5;

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

  /// IDs of purchased furniture items.
  final Set<String> ownedFurniture;

  /// Placed furniture items with their grid positions.
  final List<FurniturePlacement> placedFurniture;

  /// Placed office rooms (Build Mode).
  final List<PlacedRoom> placedRooms;

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
    this.ownedFurniture = const {},
    this.placedFurniture = const [],
    this.placedRooms = const [],
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
    Set<String>? ownedFurniture,
    List<FurniturePlacement>? placedFurniture,
    List<PlacedRoom>? placedRooms,
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
        ownedFurniture: ownedFurniture ?? this.ownedFurniture,
        placedFurniture: placedFurniture ?? this.placedFurniture,
        placedRooms: placedRooms ?? this.placedRooms,
        updatedAt: updatedAt ?? this.updatedAt,
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
        'ownedFurniture': ownedFurniture.toList(),
        'placedFurniture': [
          for (final p in placedFurniture) p.toJson(),
        ],
        'placedRooms': [
          for (final r in placedRooms) r.toJson(),
        ],
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

    // Clamp expansions to the number this tier actually supports.
    final maxSteps = level.expansions.length;
    if (expansions < 0) expansions = 0;
    if (expansions > maxSteps) expansions = maxSteps;

    // Drop rooms/furniture that no longer fit in the effective grid (post
    // migration — e.g. v3 → v4 grids may have shrunk).
    final gCols = level.effectiveCols(expansions);
    final gRows = level.effectiveRows(expansions);
    rooms = rooms
        .where((r) =>
            r.col >= 1 &&
            r.row >= 1 &&
            r.col + r.type.widthTiles <= gCols - 1 &&
            r.row + r.type.heightTiles <= gRows - 1)
        .toList();
    furniture = furniture
        .where((p) => p.col < gCols - 1 && p.row < gRows - 1)
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
        ownedFurniture: {
          for (final id in (json['ownedFurniture'] as List<dynamic>?) ?? [])
            id as String,
        },
        placedFurniture: furniture,
        placedRooms: rooms,
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
    // Accept v2 (empty placedRooms), v3 (no officeExpansions) and v4. Reject
    // older/unknown.
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
        agents[id] = AgentGameData(
          instanceId: id,
          roleType: role.roleType,
          nickname: defaultNicknameFor(role, i),
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
      ownedFurniture: {'old_desk', 'stool', 'cardboard_boxes'},
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

// ─── Office presets (room bundles) ─────────────────────────────────────────

/// A single room within a preset, positioned relative to the preset anchor.
class PresetRoomSlot {
  final RoomType type;
  final int colOffset;
  final int rowOffset;

  const PresetRoomSlot({
    required this.type,
    required this.colOffset,
    required this.rowOffset,
  });
}

/// A named bundle of rooms placed as a single unit — the "drop a whole
/// wing in one click" mechanic. Useful when a player wants new space but
/// doesn't feel like hand-placing individual rooms.
class OfficePreset {
  final String id;
  final String name;
  final String description;
  final String icon;
  final List<PresetRoomSlot> rooms;

  /// Discount on the summed cost of all component rooms, in percent (0–100).
  /// Reward for using curated layouts instead of buying each room alone.
  final int discountPercent;

  const OfficePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.rooms,
    this.discountPercent = 8,
  });

  int get widthTiles {
    var maxRight = 0;
    for (final r in rooms) {
      final right = r.colOffset + r.type.widthTiles;
      if (right > maxRight) maxRight = right;
    }
    return maxRight;
  }

  int get heightTiles {
    var maxBottom = 0;
    for (final r in rooms) {
      final bottom = r.rowOffset + r.type.heightTiles;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    return maxBottom;
  }

  int get componentsCost {
    var total = 0;
    for (final r in rooms) {
      total += r.type.cost;
    }
    return total;
  }

  int get totalCost =>
      (componentsCost * (100 - discountPercent) / 100).round();

  /// True if any component room is a luxury room (gym, cinema, pool, mini-golf).
  /// Garage-tier offices hide luxury presets since they can't host them anyway.
  bool get hasLuxury {
    for (final r in rooms) {
      if (r.type.isLuxury) return true;
    }
    return false;
  }
}

/// Starter catalog of curated room bundles.
const officePresetCatalog = <OfficePreset>[
  OfficePreset(
    id: 'starter_desk',
    name: 'Стартовий куток',
    description: 'Одне робоче місце + переговорна. Мінімум для старту.',
    icon: '🪑',
    discountPercent: 5,
    rooms: [
      PresetRoomSlot(type: RoomType.workstation, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.meetingRoom, colOffset: 2, rowOffset: 0),
    ],
  ),
  OfficePreset(
    id: 'dev_pod',
    name: 'Дев-гніздо',
    description: 'Два робочі місця + куток відпочинку поруч.',
    icon: '💻',
    discountPercent: 10,
    rooms: [
      PresetRoomSlot(type: RoomType.workstation, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.workstation, colOffset: 2, rowOffset: 0),
      PresetRoomSlot(type: RoomType.breakRoom, colOffset: 0, rowOffset: 2),
    ],
  ),
  OfficePreset(
    id: 'meeting_hub',
    name: 'Переговорний хаб',
    description: 'Переговорна + куток відпочинку. Ідеально для планування.',
    icon: '🗣️',
    discountPercent: 8,
    rooms: [
      PresetRoomSlot(type: RoomType.meetingRoom, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.breakRoom, colOffset: 0, rowOffset: 2),
    ],
  ),
  OfficePreset(
    id: 'data_fortress',
    name: 'Фортеця даних',
    description: 'Сервер + робоче місце для devops. Спід-буст усій команді.',
    icon: '🖥️',
    discountPercent: 10,
    rooms: [
      PresetRoomSlot(type: RoomType.serverRoom, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.workstation, colOffset: 2, rowOffset: 0),
    ],
  ),
  OfficePreset(
    id: 'chill_wing',
    name: 'Релакс-крило',
    description: 'Скейт-куток + куток відпочинку. Тут батареї заряджаються.',
    icon: '🛹',
    discountPercent: 12,
    rooms: [
      PresetRoomSlot(type: RoomType.lounge, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.breakRoom, colOffset: 0, rowOffset: 2),
    ],
  ),
  OfficePreset(
    id: 'production_line',
    name: 'Виробнича лінія',
    description: 'Три робочі місця в ряд + сервер поруч.',
    icon: '⚙️',
    discountPercent: 12,
    rooms: [
      PresetRoomSlot(type: RoomType.workstation, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.workstation, colOffset: 2, rowOffset: 0),
      PresetRoomSlot(type: RoomType.workstation, colOffset: 4, rowOffset: 0),
      PresetRoomSlot(type: RoomType.serverRoom, colOffset: 0, rowOffset: 2),
    ],
  ),
  OfficePreset(
    id: 'luxury_retreat',
    name: 'Люкс-ретрит',
    description: 'Спортзал + басейн. Для команд з бюджетом і мріями.',
    icon: '🏊',
    discountPercent: 8,
    rooms: [
      PresetRoomSlot(type: RoomType.gym, colOffset: 0, rowOffset: 0),
      PresetRoomSlot(type: RoomType.pool, colOffset: 4, rowOffset: 0),
    ],
  ),
];

OfficePreset? officePresetById(String id) {
  for (final preset in officePresetCatalog) {
    if (preset.id == id) return preset;
  }
  return null;
}
