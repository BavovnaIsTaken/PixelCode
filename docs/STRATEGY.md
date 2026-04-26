# PixelCode — Стратегія до 2027

> Документ-стратегія: вектор руху, бізнес-план, контент-план для соцмереж.
> Підготовка до ери, коли локальний інференс **і локальне тренування** на смартфоні стане реальністю для пересічного користувача — free-to-play механіка зі спавном власних моделей, community-driven training, marketplace торгівлі та злиття агентів.

---

## Context

PixelCode (alpha v0.3.0, дата 2026-04-26) — **візуальна платформа для оркестрації AI-агентів** у форматі піксель-арт гри. Сьогодні в основі — Claude Agent SDK (одна з найкращих опцій на ринку зараз), але архітектура з самого початку проєктується **agent-backend-agnostic**: SDK — це лише перший імплементований backend, а не центр гравітації продукту.

Архітектура вже містить більшість будівельних блоків, потрібних для 2027:

- **Multi-tier model routing** — Haiku / Sonnet / Opus на основі агентського skill score ([lib/models/agent_level.dart](../lib/models/agent_level.dart)); цей шар легко узагальнити до tier-based routing незалежно від провайдера
- **Energy meter** — daily token meter як ігровий ресурс ([lib/widgets/energy/energy_meter.dart](../lib/widgets/energy/energy_meter.dart))
- **Economy layer** — валюта Grim, магазин, апгрейди ([lib/models/game_economy.dart](../lib/models/game_economy.dart))
- **Agent personalization** — score/decay/eviction memory lifecycle (бекенд готовий, UI попереду); сама абстракція "агент має пам'ять" не залежить від конкретного SDK
- **Cross-platform real-time mirroring** — Flutter на 5 платформах з WebSocket-синхронізацією

**Стратегічна позиція щодо backends:** Claude Agent SDK сьогодні — найзручніший спосіб запускати агента з tool use і memory. Завтра з'являться інші: open-source agent frameworks, локальні runtime, спеціалізовані SDK для on-device моделей. Завдання PixelCode — лишатися шаром UI/гри/економіки/marketplace **поверх** будь-якого з них, а не намертво приварюватися до одного.

Поточна ліцензія `PolyForm Noncommercial 1.0.0` блокує комерційне використання третіми сторонами — це підходить для community-фази, але потребує переходу до dual license перед монетизацією.

---

## 1. Вектор руху

### Загальна теза

До 2027 Haiku-клас моделей буде доступний локально на більшості сучасних смартфонів (Apple Intelligence, Qualcomm NPU, on-device Gemma/Phi/Llama), і — ключовіше — буде доступне **локальне дотренування** через LoRA / QLoRA / adapter-merging на пристрої або у дуже дешевому хмарному GPU-shot.

PixelCode вже має всі архітектурні кубики. Потрібно:

1. **Перемаплювати routing** так, щоб локальна модель = безкоштовний агент, хмара = преміум апгрейд (без переписування гри)
2. **Дозволити спавн власних моделей** — користувач не наймає одного з 7 пресетів, а створює унікальну модель/агента, тренує її на своїх задачах, диференціює від решти
3. **Зробити агентів торговельним об'єктом** — community marketplace, де агенти зливаються, продаються, обмінюються; кожний training run робить агента унікальним активом

Це перетворює PixelCode з "інструменту з ігровим шаром" на **платформу-екосистему** з мережевим ефектом: чим більше користувачів тренують, тим багатша палітра агентів, тим цінніша гра для нових юзерів.

### Чому це критично робити рано

- **Community повинна тренувати раніше за конкурентів.** Перші 6–12 місяців marketplace формують стандарти й каталог "топ-агентів". Хто перший збудує екосистему — отримує network lock-in.
- **Тренування створює особистий зв'язок.** Агент, якого ти прокачував 3 місяці, не викинеш — це найсильніший retention механізм у грі.
- **User-generated content = безкоштовне покращення продукту.** Кожен training run спільноти робить базу моделей багатшою без витрат R&D з нашого боку.
- **Marketplace = вторинний дохід** від комісії з продажів агентів, без необхідності продавати власні підписки агресивніше.

### Фази

#### Q2–Q3 2026 — Завершення ядра

- **Agent Personalization System** — UI інтеграція + decay/eviction (бекенд є в [memory_lifecycle.ts](../server/src/memory_lifecycle.ts), [lesson_extractor.ts](../server/src/lesson_extractor.ts))
- **Android deploy** — закрити скелет
- **Room adjacency bonuses** — провести дроти у наявному фреймворку
- Стабілізувати alpha, набрати 50–100 активних тестерів

**Принцип кварталу:** жодного нового scope. Тільки доводимо до ладу те, що вже заплановано.

#### Q3 2026 — НЕ ЧЕКАЄМО 2027: ранній Custom Agent Spawn (MVP)

Перший крок до екосистеми — **не з повного локального тренування на телефоні**, а з легкодоступної версії, яку можна запустити вже зараз:

- **Custom agent spec.** Користувач створює агента через UI: вибирає базову модель (Haiku/Sonnet), визначає system prompt, role bias, skill weights, "особистість"
- **Training через Agent Personalization System** (вже є бекенд!) — кожен dungeon run і завершена задача додають lessons; це і є "тренування" у м'якому сенсі (промпт-tuning, не вагові градієнти)
- **Експорт/імпорт агентів** — JSON-файл агента можна поділитися. Це початок marketplace без блокчейну, без NFT, без crypto
- **Перший community trade** — Discord/Reddit thread, де люди обмінюються своїми "коучингами" агентів

Це робиться **на існуючому стеці**, без чекання локальних моделей.

#### Q4 2026 — Публічна бета + перший монетизаційний шар

- Перейти PolyForm Noncommercial → **dual license** (особисте/освітнє безкоштовно, комерційне Pro paid)
- Запустити **Pro tier:** cloud sync (сервер не на Mac, а в хмарі), необмежені проєкти, розширена аналітика персоналізації
- Косметика: скіни, меблі, теми — перший потік мікротранзакцій
- **Companion PWA:** моніторинг офісу з браузера (без повного Flutter-клієнта)

#### Q4 2026 — Agent Marketplace v1

- **Каталог агентів** в аппці: рейтинг, відгуки, статистика виконаних задач
- **Агент = NFT без NFT** — унікальний ID, історія тренування, performance record. Технічно — підписаний JSON у репо власника
- **Перші мікротранзакції з агентами** — продаж популярних "тренованих" агентів (через Pro-облікові записи)
- **Злиття агентів (merge)** — два агенти → новий зі змішаними характеристиками; механіка "розмноження" як у Pokémon

#### Q1 2027 — Backend-agnostic шар + підготовка до local-AI era

Тут робимо один з найважливіших архітектурних кроків — **виносимо все, що зараз зав'язано на Claude Agent SDK, за абстракцію `AgentBackend`**:

```
AgentBackend (interface)
 ├─ ClaudeAgentSdkBackend   (поточна реалізація)
 ├─ OpenAgentBackend        (для open-source agent frameworks)
 ├─ LocalRuntimeBackend     (Ollama / MLX / llama.cpp)
 └─ CustomBackend           (community plugins)
```

Конкретні задачі:

- **Виокремити `AgentBackend` interface** — все, що зараз робить [server/src/server.ts](../server/src/server.ts) через SDK (session, tool use, hooks, memory) → за абстракцією
- **Зберегти Claude Agent SDK як перший і default backend** — він залишається найкращим вибором сьогодні; ми просто перестаємо бути від нього залежними
- **Routing tier-based, а не provider-based** — `local-fast` / `local-quality` / `cloud`, де "cloud" може бути Anthropic, OpenAI, чи будь-хто інший
- **Прототип з Ollama + llama3.2:1b або phi4-mini** — перший non-Anthropic backend, перевірити, що dungeon-суддя коректно оцінює локальні відповіді
- **LoRA-adapter spec** — формат, у якому "тренований агент" зберігає не тільки промпти, а й майбутні adapter weights, та працює через `LocalRuntimeBackend`

**Чому це робимо саме зараз, а не пізніше:** marketplace (Q4 2026) уже починає торгувати агентами; якщо backend намертво приварений до одного SDK, кожна торгівельна одиниця — це лише promptpack. З абстракцією агент стає повноцінним об'єктом, який може жити на будь-якому runtime — це різниця між "обмін JSON-конфігами" та "обмін активами".

#### Q2–Q4 2027 — Free-to-play + локальні моделі + community training

**Дві колонки еволюції одночасно:**

**Колонка А — Free-to-play з локальним інференсом:**

```
Безкоштовно:  локальна модель (~Haiku-tier) → агенти 1–7 рівня → без API costs
Платно:       хмарний апгрейд → Sonnet/Opus → складні задачі
Валюта Grim:  заробляється локальними агентами → витрачається на cloud time
Real money:   Grim packs / energy packs / cosmetics
```

**Колонка Б — Локальне дотренування агентів (детально нижче, секція 2).**

**Ефект для гри:**

- Енергія перестає бути бар'єром (локально безкоштовно)
- Виникає новий ресурс: **час тренування** і **якість датасету** (dungeon victories)
- "Найкращий агент" перестає означати "найдорожча модель" — починає означати "найдовше тренований саме під твій стиль"
- Топ-агенти спільноти стають культовими активами

Energy meter стає центральним монетизаційним хуком для cloud-tier; локальні training runs мають свою валюту "training credits".

---

## 2. Local Training Roadmap (детально)

### 2.1 Реалістичні дати on-device training

| Рік | Що можливо | Залізо | Практичний use case |
|---|---|---|---|
| 2026 (зараз) | QLoRA 1B моделі, повільно, гарячиться | iPhone 17 Pro / Snapdragon 8 Elite | Лише експериментально, demo |
| 2027 | QLoRA 1–3B "за ніч" поки телефон на зарядці | Флагмани з NPU train-ops | **Перший mainstream-сценарій для PixelCode** |
| 2028 | Training як штатний use case | A19/A20, Snapdragon X mobile | Масовий запуск local training tier |
| 2029–2030 | Mainstream (не флагмани) телефони тренують вночі | Масовий ринок | F2P-механіка повністю розкривається |

**Бар'єри сьогодні** — не RAM (8–12GB достатньо для QLoRA 1–3B), а **батарея + температура + NPU зараз inference-only**. Apple Neural Engine і Qualcomm Hexagon потребують наступного покоління для training ops без перегріву.

**Тому стратегія зараз — гібрид:**

- Cloud-shot training як перший крок (2026–2027) — $0.05–0.20 за training run, працює на будь-якому пристрої
- On-device training приходить як додатковий шар (2027+), не замінює cloud, а доповнює

### 2.2 Архітектура: Foundation + Adapter

Не "генеруємо моделі з нуля" — це нереалістично. Натомість:

```
PixelCode Foundation Model (одна, шерена між усіма)
  └── базується на Llama 3.2 / Phi-4 / Qwen, файнтюнена нами
      на coding-style задачах PixelCode (dungeon, code review etc.)
  └── скачується один раз (~1–3GB)
  └── живе в пам'яті пристрою або на сервері

Player Agent = Foundation + LoRA Adapter
  └── adapter ~10–100MB
  └── тренується на історії гравця (dungeon перемоги, успішні задачі)
  └── торгується на marketplace як легкий файл
  └── adapter merge = два adapters → новий зі змішаною поведінкою
```

**Чому Foundation + Adapter, а не повна модель на гравця:**

- Гравець не качає 7GB модель з нуля
- Базова модель шерена між усіма (один download для всієї спільноти)
- Adapter — це справжня "індивідуальність агента"
- Marketplace торгує легкими adapters, а не повними моделями
- Merge / breeding математично простий (lora weight averaging)

### 2.3 F2P "час замість грошей" loop

Це **головна механіка retention** і одночасно етичний F2P без pay-to-win.

```
Старт:    free starter agent (Foundation + базовий adapter)
   ↓
Гра:      dungeon перемоги, виконані задачі → training data
   ↓
Тренування (вибір гравця):
   • Безкоштовно: on-device, повільно (2–8 годин на adapter update)
   • Платно:      cloud-shot $0.10, 5 хвилин
   ↓
Прокачка: через 1–2 тижні агент має унікальний "характер"
   ↓
Продаж:   виставив на marketplace → перший Grim → конвертується в реальні гроші (мінус комісія)
   ↓
Реінвест: купив training credits → швидше тренує наступного агента
   ↓
Loop:     кращі агенти → більше продаж → більше Grim → ...
```

**Етична позиція:** F2P гравець може досягти топу, просто граючи довго. Pay-to-progress прискорює, але не разблоковує. Це принципово — без цього втрачаємо moral high ground і community trust.

### 2.4 Offline стратегія — ТАК, обов'язково

Не просто "розглядаємо" — це **головний диференціатор продукту**:

- **Privacy:** training data не залишає пристрій (величезна перевага в епоху AI act / GDPR / приватності)
- **Cost:** $0 на inference для гравця, $0 на серверну інфраструктуру для нас
- **Marketing:** "AI team у твоїй кишені, інтернет не потрібен"
- **Differentiation:** Cursor / Copilot / Devin — всі cloud-only. Ми єдині йдемо у local-first для масового користувача
- **Reliability:** тренування і гра не залежать від API uptime, rate limits, ціни на токени

**Tradeoff offline:** marketplace, агент-обмін, breeding — все ж потребують serverської координації. Але **самі агенти живуть локально**, server тільки для маркетплейсу.

### 2.5 Roadmap локального тренування

| Квартал | Milestone |
|---|---|
| Q3 2026 | Custom Agent Spawn UI (без weights, тільки prompt + skills + lessons) |
| Q3 2026 | **Self-play в dungeon** — агент пробує задачу N разів, кращі attempts → memory; це попередник self-distillation |
| Q4 2026 | Marketplace v1 — обмін JSON-агентами |
| Q4 2026 | **Crowdsourced training data pool (opt-in)** — анонімізований data lake з real gameplay |
| Q1 2027 | AgentBackend abstraction; перший non-Anthropic backend (Ollama) |
| Q1 2027 | **Distillation pipeline v1** — Cloud Opus генерує Foundation Training Set |
| Q2 2027 | **PixelCode Foundation Model v1** — fine-tuned Llama 3.2 / Phi-4 на distilled output |
| Q2 2027 | **Cloud-shot training** — $0.05–0.20 на adapter update (як прискорювач, не основа) |
| Q3 2027 | **LoRA adapter format** — стандартизований marketplace-сумісний формат |
| Q3 2027 | **Adapter merge mechanic** — breeding двох агентів |
| Q3 2027 | **AI judge ensemble** — кілька судів для anti-reward-hacking |
| Q4 2027 | **On-device training (alpha) + on-device self-distillation** — для флагманів з NPU train-ops |
| 2028+ | On-device training mainstream; повний offline experience; community-driven Foundation updates |

### 2.6 Self-Distillation: майже безкоштовне тренування

Це **окремий потужний шар стратегії** — використання моделей для тренування інших моделей. Перевертає всю економіку training, бо переводить його з cloud-cost у вільний gameplay.

#### Чотири джерела безкоштовного training signal

**1. Knowledge Distillation (teacher → student):**

- Потужна cloud-модель (Sonnet/Opus) одноразово генерує 10K зразків
- Cost: $50–100 разово
- Це стає PixelCode Foundation Training Set — шерений з усіма гравцями

**2. Self-play:**

- Агент розв'язує одну задачу 10 разів
- Обирає найкращу спробу як positive example, найгірші — як negative
- Adapter навчається на власних кращих відповідях (AlphaZero approach)

**3. AI judge / RLAIF:**

- Одна локальна модель оцінює відповіді іншої → training signal
- **У PixelCode це вже існує** — [server/src/dungeon.ts](../server/src/dungeon.ts) має Haiku-суддю; інфраструктура готова для перевикористання як distillation pipeline

**4. Crowdsourced from gameplay:**

- Кожен гравець, граючи, генерує training data
- Opt-in pool → community-driven Foundation Model updates
- 10K активних гравців × 10 interactions/день = 100K examples/день. Після фільтрації якості → 10K якісних examples/день. Тиждень = 70K training tokens безкоштовно

#### Триярусна distillation chain

```
Шар 1 (один раз, дорого):
  Cloud Opus → генерує 10K зразків для coding задач PixelCode
  Cost: $50-100, разово
  Output: PixelCode Foundation Training Set

Шар 2 (періодично, дешево):
  Foundation Model fine-tune на cloud GPU
  Cost: ~$5-20 per major version
  Output: PixelCode Foundation Model (1-3GB, free для всіх гравців)

Шар 3 (постійно, безкоштовно):
  Player on-device:
    Local agent A розв'язує dungeon задачу
    Local agent B (judge) оцінює якість
    Best attempts → adapter training data
    Adapter update happens overnight while charging
  Cost: $0 (тільки електрика)
  Output: персональний adapter гравця
```

#### Інфраструктура, що вже є в PixelCode

- Multi-agent система ([server/src/server.ts](../server/src/server.ts)) — основа для AI-vs-AI generation
- Dungeon з Haiku-суддею ([server/src/dungeon.ts](../server/src/dungeon.ts)) — готовий judge для RLAIF
- Task outcome scoring (bug / crit / incomplete) — quality signal
- XP як ground truth для якості рішень
- Agent personalization memory ([server/src/memory_lifecycle.ts](../server/src/memory_lifecycle.ts)) — структурований формат "lessons" вже існує і може бути використаний як seed для adapter training

#### Pitfalls (важливо не пропустити)

- **Garbage in → garbage out:** якщо local judge слабкий, тренування на його output погіршує student. Лікується ensemble of judges + occasional cloud Opus quality check
- **Mode collapse:** модель після кількох циклів self-distillation стає одноманітною, втрачає різноманіття. Лікується diversification: різні data sources, periodic injection of cloud-generated examples
- **Privacy:** crowdsourced pool має бути strictly opt-in, з anonymization training data перед агрегацією
- **Reward hacking:** агенти знаходять "тріщини" в judge-моделі і експлойтять їх. Лікується періодичним оновленням judge

#### Економічний наслідок

- Раніше планували: cloud-shot training $0.05–0.20 на adapter update (Колонка Б, секція 2.1)
- З self-distillation: $0 на adapter update (overnight on-device + локальний AI judge)
- **Бар'єр входу для F2P гравця падає до нуля** — буквально не платить нічого
- Cloud-shot training залишається як **прискорювач** для платних гравців, але не як необхідність

Це робить F2P loop (2.3) реально працюючим у мейнстрімі — не "грай 6 місяців щоб щось продати", а "грай тиждень → перший продаж".

### 2.7 Економіка training credits

**Питання cost / margin (актуально для гравців, що купують прискорення поверх free on-device):**

- Cloud-shot training run = ~$0.02–0.05 нашого cost (GPU-секунди)
- Продаємо за $0.10 → margin ~50–80%
- Гравець може заробити training credits через гру (Grim → credits) або купити прямо
- **Note:** після впровадження self-distillation (2.6), credits — це не основа monetization, а опція для нетерплячих

**Питання real money out:**

- Гравець продав агента за 1000 Grim → конвертує в реальні $5 (мінус 15-20% комісії)
- Це створює реальну economic loop, де час → гроші
- Юридично це треба робити обережно — gambling/marketplace регуляції різняться по країнах

**Питання toxicity / fraud:**

- Auto-generated low-quality agents спамлять marketplace
- Рішення: agent quality score (вимірюється на standardized dungeon challenges перед listing)
- Anti-collusion: один акаунт не може торгувати з собою для накачки rating

---

## 3. Бізнес-план

### Позиціонування

| | |
|---|---|
| **Категорія** | AI development gamification + agent platform |
| **Хто** | Розробники, яким нудно/страшно з pure CLI AI tools; та геймери, що хочуть тренувати "своїх" AI-агентів |
| **Диференціатор** | Game mechanics + agent personalization + community marketplace + backend-agnostic архітектура |
| **Конкурент** | Прямого немає. Непрямі: Cursor, GitHub Copilot (вони не грають); a16z-style agent platforms (вони не для масової аудиторії) |

**Важливо для повідомлень:** не позиціонуємось як "обгортка над Claude Agent SDK". Позиціонуємось як **платформа, де живуть AI-агенти, які ти тренуєш і прокачуєш** — а яким SDK / runtime вони працюють під капотом, це деталь реалізації. Сьогодні це Claude Agent SDK (бо найкращий), завтра — будь-що.

### Моделі доходу (по часових шарах)

| Шар | Коли | Що | Ціна |
|---|---|---|---|
| Cosmetics | Q4 2026 | Скіни агентів, меблі, теми офісу | $2–5 one-time |
| Pro subscription | Q4 2026 | Cloud server + sync + analytics | $9/міс |
| **Marketplace commission** | **Q4 2026** | **Комісія з продажів агентів спільноти (15–20%)** | **% від угоди** |
| B2B team license | Q1 2027 | Команди розробників, shared agent pools | $29/міс/team |
| **Training credits** | **Q2 2027** | **Cloud GPU-shots для дотренування агентів** | **$0.05–0.20 / run** |
| Grim packs | Q3 2027 | Cloud inference time | $0.99–$4.99 |
| Local AI tier | Q3 2027 | Базова гра безкоштовна, local models на пристрої | $0 |
| **Premium agent listings** | **Q3 2027** | **Просування власного агента в каталозі** | **$2–10/міс** |

**Ключове спостереження:** Marketplace commission та training credits — це **non-zero-sum monetization**. Чим більше юзерів, тим більше тренують, тим більше угод, тим більше комісії. Не потрібно агресивно тиснути на підписки.

### Unit economics (orієнтир)

- Local-only user — $0 ARPU, але органічне зростання + word of mouth
- Cosmetics buyer — $5–15 LTV
- Pro subscriber — $108/рік LTV
- B2B team (5 людей) — $1740/рік LTV

### Критичне рішення щодо ліцензії

PolyForm Noncommercial зараз правильна для community building, але блокує B2B. До Q4 2026 потрібен перехід на dual license — особисте/освітнє use безкоштовно, комерційне платне (як модель Sentry, MongoDB).

---

## 4. Контент-план для соцмереж

### Платформи

| Платформа | Ціль | Чому |
|---|---|---|
| **X (Twitter)** | Devtool community, Claude/AI екосистема | Тут живуть ранні adopters AI tools |
| **TikTok / Reels / Shorts** | Вірусний потенціал | "AI codes for me" → масова аудиторія |
| **YouTube** | Конвертація + SEO | Довгі demo, tutorials |
| **Reddit** | r/programming, r/FlutterDev, r/MachineLearning | Trust + нішева credibility |

LinkedIn — пропустити до фази B2B (Q1 2027).

### Контентні колони

1. **"Watch AI work"** — екранний запис пікселів у real-time
2. **"Agent leveled up"** — прогрес агентів, персоналізація, історії тренування
3. **"I didn't write a line"** — задача виконана командою
4. **"Future of coding"** — thought leadership про local AI + community training
5. **"Behind the pixel"** — devlog, технічні рішення
6. **"Meet the breeders"** — інтерв'ю з топ-тренерами спільноти, історії унікальних агентів (важлива колонка з Q4 2026, коли запуститься marketplace)
7. **"Agent battles"** — два агенти від різних тренерів змагаються на одній dungeon-задачі

### X (Twitter) — 1–2 пости/день

**Тип A — Performance thread (щотижня):**

> Мій AI team закрив 31 задачу цього тижня.
> Haiku — дрібниці. Sonnet — архітектура. Opus — review.
> Ось що ми зібрали.

**Тип B — Hot take (2–3/тиждень):**

> До 2027 ваш телефон запускатиме Haiku-клас локально.
> PixelCode будується під цей майбутній світ:
> local agent = free worker, cloud = elite squad.

**Тип C — Агент milestone:**

> coder#1 щойно вийшов на рівень 12 і перейшов на Sonnet.
> 3 тижні dungeon runs, 47 задач.
> Він буквально краще кодить ніж на старті.

**Тип D — Demo GIF (найвірусніший):**

> Запустив задачу о 23:00, ліг спати.
> Прокинувся — офіс вже відсвяткував деплой.
> [GIF піксель-офісу в дії]

### TikTok / Reels / Shorts — 3–4 на тиждень

Формат: 30–60 секунд, hook у перші 2 секунди.

- **"Мої AI кодери написали додаток поки я пив каву"** — таймлапс screen recording офісу + результат
- **"Що якщо твоя dev team виглядала б ось так?"** — showcase піксель-анімації, character sprites, dungeon
- **"Я не написав жодного рядка коду цього тижня"** — split screen: PixelCode офіс / готовий продукт
- **"AI agent provoked a bug. Then fixed it. Then apologized."** — смішний момент з task outcome системи (bug roll)
- **"Level up your AI coder"** — dungeon challenge gameplay, XP система, реакція

### YouTube — 1–2 відео/місяць

| Відео | Ціль |
|---|---|
| "I built an app with a team of AI agents — 30 day challenge" | Flagship, повний цикл |
| "The pixel office that actually codes" | Demo + behind the scenes |
| "Why my AI agent remembers everything now" | Personalization deep-dive |
| "PixelCode dungeon — can AI beat a real coding challenge?" | Gamified content |
| "Building PixelCode: from CLI tool to game" | Devlog, origin story |

### Reddit — 2–3 на тиждень

| Субредит | Формат |
|---|---|
| r/programming | Show & Tell: "I turned AI agent orchestration into a pixel-art game" |
| r/FlutterDev | Технічний пост: кастомний Canvas renderer без game engine |
| r/MachineLearning | "Preparing PixelCode for on-device inference era — architecture decisions" |
| r/gamedev | "Game design in a devtool: why XP and economy make AI more useful" |
| r/webdev | "My AI team deploys faster than I do" (cross-post) |

**Reddit-правило:** value-first, no spam. Тільки справжній контент, ніяких прямих sales pitches.

### Ритм запуску

```
Тиждень 1–2:  Налаштувати X + Reddit (мінімальний cost)
Тиждень 3–4:  Перший TikTok / Reels (найбільший потенціал охоплення)
Місяць 2:     Перше YouTube відео
Місяць 3:     Аналіз — що зайшло, подвоїти там
```

**Головний KPI зараз:** не підписники, а **GitHub stars + alpha signups**. Усі соцмережі конвертують у ці дві точки.

---

## 5. Що це міняє у поточному roadmap

Існуючі фічі залишаються — але змінюється **порядок пріоритетів**:

| Що | Старий пріоритет | Новий пріоритет |
|---|---|---|
| Custom agent spawn UI | "колись після alpha" | **Q3 2026 (P0)** |
| Agent export/import (JSON) | не планувалось | **Q3 2026 (P0)** |
| Agent personalization UI | Q2 2026 | Q3 2026 (об'єднати з custom agent spawn) |
| Marketplace v1 | не планувалось | **Q4 2026 (P0)** |
| Agent merge mechanic | не планувалось | Q4 2026 (P1) |
| AgentBackend abstraction (не лише model, а весь runtime) | "колись" | Q1 2027 (P0) |
| LoRA adapter spec | не планувалось | Q3 2027 (P0) |
| PixelCode Foundation Model | не планувалось | Q2 2027 (P0) |
| Cloud-shot training (як перший крок до on-device) | не планувалось | Q2 2027 (P0) |
| **Distillation pipeline (cloud teacher → local student)** | не планувалось | **Q1 2027 (P0)** |
| **Self-play в dungeon (попередник self-distillation)** | не планувалось | **Q3 2026 (P0)** |
| **Crowdsourced training data pool (opt-in)** | не планувалось | **Q4 2026 (P0)** |
| **AI judge ensemble** | не планувалось | **Q3 2027 (P1)** |
| On-device training (alpha) | не планувалось | Q4 2027 (P1) |
| On-device training (mainstream) | не планувалось | 2028+ (P1) |

---

## 6. Одне речення — суть стратегії

PixelCode перестає бути "обгорткою над одним SDK" і стає **backend-agnostic платформою-екосистемою агентів, яких користувачі тренують, торгують і зливають**. Завдання зараз: **MVP custom agent spawn у Q3 2026, marketplace v1 у Q4 2026, AgentBackend abstraction у Q1 2027, локальне дотренування у Q2–Q4 2027**, паралельно будуючи community через TikTok (вірусність) + X (devtool ecosystem) + Reddit (credibility) + agent battles / breeder interviews як унікальний контент-формат.
