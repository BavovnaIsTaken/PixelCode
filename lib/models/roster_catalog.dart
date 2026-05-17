/// Curated Roster v1 — named characters as hireable entities.
///
/// Phase 1.5 (Q3 2026) per `docs/STRATEGY.md`. Each character has a stable
/// identity (name, portrait, statWeights, promptBias) and a swappable
/// `defaultProvider`. Stats are immutable per character — cosmetic upgrades
/// only, per "no pay-to-progress" (STRATEGY §3).
///
/// Stat budget rule: `statWeights` sums to 18, each in `[1, 7]`, with
/// `max - min >= 4`. Asserted in tests.
library;

import 'agent_message.dart';
import 'game_economy.dart';

/// One curated character available for hire.
class RosterCharacter {
  /// Stable identifier, e.g. `"andriy_coder"`. Persisted into agent data
  /// so we can attribute "this Андрій came from the roster" later.
  final String id;

  /// Display name (Ukrainian, character-first — no vendor branding).
  final String name;

  /// Underlying role from [roleCatalog]. The hire flow reuses the same
  /// role infrastructure; `RosterCharacter` is a curated overlay.
  final String roleType;

  /// 5-stat weights. Sum = 18, each in [1, 7], spread (max-min) >= 4.
  /// Indices follow [SkillType] enum order.
  final Map<SkillType, int> statWeights;

  /// One-line personality bias injected into the agent's prompt at runtime.
  final String promptBias;

  /// Default backend for this character. Soft vendor-disclosure: visible
  /// to the player but swappable via advanced settings without changing
  /// character identity (STRATEGY §Phase 1.5).
  final AgentProviderType defaultProvider;

  /// Hire cost in гримні (₲). 0 = seed character (granted at start).
  final int price;

  /// Short tagline for the catalog card (1 line, framing strength as
  /// distinct trait, not weakness — see UX spec).
  final String tagline;

  /// One-sentence elevator pitch — what this character is known for.
  final String strength;

  /// One-sentence honest limitation — never weaponise a stat as "bad".
  final String weakness;

  const RosterCharacter({
    required this.id,
    required this.name,
    required this.roleType,
    required this.statWeights,
    required this.promptBias,
    required this.defaultProvider,
    required this.price,
    required this.tagline,
    required this.strength,
    required this.weakness,
  });

  /// The single highest stat (signature). Ties resolved by [SkillType] order.
  SkillType get signatureStat {
    SkillType best = statWeights.keys.first;
    int bestVal = statWeights[best] ?? 0;
    for (final entry in statWeights.entries) {
      if (entry.value > bestVal) {
        best = entry.key;
        bestVal = entry.value;
      }
    }
    return best;
  }

  /// Sum of all stat weights (should equal `statBudget`).
  int get statSum => statWeights.values.fold(0, (a, b) => a + b);
}

/// Total stat budget per roster character.
const int rosterStatBudget = 18;

/// Maximum value for any single stat in a roster character.
const int rosterStatMax = 7;

/// Minimum value for any single stat in a roster character.
const int rosterStatMin = 1;

/// Required minimum spread between max and min stat (anti-blandness).
const int rosterStatSpreadMin = 4;

/// Curated starter roster — 8 characters covering 8 of the 11 hireable roles.
///
/// `manager` is excluded (singleton, seeded). `game-designer` and
/// `strategy-keeper` are excluded as v1 — they are meta-roles better suited
/// to Marketplace v1 (E) unlocks. `character-artist` is included alongside
/// `ui-ux-designer` as a parallel creative role (genesis vs polish).
///
/// Balance rationale and telemetry plan: see `docs/STRATEGY.md` §Phase 1.5
/// and `docs/ROADMAP.md` §D.1.
const List<RosterCharacter> rosterCatalog = [
  RosterCharacter(
    id: 'andriy_coder',
    name: 'Андрій',
    roleType: 'coder',
    statWeights: {
      SkillType.speed: 6,
      SkillType.precision: 5,
      SkillType.creativity: 2,
      SkillType.insight: 3,
      SkillType.reliability: 2,
    },
    promptBias:
        'Менше слів — більше коду. Перша робоча версія понад ідеальну.',
    defaultProvider: AgentProviderType.deepseek,
    price: 0,
    tagline: 'Він просто пише.',
    strength: 'Найшвидший throughput на рутинних задачах.',
    weakness: 'На складних задачах часто incomplete; не тягне архітектуру.',
  ),
  RosterCharacter(
    id: 'tetyana_tester',
    name: 'Тетяна',
    roleType: 'tester',
    statWeights: {
      SkillType.speed: 4,
      SkillType.precision: 3,
      SkillType.creativity: 1,
      SkillType.insight: 3,
      SkillType.reliability: 7,
    },
    promptBias:
        'Що може піти не так — перевір це першим. Генеруй edge-case сценарії.',
    defaultProvider: AgentProviderType.deepseek,
    price: 350,
    tagline: 'Параноя — її суперсила.',
    strength: 'Найвища reliability у roster — щит проти регресій.',
    weakness: 'Креативно нестандартних багів не знайде.',
  ),
  RosterCharacter(
    id: 'olya_reviewer',
    name: 'Оля',
    roleType: 'reviewer',
    statWeights: {
      SkillType.speed: 2,
      SkillType.precision: 7,
      SkillType.creativity: 1,
      SkillType.insight: 5,
      SkillType.reliability: 3,
    },
    promptBias:
        'Кожен коментар — конкретний файл і рядок. Знайди приховану проблему.',
    defaultProvider: AgentProviderType.cloud,
    price: 500,
    tagline: 'Вона знайде те, що ти пропустив.',
    strength: 'Найвища precision — ловить баги яких всі пропустили.',
    weakness: 'Повільна, ніколи не запропонує нестандартного fix.',
  ),
  RosterCharacter(
    id: 'sonya_designer',
    name: 'Соня',
    roleType: 'ui-ux-designer',
    statWeights: {
      SkillType.speed: 3,
      SkillType.precision: 2,
      SkillType.creativity: 7,
      SkillType.insight: 2,
      SkillType.reliability: 4,
    },
    promptBias:
        'Запропонуй альтернативне рішення яке клієнт не очікував.',
    defaultProvider: AgentProviderType.local,
    price: 600,
    tagline: 'Вона бачить те, чого ще немає.',
    strength: 'Найвища creativity — wow-моменти на дизайн-задачах.',
    weakness: 'Дизайни часто потребують доопрацювання деталей.',
  ),
  RosterCharacter(
    id: 'nazar_artist',
    name: 'Назар',
    roleType: 'character-artist',
    statWeights: {
      SkillType.speed: 1,
      SkillType.precision: 4,
      SkillType.creativity: 7,
      SkillType.insight: 2,
      SkillType.reliability: 4,
    },
    promptBias:
        'Перш ніж пропонувати новий колір — пошукай у існуючих скінах. Reuse first.',
    defaultProvider: AgentProviderType.local,
    price: 700,
    tagline: 'Він пише характер кольором.',
    strength:
        'Найвища creativity у roster — нові скіни і NPC народжуються з першого ескізу.',
    weakness: 'Без content-задач у беклозі простоює — не вигадує роботу.',
  ),
  RosterCharacter(
    id: 'bohdan_techlead',
    name: 'Богдан',
    roleType: 'tech-lead',
    statWeights: {
      SkillType.speed: 2,
      SkillType.precision: 3,
      SkillType.creativity: 4,
      SkillType.insight: 7,
      SkillType.reliability: 2,
    },
    promptBias:
        'Спочатку чому, потім як. Завжди питай про масштабованість.',
    defaultProvider: AgentProviderType.cloud,
    price: 900,
    tagline: 'Він бачить систему цілком.',
    strength: 'Найвищий insight — архітектурні рішення на рівні системи.',
    weakness: 'У реалізації low-level деталей може щось пропустити.',
  ),
  RosterCharacter(
    id: 'dmytro_security',
    name: 'Дмитро',
    roleType: 'security',
    statWeights: {
      SkillType.speed: 1,
      SkillType.precision: 6,
      SkillType.creativity: 2,
      SkillType.insight: 6,
      SkillType.reliability: 3,
    },
    promptBias:
        'OWASP Top 10 першим. Кожен finding — severity і remediation.',
    defaultProvider: AgentProviderType.cloud,
    price: 1400,
    tagline: 'Повільно, але жодної вразливості.',
    strength:
        'Найбалансованіший capability-профіль; перший хто досягає sonnet.',
    weakness: 'Найповільніший у roster — терпеливість частина роботи.',
  ),
  RosterCharacter(
    id: 'maxim_llm',
    name: 'Максим',
    roleType: 'llm-specialist',
    statWeights: {
      SkillType.speed: 1,
      SkillType.precision: 4,
      SkillType.creativity: 5,
      SkillType.insight: 6,
      SkillType.reliability: 2,
    },
    promptBias:
        'Спочатку зрозумій що модель насправді робить. Завжди питай про token budget.',
    defaultProvider: AgentProviderType.cloud,
    price: 2000,
    tagline: 'Він думає метарівнями.',
    strength: 'Єдиний хто розуміє LLM-архітектуру зсередини.',
    weakness: 'Без LLM-задач у беклозі цінність обмежена.',
  ),
];

/// Lookup by character id. Returns `null` if not in catalog.
RosterCharacter? rosterCharacterById(String id) {
  for (final c in rosterCatalog) {
    if (c.id == id) return c;
  }
  return null;
}
