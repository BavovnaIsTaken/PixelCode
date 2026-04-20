# Agent Level, Skills та Archetype System

**Дата:** 2026-04-20
**Автор:** Danylo Oliinyk
**Тип:** Game mechanics rework (breaking change)

## Мета

Поточна система агентів має кілька структурних слабкостей, які обмежують ігрову глибину:

1. "Рівень агента" неявний — похідне від середнього скілів, не first-class стат.
2. Складність задачі (`requiredSkill`) gating-ується середнім скілом — агент-спеціаліст (9/9/1/1/9) і агент-дженераліст (6/6/6/6/6) мають однаковий `avg=5.8` і взаємозамінні. Це стирає ідентичність.
3. Усі ролі мають однакові 5 скілів. Архітектор-"precision-focused" механічно нічим не відрізняється від rapid-fire тестувальника.
4. Скіл `specialization` неконкретний — не впливає на реальні LLM-параметри.
5. Немає прогресійної петлі "задачі → XP → Lvl → більше можливостей". Скіли просто купуються грошима без стелі.

Rework вводить: **Level** як first-class стат з XP/cap-ом, **5 нових capability-скілів** мапованих на реальні LLM-параметри, **еволюційні архетипи** на основі існуючого `TraitStore`, **hybrid gating** задач, і **Energy meter** як геймплейний ресурс токенів.

Довідкова консультація з геймдизайнером + LLM-експертом зафіксована у conversation-контексті brainstorming-сесії.

## Не входить у цю роботу (v2+)

Спроектовано в цьому документі (розділ 11), але НЕ реалізується у v1:

- P2P marketplace (SSP формула, fees, resale lock, reputation).
- Rarity tier при спауні (Common/Uncommon/Rare/Epic).
- LLM-procgen daily recruitment pool.
- Adjustment Period (48h trait-freq debuff) після купівлі.
- Enum-словник для traits з sanitization (prompt injection захист).
- Mentoring lever (L2).
- Paid training course (L3).

Також поза scope-ом:

- Міграція існуючих save-файлів. Старі save-и дропаються; гравця попереджає toast при першому запуску нової версії.
- Фундаментальна перебудова existing-ролей (coder/tech-lead/reviewer/tester/security/ui-ux-designer/manager) — їхні прокмпти/моделі/tools у [server/src/agents.ts](../../server/src/agents.ts) лишаються майже без змін, оновлюється лише маппінг скілів.

## 1. Level

### 1.1 Концепція

`Level` — first-class стат на `AgentGameData`, росте через XP, дає два ефекти:

1. **Gate:** визначає, які задачі агент може брати (`task.requiredLevel`).
2. **Cap:** обмежує максимум, до якого можна прокачати кожен скіл за гроші. Без лвл-апу скіли не ростуть далі.

### 1.2 Формули

```
xp_gain_per_task = difficulty² × quality_multiplier × (1 + failure_bonus)
xp_to_next_level = 50 × level^1.6
skill_cap         = 10 + 2 × level   (мін. 12 на Lv1, 50 на Lv20)
```

- `difficulty²` — щоб Hard/Expert давали непропорційно більше XP, запобігає grinding-у Trivial.
- `quality_multiplier` — 1.0 при normal completion, 1.5 якщо без багу/retry, 0.5 якщо повернулось з testing.
- `failure_bonus` — +20% XP, якщо агент провалив задачу і доробив з другої спроби (навчання з помилок).
- Diminishing XP: якщо `task.difficulty + 3 < agent.level`, XP × 0.25 (Lv10 на Trivial дає мізер).

### 1.3 Cap

- Hard cap рівня — **Lv 20**. Після цього агент не росте.
- Soft cap — **Lv 10**: до нього зростання лінійне, далі експоненційне (перший тиждень гри — до ~Lv 5-7; Lv 20 = "Legendary", рідкий).

### 1.4 Зв'язок зі старим кодом

- Поле `AgentGameData.skills` зберігається, але значення скілів тепер обмежені `skill_cap(level)`.
- Поле `AgentGameData.skillXp` — прибирається (XP тепер на рівень агента, не на окремий скіл).
- Нові поля на `AgentGameData`: `level: int`, `xp: int`.

## 2. Skills (5 нових)

### 2.1 Список і LLM-маппінг

| Скіл | Іконка | LLM-параметр |
|---|---|---|
| **Speed** | ⚡ | `reasoning_effort: low` при високому; інверсно впливає на вибір моделі (high Speed дозволяє haiku без штрафу якості) |
| **Precision** | 🎯 | Trigger `reviewer` sub-agent pass після завершення (див. 2.4) |
| **Creativity** | 💡 | `temperature` bucket (low=0.3/mid=0.6/high=0.9); застосовується ТІЛЬКИ на divergent task types |
| **Insight** | 🔮 | Model tier bias — високий Insight зсуває `skillsToModel` ближче до `opus`; розблоковує Hard/Expert задачі |
| **Reliability** | 🔒 | Retry policy + output validation. Низький = вищий шанс incomplete-повернення в backlog. Не плутати з Precision (bug — це different outcome) |

**Чесно:** `Empathy` не ввійшов — у коду-генераційному контексті Claude він впливає на тон, не на capability. Replaced by `Reliability`, який має реальний LLM-відповідник.

### 2.2 Природні XP-жили

Кожен скіл росте від конкретних типів задач:

| Скіл | Як росте |
|---|---|
| Speed | Задачі з deadline/priority=urgent |
| Precision | Задачі, де `reviewer` не знайшов багів |
| Creativity | Divergent-задачі (brainstorm, architecture options, naming) |
| Insight | Hard/Expert задачі (difficulty ≥ 4) |
| Reliability | Кожна успішно завершена задача, незалежно від якості |

Reliability XP **падає** при `incomplete` return (анти-abuse швидкого провалу).

### 2.3 Stat budget і архетипи

На Lv1 агент отримує **30 points**, розподілених за архетипом ролі ± 15% noise (див. розділ 4). При кожному лвл-апі — **+3 pts**, розподіл за тими ж вагами.

Максимум на окремий скіл — `skill_cap = 10 + 2×level`.

### 2.4 Precision → reviewer-pass

При `agent.skills[Precision] ≥ 7`, після завершення задачі **автоматично** запускається окремий `reviewer` sub-agent-прохід. Це коштує ~50-80% додаткових токенів (окремий Claude query).

UI попереджає про це явно: коли гравець призначає high-Precision агента на задачу, на картці відображається бейдж **"⚡ ×1.8 tokens (reviewer pass)"**. Це частина Energy-economy (див. розділ 7).

Якщо гравець хоче заощадити — може використати low-Precision агента для простих задач.

## 3. Hybrid gating задач

### 3.1 Трирівневий фільтр

Задача виконується агентом лише якщо:

1. **Hard gate:** `agent.level ≥ task.requiredLevel`.
2. **Role gate:** `agent.role ∈ task.allowedRoles` (роль може бути мультиматч — напр. `[coder, tech-lead]` для рефакторингу).
3. **Soft modifier:** скіли впливають на **час і якість**, але не на доступ.

### 3.2 `requiredLevel` per difficulty

| Difficulty | Required Level |
|---|---|
| 1 (Trivial) | 1 |
| 2 (Easy) | 2 |
| 3 (Medium) | 4 |
| 4 (Hard) | 7 |
| 5 (Expert) | 11 |

Логарифмічна крива — Expert залишається справжнім челленджем.

### 3.3 Task types і role mapping

Кожна задача має `taskType` (enum). Role catalog мапить, які `taskType` дана роль може виконувати.

**Базові task types:**
- `coding` (coder, tech-lead)
- `architecture` (tech-lead)
- `review` (reviewer)
- `testing` (tester)
- `security-audit` (security)
- `ui-design` (ui-ux-designer)
- `management` (manager)

**Нові task types (з v1):**
- `product-spec` (PM)
- `data-analysis` (data-analyst)
- `devops` (devops)

### 3.4 Замість `requiredSkill`

Поле `TaskCard.requiredSkill` (extension на int у [lib/models/task_board.dart:89-91](../../lib/models/task_board.dart#L89-L91)) **видаляється**. Natively додається:

```dart
class TaskCard {
  int difficulty;            // 1-5, зберігається
  int requiredLevel;         // derived from difficulty (див. 3.2)
  List<String> allowedRoles; // нове поле
  String taskType;           // нове поле
  // ...
}
```

## 4. Archetypes (evolving)

### 4.1 Концепція

Архетип агента — **вектор ваг** розподілу stat-budget-у по 5 скілах. Сума ваг = 100%.

**Приклад для tech-lead "Perfectionist Architect":**
```
{ speed: 10%, precision: 40%, creativity: 10%, insight: 30%, reliability: 10% }
```

**Приклад для tester "Rapid-Fire":**
```
{ speed: 35%, precision: 15%, creativity: 5%, insight: 5%, reliability: 40% }
```

### 4.2 Стартове leaning

Кожна роль має **дефолтний архетип-вектор** у `RoleCatalogEntry`. При наймі у v1 застосовується саме він (без rarity-roll — це v2). На результат накладається **±15% noise** per-скіл для легкої варіації між агентами однієї ролі.

### 4.3 Drift через TraitStore

Архетип **еволюціонує** через досвід. Існуюча `AgentTrait` система ([lib/models/agent_trait.dart](../../lib/models/agent_trait.dart), server `TraitStore`) — субстрат.

Кожен завершений task оновлює `TraitStore`:
- Швидка задача без багів → `strength: {tag: "fast-delivery"}`.
- Глибокий рефакторинг → `strength: {tag: "architecture"}`.
- Провалена Hard задача → `weakness: {tag: "complex-reasoning"}`.

Після досягнення порогу (`frequency ≥ 3`, `≥ 5` — emphasis escalates), trait мапиться на архетип-drift:

```
fast-delivery       → +0.5% speed weight,     −0.25% precision, −0.25% reliability
architecture        → +0.5% insight weight,   −0.25% speed
refactoring-patience → +0.5% precision,       −0.5% speed
rapid-iteration     → +0.5% reliability,      +0.25% speed, −0.5% precision
divergent-brainstorm → +0.5% creativity,      −0.25% precision
complex-reasoning (weakness) → −0.5% insight (агент стає обережнішим)
```

Сумарний drift обмежений: **жодна вага не виходить за ±15% від стартового leaning**. Це — математична межа "10-15% behavioral drift", підтверджена LLM-експертом.

### 4.4 Видимість для гравця

- Radar-chart (пентагон) показує **поточний** стат-розподіл агента.
- Tooltip: "Архетип: Methodical Architect (еволюціонує)".
- Якщо drift наближається до порогу — в UI з'являється annotation: "⚡ Stat drift: +3% speed, -2% precision over 12 tasks".

Гравець НЕ може вручну перевизначити вектор. Вплив — через вибір задач (L1).

## 5. Quirks

### 5.1 Концепція

Quirks — **permanent flavor-модифікатори**, призначені при наймі (1-2 випадкових з пулу). Не еволюціонують, не дрейфують. Дають характер поза межами ролі/архетипу.

### 5.2 Пул (server-side enum)

Стартовий каталог — 12 quirks. Всі з enum-словника (не freeform), безпечно інжектяться в system prompt:

| ID | Name (UA) | Ефект |
|---|---|---|
| `night_owl` | Сова | +25% speed після 20:00 local, -10% до 12:00 |
| `perfectionist` | Перфекціоніст | +15% precision, +15% task time |
| `caffeine` | Кофеїнозалежний | +30% reliability, 5% chance `-50% speed` (crash) |
| `fast_learner` | Швидконавчаний | +50% XP gain, але skills start -1 |
| `mentor` | Наставник | Інші агенти поруч отримують +5% швидкості |
| `minimalist` | Мінімаліст | Виконує задачі короткими патчами (-20% tokens) |
| `over_engineer` | Оверінженір | +20% quality на Hard+, +15% time |
| `team_player` | Командний | +10% якщо в multi-assignee задачі |
| `lone_wolf` | Одинак | +15% speed на solo задачах, -15% на multi |
| `polyglot` | Поліглот | Може виконувати `ui-design` і `coding` однаково |
| `rookie` | Новачок | -10% всі стати, +100% XP gain (росте швидко) |
| `legend` | Легенда | Stats start at 1.5× normal, 0 extra XP (не росте) |

### 5.3 Assign logic

- 1 quirk з імовірністю 70%.
- 2 quirks з імовірністю 25%.
- 0 quirks з імовірністю 5%.
- Два `legend`+`rookie` одночасно — заборонено (конфлікт).

Quirks видимі в UI як бейджі під аватаром.

## 6. Task completion formulas

### 6.1 Time

```
base_time = difficulty × 12s      (implementation column)
          = difficulty × 6s       (testing column)

speed_modifier    = 20 / (10 + skill[Speed])
hardware_modifier = hardwareTier.speedModifier  (existing)

effective_time = base_time × speed_modifier × hardware_modifier
              × quirk_time_multiplier  (якщо є perfectionist/over_engineer/etc.)
```

Speed 10 → коеф. 1.0. Speed 0 → 2.0 (×2 повільніше). Speed 20 (Lv 5+) → 0.67 (×1.5 швидше). Діапазон безпечний.

### 6.2 Quality rolls при completion

```
bug_chance        = max(0, 0.4 - 0.03 × skill[Precision])
crit_chance       = 0.02 × skill[Creativity]   (тільки на divergent task types)
completion_success = min(1, 0.85 + 0.01 × skill[Reliability])
```

- `bug`: задача переходить `in-progress → testing → in-progress` (повернення з testing, -50% XP gain).
- `crit`: +100% gold reward.
- `incomplete` (провал `completion_success`): задача переходить `in-progress → backlog`, агент отримує weakness-trait і +20% XP при наступній спробі (failure_bonus).

### 6.3 Reviewer-pass trigger

Якщо `skill[Precision] ≥ 7`:
- Автоматично спаунить `reviewer` sub-agent як другий прохід.
- Затрата токенів +50-80% від базової.
- `bug_chance` ділиться на 3 (додаткова перевірка).

## 7. Energy meter (token budget)

### 7.1 Концепція

**Явний** ресурс у UI, що обмежує використання дорожчих моделей. Мапиться на реальну токен-економіку Claude API. Три tier-и:

| Tier | Model | Daily budget (F2P) | Cooldown |
|---|---|---|---|
| **Basic** | haiku | unlimited | - |
| **Pro** | sonnet | 20 tasks/day | - |
| **Luxury** | opus | 3 tasks/day | 2h between |

Idle-режим (коли app минімізований або офіс не активний) = **haiku only**. Active-play розблоковує Sonnet/Opus.

### 7.2 Hard cap

Hard cap на tokens/day (summed across all agents) — встановлюється у settings. **За замовчуванням — 500k tokens/day** (~$1-3 реальних витрат залежно від моделі). Гравець може підвищити в settings, але warning-модалка показує estimated cost.

### 7.3 UI

- Energy bar у хедері офісу: `🪫 124k / 500k tokens`.
- При старті дорогої задачі: tooltip "Estimated: 15k tokens (~$0.12)".
- При досягненні 90% — попередження-toast.
- При досягненні 100% — Sonnet/Opus вимикаються, haiku лишається.

### 7.4 Зв'язок з existing dynamicModel

`hardwareToModel + skillsToModel + minModel` ([server/src/agents.ts:225-251](../../server/src/agents.ts#L225-L251)) зберігається, але шарується з Energy check:

```
effective_model = energyCheck(min(hardwareToModel, skillsToModel))

function energyCheck(requested):
  if daily_budget_exceeded:
    return "haiku"
  if requested == "opus" and opus_cooldown_active:
    return "sonnet"
  return requested
```

## 8. New roles (first wave)

### 8.1 Role catalog additions

Три нові ролі додаються до `roleCatalog` ([lib/models/game_economy.dart:481](../../lib/models/game_economy.dart#L481)):

#### Product Manager
```
roleType: 'product-manager'
baseName: 'Продакт'
role: 'Продакт менеджер'
specialization: 'Написання specs, roadmap, feature prioritization'
weakness: 'Не пише код; залежить від coder для реалізації'
hireCost: 600
salary: 60
archetype_weights: { speed: 15%, precision: 30%, creativity: 25%, insight: 25%, reliability: 5% }
task_types: ['product-spec', 'management']
passive: AgentPassive(
  icon: '📋',
  name: 'Clarity of Vision',
  nameUk: 'Чіткість візії',
  description: 'PM-написані тикети дають -20% bug_chance coder-у на implement.',
)
```

#### Data Analyst
```
roleType: 'data-analyst'
baseName: 'Аналітик'
role: 'Аналітик даних'
specialization: 'Funnel аналіз, A/B testing, retention reports'
weakness: 'Повільний на implement-задачах; не вміє в UI'
hireCost: 700
salary: 55
archetype_weights: { speed: 10%, precision: 40%, creativity: 15%, insight: 30%, reliability: 5% }
task_types: ['data-analysis']
passive: AgentPassive(
  icon: '📊',
  name: 'Pattern Recognition',
  nameUk: 'Розпізнавання патернів',
  description: 'Завершена analysis-задача дає -20% time наступній coding-задачі.',
)
```

#### DevOps
```
roleType: 'devops'
baseName: 'Опс'
role: 'DevOps інженер'
specialization: 'CI/CD, infra, incidents, monitoring'
weakness: 'Не пише фічі; реактивна роль'
hireCost: 650
salary: 55
archetype_weights: { speed: 20%, precision: 25%, creativity: 5%, insight: 20%, reliability: 30% }
task_types: ['devops']
passive: AgentPassive(
  icon: '🔧',
  name: 'Infra Stability',
  nameUk: 'Стабільність інфри',
  description: 'DevOps-активний = -50% шанс production incident (нова механіка, v2).',
)
```

### 8.2 Server-side role templates

Додаються у [server/src/agents.ts](../../server/src/agents.ts) як нові записи в `roleTemplates`:

- `product-manager`: `prompt` фокус на specs, `tools: [Read, Write, Grep]`, `model: sonnet`.
- `data-analyst`: `prompt` фокус на читання логів/даних, `tools: [Read, Bash, Grep]`, `model: sonnet`.
- `devops`: `prompt` фокус на deployment/infra, `tools: [Read, Bash, Write, Edit]`, `model: sonnet`.

## 9. UI changes

### 9.1 Radar chart

Новий віджет `AgentSkillRadar` у `lib/widgets/agent/`. Рендерить пентагон з 5 осями (Speed/Precision/Creativity/Insight/Reliability). Значення 0-20 (враховуючи skill cap).

Показується:
- На картці агента у shop / team панелі.
- В tooltip при наведенні.
- В модалці деталей агента (повний радар + drift annotation).

### 9.2 Task card зміни

Картки задач у [lib/widgets/board/task_board_panel.dart](../../lib/widgets/board/task_board_panel.dart) отримують:
- Чипи `🎯 Lv 4+ · PM` (required level + allowed roles).
- Difficulty badge залишається (1-5 зірочок).
- При призначенні невідповідного агента — error tooltip з конкретикою: "Coder не робить product-spec задачу. Потрібен Product Manager Lv2+."

### 9.3 Level badge

Біля nickname агента — `Lv 5` бейдж. На канвасі (pixel art office) — рівень над головою спрайту (Lv 1-9 → "1"-"9", Lv 10+ → "⚡").

### 9.4 Token/Energy meter

У хедері офісу:
```
🪫 124k / 500k   ⚡ Opus: 2/3   ⚡ Sonnet: 15/20
```

Клік → модалка з деталями витрат і налаштувань cap-у.

### 9.5 Reviewer-pass індикатор

Коли призначається агент з `Precision ≥ 7` — бейдж на картці задачі: `⚡ ×1.8 tokens (reviewer pass auto)`. Колір — yellow/amber (застереження про вартість).

## 10. Архітектура коду

### 10.1 Dart (client)

#### Нові моделі

**Файл:** `lib/models/agent_archetype.dart` (новий)

```
class ArchetypeVector {
  final Map<SkillType, double> weights;  // сума = 1.0
  ArchetypeVector normalize();
  ArchetypeVector driftBy(TraitType, String tag);  // apply drift from trait
}

class Quirk {
  final String id;             // 'night_owl', 'perfectionist', ...
  final String nameUk;
  // Effects резолвяться за id в логіці — не зберігаються в Dart (server-side).
}

const quirkCatalog = <Quirk>[ /* 12 штук з розділу 5.2 */ ];
```

**Файл:** `lib/models/game_economy.dart` (зміни)

```
// ─ SkillType ─ замінюємо
enum SkillType {
  speed,
  precision,     // було quality
  creativity,    // нове
  insight,       // було problemSolving
  reliability,   // було specialization/communication (оновлена семантика)
}

// ─ AgentGameData ─ додаємо поля
class AgentGameData {
  // існуючі: instanceId, roleType, nickname, hardware, skills
  final int level;                        // нове
  final int xp;                           // нове
  final ArchetypeVector archetype;        // нове (поточний вектор після drift-ів)
  final List<String> quirkIds;            // нове
  // skillXp — прибираємо
}

// ─ RoleCatalogEntry ─ розширюємо
class RoleCatalogEntry {
  // існуючі
  final ArchetypeVector defaultArchetype;      // нове
  final List<String> taskTypes;                // нове (які типи задач може брати)
}
```

**Файл:** `lib/models/task_board.dart` (зміни)

```
class TaskCard {
  // існуючі
  final int requiredLevel;          // нове (derived from difficulty)
  final List<String> allowedRoles;  // нове
  final String taskType;            // нове
}

// Прибираємо extension TaskDifficultyExt.requiredSkill
// Додаємо: int requiredLevelFor(int difficulty) => [0, 1, 2, 4, 7, 11][difficulty];
```

#### Нові провайдери

**Файл:** `lib/providers/agent_evolution_provider.dart` (новий)

- Слухає завершення задач (task moved to `done`).
- Обчислює drift для архетипу (викликає `ArchetypeVector.driftBy`).
- Персистить оновлений `AgentGameData.archetype`.

**Файл:** `lib/providers/energy_provider.dart` (новий)

- Зберігає daily token budget.
- Відстежує cooldown-и на Opus/Sonnet.
- Рекомендує effective model перед відправкою задачі.
- Скидає budget о півночі local.

### 10.2 Server (TypeScript)

**Файл:** [server/src/agents.ts](../../server/src/agents.ts) (зміни)

- `roleTemplates` — додати `product-manager`, `data-analyst`, `devops` (див. 8.2).
- `skillsToModel` — перекалібрувати під нові 5 скілів. Нова формула:
  ```
  capability_score = 0.4 × insight + 0.3 × precision + 0.2 × reliability + 0.1 × creativity
  if capability_score ≥ 14: opus
  if capability_score ≥ 8:  sonnet
  else: haiku
  ```
  Speed НЕ входить у capability — він впливає тільки на `reasoning_effort`.

**Файл:** `server/src/archetype_drift.ts` (новий)

- Функція `applyDrift(agentId, taskOutcome, traitStore)`.
- Маппінг trait tags → archetype weight deltas (таблиця з 4.3).
- Клемпер: не дозволяє вазі вийти за ±15% від дефолтного leaning.

**Файл:** `server/src/reviewer_pass.ts` (новий)

- Wrapper навколо `query()`: якщо `agent.skills[Precision] ≥ 7`, після основного проходу спаунить `reviewer` sub-agent з контекстом змін.
- Повертає combined result + бейджик "reviewer-validated".

**Файл:** `server/src/energy_tracker.ts` (новий)

- Per-user accumulator daily token usage.
- API для Dart: GET `/energy/budget`, POST `/energy/task-estimate`.
- При перевищенні — downgrade model silently (вже повідомлено UI через push).

### 10.3 Drop migration

- `GameState.schemaVersion` bumped (наприклад, 2 → 3).
- При завантаженні save з попередньою версією: `GamePersistenceService` детектить mismatch і reset-ить state до fresh з current version.
- Toast при першому запуску нової версії: **"Оновлення системи агентів вимагає перезапуску прогресу. Ваші гримні і ачівки збережені." — OK**.
- Що зберігається: `grymni`, `coinsEarnedTotal`, `cosmeticsPurchased`, `achievementsUnlocked`. Що скидається: `agents`, `office`, `taskBoard`, `traits`.

## 11. Дизайн v2+ (документація, не імплементуємо)

### 11.1 Rarity при наймі

Розподіл: Common 70% / Uncommon 22% / Rare 7% / Epic 1%.

Впливає на:
- Стартовий `stat_budget` (Common=30, Uncommon=35, Rare=42, Epic=55 pts).
- Кількість quirks (Common: 1, Uncommon: 1-2, Rare: 2, Epic: 2-3).
- Рідкість trait-tag-ів одразу в TraitStore.

**НЕ** впливає на: `skill_cap`, `level cap`, task gating. Common може вирости в топового.

### 11.2 Marketplace

- Одна валюта: `grymni`.
- Listing fee: 5% SSP. Transaction fee: 10% sale price.
- Resale time-lock: 72h real time.
- Max active listings на гравця: 3 (стартово), розблоковується до 10 через engagement.
- System-suggested price:
  ```
  SSP = 500 × level^1.4
      + 80 × stat_sum
      + trait_value (Common 300, Uncommon 1200, Rare 5000, Epic 20000 per trait)
      + 2000 × (archetype_purity > 0.7 ? 1 : 0)
      + model_tier_bonus (haiku 0, sonnet +3000, opus +15000)
  ```
- Price floor: `SSP × 0.3` (захист від dumping).

### 11.3 LLM-procgen daily pool

- Cron job генерує 3 кандидати/день на гравця (seed = `hash(userId + date + slot)`).
- Cost ~$0.01/рекрут (haiku generation).
- Batched request (10 за раз) з інструкцією "make distinct".
- Непохані згорають о півночі (anti-hoarding).
- Weekly event → guaranteed pity recruit.

### 11.4 Adjustment Period

Після купівлі агента на marketplace:
- 48h real-time: trait frequency × 0.7 (агент "звикає до нового офісу").
- 7 day real-time: archetype drift швидкість × 0.5.
- Traits зберігаються, просто тимчасово приглушені.

### 11.5 Enum-словник для traits

Server-only enum `TraitTag`:
- Сервер обирає tag з fixed pool на основі task outcome (не freeform text).
- Traits сериалізуються як `{tagId, frequency, firstSeen, lastSeen}` — no free text.
- Sanitization при експорті для marketplace: whitelist полів + LLM-classifier на suspicious patterns.

### 11.6 Spawn progression

```
Week 1: Tutorial + 1 permanent agent (Junior Coder) + 2 rental contracts.
Week 2+: Daily pool 3 candidates (procgen) + weekly event + marketplace access.
Lv 5 achievement: unlocks Uncommon rarity candidate slots.
Lv 10: unlocks Rare.
Lv 15: unlocks Epic.
```

## 12. Ризики та відкриті питання

1. **Capability ceiling** (LLM-обмеження): гравці можуть очікувати, що еволюційний Haiku-агент буде кращий за свіжого Opus-а. Це фундаментально не так. **Мітигація:** UI явно показує model tier як окрему характеристику; у гайді пояснюємо "модель — це стеля".

2. **Token budget calibration:** 500k tokens/day — стартова цифра, може виявитись забагато/замало. **Мітигація:** collect data в перший тиждень soft-launch, adjust у configs.

3. **Drop save-файлів:** засмутить гравців з прогресом. **Мітигація:** toast-попередження + `grymni`/achievements/cosmetics зберігаються; фічі значні.

4. **Stat-budget 30 pts на Lv1:** 30/5=6 на скіл в середньому. Потрібно перевірити, чи цього достатньо для відчутних відмінностей між архетипами. **Можливо підняти до 40**, якщо playtest покаже мляву варіацію.

5. **Precision reviewer-pass cost:** гравець може зловживати низько-Precision агентами, щоб не витрачати токени. Це ОК як геймплейний tradeoff, але треба перевірити, чи не робить це Precision просто "dominant stat to avoid".

6. **Drift mapping table (4.3) баланс:** коефіцієнти ±0.5%/tag — емпірично. Треба sim-тестити: скільки задач до повного drift-у до cap-у 15%?

## 13. Критерії готовності v1

- [ ] `AgentGameData` має `level`, `xp`, `archetype`, `quirkIds`.
- [ ] `SkillType` — 5 нових enum values: `speed, precision, creativity, insight, reliability`.
- [ ] `skill_cap = 10 + 2×level` enforce-иться при апгрейді у shop.
- [ ] XP-формула обчислюється на завершенні задачі; `level` росте.
- [ ] `TaskCard` має `requiredLevel`, `allowedRoles`, `taskType`; gating працює.
- [ ] UI показує: radar chart, level badge, task card з requirements, energy meter, reviewer-pass індикатор.
- [ ] 3 нові ролі видимі в shop (product-manager, data-analyst, devops) + їхні prompts у server.
- [ ] 12 quirks призначаються при наймі з probability distribution.
- [ ] Archetype drift працює: після 20+ завершених задач вектор зсувається.
- [ ] `reviewer` sub-agent автоматично спаунить при `Precision ≥ 7`.
- [ ] Energy meter show-ить token budget; модель падає до haiku при перевищенні.
- [ ] Toast при завантаженні старого save + reset state.
- [ ] Документ v2+ (розділ 11 вище) існує як reference для наступних ітерацій.

## 14. Посилання

Основні файли, які зачіпаються:
- [lib/models/game_economy.dart](../../lib/models/game_economy.dart) — SkillType, AgentGameData, RoleCatalogEntry, HardwareTier.
- [lib/models/task_board.dart](../../lib/models/task_board.dart) — TaskCard, TaskDifficulty.
- [lib/models/agent_trait.dart](../../lib/models/agent_trait.dart) — TraitStore (існуюча база для drift).
- [lib/providers/task_progress_provider.dart](../../lib/providers/task_progress_provider.dart) — час виконання задач.
- [lib/providers/game_economy_provider.dart](../../lib/providers/game_economy_provider.dart) — XP/gold awards.
- [lib/widgets/board/task_board_panel.dart](../../lib/widgets/board/task_board_panel.dart) — UI карток.
- [lib/widgets/shop/shop_panel.dart](../../lib/widgets/shop/shop_panel.dart) — shop, найм, апгрейд скілів.
- [server/src/agents.ts](../../server/src/agents.ts) — role templates, model selection.
- [server/src/agent_runner.ts](../../server/src/agent_runner.ts) — sub-agent dispatch.
