/// PixelCode game economy — currency, hiring, skills, office upgrades, donations.
///
/// Currency: "гримні" (₲). Start in a shabby garage with cheap laptops.
/// Progress by completing tasks, hiring agents, upgrading skills & hardware.
library;

import 'dart:convert';

// ─── Office levels ─────────────────────────────────────────────────────────

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
        OfficeLevel.smallOffice => 5,
        OfficeLevel.modernOffice => 7,
        OfficeLevel.techHub => 7,
        OfficeLevel.campus => 7,
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
        OfficeLevel.modernOffice => 5000,
        OfficeLevel.techHub => 20000,
        OfficeLevel.campus => 100000,
      };

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

enum SkillType {
  speed,
  quality,
  communication,
  problemSolving,
  specialization,
}

extension SkillTypeExt on SkillType {
  String get label => switch (this) {
        SkillType.speed => 'Швидкість',
        SkillType.quality => 'Якість коду',
        SkillType.communication => 'Комунікація',
        SkillType.problemSolving => 'Вирішення проблем',
        SkillType.specialization => 'Спеціалізація',
      };

  String get icon => switch (this) {
        SkillType.speed => '⚡',
        SkillType.quality => '✨',
        SkillType.communication => '💬',
        SkillType.problemSolving => '🧩',
        SkillType.specialization => '🎯',
      };

  int get baseCost => switch (this) {
        SkillType.speed => 100,
        SkillType.quality => 150,
        SkillType.communication => 120,
        SkillType.problemSolving => 200,
        SkillType.specialization => 250,
      };

  /// Cost to upgrade from current level to next.
  int upgradeCost(int currentLevel) => baseCost * (currentLevel + 1);
}

// ─── Agent game data ───────────────────────────────────────────────────────

class AgentGameData {
  final String agentId;
  final bool isHired;
  final HardwareTier hardware;
  final Map<SkillType, int> skills;

  const AgentGameData({
    required this.agentId,
    this.isHired = false,
    this.hardware = HardwareTier.oldLaptop,
    this.skills = const {},
  });

  int get skillLevel {
    if (skills.isEmpty) return 0;
    return (skills.values.reduce((a, b) => a + b) / skills.length).round();
  }

  double get totalSpeedModifier => hardware.speedModifier;

  AgentGameData copyWith({
    bool? isHired,
    HardwareTier? hardware,
    Map<SkillType, int>? skills,
  }) =>
      AgentGameData(
        agentId: agentId,
        isHired: isHired ?? this.isHired,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
      );

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'isHired': isHired,
        'hardware': hardware.index,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
      };

  factory AgentGameData.fromJson(Map<String, dynamic> json) => AgentGameData(
        agentId: json['agentId'] as String,
        isHired: json['isHired'] as bool? ?? false,
        hardware: HardwareTier.values[json['hardware'] as int? ?? 0],
        skills: {
          for (final e
              in (json['skills'] as Map<String, dynamic>? ?? {}).entries)
            SkillType.values[int.parse(e.key)]: e.value as int,
        },
      );
}

// ─── Agent catalog ─────────────────────────────────────────────────────────

class AgentCatalogEntry {
  final String agentId;
  final String name;
  final String role;
  final String description;
  final int hireCost;
  final int salary;
  final bool startsHired;

  const AgentCatalogEntry({
    required this.agentId,
    required this.name,
    required this.role,
    required this.description,
    required this.hireCost,
    required this.salary,
    this.startsHired = false,
  });
}

const agentCatalog = <AgentCatalogEntry>[
  AgentCatalogEntry(
    agentId: 'manager',
    name: 'Менеджер',
    role: 'Координатор',
    description: 'Розподіляє задачі між командою. Без нього нікуди.',
    hireCost: 0,
    salary: 50,
    startsHired: true,
  ),
  AgentCatalogEntry(
    agentId: 'coder',
    name: 'Кодер',
    role: 'Розробник',
    description: 'Пише код, реалізує фічі та фіксить баги.',
    hireCost: 0,
    salary: 40,
    startsHired: true,
  ),
  AgentCatalogEntry(
    agentId: 'tech-lead',
    name: 'Тех Лід',
    role: 'Технічний лідер',
    description: 'Архітектор. Приймає технічні рішення та ревʼюїть архітектуру.',
    hireCost: 500,
    salary: 80,
  ),
  AgentCatalogEntry(
    agentId: 'reviewer',
    name: "Рев'юер",
    role: 'Рецензент',
    description: 'Перевіряє код на якість, знаходить анти-патерни.',
    hireCost: 300,
    salary: 40,
  ),
  AgentCatalogEntry(
    agentId: 'tester',
    name: 'Тестер',
    role: 'Контроль якості',
    description: 'Пише тести та аналізує покриття коду.',
    hireCost: 300,
    salary: 40,
  ),
  AgentCatalogEntry(
    agentId: 'security',
    name: "Сек'юріті",
    role: 'Безпека',
    description: 'Аудить код на вразливості та проблеми безпеки.',
    hireCost: 800,
    salary: 60,
  ),
  AgentCatalogEntry(
    agentId: 'ui-ux-designer',
    name: 'Дизайнер',
    role: 'UI/UX',
    description: 'Оцінює дизайн інтерфейсу та досвід користувача.',
    hireCost: 400,
    salary: 45,
  ),
];

AgentCatalogEntry? catalogFor(String agentId) {
  for (final entry in agentCatalog) {
    if (entry.agentId == agentId) return entry;
  }
  return null;
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

// ─── Game state ────────────────────────────────────────────────────────────

class GameState {
  final int grymni;
  final OfficeLevel officeLevel;
  final Map<String, AgentGameData> agents;
  final int totalEarned;
  final int totalSpent;

  const GameState({
    this.grymni = 500,
    this.officeLevel = OfficeLevel.garage,
    this.agents = const {},
    this.totalEarned = 0,
    this.totalSpent = 0,
  });

  int get hiredCount => agents.values.where((a) => a.isHired).length;

  bool get canHireMore => hiredCount < officeLevel.maxAgents;

  List<String> get hiredAgentIds =>
      agents.entries
          .where((e) => e.value.isHired)
          .map((e) => e.key)
          .toList();

  GameState copyWith({
    int? grymni,
    OfficeLevel? officeLevel,
    Map<String, AgentGameData>? agents,
    int? totalEarned,
    int? totalSpent,
  }) =>
      GameState(
        grymni: grymni ?? this.grymni,
        officeLevel: officeLevel ?? this.officeLevel,
        agents: agents ?? this.agents,
        totalEarned: totalEarned ?? this.totalEarned,
        totalSpent: totalSpent ?? this.totalSpent,
      );

  Map<String, dynamic> toJson() => {
        'grymni': grymni,
        'officeLevel': officeLevel.index,
        'agents': {
          for (final e in agents.entries) e.key: e.value.toJson(),
        },
        'totalEarned': totalEarned,
        'totalSpent': totalSpent,
      };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        grymni: json['grymni'] as int? ?? 500,
        officeLevel:
            OfficeLevel.values[json['officeLevel'] as int? ?? 0],
        agents: {
          for (final e
              in (json['agents'] as Map<String, dynamic>? ?? {}).entries)
            e.key: AgentGameData.fromJson(e.value as Map<String, dynamic>),
        },
        totalEarned: json['totalEarned'] as int? ?? 0,
        totalSpent: json['totalSpent'] as int? ?? 0,
      );

  String encode() => jsonEncode(toJson());

  factory GameState.decode(String source) =>
      GameState.fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// Create default starting state: manager + coder hired, old laptops.
  factory GameState.initial() {
    final agents = <String, AgentGameData>{};
    for (final entry in agentCatalog) {
      agents[entry.agentId] = AgentGameData(
        agentId: entry.agentId,
        isHired: entry.startsHired,
        hardware: HardwareTier.oldLaptop,
        skills: {for (final s in SkillType.values) s: 1},
      );
    }
    return GameState(
      grymni: 500,
      officeLevel: OfficeLevel.garage,
      agents: agents,
    );
  }
}
