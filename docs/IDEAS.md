# PixelCode — Ідеї на розгляд

Бекпорт де-що експериментуємо, але ще не є критичним для roadmap.

## Team dispatch

Додаткова механіка координації команди: на борді можна назначити **Manager агента** яки розподіляє задачі стратегічно (за пріоритетом, балансом навантаження) замість просто sequential assignment. Це буде UI на борді + backend логіка в manager дилегуванні.

## Voice control

Голосові команди на мобілі: "assign coder to fix-bug-123", "check the office", "start training". Потребує STT SDK, мобільна-специфічна опрацьовка (iOS Siri vs Android SpeechRecognizer), батареї + мережевих витрат.

## Agent Level / Skill / Archetype System — залишок

Повний дизайн-спек і покроковий план реалізації заархівовані у тегу `v0.3.0-alpha.1` (`git show v0.3.0-alpha.1:docs/superpowers/specs/2026-04-20-agent-level-skill-archetype-system-design.md` та `.../plans/2026-04-20-agent-level-skill-archetype-system.md`). **Більшість спека вже реалізована** — нижче лише непокриті частини, актуалізовані під поточний `develop`.

**Уже зроблено** (НЕ переробляти, див. ROADMAP розділ B):
- Level як first-class стат + XP/skillCap прогресія (`50·level^1.6`, cap `10+2·level`, Lv20) — `[DONE]` [lib/models/agent_level.dart](../lib/models/agent_level.dart).
- 5-stat skill model (speed/precision/creativity/insight/reliability) + multi-tier routing Haiku/Sonnet/Opus — `[DONE]`.
- Hybrid gating: `TaskCard.allowedRoles` + `taskType` + `requiredLevelFor(difficulty)`, енфорситься в [lib/providers/task_board_provider.dart](../lib/providers/task_board_provider.dart) (`assignmentRejectionReason`).
- Task outcome rolls (bug/crit/incomplete) за precision/creativity/reliability — `[DONE]` [server/src/task_outcome.ts](../server/src/task_outcome.ts) + [lib/services/task_outcome.dart](../lib/services/task_outcome.dart).
- Drop-migration зі `schemaVersion` (зараз v6), зберігає grymni/cosmetics/achievements — `[DONE]` [lib/services/game_persistence_service.dart](../lib/services/game_persistence_service.dart).
- Energy meter — реалізований, але `[DORMANT]` (див. ROADMAP, рядок Energy meter): на single-provider Claude лічильник стояв на нулі; повертається разом із **F (Backend Abstraction)** + **I (Monetization)**. Тут НЕ дублювати.

**Залишок (власне беклог):**

1. **Evolving archetypes через TraitStore.** Вектор ваг розподілу stat-budget-у по 5 скілах, що дрейфує від досвіду (мапінг trait-tag → weight delta), з клампом ±15% від стартового leaning. Субстрат — існуюча `AgentTrait`/`TraitStore` система (зараз вона лише для lesson-tracking, не для еволюції стат). Потрібні: модель `ArchetypeVector`, `agent_evolution_provider.dart`, серверний `archetype_drift.ts`, radar-візуалізація поточного вектора. Поки відсутнє повністю.

2. **Quirks.** Permanent flavor-модифікатори (enum-каталог ~12: night_owl, perfectionist, fast_learner, mentor, lone_wolf, legend/rookie тощо), 1-2 призначаються при наймі. Server-side резолв ефектів за id (безпечний інжект у system prompt). Відсутнє повністю.

3. **Reviewer-pass (Precision ≥ 7).** Автоматичний другий прохід `reviewer` sub-agent після завершення задачі високоточним агентом: ~+50-80% токенів, `bug_chance / 3`. UI-бейдж вартості на картці ("⚡ ×1.8 tokens"). Зав'язано на майбутню token-економіку — тому логічно піднімати разом з реактивацією Energy meter (F/I). Відсутнє.

4. **Завершити skill → LLM-param wiring.** Зараз скіли впливають лише на вибір моделі (`capabilityModelForSkills`). Незамаплені: Speed → `reasoning_effort`, Creativity → `temperature` bucket (тільки на divergent task types), Reliability → retry/validation policy. (Precision → reviewer-pass = пункт 3.)

5. **3 нові ролі: Product Manager, Data Analyst, DevOps.** Gating вже підтримує `taskType`/`allowedRoles`, але самих ролей нема (зараз 11). Потрібні записи в `roleCatalog` [lib/models/game_economy.dart](../lib/models/game_economy.dart) + `roleTemplates` [server/src/agents.ts](../server/src/agents.ts) з archetype-вагами, passives і task-типами (`product-spec` / `data-analysis` / `devops`).

6. **AgentSkillRadar (пентагон).** Віджет радар-чарта 5 осей для картки/деталей агента — потрібен і сам по собі, і як візуалізація drift-у з пункту 1. Level-бейджі та task-card чипи вже є.

**Поза scope (v2+ у спеку):** rarity-roll при наймі, P2P marketplace, LLM-procgen recruitment pool, mentoring/paid courses. Task-execution **time**-формула (`difficulty×12s × speed_modifier`) зі спека не лягає на поточну модель (нема real-time виконання задач за таймером) — переоцінити перед імплементацією.

## Account / портативна команда — залишок

Команда тепер прив'язана до **акаунта**, а не до проєкту (роутинг сховища за `accountId`, default-константа `"local"`) — перемикання проєктів зберігає той самий загін. Реалізовано: серверне account-scoped сховище game_state + traits ([server/src/account_paths.ts](../server/src/account_paths.ts), [server/src/account_migration.ts](../server/src/account_migration.ts)), `set_account` у протоколі, клієнтський `AccountProfile` ([lib/models/account_profile.dart](../lib/models/account_profile.dart) / [lib/providers/account_provider.dart](../lib/providers/account_provider.dart)). Нижче — свідомо відкладене.

1. **Справжній крос-машинний sync.** Зараз «та сама команда на іншому компі» працює лише при підключенні до *того самого* сервера (localhost/Tailscale). Коли на кожній машині свій сервер — команда не переноситься (сховище `~/.pixelcode/accounts/{id}/` локальне для машини). Потрібно: портативне/хмарне сховище акаунта **або** export/import теки акаунта (узагальнити [lib/services/agent_export_service.dart](../lib/services/agent_export_service.dart) з per-agent до per-account). Це фундамент під «взяти команду на чужий проєкт і піти з нею».

2. **Злиття traits з усіх legacy-проєктів при міграції.** Зараз [server/src/account_migration.ts](../server/src/account_migration.ts) бере game_state + traits лише з НАЙНОВІШОГО проєкту. Уроки з інших проєктів, де працювала команда, не зливаються (ризик дублів — тому відкладено). Потрібен dedup-merge по `(agentId, tag, source)`.

3. **Справжній мультиакаунт.** Зараз один акаунт із константним id `"local"` (щоб не розщепити команду між пристроями — випадковий per-device id зламав би крос-девайс sync). Для кількох акаунтів: унікальні id, UI вибору/створення акаунта, і **сервер-авторитетне узгодження** (зараз `currentAccountId` — один глобал на single-tenant сервері; треба per-connection lookup у [server/src/server.ts](../server/src/server.ts)).

## Інвентарний айтем «пробник» (timed trial)

Витратний/тимчасовий предмет у grid-інвентарі, що на певний час дає **спробувати** преміум-косметику — напр. круту кнопку відправки (send-button style). Важливо: сам **вибір** кнопки лишається в **налаштуваннях** — інвентар не дублює конфіг косметики. Айтем лише тимчасово розблоковує опцію в налаштуваннях, а по завершенню таймера вона зникає звідти назад. Потрібні: тип `consumable`/`timed` у моделі предметів, поле expiry (таймер володіння), і gate у резолвері косметики (`theme_provider` / cosmetics), який поважає тимчасовий unlock і прибирає його після спливання. Поки відкладено — спершу базовий grid-інвентар (клітинки + рух/сортування предметів).

---

Для детальних планів розвитку див. **ROADMAP.md**.
