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

  int get gridCols => switch (this) {
        OfficeLevel.garage => 20,
        OfficeLevel.smallOffice => 26,
        OfficeLevel.modernOffice => 34,
        OfficeLevel.techHub => 44,
        OfficeLevel.campus => 70,
      };

  int get gridRows => switch (this) {
        OfficeLevel.garage => 14,
        OfficeLevel.smallOffice => 16,
        OfficeLevel.modernOffice => 20,
        OfficeLevel.techHub => 26,
        OfficeLevel.campus => 40,
      };

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

  /// XP accumulated towards next level for each skill.
  final Map<SkillType, int> skillXp;

  const AgentGameData({
    required this.instanceId,
    required this.roleType,
    required this.nickname,
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
    String? nickname,
    HardwareTier? hardware,
    Map<SkillType, int>? skills,
    Map<SkillType, int>? skillXp,
  }) =>
      AgentGameData(
        instanceId: instanceId,
        roleType: roleType,
        nickname: nickname ?? this.nickname,
        hardware: hardware ?? this.hardware,
        skills: skills ?? this.skills,
        skillXp: skillXp ?? this.skillXp,
      );

  Map<String, dynamic> toJson() => {
        'instanceId': instanceId,
        'roleType': roleType,
        'nickname': nickname,
        'hardware': hardware.index,
        'skills': {
          for (final e in skills.entries) e.key.index.toString(): e.value,
        },
        'skillXp': {
          for (final e in skillXp.entries) e.key.index.toString(): e.value,
        },
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
];

RoleCatalogEntry? roleCatalogFor(String roleType) {
  for (final entry in roleCatalog) {
    if (entry.roleType == roleType) return entry;
  }
  return null;
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

  /// Placed office rooms (Build Mode).
  final List<PlacedRoom> placedRooms;

  /// Epoch millis of the last local mutation. Drives last-write-wins sync
  /// between devices — the server only accepts state with a newer timestamp
  /// than what it already holds.
  final int updatedAt;

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
    List<PlacedRoom>? placedRooms,
    int? updatedAt,
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
        placedRooms: placedRooms ?? this.placedRooms,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Current on-disk schema version. v3 adds placedRooms + office grid sizes.
  /// v2 saves load with empty placedRooms (graceful forward-compat).
  static const int schemaVersion = 3;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
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
        'placedRooms': [
          for (final r in placedRooms) r.toJson(),
        ],
        'updatedAt': updatedAt,
      };

  factory GameState.fromJson(Map<String, dynamic> json) {
    // Load raw then apply in-flight migrations before the real constructor.
    var level = OfficeLevel.values[json['officeLevel'] as int? ?? 0];
    var rooms = [
      for (final r in (json['placedRooms'] as List<dynamic>?) ?? [])
        PlacedRoom.fromJson(r as Map<String, dynamic>),
    ];
    var furniture = [
      for (final p in (json['placedFurniture'] as List<dynamic>?) ?? [])
        FurniturePlacement.fromJson(p as Map<String, dynamic>),
    ];

    // Migration: campus is WIP ("В розробці") — saves stuck at campus are
    // pulled back to smallOffice so the player can pick a reachable tier.
    if (level == OfficeLevel.campus) {
      level = OfficeLevel.smallOffice;
      // Rooms from a campus map will almost certainly be outside the new
      // bounds — drop them all and let the player rebuild.
      rooms = const [];
    }

    // Drop rooms/furniture that no longer fit in the (possibly shrunken) grid.
    final gCols = level.gridCols;
    final gRows = level.gridRows;
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
        grymni: json['grymni'] as int? ?? 500,
        officeLevel: level,
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
    // Accept v2 (loads with empty placedRooms) and v3. Reject older/unknown.
    if (version < 2 || version > schemaVersion) {
      throw const FormatException('Incompatible game state schema');
    }
    return GameState.fromJson(json);
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
          skills: {for (final s in SkillType.values) s: 1},
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
      ownedFurniture: {'snack_table_basic'}, // Free starter furniture
      placedFurniture: [
        FurniturePlacement(itemId: 'snack_table_basic', col: 14, row: 1),
      ],
      // 0 = never persisted / never synced. Bumped on first real mutation via
      // _scheduleSave(). The server treats ts=0 as "fresh client, don't let me
      // clobber authoritative state" — see set_game_state handler.
      updatedAt: 0,
    );
  }
}
