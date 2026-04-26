# Facilitator: Game Master — Design Document

> **Контекст:** Цей документ описує **один з режимів** Facilitator System (див. [FACILITATOR_SYSTEM.md](FACILITATOR_SYSTEM.md)) — **Game Master** (Laloux Green / Pluralistic).
>
> Game Master адресовано hobby-builder'ам і нетехнічним юзерам з ідеєю; output формат — `QuestLine` з наративною структурою, актами і фінальним reveal-моментом. Інші стилі (Drill / Marina / Scrum / Stoic) мають свої output формати — `MissionBriefing`, `MilestoneTree`, `SprintBacklog`, `KoanEntry` відповідно.
>
> Артефакти описані тут (`QuestLine`, `ScopeScorer`, `QuestPersistence`) перевикористовуються **усіма** стилями: scope scorer калібрує розмір output-у, persistence генералізується на `FacilitatorOutputPersistence`. Деталі — в FACILITATOR_SYSTEM.md §4.

## 1. Теза ідеї (Game Master режим)

**Проблема:** Hobby-builder з ідеєю аппки потребує **наративного супроводу**, не sprint backlog'у. "Зробити CRUD на сьогодні" і "побудувати щось живе через історію" — різні UX контракти.

**Рішення:** Перетворити побудову аппки на **квест-лайн** — наративну послідовність кроків, де кожен крок виконує реальну інженерну роботу і дає видимий артефакт. Завершення квест-лайну = робоча аппка, з фінальним reveal-моментом ("стягування тканини" з готового UI).

**Результат:**
- Чітке відчуття прогресу і scope'у з самого початку
- Емоційний payoff на кожному кроці і фінальний wow-момент
- Скоп аппки масштабується від 3 до 20+ квестів пропорційно складності ідеї
- Користувач бачить **реальний** перший екран аппки в момент завершення (не плейсхолдер)

---

## 2. Технічне завдання

### 2.1 Архітектура системи

```
┌──────────────────────────────────────────────┐
│  User describes app idea (free text)         │
└────────────────────┬─────────────────────────┘
                     │
          ┌──────────▼──────────┐
          │  ScopeScorer        │  ← keyword heuristics
          │  (5 dimensions)     │
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────┐
          │  IntakeInterview    │  ← ≤5 conditional questions
          │  (refines score)    │
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────────┐
          │  QuestGenerator         │
          │  Pass 1: DAG skeleton   │
          │  Pass 2: narrative fill │
          └──────────┬──────────────┘
                     │
          ┌──────────▼──────────┐
          │  QuestRunner        │
          │  - executes devTask │
          │  - verifies AC      │
          │  - unlocks next     │
          └──────────┬──────────┘
                     │
          ┌──────────▼──────────┐
          │  RevealMechanic     │  ← final quest only
          │  - capture screen   │
          │  - blur + drag      │
          │  - live widget      │
          └─────────────────────┘
```

### 2.2 Data Structures (Dart, client-side)

```dart
class QuestLine {
  final String id;
  final String projectPath;
  final String appSummary;
  final QuestTier tier;
  final ScopeScore scoreBreakdown;
  final List<Act> acts;
  final int transformativeChanges;  // curse counter
  final DateTime createdAt;
  final DateTime? completedAt;
}

enum QuestTier { micro, small, medium, large }

class ScopeScore {
  final int entityCount;       // 0–4
  final int interactionSurface;// 0–4
  final int auth;              // 0–3
  final int integrations;      // 0–4
  final int realtime;          // 0–3
  int get total => entityCount + interactionSurface + auth + integrations + realtime;
}

class Act {
  final String id;
  final String name;
  final ActArchetype archetype;
  final List<Quest> quests;
}

enum ActArchetype { foundation, interface_, logic, connection, polish, launch }

class Quest {
  final String id;
  final String actId;
  final String title;          // narrative ("Forge the Task Vault")
  final String subtitle;       // dev task one-liner
  final String description;    // 2–4 sentence framing
  final String? payoffLine;    // shown on completion
  final DevTask devTask;
  final QuestStatus status;
  final QuestType type;        // main | side
  final List<String> dependsOn;
  final List<String> unlocks;
  final int xp;
  final int estimatedMinutes;
  final DateTime? completedAt;
}

enum QuestStatus { locked, available, active, completed, skipped }
enum QuestType { main, side }

class DevTask {
  final DevCategory category;
  final String description;
  final List<String> acceptanceCriteria;
  final List<String> files;
}

enum DevCategory {
  dataModel, uiScreen, uiComponent, apiRoute,
  auth, integration, realtime, testing, deploy,
}
```

### 2.3 Scope Scoring (Server-side, TS)

5 вимірів, сума 0–18 → tier:

| Вимір | Range | Сигнали |
|---|---|---|
| `entityCount` | 0–4 | Кількість data models у описі |
| `interactionSurface` | 0–4 | Екрани × типи взаємодії (CRUD, read-only, etc.) |
| `auth` | 0–3 | None=0, accounts=2, roles/permissions=3 |
| `integrations` | 0–4 | +1 за кожен зовнішній сервіс (push, maps, payments, camera) |
| `realtime` | 0–3 | Static=0, sync=1, websocket=2, multi-user live=3 |

**Tier mapping:**

| Total | Tier | Quests |
|---|---|---|
| 0–4 | micro | 3–4 |
| 5–8 | small | 5–7 |
| 9–12 | medium | 8–13 |
| 13–18 | large | 14–20+ |

**Pre-interview keyword bumps:**

```ts
const KEYWORDS: Record<string, Partial<ScopeScore>> = {
  "users|accounts|login|signup":   { auth: 2 },
  "payments|stripe|checkout":      { integrations: 2 },
  "real-?time|live|chat|push":     { realtime: 2 },
  "map|location|gps":              { integrations: 1 },
  "admin|dashboard|roles":         { auth: 1 },
  "upload|photo|video|file":       { integrations: 1 },
  "notification|remind|alert":     { integrations: 1 },
};
```

### 2.4 Intake Interview (≤5 conditional questions)

Хард-кеп — 5 питань. Більшість аппок — 3. Питання задається тільки якщо delta відповідей ≥2 на профіль.

```
Q1 [always] WHO AND WHY
   "Тільки для тебе чи будуть інші акаунти?"
   → answer scores `auth`

Q2 [if auth ≥ 2] COLLABORATION
   "Дані ізольовані чи юзери бачать одне одного?"
   → adjusts `entityCount`

Q3 [if integrations ambiguous] OUTSIDE WORLD
   "Підключення до зовнішніх сервісів?"
   → adds specific integrations

Q4 [if realtime ambiguous] LIVE UPDATES
   "Live-апдейти без рефрешу?"
   → scores `realtime`

Q5 [if micro tier or ambiguous] SCOPE SANITY
   "MVP на день чи повний продукт?"
   → caps quest count low/high in tier
```

Перед генерацією — confirmation summary: *"Got it — small personal app, no accounts, with reminders. I'll build a 6-quest journey."*

### 2.5 Quest Generation (Two-Pass)

**Pass 1 — DAG skeleton:**
- Розподіл `quest count` по актах за процентами:
  - Foundation 10–15% / Interface 25–30% / Logic 25–30% / Connection 10–20% / Polish 10–15% / Launch 5–10%
- Для кожного quest — `category`, `dependsOn`, `unlocks`, `type` (main/side)
- Polish-квести в Small tier стають side quests
- Side quests не блокують main critical path

**Pass 2 — Narrative fill:**
- Title: `[Verb] the [Thing]` ("Forge the Task Vault")
- Description: 2–4 sentences (framing → what you'll build → why → unlock hint)
- PayoffLine: closes the loop opened in description
- XP: main=100 base × modifiers, side=60 base × modifiers
- Estimated minutes per category (data-model=25, ui-screen=35, integration=45, etc.)

**Контракт:** Pass 1 і Pass 2 — окремі prompt'и до LLM. Це дозволяє перегенерувати narrative без перебудови DAG.

### 2.6 Quest Lifecycle

```
locked  ──(deps satisfied)──▶  available
                                    │
                                    ├──(user starts)──▶  active
                                    │                       │
                                    │                       ├──(AC met)──▶  completed
                                    │                       │
                                    │                       └──(user skips)──▶  skipped
                                    │
                                    └──(user skips main)──▶  skipped (with debt)
```

**Acceptance Criteria verification:**
- Machine-checkable: file exists, test passes, command exits 0 → автоматично
- Human-checkable: UI looks correct → юзер тапає чекбокс

### 2.7 Player Feedback Loop (per quest)

Три шари при completion:

1. **Immediate (0–2s):** Quest card → "Completed" з печаткою, XP tick, payoff sentence
2. **Unlock reveal (2–4s):** Наступні квести з'являються на мапі, act banner якщо акт закритий
3. **Progress reflection (on demand):** "Journey so far" card, artifact preview ("Your app right now can do: X, Y")

### 2.8 Final Reveal Mechanic (V1)

**Trigger:** Останній квест останнього акту = `completed`.

**Flow:**
1. Server-side: запустити аппку в симуляторі (`xcrun simctl io booted screenshot` або Android emulator equivalent)
2. Зберегти PNG як `quest_line.finalScreenshot`
3. На клієнті: відкрити RevealScreen
4. Рендерити overlay: blurred backdrop (`ImageFilter.blur(sigma: 30)`) над скріншотом
5. `GestureDetector` ловить vertical drag — overlay "стягується" (translateY + animated alpha)
6. Поріг 60% drag → overlay сам падає з gravity-like animation (`AnimationController` з ease-out)
7. CTA з'являється: "Open in simulator" / "Install full version"

**V1 НЕ робить:**
- Cloth physics через GPU shaders (відкладено на V2)
- Embedded Flutter engine для running app (відкладено на V2/V3)

**V2 path (для cloth):**
- `CustomPainter` + spring-mesh симуляція через Skia
- 8×12 grid вузлів, кожен — spring-damper до сусідів
- Drag тягне найближчий вузол, інші коливаються
- Threshold velocity → mesh падає з gravity

### 2.9 Live First-Screen Preview (V1: Copy-Paste)

**Підхід:** Згенерована аппка — Flutter. PixelCode — Flutter. Перший екран копіюється як **stateless preview widget** в `lib/widgets/quest_preview/`.

**Constraints на генератор (це КЛЮЧОВЕ):**
- Перший екран генерується як standalone `StatelessWidget`
- БЕЗ `Provider`/`Bloc`/`Riverpod` від root
- БЕЗ кастомних шрифтів які не підключені в PixelCode
- Дані хардкоджені (sample data) для preview-варіанту
- Експортується окремий файл `lib/preview/first_screen_preview.dart` поряд з реальним

**Renderer на клієнті PixelCode:**

```dart
class FirstScreenPreview extends StatelessWidget {
  final Widget previewWidget;  // dynamically loaded from generated app
  const FirstScreenPreview({required this.previewWidget});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: Size(390, 844)),  // iPhone-ish frame
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 390, height: 844,
          child: Theme(
            data: ThemeData.light(),  // isolated theme
            child: previewWidget,
          ),
        ),
      ),
    );
  }
}
```

**Scaling path:**

| Version | Approach | Limitation |
|---|---|---|
| V1 | Copy-paste stateless preview widget | No state mgmt, hardcoded data |
| V2 | Separate `FlutterEngine` instance | Resource cost, multi-engine setup |
| V3 | Platform view із згенерованою аппкою як sub-process | Fully isolated, complex IPC |

### 2.10 Edge Cases

**User changes scope mid-development:**
- *Additive:* інжектимо новий side quest у відповідний акт, XP бюджет ↑
- *Subtractive:* квест → `skipped`; downstream квести → `locked` із warning
- *Transformative (data model change):* `transformativeChanges++`, при threshold=3 інжектиться "Break the Curse" refactoring quest

**User skips a quest:**
- Side: вільно, без штрафу
- Main: дозволено тільки якщо deps satisfied іншим шляхом, інакше блокує downstream
- Tech debt summary показується на кордоні актів

**Idea too vague:** Замість додаткових питань — три pre-scoped варіанти на вибір (A/B/C з різними tier-ами)

**Idea too massive (score ≥ 16):** Генерується тільки kernel (5–8 квестів), решта — "Future Expansions" як ungenerated chapters

---

## 3. Implementation Roadmap

### Phase 1: Data Foundation (1–2 days)

**Deliverables:**
- [ ] `lib/models/quest_line.dart` — QuestLine, Act, Quest, DevTask, ScopeScore + JSON serde
- [ ] `lib/services/quest_persistence_service.dart` — load/save QuestLine per project
- [ ] Unit tests for serde + persistence

### Phase 2: Generation Pipeline (3–4 days)

**Deliverables:**
- [ ] `server/src/quest/scope_scorer.ts` — keyword heuristics + scoring math
- [ ] `server/src/quest/intake_interview.ts` — conditional question tree, answer parsing
- [ ] `server/src/quest/quest_generator.ts` — two-pass generator (skeleton + narrative)
- [ ] New agent role: `quest-master` in `server/src/agents.ts` — orchestrates intake + gen
- [ ] Protocol messages: `questLineGenerated`, `questStatusChanged`, `questCompleted`
- [ ] Server tests (Jest) for scorer + generator

### Phase 3: Quest UI (3–4 days)

**Deliverables:**
- [ ] `lib/screens/quest_map/` — QuestMapScreen with DAG visualization
- [ ] `lib/widgets/quest_card.dart` — card with status, XP, narrative title
- [ ] `lib/widgets/act_banner.dart` — chapter heading
- [ ] `lib/providers/quest_provider.dart` — Riverpod provider for quest state
- [ ] 3-layer completion feedback animation
- [ ] Widget tests

### Phase 4: Final Reveal V1 (2 days)

**Deliverables:**
- [ ] `server/src/quest/screenshot_capture.ts` — sim CLI invocation
- [ ] `lib/screens/reveal/reveal_screen.dart` — blur overlay + drag-to-reveal
- [ ] `lib/widgets/blur_overlay.dart` — gesture-driven `BackdropFilter` reveal
- [ ] CTA: open simulator / install
- [ ] E2E test: complete quest → see screenshot

### Phase 5: Live Preview (2–3 days)

**Deliverables:**
- [ ] Generator constraint update: agent must produce `lib/preview/first_screen_preview.dart` як stateless preview
- [ ] `lib/widgets/quest_preview/first_screen_preview.dart` — wrapper container
- [ ] Dynamic widget loading mechanism (initial: file-based copy on generation, future: hot-reload)
- [ ] Tests

### Phase 6 (deferred): Cloth Physics V2

- [ ] `CustomPainter` spring-mesh
- [ ] Drag handler with nearest-node grab
- [ ] Threshold detection + gravity fall

---

## 4. Key Design Decisions

### Decision 1: Two-pass quest generation
**Why:** DAG structure (Pass 1) and narrative text (Pass 2) eволюціонують різно. User changes scope → re-run Pass 1 діффом, narrative переграється дешево без перебудови.

### Decision 2: Server-side scoring + generation, client-side rendering
**Why:** LLM access живе на сервері (наш агентний runtime). Клієнт лише відображає квест-стейт і виконує UX-частину. Рантайм Quest Master = окрема роль в `agents.ts`.

### Decision 3: Screenshot via simulator (not embedded engine) for V1
**Why:** Embedded Flutter engine — це повноцінна сабсистема (multi-engine, IPC, lifecycle). Screenshot через `xcrun simctl io booted screenshot` дає 80% wow-ефекту за 5% складності. Embedded engine — V2.

### Decision 4: Generator constraint — preview widget separate from real
**Why:** Тримає V1 Live Preview простим (copy-paste). Без цього constraint'а ми впремося в Provider/theme conflicts при першій же реальній аппці. Це **архітектурне рішення в промпті агента**, не в коді PixelCode.

### Decision 5: Side quests as first-class data
**Why:** Differentiating side vs main only by `type` field (not by separate collection) спрощує DAG логіку, рендер, persistence. Один шлях коду на всі квести.

### Decision 6: Curse mechanic for transformative changes
**Why:** Scope creep — найболючіший фейл-моуд. Лічильник + спеціальний refactor-квест перетворює tech debt на гру замість мовчазної проблеми.

### Decision 7: V1 reveal без cloth physics
**Why:** Cloth simulation — тиждень+ роботи на платформо-специфічний GPU код. Blur + clip + drag дає той самий emotional beat значно дешевше. Cloth — V2 коли продукт довів цінність.

---

## 5. Success Criteria

- ✅ Користувач описує ідею → отримує квест-лайн за <30 сек
- ✅ Інтерв'ю задає ≤5 питань (середнє: 3)
- ✅ Tier scoring точний на >80% (validated через batch examples)
- ✅ Квести мають видимий артефакт після кожного step'у
- ✅ Final reveal працює: screenshot з симулятора → blur overlay → drag → CTA
- ✅ Live preview рендерить реальний перший екран в PixelCode container
- ✅ Scope change → curse mechanic коректно ловить transformative changes
- ✅ Test coverage: усі модулі quest pipeline покриті unit-тестами

---

## 6. Open Questions

1. **Storage location:** QuestLine — у проектному `.pixelcode/quest.json` чи в global `~/.pixelcode/quests/<projectKey>.json`? (Потрібно для multi-device sync)
2. **Resume mid-quest:** Як точно відновити стан якщо юзер закрив PixelCode після Q5/Q10?
3. **Multi-device:** Чи синхронізується quest progress між пристроями через сервер?
4. **Internationalization:** Narrative text англомовний у прикладах — чи генеруємо ua/uk варіанти?
5. **Estimated time accuracy:** Як калібрувати estimatedMinutes на основі реальних completion times?
6. **Скріншот в симуляторі:** який саме симулятор юзаємо за замовчуванням — iOS чи Android? Залежить від target платформи аппки.

---

## 7. Example Quest Lines

### Example A — Todo App with Reminders (Small, score=6)

```
"Chronicles of the Undone" — 6 main + 2 side quests

ACT 1 — FOUNDATION
  Q1 [main] "Forge the Task Vault"        — data-model, 25min, 100xp

ACT 2 — INTERFACE
  Q2 [main] "Raise the Hall of Tasks"     — ui-screen, 35min, 150xp
  Q3 [side] "Paint the Crest of Priority" — ui-component, 20min, 60xp
  Q3 [main] "Carve the Chamber of Creation"— ui-screen, 30min, 100xp

ACT 3 — LOGIC
  Q4 [main] "Teach the Vault to Forget"   — logic, 25min, 100xp
  Q5 [main] "Raise the Reminder Tower"    — integration, 40min, 150xp
  Q5 [side] "Silence the Sleeping Tasks"  — logic, 20min, 60xp

ACT 4 — LAUNCH
  Q6 [main] "Open the Gates"              — deploy+reveal, 30min, 200xp + 500 bonus
```

### Example B — Social Photo Sharing (Medium, score=11)

```
"Legends of the Shared Eye" — 13 main + 4 side quests
Acts: Foundation(2) → Interface(4) → Logic(3) → Connection(2) → Launch(2)
~535min main + ~135min side, 2,300 XP total
```

(Full breakdown in `docs/QUEST_EXAMPLES.md` — to be created during Phase 2)

---

**Document Version:** 1.0
**Last Updated:** 2026-04-26
**Status:** Approved — Ready for Phase 1 Implementation
