/// PixelCode game economy — currency, hiring, skills, office upgrades, donations.
///
/// Currency: "гримні" (₲). Start in a shabby garage with cheap laptops.
/// Progress by completing tasks, hiring agents, upgrading skills & hardware.
library;

import 'dart:convert';

import 'app_theme.dart';

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
  /// XP accumulated towards next level for each skill.
  final Map<SkillType, int> skillXp;

  const AgentGameData({
    required this.agentId,
    this.isHired = false,
    this.hardware = HardwareTier.oldLaptop,
    this.skills = const {},
    this.skillXp = const {},
  });

  int get skillLevel {
    if (skills.isEmpty) return 0;
    return (skills.values.reduce((a, b) => a + b) / skills.length).round();
  }

  double get totalSpeedModifier => hardware.speedModifier;

  /// XP required to unlock the next level for a skill (level × 100).
  int xpForNextLevel(SkillType skill) => (skills[skill] ?? 1) * 100;

  AgentGameData copyWith({
    bool? isHired,
    HardwareTier? hardware,
    Map<SkillType, int>? skills,
    Map<SkillType, int>? skillXp,
  }) =>
      AgentGameData(
        agentId: agentId,
        isHired: isHired ?? this.isHired,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
        skillXp: skillXp ?? this.skillXp,
      );

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'isHired': isHired,
        'hardware': hardware.index,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
        'skillXp': {
          for (final e in skillXp.entries) e.key.index.toString(): e.value,
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
        skillXp: {
          for (final e
              in (json['skillXp'] as Map<String, dynamic>? ?? {}).entries)
            SkillType.values[int.parse(e.key)]: e.value as int,
        },
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

// ─── Agent catalog ─────────────────────────────────────────────────────────

class AgentCatalogEntry {
  final String agentId;
  final String name;
  final String role;
  final String description;
  final int hireCost;
  final int salary;
  final bool startsHired;
  final AgentPassive passive;

  const AgentCatalogEntry({
    required this.agentId,
    required this.name,
    required this.role,
    required this.description,
    required this.hireCost,
    required this.salary,
    required this.passive,
    this.startsHired = false,
  });
}

const agentCatalog = <AgentCatalogEntry>[
  AgentCatalogEntry(
    agentId: 'manager',
    name: 'Капітан',
    role: 'Координатор',
    description: 'Розподіляє задачі між командою. Без нього нікуди.',
    hireCost: 0,
    salary: 50,
    startsHired: true,
    passive: AgentPassive(
      icon: '🧠',
      name: 'Tactical Mind',
      nameUk: 'Тактичний розум',
      description: 'Оптимально розподіляє задачі — команда працює швидше коли він на чолі.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'coder',
    name: 'Майстер',
    role: 'Розробник',
    description: 'Пише код, реалізує фічі та фіксить баги.',
    hireCost: 0,
    salary: 40,
    startsHired: true,
    passive: AgentPassive(
      icon: '⌨️',
      name: 'Speed Typing',
      nameUk: 'Швидкодрук',
      description: 'Пише код з нелюдською швидкістю — менше помилок, більше фіч за раунд.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'tech-lead',
    name: 'Архітект',
    role: 'Технічний лідер',
    description: 'Будівничий системи. Приймає технічні рішення та ревʼюїть архітектуру.',
    hireCost: 500,
    salary: 80,
    passive: AgentPassive(
      icon: '🏗️',
      name: 'System Vision',
      nameUk: 'Системне бачення',
      description: 'Бачить повну картину проєкту — його архітектурні рішення економлять час.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'reviewer',
    name: 'Детектив',
    role: 'Рецензент',
    description: 'Розслідує код, знаходить анти-патерни та приховані помилки.',
    hireCost: 300,
    salary: 40,
    passive: AgentPassive(
      icon: '🔍',
      name: 'Bug Radar',
      nameUk: 'Радар багів',
      description: 'Інтуїтивно відчуває приховані баги — знаходить проблеми ще до тестування.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'tester',
    name: 'Крашер',
    role: 'Контроль якості',
    description: 'Ламає все що може зламатись — до того як це зробить користувач.',
    hireCost: 300,
    salary: 40,
    passive: AgentPassive(
      icon: '👆',
      name: 'Swipe Master',
      nameUk: 'Майстер свайпів',
      description: 'Має особливий хист до тестування UI — свайпи, жести та анімації не вислизнуть.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'security',
    name: 'Страж',
    role: 'Безпека',
    description: 'Невсипущий вартовий — аудить код на вразливості та проблеми безпеки.',
    hireCost: 800,
    salary: 60,
    passive: AgentPassive(
      icon: '🛡️',
      name: 'Firewall',
      nameUk: 'Фаєрвол',
      description: 'Невидимий щит — автоматично виявляє вразливості OWASP Top 10 в коді.',
    ),
  ),
  AgentCatalogEntry(
    agentId: 'ui-ux-designer',
    name: 'Піксельник',
    role: 'UI/UX',
    description: 'Творець краси — малює інтерфейси піксель за пікселем.',
    hireCost: 400,
    salary: 45,
    passive: AgentPassive(
      icon: '🎨',
      name: 'Pixel Perfect',
      nameUk: 'Ідеальний піксель',
      description: 'Бачить кожен піксель — інтерфейси виходять бездоганними з першого разу.',
    ),
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
}

extension CosmeticTypeExt on CosmeticType {
  String get label => switch (this) {
        CosmeticType.skin => 'Скіни',
        CosmeticType.nicknameDecor => 'Декор нікнейму',
        CosmeticType.avatarFrame => 'Рамки аватара',
        CosmeticType.titleBadge => 'Титули',
      };

  String get icon => switch (this) {
        CosmeticType.skin => '👔',
        CosmeticType.nicknameDecor => '✏️',
        CosmeticType.avatarFrame => '🖼️',
        CosmeticType.titleBadge => '🏷️',
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

// ─── Game state ────────────────────────────────────────────────────────────

class GameState {
  final int grymni;
  final OfficeLevel officeLevel;
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

  const GameState({
    this.grymni = 500,
    this.officeLevel = OfficeLevel.garage,
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
  });

  int get hiredCount => agents.values.where((a) => a.isHired).length;

  bool get canHireMore => hiredCount < officeLevel.maxAgents;

  List<String> get hiredAgentIds =>
      agents.entries
          .where((e) => e.value.isHired)
          .map((e) => e.key)
          .toList();

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

  GameState copyWith({
    int? grymni,
    OfficeLevel? officeLevel,
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
  }) =>
      GameState(
        grymni: grymni ?? this.grymni,
        officeLevel: officeLevel ?? this.officeLevel,
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
      );

  Map<String, dynamic> toJson() => {
        'grymni': grymni,
        'officeLevel': officeLevel.index,
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
        placedFurniture: [
          for (final p in (json['placedFurniture'] as List<dynamic>?) ?? [])
            FurniturePlacement.fromJson(p as Map<String, dynamic>),
        ],
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
    // Generate a random starter nickname
    final seed = DateTime.now().microsecondsSinceEpoch;
    return GameState(
      grymni: 500,
      officeLevel: OfficeLevel.garage,
      agents: agents,
      nickname: generateGameNickname(seed),
      ownedCosmetics: {'title_rookie'}, // Free starter title
      ownedFurniture: {'snack_table_basic'}, // Free starter furniture
      placedFurniture: [
        FurniturePlacement(itemId: 'snack_table_basic', col: 14, row: 1),
      ],
    );
  }
}
