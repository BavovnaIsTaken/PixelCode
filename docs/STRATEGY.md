# PixelCode — Архітектурна стратегія

> **Короткий виклад:** PixelCode переходить від "обгортки над Claude Agent SDK" до backend-agnostic платформи-екосистеми, де користувачі тренують, торгують і зливають AI-агентів. Архітектура вже має більшість будівельних блоків; завдання — додати custom spawn, персоналізацію UI, marketplace, та abstraction layer для agent backends.

## Context

PixelCode (v0.4.0+) — **візуальна платформа для оркестрації AI-агентів** у форматі піксель-арт гри. Сьогодні в основі — Claude Agent SDK, але архітектура з самого початку проєктується **agent-backend-agnostic**: SDK — це перший імплементований backend, не центр гравітації.

**Існуючі архітектурні кубики:**

- **Multi-tier model routing** — Haiku / Sonnet / Opus на основі агентського skill score
- **Energy meter** — daily token meter як ігровий ресурс
- **Economy layer** — валюта Grim, магазин, апгрейди
- **Agent personalization** — score/decay/eviction memory lifecycle; абстракція "агент має пам'ять" не залежить від SDK
- **Cross-platform real-time** — Flutter 5 платформ з WebSocket-синхронізацією

**Стратегічна позиція на backends:** Claude Agent SDK сьогодні — найзручніший спосіб запускати агента з tool use й memory. Завтра з'являться інші: open-source frameworks, локальні runtime, спеціалізовані SDK. PixelCode має лишатися шаром UI/гри/економіки **поверх** будь-якого з них.

**Ліцензія:** Поточна `PolyForm Noncommercial 1.0.0` підходить для community-фази, але потребує dual-license переходу для B2B та комерційного використання.

---

## Архітектурні етапи

### Phase 0: Completion of core (Q2–Q3 2026)

- Agent Personalization System UI інтеграція
- Android deploy
- Room adjacency bonuses
- Стабілізація alpha

### Phase 1: Custom Agent Spawn (Q3 2026)

Перший крок до екосистеми — **не з локального тренування на телефоні**, а з легкодоступної версії:

- Користувач створює агента через UI: базова модель, system prompt, role bias, skill weights
- Training через Agent Personalization System (бекенд існує) — lessons із завдань / dungeons
- Експорт/імпорт як JSON → початок community trades без marketplace-інфраструктури
- Discord/Reddit thread для обміну агентами

### Phase 1.5: Curated Roster v1 (Q3 2026)

Між Custom Agent Spawn (Phase 1) і Marketplace v1 (Phase 2) — крок-проміжок: **запечений roster іменованих персонажів** як hiring UX і marketplace mental-model rehearsal. Гравець наймає не "Developer на DeepSeek", а "Андрія, Code Specialist".

- 5–7 named characters на старті (далі +; решта — на основі телеметрії), кожен має `{name, portrait, statWeights, promptBias, defaultBackend, price}`
- **Character identity = stat weights + personality**, не provider. Свап провайдера ≠ зміна персонажа.
- **Soft vendor-disclosure (не firewall):** lore і name — character-first, але `powered by X` видно дрібним шрифтом з можливістю свапу. PixelCode позиціонується як прозорий marketplace, де гравець свідомо вибирає модель за ціною/якістю/задачею.
- **Brand-guidelines compliance:** для Anthropic / OpenAI використовувати тільки дозволені forms ("powered by Claude", без модифікацій лого); версії моделей живуть у single-source-of-truth catalog для централізованого оновлення.
- **Portrait pipeline:** reuse існуючої 8-skin × 9-class sprite system + palette swaps + accessory overlays — без нових base sprites (combinatorial space ~1440 unique looks з ~10 нових pixel assets).
- Catalog UI: filter/sort за статами, ціною, спеціалізацією → reused як stats-card компонент для Marketplace v1 (E).

**Чому це не суперечить §2 (tier-based, не provider-based):** провайдер = `defaultBackend` runtime field, не identity. Identity = `{name, portrait, statWeights, promptBias}` — стабільна між backend-свапами. Tier-based routing (Haiku/Sonnet/Opus per task) працює всередині будь-якого character-а як раніше.

**Чому це не Marketplace v1 (E):** немає commission infra, listings flow, reviews, P2P trade, anti-collusion. Це curated roster від розробника, не user-generated trade ground.

**Monetization:** cosmetic-only (portrait skins, accessories, voice-stings, idle animations). Stats фіксовані per character — F2P гравець може дотягти top-комбо без платежу. Узгоджено з §3 "no pay-to-progress".

### Phase 2: Marketplace v1 (Q4 2026)

- Каталог агентів: рейтинг, відгуки, статистика
- Агент = унікальний ID із історією тренування
- Перші мікротранзакції
- Merge mechanic — два агенти → новий зі змішаними характеристиками

### Phase 3: Backend abstraction (Q1 2027)

Критичний архітектурний крок:

```
AgentBackend (interface)
 ├─ ClaudeAgentSdkBackend   (текущий default)
 ├─ OpenAgentBackend        (open-source frameworks)
 ├─ LocalRuntimeBackend     (Ollama / MLX / llama.cpp)
 └─ CustomBackend           (community plugins)
```

- Виокремити `AgentBackend` interface — все, що [server/src/server.ts](../server/src/server.ts) робить через SDK → за абстракцією
- Routing tier-based (`local-fast` / `local-quality` / `cloud`), не provider-based
- Прототип з Ollama + llama3.2:1b
- LoRA-adapter spec — формат для збереження тренованих агентів

**Чому зараз:** marketplace (Q4 2026) уже торгує агентами; без abstraction кожна одиниця = promptpack. З абстракцією агент стає об'єктом на будь-якому runtime — реальний asset, не конфіг.

### Phase 4: Local training era (Q2–Q4 2027+)

**Две колонки еволюції:**

**A) Free-to-play з локальним інференсом:**

```
Безкоштовно:  локальна модель (~Haiku) → агенти 1–7 рівня → $0 API costs
Платно:       хмарний апгрейд → Sonnet/Opus → складні задачі
```

**B) Локальне дотренування агентів:**

```
Foundation Model (шерена, ~1–3GB)
  └── fine-tuned на Llama 3.2 / Phi-4 / Qwen
  └── завантажується один раз
  
Player Agent = Foundation + LoRA Adapter
  └── adapter ~10–100MB
  └── тренується на історії гравця (dungeon перемоги, успішні задачі)
  └── торгується на marketplace як легкий файл
```

**Self-distillation стратегія** (4 джерела тренувального сигналу без費用):

1. Knowledge distillation — потужна cloud модель генерує 10K зразків один раз ($50–100)
2. Self-play — агент розв'язує задачу 10 разів, обирає найкращу спробу
3. AI judge — одна модель оцінює відповіді іншої (судді існують: [server/src/dungeon.ts](../server/src/dungeon.ts))
4. Crowdsourced from gameplay — opt-in pool від гравців

---

## Архітектурні рішення

### Персоналізація як memoria lifecycle, не як fine-tuning

Agent Personalization System ([server/src/memory_lifecycle.ts](../server/src/memory_lifecycle.ts), [lesson_extractor.ts](../server/src/lesson_extractor.ts)) вже реалізує score/decay/capacity-tier eviction. Це дозволяє:

- Агентам "пам'ятати" минулі запуски
- Промптам адаптуватись без перетренування ваг
- Экономити на токені (cached context fragment замість full history)

UI інтеграція попереду; технічна основа готова.

### Energy meter як главний монетизаційний ресурс

[lib/widgets/energy/energy_meter.dart](../lib/widgets/energy/energy_meter.dart) — daily token meter як ігровий ресурс. З появою локальних моделей:

- Локальний inference = $0 energy cost
- Cloud inference = energy spend
- Training credits = окремий ресурс для adapter updates

### Permissions runtime: bypass-by-default

PixelCode runtime **ніколи** не показує користувачу permission prompt. `permissionMode: "bypassPermissions"` — обов'язковий інваріант для всіх `query()`-call-ів у [server/src/](../server/src/), регресійно перевіряється у [server/test/permissions_invariant.test.ts](../server/test/permissions_invariant.test.ts).

Обґрунтування: користувач, що запустив PixelCode, делегував агентам контроль над project working directory на час сесії. Кор-петля гри ("команда агентів виконує роботу") програє в момент, коли середина task-у переривається на "Allow this Edit?" модал. Дизайнерські обмеження на дії агента виражаються через **`tools: [...]` allowlist** — не давати тулу в принципі, не питати про неї runtime.

Trade-off усвідомлений: ми обмінюємо theoretical defense-in-depth (захист від agent-mistake без явного user-confirm) на **continuous flow** і **predictable agent behavior**. Це частина дизайнерського контракту з користувачем — як `git push --force` після `git pull`: інструмент дає тобі мотузку, бо ти знаєш що робиш.

### Economy без pay-to-win

F2P гравець може досягти топу, граючи довго. Pay-to-progress прискорює, не разблоковує. Це принципово для community trust.

```
Безкоштовно:  on-device training (повільно, 2–8 годин)
Платно:       cloud GPU-shot (5 хвилин, $0.10)
```

Обидва шляхи ведуть в кінці, один просто довше.

---

## Посилання на реалізацію

- [lib/models/agent_level.dart](../lib/models/agent_level.dart) — skill profile + routing
- [lib/models/game_economy.dart](../lib/models/game_economy.dart) — Grim валюта
- [lib/widgets/energy/energy_meter.dart](../lib/widgets/energy/energy_meter.dart) — energy resource
- [server/src/server.ts](../server/src/server.ts) — Claude Agent SDK orchestration
- [server/src/dungeon.ts](../server/src/dungeon.ts) — dungeon judge (future self-distillation)
- [server/src/memory_lifecycle.ts](../server/src/memory_lifecycle.ts) — agent memory management
- [server/src/lesson_extractor.ts](../server/src/lesson_extractor.ts) — pattern extraction для personalization

Для деталей бізнес-плану, контент-стратегії й таймлайнів див. **Obsidian vault** `~/Obsidian/PixelCode/STRATEGY.md`.
