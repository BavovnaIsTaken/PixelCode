# PixelCode — Roadmap та План Реалізації

> Високорівневе ТЗ і трекер прогресу. Базується на стратегії з [STRATEGY.md](STRATEGY.md).
> Кожен пункт має статус і прив'язку до фази/кварталу.

## Статуси

- `[DONE]` — реалізовано і працює
- `[WIP]` — в активній роботі
- `[PARTIAL]` — каркас є, треба завершити дроти
- `[TODO]` — заплановано, ще не почали
- `[FUTURE]` — після 2027, залежить від зовнішніх умов (залізо, моделі)

---

## A. Платформа і ядро (Foundation)

Базовий шар: процеси, транспорт, мережа, міжплатформеність. Здебільшого готовий.

| Компонент | Статус | Файли |
|---|---|---|
| Flutter cross-platform клієнт (macOS/Win/Linux/iOS/Android) | `[DONE]` | [pubspec.yaml](../pubspec.yaml) |
| Node.js + TypeScript сервер | `[DONE]` | [server/package.json](../server/package.json) |
| Server/client split (клієнт не спавнить сервер) | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| Launcher daemon з respawn-on-75 | `[DONE]` | [server/src/launcher.ts](../server/src/launcher.ts) |
| `pixelcode-server` CLI | `[DONE]` | [server/bin/pixelcode-server.mjs](../server/bin/pixelcode-server.mjs) |
| Layered config (defaults → file → ENV → CLI) | `[DONE]` | [server/src/config.ts](../server/src/config.ts) |
| WebSocket transport | `[DONE]` | [server/src/server.ts](../server/src/server.ts), [lib/services/agent_ws_service.dart](../lib/services/agent_ws_service.dart) |
| mDNS/Bonjour LAN discovery | `[DONE]` | [lib/services/network_discovery_service.dart](../lib/services/network_discovery_service.dart) |
| Tailscale Funnel (OTA з будь-якої мережі) | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| Real-time mirroring між пристроями | `[DONE]` | — |
| Shared SDK session між реконнектами | `[DONE]` | — |
| PixelDock admin app | `[DONE]` | [server_admin/](../server_admin/) |

**Що залишилось у цьому напрямку:** нічого критичного. Можна розглянути в майбутньому: cross-machine remote orchestration (WS-шар готовий, але UX-flow попереду).

---

## B. Гра і економіка (Game Layer)

Поточний game loop працює end-to-end. Деякі бонуси/механіки ще не активні.

| Компонент | Статус | Файли |
|---|---|---|
| Hub-екран з анімованим пікселарт-офісом | `[DONE]` | [lib/widgets/canvas/](../lib/widgets/canvas/) |
| Z-sorted рендер 320×224, walk/type/read/idle анімації | `[DONE]` | [lib/widgets/canvas/pixel_office_painter.dart](../lib/widgets/canvas/pixel_office_painter.dart) |
| 6-тирова система спрайтів, 7 кадрів × 3 напрямки | `[DONE]` | [assets/characters/](../assets/characters/), [lib/widgets/canvas/pixel_sprites.dart](../lib/widgets/canvas/pixel_sprites.dart) |
| Меблі (столи, монітори, стільці, рослини) | `[DONE]` | [assets/furniture/](../assets/furniture/) |
| Hire/fire агентів за ролями (7 ролей) | `[DONE]` | [lib/widgets/](../lib/widgets/) |
| Kanban task board з drag-and-drop | `[DONE]` | [lib/widgets/board/task_board_panel.dart](../lib/widgets/board/task_board_panel.dart) |
| Real-time chat і activity feed | `[DONE]` | [lib/widgets/chat/](../lib/widgets/chat/) |
| Agent-level XP + skillCap progression | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| 5-stat skill model (precision/insight/reliability/creativity/speed) | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| Multi-tier model routing (Haiku/Sonnet/Opus) | `[DONE]` | [lib/models/agent_level.dart](../lib/models/agent_level.dart) |
| Grim currency + economy | `[DONE]` | [lib/models/game_economy.dart](../lib/models/game_economy.dart) |
| Office tiers (Garage → Campus) | `[DONE]` | — |
| Hardware upgrades (laptop → workstation) | `[DONE]` | — |
| Dungeon training з Haiku-суддею | `[DONE]` | [server/src/dungeon.ts](../server/src/dungeon.ts) |
| Task outcome rolls (bug/crit/incomplete) | `[DONE]` | [lib/services/task_outcome.dart](../lib/services/task_outcome.dart) |
| Energy meter (daily token meter) | `[DONE]` | [lib/widgets/energy/energy_meter.dart](../lib/widgets/energy/energy_meter.dart) |
| Quest line / quest persistence (Game Master mode foundation) | `[PARTIAL]` | [server/src/quest/](../server/src/quest/), [lib/services/quest_persistence_service.dart](../lib/services/quest_persistence_service.dart) — data shapes готові, інтеграція в [Facilitator System](FACILITATOR_SYSTEM.md) попереду |
| **Style picker UI** (вибір facilitator-а на старті проєкту) | `[TODO]` | Q3 2026 |
| **Lexicon swap layer** (kanban labels через style.lexicon) | `[TODO]` | Q3 2026 |
| Shop panel (скіни, меблі, апгрейди) | `[DONE]` | [lib/widgets/shop/](../lib/widgets/shop/) |
| Multi-project / session profiles | `[DONE]` | [lib/models/session_profile.dart](../lib/models/session_profile.dart) |
| Easter eggs (Arkanoid, dungeon crawler) | `[DONE]` | [lib/widgets/easter_eggs/](../lib/widgets/easter_eggs/) |
| Logo Path DSL (анімація логотипу) | `[DONE]` | [lib/services/logo_path_program.dart](../lib/services/logo_path_program.dart) |
| **Room adjacency bonuses** (Workstation↔Server Room і т.д.) | `[PARTIAL]` | [docs/office_design.md](office_design.md) — фреймворк є, проводка часткова |
| **Break Room morale system** (+20% при відпочинку) | `[TODO]` | Q2–Q3 2026 |
| **Server Room cable proximity penalty** | `[TODO]` | Q2–Q3 2026 |
| **Manager Meeting Room dispatch boost** | `[TODO]` | Q2–Q3 2026 |
| **Diagnostics panel polish** | `[DONE]` | [lib/widgets/debug/](../lib/widgets/debug/) |

---

## C. Агентна система і персоналізація

Бекенд персоналізації зібраний, UI попереду. Це фундамент для Custom Agent Spawn (D).

| Компонент | Статус | Файли |
|---|---|---|
| Per-agent profile cache | `[DONE]` | [server/src/profile_cache.ts](../server/src/profile_cache.ts) |
| Execution hooks (beforeDispatch / afterExecution / onError) | `[DONE]` | [server/src/hooks/executionHooks.ts](../server/src/hooks/executionHooks.ts) |
| Memory lifecycle (score / decay / capacity-tier eviction) | `[DONE]` | [server/src/memory_lifecycle.ts](../server/src/memory_lifecycle.ts) |
| Lesson extractor (pattern recognition + apply with eviction) | `[DONE]` | [server/src/lesson_extractor.ts](../server/src/lesson_extractor.ts) |
| Prompt cache manager (system prompt + learned-context) | `[DONE]` | [server/src/prompt_cache_manager.ts](../server/src/prompt_cache_manager.ts) |
| Agent context preparer | `[DONE]` | [server/src/agent_context.ts](../server/src/agent_context.ts) |
| Project context manager (cross-project profile migration) | `[DONE]` | [server/src/project_context_manager.ts](../server/src/project_context_manager.ts) |
| Trait memory | `[DONE]` | [server/src/trait_memory.ts](../server/src/trait_memory.ts), [lib/models/agent_trait.dart](../lib/models/agent_trait.dart) |
| Personalization orchestrator | `[DONE]` | [server/src/personalization.ts](../server/src/personalization.ts) |
| **Personalization UI** (показати lessons, дозволити edit, reset) | `[TODO]` | Q3 2026 — критично перед Custom Agent Spawn |
| **Lessons history viewer** | `[TODO]` | Q3 2026 |
| **Topic affinity inspector** | `[TODO]` | Q3 2026 |
| **User consent flow** для запису lessons | `[TODO]` | Q3 2026 |
| **Per-agent facilitator binding** (manager пам'ятає обраний style) | `[TODO]` | Q3 2026 |
| **Facilitator lessons namespace** (style-scoped lesson channel) | `[TODO]` | Q3 2026 |
| **Style switch flow** (UI для зміни facilitator з explanation) | `[TODO]` | Q4 2026 |

Дизайн — у [AGENT_PERSONALIZATION_SYSTEM.md](AGENT_PERSONALIZATION_SYSTEM.md), план — у [IMPLEMENTATION_GUIDE.md](IMPLEMENTATION_GUIDE.md).

---

## D. Custom Agent Spawn і агенти як активи

Перший крок до екосистеми. Не чекаємо локальних моделей — починаємо з prompt-level кастомізації.

| Компонент | Статус | ETA |
|---|---|---|
| **Custom Agent Spawn UI** — створення агента (system prompt, role bias, skill weights) | `[TODO]` | Q3 2026 |
| **Self-play в dungeon** — агент пробує задачу N разів, кращі attempts → memory | `[TODO]` | Q3 2026 |
| **Agent JSON export/import** — поділитися агентом як файлом | `[TODO]` | Q3 2026 |
| **Agent signature/identity** (унікальний ID, історія тренування) | `[TODO]` | Q3 2026 |
| **Personality presets** (templates для швидкого старту) | `[TODO]` | Q3 2026 |
| **Custom facilitator spawn** (user-defined persona_prompt + lexicon) | `[TODO]` | Q3 2027 |
| **Agent stats card** — для marketplace listing (XP, success rate, specializations) | `[TODO]` | Q3 2026 |
| **Discord/Reddit thread** — перший community trade ground (поза-аппка) | `[TODO]` | Q3 2026 |

**Залежності:** C (Personalization UI) має бути готова раніше, бо Custom Agent Spawn зливається з нею в одне UI.

---

## E. Marketplace v1

Інфраструктура торгівлі агентами. Поки агенти — JSON, але архітектура має бути готова для adapter weights пізніше.

| Компонент | Статус | ETA |
|---|---|---|
| **Marketplace catalog UI** (список агентів, filter, sort) | `[TODO]` | Q4 2026 |
| **Agent listing flow** (виставити свого агента) | `[TODO]` | Q4 2026 |
| **Agent quality score** (standardized dungeon challenges перед listing) | `[TODO]` | Q4 2026 |
| **Rating + review system** | `[TODO]` | Q4 2026 |
| **Anti-collusion logic** (один акаунт не торгує з собою) | `[TODO]` | Q4 2026 |
| **Marketplace backend** (server-side каталог, не P2P) | `[TODO]` | Q4 2026 |
| **Crowdsourced training data pool (opt-in)** | `[TODO]` | Q4 2026 |
| **Anonymization pipeline** для opt-in pool | `[TODO]` | Q4 2026 |
| **Agent merge mechanic v1** (для JSON-агентів — merge prompts/skills) | `[TODO]` | Q4 2026 |
| **Marketplace commission infra** (15–20% на угоду) | `[TODO]` | Q4 2026 |
| **Facilitator marketplace catalog** (style listings) | `[TODO]` | Q4 2026 |
| **Style quality signal** (token-spend / retention test on demo) | `[TODO]` | Q4 2026 |
| **Curated submission queue** (anti-edgelord moderation) | `[TODO]` | Q1 2027 |

---

## F. Backend Abstraction шар

Найважливіший архітектурний крок 2027. Виносимо все, що зараз зав'язано на Claude Agent SDK, за абстракцію.

| Компонент | Статус | ETA |
|---|---|---|
| **`AgentBackend` interface** | `[TODO]` | Q1 2027 |
| **`ClaudeAgentSdkBackend`** (refactor існуючого коду) | `[TODO]` | Q1 2027 |
| **`OpenAgentBackend`** (для open-source agent frameworks) | `[TODO]` | Q1 2027 |
| **`LocalRuntimeBackend`** (Ollama / MLX / llama.cpp) | `[TODO]` | Q1 2027 |
| **`CustomBackend`** plugin loader | `[TODO]` | Q1 2027 |
| **Tier routing refactor** — Haiku/Sonnet/Opus → local-fast/local-quality/cloud | `[TODO]` | Q1 2027 |
| **Provider-agnostic session/tool-use abstraction** | `[TODO]` | Q1 2027 |
| **First non-Anthropic prototype** (Ollama + llama3.2:1b або phi4-mini) | `[TODO]` | Q1 2027 |
| **Dungeon judge на локальній моделі** (verify quality) | `[TODO]` | Q1 2027 |

**Чому критично:** marketplace (E) уже торгує агентами; без абстракції кожна одиниця — лише promptpack. З абстракцією агент стає повноцінним активом, що працює на будь-якому runtime.

---

## G. Модельний шар (Foundation + Adapter)

Перший власний модельний артефакт. PixelCode Foundation Model — спільна база, поверх якої тренуються adapters.

| Компонент | Статус | ETA |
|---|---|---|
| **PixelCode Foundation Training Set** — 10K зразків від Cloud Opus | `[TODO]` | Q1 2027 |
| **Distillation pipeline v1** (cloud teacher → student data) | `[TODO]` | Q1 2027 |
| **PixelCode Foundation Model v1** (fine-tuned Llama 3.2 / Phi-4 / Qwen) | `[TODO]` | Q2 2027 |
| **Foundation Model distribution** (CDN, ~1–3GB download) | `[TODO]` | Q2 2027 |
| **Foundation Model versioning** | `[TODO]` | Q2 2027 |
| **LoRA adapter format spec** (стандартизований marketplace-сумісний) | `[TODO]` | Q3 2027 |
| **Adapter merge mechanic v2** (математичний weight averaging для LoRA) | `[TODO]` | Q3 2027 |
| **Foundation Model evaluation suite** (regression test перед release) | `[TODO]` | Q2 2027 |

---

## H. Тренування і Self-Distillation

Шар, що перевертає економіку. Self-distillation робить тренування майже безкоштовним.

| Компонент | Статус | ETA |
|---|---|---|
| **Cloud-shot training service** ($0.05–0.20 per adapter update) | `[TODO]` | Q2 2027 |
| **Cloud GPU вибір** (provider, billing, rate limiting) | `[TODO]` | Q2 2027 |
| **Training credits economy** (Grim → credits → GPU shots) | `[TODO]` | Q2 2027 |
| **Self-play training data collection** з dungeon | `[TODO]` | Q3 2026 (співпадає з D) |
| **AI judge v1** — Haiku-суддя як training signal generator | `[DONE]` | Перевикорис. з [server/src/dungeon.ts](../server/src/dungeon.ts) |
| **AI judge ensemble** (кілька судів для anti-reward-hacking) | `[TODO]` | Q3 2027 |
| **Reward hacking detection** | `[TODO]` | Q3 2027 |
| **Mode collapse safeguards** (diversification + cloud injection) | `[TODO]` | Q3 2027 |
| **On-device training (alpha)** — флагмани з NPU train-ops | `[FUTURE]` | Q4 2027 |
| **On-device self-distillation loop** (overnight while charging) | `[FUTURE]` | Q4 2027 |
| **Battery/thermal scheduler** (training only when plugged + cool) | `[FUTURE]` | Q4 2027 |
| **On-device training (mainstream)** — non-флагмани | `[FUTURE]` | 2028+ |
| **Community-driven Foundation updates** | `[FUTURE]` | 2028+ |

---

## I. Монетизація

Поетапне впровадження доходових потоків. Перший крок — license + cosmetics; останні — marketplace commission і training credits як основні.

| Компонент | Статус | ETA |
|---|---|---|
| **Перехід на dual license** (PolyForm Noncommercial → особисте + комерційне) | `[TODO]` | Q4 2026 |
| **Pro tier subscription infrastructure** (auth, billing, entitlement check) | `[TODO]` | Q4 2026 |
| **Pro tier features** (cloud sync, unlimited projects, advanced analytics) | `[TODO]` | Q4 2026 |
| **Cosmetics shop** (скіни, меблі, теми — $2–5 each) | `[TODO]` | Q4 2026 |
| **Cloud server (managed)** — для Pro tier (без потреби Mac у юзера) | `[TODO]` | Q4 2026 |
| **Companion PWA** (моніторинг офісу з браузера) | `[TODO]` | Q4 2026 |
| **Marketplace commission (15–20%)** | `[TODO]` | Q4 2026 |
| **B2B team license** ($29/міс/team, shared agent pools) | `[TODO]` | Q1 2027 |
| **Training credits packs** ($0.05–0.20 per run) | `[TODO]` | Q2 2027 |
| **Grim packs** (real money → in-game currency) | `[TODO]` | Q3 2027 |
| **Premium agent listings** ($2–10/міс promotion) | `[TODO]` | Q3 2027 |
| **Real money out** (Grim → cash для top sellers) | `[TODO]` | Q3 2027 |
| **Юридичний review** (gambling/marketplace регуляції по країнах) | `[TODO]` | Q1 2027 (перед marketplace launch) |

---

## J. Mobile деплой і дистрибуція

| Компонент | Статус | Файли |
|---|---|---|
| Silent iOS deploy через `xcrun devicectl` | `[DONE]` | [lib/services/ios_deploy_service.dart](../lib/services/ios_deploy_service.dart) |
| OTA iOS deploy через Tailscale Funnel | `[DONE]` | [server/src/server.ts](../server/src/server.ts) |
| **Android deploy (повний)** | `[PARTIAL]` | [lib/services/android_deploy_service.dart](../lib/services/android_deploy_service.dart) — скелет є, треба завершити |
| iOS signing flow + onboarding | `[DONE]` | [docs/iOS_DEPLOYMENT.md](iOS_DEPLOYMENT.md) |
| **Android signing flow + onboarding** | `[TODO]` | Q2–Q3 2026 |
| GitHub Releases для macOS артефактів | `[DONE]` | — |
| **App Store / Play Store presence** | `[TODO]` | Q4 2026 (після Pro tier infra) |

---

## K. Community і контент

Маркетинг і community building. Деталі в [STRATEGY.md §4](STRATEGY.md#4-контент-план-для-соцмереж).

| Канал | Статус | ETA |
|---|---|---|
| **GitHub presence** (README, CONTRIBUTING, LICENSE) | `[DONE]` | — |
| **X (Twitter) account** з активним постингом | `[TODO]` | Старт паралельно з alpha |
| **TikTok / Reels / Shorts** | `[TODO]` | Старт після першого polished demo |
| **YouTube канал** (1–2 відео/місяць) | `[TODO]` | Місяць 2 від старту contentу |
| **Reddit** (r/programming, r/FlutterDev, r/MachineLearning, r/gamedev) | `[TODO]` | Старт паралельно з X |
| **Discord server** | `[TODO]` | Q3 2026 (для Custom Agent Spawn community) |
| **"Meet the breeders" series** | `[TODO]` | Q4 2026 (після Marketplace v1) |
| **"Agent battles" content format** | `[TODO]` | Q4 2026 |
| **LinkedIn presence (B2B)** | `[TODO]` | Q1 2027 |

---

## L. Інфраструктура підтримки

Щоб тримати якість і зрозуміти що відбувається.

| Компонент | Статус | ETA |
|---|---|---|
| Diagnostics panel (server health, deps, logs) | `[DONE]` | [lib/widgets/debug/](../lib/widgets/debug/) |
| Structured logging | `[DONE]` | — |
| Boot logs ring buffer | `[DONE]` | [server/src/launcher.ts](../server/src/launcher.ts) |
| **Telemetry / metrics opt-in** (anonymous usage stats) | `[TODO]` | Q3 2026 |
| **Crash reporting** (Sentry або власне) | `[TODO]` | Q3 2026 |
| **A/B test infra** (для UI-експериментів) | `[TODO]` | Q4 2026 |
| **Feature flags** | `[TODO]` | Q4 2026 |
| **Rate limiting / abuse prevention** на marketplace | `[TODO]` | Q4 2026 |
| **CI/CD pipeline** (build matrix для всіх платформ) | `[PARTIAL]` | Поточний стан — `flutter build` локально; потрібен GitHub Actions |
| **Automated test suite** (Flutter widget tests + server unit tests) | `[PARTIAL]` | Є щось у [test/](../test/), треба розширити |

---

## M. Facilitator System (стиль ведення розробки)

Facilitator — модальність взаємодії manager-агента, що визначає лексикон, ритм церемоній і output-формат (quest / sprint / milestone / mission / koan). Quest System стає одним з режимів (Game Master). Дизайн — у [FACILITATOR_SYSTEM.md](FACILITATOR_SYSTEM.md), Game Master режим — у [FACILITATOR_GAMEMASTER.md](FACILITATOR_GAMEMASTER.md).

| Компонент | Статус | ETA |
|---|---|---|
| **`FacilitatorStyle` schema** (persona_prompt, lexicon, ceremony, output_mapper) | `[TODO]` | Q3 2026 |
| **`FacilitatorRunner` server-side** (intake, seed kanban, on-event ceremonies) | `[TODO]` | Q3 2026 |
| **`FacilitatorOutput` interface** (toKanbanTasks/toCanonicalProgress) | `[TODO]` | Q3 2026 |
| **Refactor: QuestLine → FacilitatorOutput impl** (Game Master mode) | `[TODO]` | Q3 2026 |
| **Refactor: QuestPersistence → FacilitatorOutputPersistence** | `[TODO]` | Q3 2026 |
| **Default styles MVP**: Game Master, Marina (Amber), Drill Sergeant | `[TODO]` | Q3 2026 |
| **`MissionBriefing` output format** (Drill Sergeant) | `[TODO]` | Q3 2026 |
| **`MilestoneTree` output format** (Marina) | `[TODO]` | Q3 2026 |
| **Hierarchical prompt safety** (style ≠ tech decisions; tech-lead veto) | `[TODO]` | Q3 2026 |
| **Default styles v2**: Scrum Master, Stoic Mentor | `[TODO]` | Q4 2026 |
| **`SprintBacklog` output format** (Scrum Master) | `[TODO]` | Q4 2026 |
| **`KoanEntry` output format** (Stoic Mentor) | `[TODO]` | Q4 2026 |
| **Style-aware ceremony engine** (standup/retro/journal/none) | `[TODO]` | Q4 2026 |
| **Suggest-switch heuristic** (sentiment-based fatigue detection) | `[TODO]` | Q1 2027 |

**Залежності:** Перетинається з C (style binding в personalization UI), B (kanban lexicon swap), E (marketplace path для community styles). Перевикористовує існуючі artifacts: [quest_line.dart](../lib/models/quest_line.dart), [scope_scorer.ts](../server/src/quest/scope_scorer.ts), [quest_persistence_service.dart](../lib/services/quest_persistence_service.dart).

---

## Залежності між напрямками

```
A (Foundation) ─────────────────────────────────────────────► все інше
B (Game Layer) ─┐
                ├──► D (Custom Spawn) ──► E (Marketplace) ──► F (Backend abstraction)
C (Personalization) ─┘                                              │
                                                                    ▼
                                                              G (Foundation Model)
                                                                    │
                                                                    ▼
                                                              H (Training)
                                                                    │
                                                                    ▼
                                                              On-device training (FUTURE)

I (Monetization) — паралельно з E (Marketplace v1 потребує commission infra)
J (Mobile deploy) — паралельно, не блокує
K (Community) — паралельно, не блокує
L (Infra) — підтримує все
```

**Критичний шлях до 2027:**

```
C (Personalization UI) → D (Custom Agent Spawn) → E (Marketplace v1)
  → F (AgentBackend abstraction) → G (Foundation Model) → H (Training)
```

---

## Орієнтовні зусилля (engineer-weeks)

Дуже грубо, для самооцінки. Один розробник full-time.

| Напрямок | Estimate |
|---|---|
| C — Personalization UI | 3–4 weeks |
| D — Custom Agent Spawn | 4–6 weeks |
| E — Marketplace v1 | 6–8 weeks |
| F — Backend abstraction | 6–10 weeks |
| G — Foundation Model | 4–6 weeks (плюс GPU witty) |
| H — Training infra | 8–12 weeks |
| I — Monetization | 4–6 weeks |
| J — Android deploy завершення | 1–2 weeks |
| L — CI/CD + tests | 2–3 weeks |

**Сумарно до Q4 2027:** ~40–55 engineer-weeks для критичного шляху + monetization. Тобто реалістично — якщо є фокус і немає великих відволікань.

---

## Що відкрите (open questions)

1. **Foundation Model — будувати самим чи партнеритися?** Якщо партнеритися (наприклад, з Ollama чи Mistral), economy training credits спрощується.
2. **Real money out — через Stripe Connect, чи інший шлях?** Залежить від країн, де запускаємось.
3. **Marketplace — централізований каталог чи P2P?** Централізований простіше для quality control, P2P більш censorship-resistant.
4. **GPU provider для cloud-shot training — Modal, RunPod, Lambda, чи власне?** Визначить unit economics.
5. **Foundation Model license** — open weights чи власна? Open weights це credibility, але більший R&D effort.
6. **Mobile App Store policies** — як обходити обмеження на in-app purchase для Marketplace? (Apple бере 30%)
