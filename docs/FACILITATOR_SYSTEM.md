# Facilitator System — Design Document

## 0. Теза ідеї

**Проблема:** Розмова про код "голою" мовою має технічний нахил, який далеко не всім користувачам комфортний. PixelCode має 7 ролей агентів, hire/fire, traits — але **стиль ведення роботи** залишається фіксованим: один тон, одна риторика, один процес для всіх.

**Рішення:** **Facilitator System** — користувач обирає **стиль ведення розробки** (як працює його команда), а не лише її склад. Facilitator — це не новий агент, а **модальність взаємодії manager-агента**: лексикон, ритм церемоній і output-формат, через який великі цілі стікають у kanban-задачі.

**Перевіт у стратегію:**
- Не конкуруємо з Lovable/Bolt/v0 на полі "idea→app"
- Розширюємо existing PixelCode як "оркестратор агентів на твоєму проекті"
- Quest System стає **одним з режимів** (Game Master), не центральною механікою
- Facilitator-пресети — natural fit для marketplace (E, Q4 2026)

---

## 1. Reframe — як вписується в існуючі моделі

**Одне речення:** Facilitator — це **lexicon + ceremony + output-mapper layer** поверх manager-агента ([agents.ts](../server/src/agents.ts)), що визначає *як* команда веде роботу, не змінюючи *хто* в команді.

### Що використовуємо як є (нуль нового scope)

| Існуюча система | Як використовуємо |
|---|---|
| Hire/fire 7 ролей | Незмінно. Facilitator не змінює ростер. |
| Kanban board ([task_board_panel.dart](../lib/widgets/board/task_board_panel.dart)) | **Інваріант.** Всі стилі врешті-решт продукують `Task[]` у ту саму дошку. Style — transformation шар поверх. |
| Agent traits ([agent_trait.dart](../lib/models/agent_trait.dart)) | Facilitator зчитує traits для tone-adaptation ("trait `meticulous` → Drill пом'якшує наїзд"). |
| Agent level / skillCap ([agent_level.dart](../lib/models/agent_level.dart)) | XP належить **агенту**, не стилю. Style switch не скидає рівень. |
| Energy meter ([energy_meter.dart](../lib/widgets/energy/energy_meter.dart)) | Обмежувач ceremony cost. |
| Lesson lifecycle ([memory_lifecycle.ts](../server/src/memory_lifecycle.ts)) | Facilitator пише lessons в окремий namespace (див. §5). |
| Quest System ([quest_line.dart](../lib/models/quest_line.dart), [scope_scorer.ts](../server/src/quest/scope_scorer.ts), [quest_persistence_service.dart](../lib/services/quest_persistence_service.dart)) | `QuestLine` стає одним з імплементаторів `FacilitatorOutput`. `ScopeScorer` використовується **всіма** стилями. Persistence генералізується. |

### Що нове (мінімум)

- `FacilitatorStyle` — preset (JSON): persona prompt, lexicon, ceremony schedule, output-format mapper
- `FacilitatorRunner` — server-side: intake → seed kanban → on-event ceremonies
- `FacilitatorOutput` — спільний контракт, що всі формати конвертуються в kanban tasks

---

## 2. Стартовий набір стилів (5)

Чому 5: контраст важливіший за охоплення. Покривають Laloux Red→Teal без надлишкових варіацій. 6-та (Orange-corporate-classic) дублює Scrum Master по mechanics — викинуто свідомо.

| Style | Laloux | One-liner | Audience | Ceremony rhythm | Lexicon (приклади) | Output format |
|---|---|---|---|---|---|---|
| **Drill Sergeant** | Red (Impulsive) | "Стули рота і деплой." | Solo з tendency to over-plan; brutal forcing function | Daily 30s "report"; жодних retros | "deploy", "ship it", "no excuses", "mission" | `MissionBriefing` |
| **Marina** | Amber (Conformist) | "Процес важливіший за людей. Дотримуємось плану." | Corporate refugees; хто звик до Jira; love hierarchy | Weekly status; monthly review | "milestone", "blocker", "stakeholder", "scope" | `MilestoneTree` |
| **Scrum Master** | Orange (Achievement) | "Sprint goal, daily standup, retro в п'ятницю." | Команди >2 агенти; хто любить ритм + velocity | 2-week sprints, daily standup, retro | "sprint", "velocity", "story points", "DoD" | `SprintBacklog` |
| **Game Master** | Green (Pluralistic) | "Quest-line з наративом і reveal-ом." | Hobby-builder, нетехнічний юзер з ідеєю | Per-quest pacing (no fixed cadence) | "quest", "act", "forge", "reveal" | `QuestLine` (existing) |
| **Stoic Mentor** | Teal (Evolutionary) | "Що ти насправді хочеш збудувати? Опиши перешкоду." | Solo deep-work; sam собі менеджер | On-demand reflection; weekly journal | "obstacle", "discipline", "intention" | `KoanEntry` |

### Контрастна матриця

```
            High structure          Low structure
Hard tone   Drill Sergeant          —
Mid tone    Marina, Scrum Master    —
Soft tone   Game Master             Stoic Mentor
```

Порожня клітинка "hard tone, low structure" — навмисно лишена як кандидат для marketplace ("Punk Anarcho", "Hacker News Maximalist").

### Laloux mapping rationale

Marina = **Amber** (не Orange), бо її кістяк — *формальна ієрархія, дотримання плану, milestone-tree*. Scrum Master = **Orange**, бо ядро — *meritocratic achievement через velocity і retros*. Це різні output shapes (декларативний план vs емпіричний цикл) і різні lessons.

---

## 3. Спільний інтерфейс

```typescript
interface FacilitatorStyle {
  id: string;                          // "drill_sergeant"
  laloux: "red" | "amber" | "orange" | "green" | "teal";
  personaPrompt: string;               // injected у manager-агента
  lexicon: Record<string, string>;     // canonical → styled ("task" → "mission")
  ceremonySchedule: CeremonySpec[];
  intakeTemplate: IntakeQuestion[];    // 0..N питань на старті
  outputMapper: OutputFormat;          // "quest_line" | "sprint_backlog" | "milestone_tree" | "mission_briefing" | "koan_entry"
  toneModifiers: {
    aggression: number;                // 0..1
    formality: number;                 // 0..1
    verbosity: number;                 // 0..1
  };
}

interface FacilitatorRunner {
  start(projectIdea: string, style: FacilitatorStyle, team: Agent[]): Promise<FacilitatorOutput>;
  tick(event: FacilitatorEvent): Promise<CeremonyTrigger | null>;
  ceremonyDue(now: Date): Ceremony | null;
  switchStyle(toStyle: FacilitatorStyle): SwitchResult;
}

// Всі output shapes імплементують це:
interface FacilitatorOutput {
  toKanbanTasks(): TaskCard[];          // канонізація — kanban як ground truth
  toCanonicalProgress(): ProgressView;  // % completion, агрегати
  serialize(): string;                  // для persistence + marketplace
}
```

**Принцип:** kanban — інваріант. Style — transformation поверх. Це робить marketplace-валідацію тривіальною (`output.toKanbanTasks().length > 0` — sanity check).

---

## 4. Перевикористання Quest System роботи

**Рекомендація: НЕ переліплюємо `QuestLine` на всі стилі. Кожен output-формат — свій shape.**

Чому ні:
- `Act` / `payoffLine` / cloth-reveal — narrative-specific. Sprint не має "акту", milestone не має "reveal-у з тканиною".
- Силоміць натягувати QuestLine на Sprint — lossy abstraction. Sprint потребує `velocity`, `points`, `retroNotes`, яких в QuestLine немає.
- Marketplace-листинг хоче відрізняти "Game Master preset з 5 quest templates" від "Scrum preset з sprint cadence config" — різні shapes тут це фіча.

### Конкретний refactor план

| Артефакт | Що з ним відбувається |
|---|---|
| [`lib/models/quest_line.dart`](../lib/models/quest_line.dart) | Стає одним з імплементаторів `FacilitatorOutput` (Game Master mode). Внутрішня структура без змін, додається interface contract. |
| [`server/src/quest/scope_scorer.ts`](../server/src/quest/scope_scorer.ts) | Перейменовується (опційно) в `project_scope_scorer.ts`. Використовується **всіма стилями** для калібрування output size. |
| [`lib/services/quest_persistence_service.dart`](../lib/services/quest_persistence_service.dart) | Узагальнюється до `facilitator_output_persistence_service.dart`. File path формат: `quest_line.json` → `facilitator_output.json` (один на проект). |
| 23+7+13 тестів | Лишаються. Тільки namespace оновлюється. |

### Нові shape-и (мінімум на старті)

- `MissionBriefing` (Drill) — 1-3 mission cards, кожен з brutal one-liner
- `MilestoneTree` (Marina) — root → milestones → tasks (gantt-light)
- `SprintBacklog` (Scrum) — sprint windows, backlog items, points
- `KoanEntry` (Stoic) — reflection prompt + 1-2 next actions
- `QuestLine` (GM) — existing

Кожен має мінімальний JSON serde і метод `toKanbanTasks()`.

---

## 5. Personalization integration

### Style binding — до агента, не сам по собі

Facilitator — **preset з progression-шаром, але без власного "рівня"**. Прогрес belongs to **manager-агента** (Marina, Drill Sergeant Hartman).

**Чому:**
- Уникає 2 progression-bars (агент + стиль) → подвійне когнітивне навантаження
- Перевикористовує [agent_level.dart](../lib/models/agent_level.dart) — нуль нового UI/механіки
- "Marina рівень 5" — природне читання: конкретна персона менеджера, що з тобою росте

### Lesson namespacing

```
agent.lessons (existing — task-level patterns, style-agnostic)
  └── "коли user пише 'TODO без deadline' → запитати timeframe"

agent.facilitatorLessons (NEW — namespaced subset)
  ├── drill_sergeant: "user freaks out при >3 missions/day → cap"
  ├── scrum:           "user пропускає retros → switch to async retro"
  └── stoic:           "user стабільно пропускає koans на тиждень → silent mode"
```

### Style switch behavior

| Що відбувається | Поведінка |
|---|---|
| `agent.lessons` (task-level) | **Переходять.** Знання про код/проєкт — інваріант. |
| `agent.facilitatorLessons[oldStyle]` | **Залишаються в namespace, але не активні.** |
| `agent.facilitatorLessons[newStyle]` | **Починаються з нуля для нового стилю.** |

**Гравцевий experience:** "перейшов з Drill на Marina — manager знає мій код, але не знає, як ZE мене веде по Marina-режиму". Бонус: природний retention хук — switch коштує накопичений facilitator-досвід.

**Decay:** facilitatorLessons підпадають під ту саму schedule з [memory_lifecycle.ts](../server/src/memory_lifecycle.ts), без додаткового коду.

---

## 6. Hierarchical Prompt Safety

**Це найризикованіша частина системи.** Без неї Drill Sergeant буде пропихати "ship it" повз tech-lead-а, а Marina — наполягати на "milestone хоч в продакшен з багами".

### Інваріант

Facilitator-style **впливає на**:
- Тон, формальність, verbosity
- Lexicon (label substitution)
- Ceremony rhythm (коли/як часто)
- Output format shape

Facilitator-style **НЕ впливає на**:
- Архітектурні рішення
- Code quality bar
- Whether to ship vs rewrite
- Security/quality gates

### Routing

```
User message
    │
    ▼
Manager-агент (з facilitator persona) парсить intent
    │
    ├─ Якщо "як зробити X технічно?" / "чи варто Y?"
    │     → Tech-lead consulted (його prompt — інваріант)
    │     → Tech-lead-відповідь pure-tech
    │     → Manager переформулює через style.lexicon
    │
    └─ Якщо "коли deadline?" / "розкажи progress" / "стартанемо нову задачу"
          → Manager сам відповідає в style
```

**Tech-lead має veto.** Якщо tech-lead каже "ні, не ship — потрібен rewrite", facilitator-style лише визначає **тон передачі цього "ні"**:

- Drill: "Stand down. Tech-lead каже rewrite. Деплой блоковано."
- Marina: "Milestone delayed. Blocker: rewrite required. Updating gantt."
- Scrum: "Adding to backlog: rewrite. Story points: 8. Не входить у поточний sprint."

### Реалізація (prompt template)

```
[manager-base-prompt]    ← invariant, з agents.ts
[facilitator-style-overlay]   ← тільки lexicon + tone + ceremony, БЕЗ tech-decisions
[delegation-rules]  ← invariant: "any 'should we' / 'how to' / 'is X safe'
                      → дзвоніть tech-lead first, потім переформулюйте"
```

Цей розподіл прописується в **base prompt template** до того як писати першу style-у. Інакше неможливо буде fix-нути після.

---

## 7. Marketplace path

**Що продається:** `FacilitatorStyle` JSON. Без weights, без LoRA — pure prompt-pack (співпадає з STRATEGY §1, Q3 2026 фаза).

### Quality signals (перевикористання E.quality_score)

- **Compatibility tag** — automatically тестуємо style на standardized "demo project" (todo-app зі scope_scorer-а), фіксуємо: чи довів до deploy / token spend / ceremony count / retention в test harness
- **Adoption + retention rate** — % юзерів що активно використовують стиль 7+ днів після install
- **NPS-like rating** від юзерів (вже планується в E.rating+review)

### Anti-collusion (вже в E.anti-collusion logic)

- Один акаунт ≤ 3 styles published / місяць
- Style з <100 input bytes у personaPrompt — блокується (anti-low-effort spam)
- Token-spend median test: якщо style провокує 3× median token spend на demo project → flagged for review (anti-token-burner styles)

### Pricing

| Tier | Ціна |
|---|---|
| Default 5 styles | Free вічно |
| Community styles | $1.99–4.99 one-time, OR free + 15-20% commission якщо paid |
| Premium "celebrity" styles | $9.99 (за умови ліцензії — "Linus Torvalds Mode" і т.п.) |
| Premium agent listings (з I.monetization, Q3 2027) | $2-10/міс promotion |

### Cold start

- 5 default стилів у Q3 2026 — закриває 80% need
- Marketplace відкриваємо в Q4 2026 паралельно з E — спочатку seedимо самі (ще 5-10 стилів від нас)
- Перші 3 місяці marketplace — **curated only**, open submissions з Q1 2027

---

## 8. MVP cut для Q3 2026

**Мета:** 2-3 стилі викочуються паралельно з C (Personalization UI), без marketplace, без Custom Agent Spawn dependency.

### В MVP

1. **3 стилі:** Game Master, Marina (Amber), Drill Sergeant
   - GM — переробка existing quest роботи (нуль ризику)
   - Marina — найпопулярніший очікуваний стиль (corporate refugees)
   - Drill — emotional contrast, доводить що абстракція справді абстрагує
2. **Style picker UI** — modal на старті проєкту "Choose your facilitator". Lockable via "remember choice"
3. **`FacilitatorStyle` schema + 3 hard-coded JSON-и** в `assets/facilitators/*.json`
4. **`FacilitatorRunner` server-side** — мінімум: intake, seed kanban, on-task-completed reaction
5. **Lexicon swap у UI strings** — kanban headers інваріант, тільки subtitle/badge style-specific
6. **Per-agent style binding** — manager-агент запам'ятовує style; switch UI у personalization screen (єдина точка інтеграції з C)
7. **Hierarchical prompt safety** — base prompt template з §6 готовий до того як перший стиль ініціалізується
8. **Test coverage** — кожен з 3 стилів має integration test "intake → seed kanban → 1 task complete → ceremony fires"

### НЕ в MVP

- Scrum Master і Stoic Mentor (Q4 2026)
- Marketplace listing (Q4 2026 паралельно з E)
- User-defined styles (Q3 2027 з Custom Agent Spawn)
- Cross-style lesson migration UI (Q4 2026, маленька фіча)
- Style "level" візуалізація (явно НЕ робимо — рівень agent-а покриває)
- Adapter weights для styles (Q3 2027 коли G/H готові)

**Effort:** ~2-3 engineer-weeks паралельно з C (3-4 weeks). Більшість часу — refactor quest persistence у generic `FacilitatorOutput` infrastructure + style picker UI.

---

## 9. Failure modes + запобіжники

| Failure mode | Як виглядає | Запобіжник |
|---|---|---|
| **Token cost double-billing** | Facilitator + tech-lead обидва генерують → 2× token burn → energy meter висихає | Lexicon swap — pure string-level (zero LLM); ceremony — один LLM call; persona-prompts кешуються через [prompt_cache_manager.ts](../server/src/prompt_cache_manager.ts) |
| **Style fatigue** | DAU drop через 3 тижні; sentiment негативний | Built-in suggest-switch prompt: facilitator пропонує style change після N negative-sentiment events. Telemetry tracking (L, Q3 2026) |
| **Style/tech mismatch** | Drill хоче "ship it", tech-lead "rewrite" → confused user | Hierarchical prompt routing з §6: tech-lead має veto, style — лише lexicon translation |
| **Choice paralysis** | Drop-off на onboarding screen (5 опцій) | Default = Game Master. Style picker — secondary в Settings, не блокуючий |
| **Lexicon-pollution lessons** | Drill-lessons мігрують в Marina-mode → дисонанс | Strict namespacing (§5). `agent.lessons` — style-agnostic invariant. |
| **Marketplace race-to-bottom edgelord** | "Putin Mode", "Hitler Mode" listings | Curated submission Q1 2027+. Banned-style policy в Terms. Quality signal обмежує organic surfacing. |
| **Manager рівень "обнулився" відчувається при switch** | Юзер прокачав Marina → switch на Drill → відчуття втрати | Copywriting в UI: "Marina переходить в Drill mode. XP/lessons лишаються. Ритуали починаються заново." Це фіча, не баг — але requires explicit messaging. |
| **Reward hacking facilitator output** | Drill видає 50 фейкових completed missions / день | Outcome rolls ([task_outcome.dart](../lib/services/task_outcome.dart)) — інваріант. XP rate-limited через skillCap. Жодних додаткових захистів. |

---

## 10. Implementation Roadmap

### Phase 1: Schema + Refactor (3-4 days)

- [ ] `lib/models/facilitator_style.dart` — Style schema, output mapper enum
- [ ] `lib/models/facilitator_output.dart` — interface contract + ProgressView
- [ ] Refactor `quest_line.dart` → implements `FacilitatorOutput` (Game Master)
- [ ] Refactor `quest_persistence_service.dart` → `facilitator_output_persistence_service.dart` (generic)
- [ ] Update existing tests namespace (~43 tests should still pass)

### Phase 2: Output formats (3-4 days)

- [ ] `lib/models/mission_briefing.dart` (Drill) + `toKanbanTasks()`
- [ ] `lib/models/milestone_tree.dart` (Marina) + `toKanbanTasks()`
- [ ] Tests + JSON serde для обох

### Phase 3: Server-side runner (4-5 days)

- [ ] `server/src/facilitator/facilitator_runner.ts` — intake/seed/tick
- [ ] `server/src/facilitator/lexicon_swap.ts` — pure string translation
- [ ] `server/src/facilitator/hierarchical_safety.ts` — manager+tech-lead routing
- [ ] 3 hard-coded style JSON-и в `server/src/facilitator/styles/`

### Phase 4: UI (4-5 days)

- [ ] `lib/screens/facilitator_picker/` — modal на старті проєкту
- [ ] Style binding на manager-агенті (extends agent persistence)
- [ ] Lexicon swap layer у kanban (subtitle/badge)
- [ ] Style switch UI всередині personalization screen

### Phase 5: Integration tests (2 days)

- [ ] Per-style E2E: intake → seed → complete task → ceremony
- [ ] Style switch test: lessons preserved, namespace clean

**Сумарно:** ~16-20 engineer-days = ~2.5-3 weeks паралельно з Personalization UI.

---

## 11. Key Design Decisions

### Decision 1: Facilitator = модальність, не агент
**Why:** Уникає token-cost double-billing і дублювання personalization логіки. Fits як shape поверх existing manager-агента.

### Decision 2: Kanban як інваріант (всі стилі сходяться в одну дошку)
**Why:** Marketplace-валідація тривіальна (`output.toKanbanTasks().length > 0`). Жодного style lock-in для юзера. Switch між стилями — про lexicon, не про дані.

### Decision 3: 5 окремих output shapes (не uber-shape)
**Why:** Bag-of-options anti-pattern. Sprint не має "акту", milestone не має "reveal-у". Силоміць натягувати → lossy abstraction. Marketplace differentiation хоче різні shapes.

### Decision 4: XP належить агенту, не стилю
**Why:** Уникає 2 progression-bars. Перевикористовує [agent_level.dart](../lib/models/agent_level.dart). Природне читання "Marina рівень 5".

### Decision 5: Lessons namespaced по стилю; task-level — style-agnostic
**Why:** Знання про код інваріантне. Знання про "як вести цього юзера в Drill режимі" — style-specific. Намecpaces дають чистий switch без cross-pollution.

### Decision 6: Hierarchical prompt safety прописана **до** першої style-реалізації
**Why:** Найризикованіша частина. Якщо style починає впливати на tech-decisions — fix після факту неможливий (треба рефакторити промпти всіх стилів). Робимо invariant template на старті.

### Decision 7: 3 styles в MVP (не 5)
**Why:** GM/Marina/Drill дають максимальний контраст (емоційні полюси + corporate mid). Scrum/Stoic — Q4 2026 коли є feedback з MVP. Marketplace вимагає baseline якості — поспіх шкодить.

---

## 12. Success Criteria

- ✅ Користувач обирає style на старті проєкту → onboarding completion >70%
- ✅ Style switch flow працює без втрати task-level lessons
- ✅ Token cost ≤ 1.15× від pre-facilitator baseline (lexicon swap = string-level)
- ✅ Hierarchical safety тримається: tech-lead veto не override-ається style-prompt-ом (E2E test)
- ✅ Per-style D7 retention >50% (style fatigue не спрацьовує занадто рано)
- ✅ Quest System artifacts повністю перевикористані (нуль викинутих 43 тестів)
- ✅ Test coverage: кожен style має integration test для повного flow

---

## 13. Open Questions

1. **Style picker timing** — питати на старті проєкту, чи дати default + offer switch later? Default reduces choice paralysis, але втрачаємо "moment of personalization".
2. **Multi-project coherence** — якщо юзер обрав Drill в проекті A і Game Master в проекті B, manager-агент один і той самий чи різний? (Зараз агенти cross-project per [project_context_manager.ts](../server/src/project_context_manager.ts).) Треба рішення.
3. **Lexicon translation depth** — pure string substitution працює для labels, але як з контекстними ("blocked task" → "stuck mission" зі змінами відмінків)? Шаблони з placeholder-ами чи структуровані рядки?
4. **Ceremony skip economy** — якщо юзер пропускає standup 5 разів поспіль, що робить facilitator? Silent mode? Switch suggestion? Penalty? (Game design call.)
5. **Free style vs Pro style** — чи є styles що тільки в Pro tier? Чи 5 default — назавжди free, а Pro дає marketplace access? (Monetization design.)
6. **Custom style preview** — у Q3 2027 коли Custom Agent Spawn готовий, чи юзер тестує свій style на demo проекті перед commit, чи одразу в робочому? (UX call.)

---

**Document Version:** 1.0
**Last Updated:** 2026-04-26
**Status:** Approved by game-designer subagent — Ready for Phase 1 Implementation
