# PixelCode

**Візуальний оркестратор для Claude Agent SDK** — Android/iOS/MacOS аппка в стилі піксель-арт, яка перетворює роботу з AI-агентами на гру. Наймаєш команду агентів, даєш їм задачі, дивишся як вони працюють у маленькому офісі, і прокачуєш їх через реальні комміти та dungeon-челенджі.

> 🇬🇧 [English version below](#pixelcode-en)

---

## Що вирізняє

- **Повне real-time віддзеркалення на всіх платформах.** Запустив аппку на macOS, Windows, Linux, iOS, Android — усе синхронізовано в реальному часі. Почав задачу на ноуті, продовжив з телефона, стежиш за офісом з планшета — стан команди, прогрес задач, чат, активність агентів однакові скрізь у ту саму секунду.
- **Встановлення `.apk` / `.ipa` прямо з мобільного.** Можеш вести розробку безпосередньо з телефона чи планшета — збірка під Android або iOS ставиться з того ж самого пристрою, без кабелю, без ноутбука поруч. Працює навіть на мобільному інтернеті — нічого не потрібно, крім самого пристрою.

## Що це

PixelCode обгортає Claude Agent SDK у Flutter UI. Замість терміналу маєш:
- hub-екран з анімованим офісом,
- команду агентів за ролями (tech-lead, coder, reviewer, tester, security, UI/UX, manager),
- борд задач, чат, економіку з валютою та магазином.

Node.js-сервер ([server/](server/)) зв'язує Flutter-клієнт із Claude Agent SDK через WebSocket.

## Технічний стек

**Клієнт (Flutter desktop/mobile аппка)**
- **Flutter** 3.11+ / **Dart** 3.11+ ([pubspec.yaml](pubspec.yaml))
- **flutter_riverpod** — стейт-менеджмент
- **shared_preferences** — локальне збереження (сесії, налаштування)
- **path_provider**, **file_selector**, **image_picker** — робота з файлами та асетами
- **bonsoir** — Bonjour/mDNS для пошуку сервера в LAN
- **super_drag_and_drop** — drag-and-drop на борді задач
- **url_launcher** — відкриття зовнішніх посилань
- Кастомний Canvas-рендер для піксель-офісу (без ігрового рушія)
- Платформи: macOS, Windows, Linux, iOS, Android

**Сервер (локальний оркестратор)**
- **Node.js** 20+ з **TypeScript** 5.7 ([server/package.json](server/package.json))
- **@anthropic-ai/claude-agent-sdk** — те, що оркеструється
- **ws** — WebSocket-транспорт до Flutter-клієнта
- **bonjour-service** — публікує сервер у mDNS
- **tsx** — dev-раннер / watch-режим

**Інше**
- **Tailscale Funnel** — публічний HTTPS-тунель до локального сервера; використовується для OTA-встановлення `.ipa` / `.apk` на мобільні пристрої з будь-якої мережі
- **Xcode `devicectl`** — сайлент-встановлення на iPhone/iPad, коли пристрій уже спарений із Mac через Xcode
- **adb** (Android Platform Tools) — сайлент-встановлення `.apk` на Android, коли пристрій підключено по USB або Wi-Fi ADB
- **LeanKG** — використовується під час розробки для пошуку по коду ([leankg.yaml](leankg.yaml))

## Основні фічі

- **Оркестрація команди агентів** — наймаєш агентів за ролями; у кожного профіль скілів (precision, insight, reliability, creativity + speed), який визначає, на яку модель Claude він маршрутизується (Haiku / Sonnet / Opus). [lib/models/agent_level.dart](lib/models/agent_level.dart).
- **Борд задач і делегування** — Kanban-стиль, призначення задач агентам, статус і чат у реальному часі. [lib/widgets/board/task_board_panel.dart](lib/widgets/board/task_board_panel.dart).
- **Dungeon-тренування** — реальні кодерські челенджі (швидкість, рефакторинг, дизайн-патерни, безпека), Haiku-суддя оцінює результат і нараховує XP. [server/src/dungeon.ts](server/src/dungeon.ts).
- **XP та прокачка** — агенти отримують XP за задачі й данжі (формула: difficulty² × якість × diminishing returns); кап — 20 рівень; модель підтягується автоматично.
- **Валюта Grim (₲) та економіка** — заробляєш на завершених задачах, витрачаєш на найми, апгрейди заліза (laptop → workstation) та розширення офісу. [lib/models/game_economy.dart](lib/models/game_economy.dart).
- **Рівні офісу** — Garage → Small Office → Modern Office → Tech Hub → Campus; кожен тир підвищує капасіті команди й відкриває механіки.
- **Сервер Claude Agent SDK** — локальний Node.js WebSocket-сервер керує сесіями, диспатчить команду, робить виклики SDK. [server/src/server.ts](server/src/server.ts).
- **Мультипроєктність і сесії** — перемикання між Git-репами; іменовані сесії зберігаються per-project. [lib/models/session_profile.dart](lib/models/session_profile.dart).
- **Пошук у LAN і деплой на пристрій** — Bonjour/mDNS автоматично знаходить сервер у мережі; вбудований iOS-деплой (сайлент через `xcrun devicectl` коли пристрій спарений, або OTA по HTTPS через Tailscale Funnel з будь-якої мережі). [lib/services/ios_deploy_service.dart](lib/services/ios_deploy_service.dart).
- **Energy meter** — індикатор витрат/використання в реальному часі, прив'язаний до активності субагентів. [lib/widgets/energy/energy_meter.dart](lib/widgets/energy/energy_meter.dart).

## Косметичні та другорядні фічі

- **Піксель-арт персонажі** — 6-тирова система спрайтів, 7 кадрів × 3 напрямки на роль, палітри за ролями (волосся / шкіра / очі / одяг). [assets/characters/](assets/characters/), [lib/widgets/canvas/pixel_sprites.dart](lib/widgets/canvas/pixel_sprites.dart).
- **Анімований офіс** — кастомний рендер 320×224 з Z-сортуванням за глибиною, анімації walk / type / read / idle, блукання з AI (рандомні паузи, відпочинок на стільці). [lib/widgets/canvas/pixel_office_painter.dart](lib/widgets/canvas/pixel_office_painter.dart).
- **Меблі** — столи, анімовані монітори (3 кадри), стільці, рослини. [assets/furniture/](assets/furniture/).
- **Бульбашки й статуси** — агенти показують "думає / друкує / читає / тестує / обговорює" з анімацією крапок.
- **Магазин** — скіни персонажів, меблі, апгрейди кімнат. [lib/widgets/shop/shop_panel.dart](lib/widgets/shop/shop_panel.dart).
- **Dark synthwave тема** — cyan-акцент (`#00C0D1`), ретро-естетика по всіх діалогах.
- **Easter eggs** — міні-гра Arkanoid і dungeon-crawler у стилі XQuest2. [lib/widgets/easter_eggs/](lib/widgets/easter_eggs/).
- **Logo Path DSL** — власна скрипт-мова для анімації логотипу на запуску/вимкненні. [lib/services/logo_path_program.dart](lib/services/logo_path_program.dart).
- **Панель діагностики** — здоров'я сервера, перевірка залежностей, лог-переглядач.

## У планах / в роботі

- **Бонуси суміжності кімнат** — Workstation ↔ Server Room (+5%), Break Room ↔ Lounge (стак моралі), Meeting Room ↔ Workstation (−10% затримки). Фреймворк є, проводка часткова. [docs/office_design.md](docs/office_design.md).
- **Мораль від Break Room** — +20% продуктивності коли агенти відпочивають; поки не активне.
- **Штраф за довгий кабель до Server Room** — −5% швидкості, якщо workstation далі ніж 8 клітинок від Server Room.
- **Буст Meeting Room для менеджера** — зараз просто +1 до капасіті; у планах — прискорення диспатчу задач менеджером.
- **Пам'ять рис агента** — персистентні "уроки" з минулих запусків для тюнінгу промптів; бекенд є ([server/src/trait_memory.ts](server/src/trait_memory.ts)), UI-інтеграція ще попереду.
- **Android-деплой** — iOS через Wi-Fi вже готовий; для Android є скелет.
- **Віддалена оркестрація** — WebSocket-шар готовий запускати сервер на іншій машині, не там де клієнт.

## Як запустити

PixelCode складається з двох частин — Flutter-клієнта та Node.js-сервера ([server/](server/)), який обгортає Claude Agent SDK. На десктопі (macOS / Windows / Linux) клієнт **сам піднімає сервер** як дочірній процес через `npm run dev` ([lib/services/server_process_service.dart](lib/services/server_process_service.dart)) — це на сьогодні єдиний штатний шлях. На iOS/Android сервер не запускається з аппки (обмеження пісочниці ОС), тож мобільний клієнт підключається до сервера, який уже крутиться на десктопі. У локальній мережі клієнт знаходить сервер автоматично через Bonjour/mDNS; якщо на Mac піднято Tailscale, сервер додатково публікує себе на публічному HTTPS-endpoint через Funnel — і мобільний клієнт може під'єднатися з будь-якої Wi-Fi чи мобільної мережі.

### 1. Передумови

**Спільне для всіх платформ:**
- **Flutter SDK** з Dart ≥ 3.11.4 ([pubspec.yaml](pubspec.yaml)) — [інструкція](https://docs.flutter.dev/get-started/install)
- **Node.js 20+** та `npm` (рекомендую [nvm](https://github.com/nvm-sh/nvm))
- **Git**
- Доступ до Claude — один з варіантів:
  - **A (рекомендовано):** встановити [Claude Code CLI](https://claude.ai/download) (або VS Code-розширення `anthropic.claude-code`) і залогінитися; сервер сам підхопить OAuth через Claude Pro / Max-підписку.
  - **B:** `export ANTHROPIC_API_KEY=sk-ant-…` (ключ з [console.anthropic.com](https://console.anthropic.com/)).

**Якщо збираєш десктоп-білд під macOS або плануєш iOS-таргет:**
- Xcode 15+ та Command Line Tools (`xcode-select --install`)
- CocoaPods: `brew install cocoapods` (або `sudo gem install cocoapods`)

**Для деплою на фізичний iPhone / iPad:**
- **Apple ID / Apple Developer account.** Безкоштовний Apple ID теж працює (personal team → sideload, перепідписати раз на 7 днів). Платний акаунт — до 1 року без перепідпису.
- **Налаштувати підпис у Xcode — ОБОВ'ЯЗКОВО для форка.** Відкрий `ios/Runner.xcworkspace`, вибери таргет `Runner` → вкладка `Signing & Capabilities`:
  - `Team` — свій. У репо зафіксовано placeholder `DEVELOPMENT_TEAM = YOUR_TEAM_ID` (реальний формат — 10 символів, літери й цифри, напр. `ABCD1234EF`); треба замінити на власний у діалозі Xcode, він перепише значення в [ios/Runner.xcodeproj/project.pbxproj](ios/Runner.xcodeproj/project.pbxproj).
  - `Bundle Identifier` — унікальний (поточний `com.example.pixelCode` — плейсхолдер; Apple не дасть підписати чужий bundle ID, тож зроби напр. `com.<твій-нік>.pixelcode`).
  - `Automatically manage signing` — увімкнено; Xcode сам випише provisioning profile.
- **Tailscale — якщо хочеш ставити з будь-якої мережі (без USB).** `brew install tailscale && sudo tailscale up` на Mac. При старті сервер автоматично вмикає `tailscale funnel` ([server/src/server.ts:1872](server/src/server.ts#L1872)) — пристрій встановлює `.ipa` по публічному HTTPS з будь-якої Wi-Fi / мобільної мережі світу. Без Tailscale залишається тільки сайлент-шлях через `xcrun devicectl` (потребує одноразового спарювання пристрою з цим Mac через Xcode).
- Деталі та діагностика — [docs/iOS_DEPLOYMENT.md](docs/iOS_DEPLOYMENT.md).

**Для Android:**
- Android Studio + Android SDK (API 34+); `ANDROID_HOME` або `ANDROID_SDK_ROOT` у середовищі (або стандартна тека `~/Library/Android/sdk` / `~/Android/Sdk`)
- JDK 17+
- Tailscale (опційно) — якщо хочеш роздавати `.apk` на пристрої в іншій мережі; без нього фолбек-посилання буде на локальний IP (LAN-only)
- APK сам за себе не підписаний release-ключем — за замовчуванням Flutter випускає debug-signed APK, якого вистачає для sideload через «Install from unknown sources»

### 2. Перший запуск

```bash
git clone <repo-url> pixelcode
cd pixelcode

# Flutter-залежності
flutter pub get

# Серверні залежності (один раз)
(cd server && npm install)

# Тільки якщо запускаєш під macOS або iOS
(cd macos && pod install)   # або (cd ios && pod install)

# Запуск десктоп-клієнта — сервер підніметься автоматично
flutter run -d macos        # або windows / linux
```

Сервер стартує на `localhost:9720`, публікується у mDNS як `_pixelcode._tcp` і зупиниться разом із клієнтом.

### 3. Запуск сервера окремо (для мобільних клієнтів або дебагу)

```bash
cd server
npm run dev                 # tsx watch, перезапуск при зміні файлів
# або явно з параметрами:
PORT=9720 PROJECT_CWD=/path/to/your/repo npm run dev
```

Після цього запускаєш мобільний клієнт — він сам знайде сервер у LAN через Bonjour, або через Tailscale Funnel якщо ти не в тій самій мережі:

```bash
flutter run -d <device-id>                # iPhone по USB або Android пристрій/емулятор
```

Для **однокнопкового встановлення вже зібраного `.ipa` / `.apk` на пристрій** — відкрий у хабі попап **Deploy to device** (іконка з телефоном у верхній панелі). Вибираєш вкладку iOS або Android, жмеш **Install** — сервер збирає, пробує сайлент-інстал через `xcrun devicectl` / `adb`, а при невдачі повертає install-URL для OTA через Tailscale Funnel. Деталі: [docs/iOS_DEPLOYMENT.md](docs/iOS_DEPLOYMENT.md).

### 4. Що має працювати після першого запуску

- Хаб-екран з анімованим офісом і принаймні одним агентом.
- Панель діагностики (⚙ → **Діагностика**) — усі пункти зелені: `node`, `claude-auth`, порт `9720`, LAN.
- Тест: створи задачу на борді, признач агенту — статус має дійти до `done` / `error` без зависання.

### 5. Типові проблеми

| Симптом | Причина | Що робити |
|---------|---------|-----------|
| `server/ directory not found at …` у логах | Flutter запущено з неправильним `cwd` | Запускай `flutter run` з кореня репо, не з `macos/` чи `ios/`. |
| «Unauthenticated» / 401 у серверних логах | Немає ні OAuth-сесії, ні `ANTHROPIC_API_KEY` | Запусти `claude` у терміналі й пройди OAuth, або `export ANTHROPIC_API_KEY=…` і перезапусти клієнт. |
| Мобільний клієнт не бачить сервер | Пристрої у різних Wi-Fi / macOS-фаєрвол блокує `node` | System Settings → Network → Firewall → дозволь вхідні для `node`; переконайся що обидва у тій самій мережі. |
| `pod install` падає | Застарілий CocoaPods | `brew upgrade cocoapods` або `sudo gem install cocoapods`. |
| `EADDRINUSE :9720` | Попередній серверний процес завис | `lsof -ti:9720 \| xargs kill -9`, або запусти з `PORT=9721 npm run dev`. |
| `npm` / `node` не знайдено при автозапуску з Finder | PATH не підхопився | Сервер стартує через `/bin/zsh -l`, тож потрібно щоб `node`/`npm` були у PATH твого `~/.zshrc` / `~/.zprofile`. |
| iOS-білд: `No profiles for 'com.example.pixelCode' were found` | Bundle ID плейсхолдер і/або Team ID чужий | Відкрий `ios/Runner.xcworkspace` → `Signing & Capabilities` → заміни `Team` на свій і `Bundle Identifier` на унікальний. |
| iOS-деплой: `Tailscale Funnel не активний — OTA недоступний з іншої мережі` | Tailscale не запущений або Funnel не ввімкнений | `brew install tailscale && sudo tailscale up`; рестартани сервер — він сам увімкне `tailscale funnel`. |
| iOS-деплой: сайлент встановлення не працює, одразу OTA | Пристрій не спарений з цим Mac через Xcode | Одноразово під'єднай iPhone по USB, у Xcode → Window → Devices and Simulators прийми pairing. Після цього можна лишатись без кабелю. |
| Android-деплой: `adb не знайдено` | Відсутній Android SDK чи `platform-tools` | Встанови Android Studio й поставь Platform Tools, або `brew install --cask android-platform-tools`. Виставити `ANDROID_HOME`. |

## Ліцензія

PixelCode розповсюджується під [PolyForm Noncommercial License 1.0.0](LICENSE) — source-available ліцензія, яка дозволяє будь-яке **некомерційне** використання. Коротко це означає:

- Можеш вільно використовувати, модифікувати, форкнути і ділитися — для особистих проєктів, навчання, досліджень, хобі, а також у межах благодійних/освітніх/державних організацій.
- **Комерційне використання заборонене третім сторонам** — продавати код, продукти на його основі, SaaS-сервіси чи брати плату за послуги на базі PixelCode без окремої комерційної ліцензії не можна.
- Автор зберігає право ліцензувати PixelCode комерційно за окремою домовленістю — якщо потрібно, напиши в issue або на контакт з профілю.
- У форках і похідних треба залишати текст ліцензії й посилання на оригінал.

Повний текст — у файлі [LICENSE](LICENSE).

---

<a id="pixelcode-en"></a>

# PixelCode (EN) 🇬🇧

**Visual orchestrator for Claude Agent SDK** — an Android / iOS / macOS / Windows / Linux pixel-art app that turns AI-agent coding into a game. You hire a team of agents, give them tasks, watch them work in a tiny office, and level them up through real commits and dungeon challenges.

## Highlights

- **Full real-time mirroring across all platforms.** Run the app on macOS, Windows, Linux, iOS, Android — everything stays in sync in real time. Start a task on your laptop, pick it up on your phone, watch the office from a tablet — team state, task progress, chat, and agent activity are identical everywhere the same second.
- **Install `.apk` / `.ipa` straight from a mobile device.** You can drive development directly from a phone or tablet — Android or iOS builds install on the very same device, no cable, no laptop nearby. Works even on mobile data — nothing needed beyond the device itself.

## What it is

PixelCode wraps the Claude Agent SDK in a Flutter UI. Instead of a terminal, you get:
- a hub screen with an animated office,
- a team of role-based agents (tech-lead, coder, reviewer, tester, security, UI/UX, manager),
- a task board, chat, and a currency/shop loop.

The Node.js server ([server/](server/)) bridges the Flutter client to the Claude Agent SDK over WebSocket.

## Tech stack

**Client (Flutter desktop/mobile app)**
- **Flutter** 3.11+ / **Dart** 3.11+ ([pubspec.yaml](pubspec.yaml))
- **flutter_riverpod** — state management
- **shared_preferences** — local persistence (session profiles, settings)
- **path_provider**, **file_selector**, **image_picker** — filesystem & asset picking
- **bonsoir** — Bonjour/mDNS for LAN server discovery
- **super_drag_and_drop** — drag-and-drop on the task board
- **url_launcher** — opening external links
- Custom Canvas rendering for the pixel-art office (no game engine)
- Targets: macOS, Windows, Linux, iOS, Android

**Server (local orchestrator)**
- **Node.js** 20+ with **TypeScript** 5.7 ([server/package.json](server/package.json))
- **@anthropic-ai/claude-agent-sdk** — the thing being orchestrated
- **ws** — WebSocket transport to the Flutter client
- **bonjour-service** — publishes the server on mDNS
- **tsx** — dev runner / watch mode

**Other**
- **Tailscale Funnel** — public HTTPS tunnel to the local server; used for OTA install of `.ipa` / `.apk` onto mobile devices from any network
- **Xcode `devicectl`** — silent install to iPhone/iPad when the device is already paired with the Mac via Xcode
- **adb** (Android Platform Tools) — silent `.apk` install when a device is connected via USB or Wi-Fi ADB
- **LeanKG** — used internally during development for code search ([leankg.yaml](leankg.yaml))

## Core features

- **Multi-agent team orchestration** — hire agents by role; each has a skill profile (precision, insight, reliability, creativity + speed) driving which Claude model they route to (Haiku / Sonnet / Opus). See [lib/models/agent_level.dart](lib/models/agent_level.dart).
- **Task board & delegation** — Kanban-style board for assigning work to agents; real-time status, chat, and activity feed. See [lib/widgets/board/task_board_panel.dart](lib/widgets/board/task_board_panel.dart).
- **Dungeon training** — run real coding challenges (speed, refactoring, design patterns, security) against an agent; a Haiku judge scores the output and grants XP. See [server/src/dungeon.ts](server/src/dungeon.ts).
- **XP & level progression** — agents gain XP from tasks and dungeons (difficulty² × quality × diminishing returns); cap lvl 20; model tier auto-adjusts with capability score.
- **Grim currency (₲) & economy** — earn from completed work, spend on hiring, hardware upgrades (laptop → workstation), and office expansions. See [lib/models/game_economy.dart](lib/models/game_economy.dart).
- **Office tiers** — Garage → Small Office → Modern Office → Tech Hub → Campus; each tier raises agent capacity and unlocks mechanics.
- **Claude Agent SDK server** — local Node.js WebSocket server manages sessions, team dispatch, and SDK calls. See [server/src/server.ts](server/src/server.ts).
- **Multi-project / multi-session** — switch between Git repos; named session profiles persist per project. See [lib/models/session_profile.dart](lib/models/session_profile.dart).
- **LAN discovery & device deployment** — Bonjour/mDNS auto-discovers the server on the LAN; built-in iOS deploy via `xcrun devicectl` (silent install when the device is paired with the Mac) or OTA over HTTPS through Tailscale Funnel (installs from any network worldwide). See [lib/services/ios_deploy_service.dart](lib/services/ios_deploy_service.dart).
- **Energy meter** — live cost/usage indicator tied to subagent activity. See [lib/widgets/energy/energy_meter.dart](lib/widgets/energy/energy_meter.dart).

## Cosmetic & secondary features

- **Pixel-art characters** — 6-tier sprite system, 7 frames × 3 directions per role, role-specific palettes (hair / skin / eyes / clothes). See [assets/characters/](assets/characters/) and [lib/widgets/canvas/pixel_sprites.dart](lib/widgets/canvas/pixel_sprites.dart).
- **Animated office** — custom 320×224 canvas renderer with Z-sorted depth, walk / type / read / idle animations, wandering AI (random pauses, seat rest). See [lib/widgets/canvas/pixel_office_painter.dart](lib/widgets/canvas/pixel_office_painter.dart).
- **Furniture sprites** — desks, animated monitors (3-frame loop), chairs, plants. See [assets/furniture/](assets/furniture/).
- **Speech bubbles & status** — agents display "thinking / typing / reading / testing / discussing" with animated dots.
- **Shop panel** — buy character skins, furniture, and room upgrades. See [lib/widgets/shop/shop_panel.dart](lib/widgets/shop/shop_panel.dart).
- **Dark synthwave theme** — cyan accent (`#00C0D1`), retro aesthetic across all dialogs.
- **Easter eggs** — Arkanoid mini-game and an XQuest2-style dungeon crawler hidden in the app. See [lib/widgets/easter_eggs/](lib/widgets/easter_eggs/).
- **Logo path DSL** — custom scripting language for the startup/shutdown logo animation. See [lib/services/logo_path_program.dart](lib/services/logo_path_program.dart).
- **Diagnostics panel** — server health, dependency checks, log viewer.

## Planned / in progress

- **Room adjacency bonuses** — Workstation ↔ Server Room (+5%), Break Room ↔ Lounge (morale stacking), Meeting Room ↔ Workstation (−10% latency). Framework exists, wiring partial. See [docs/office_design.md](docs/office_design.md).
- **Break Room morale system** — +20% productivity when agents rest; not yet active.
- **Server Room cable proximity** — −5% speed penalty if a workstation is >8 tiles from the Server Room.
- **Meeting Room manager boost** — currently just +1 capacity; planned to speed up Manager task dispatch.
- **Agent trait memory** — persistent lessons from past runs to tune prompts; backend exists ([server/src/trait_memory.ts](server/src/trait_memory.ts)), UI integration pending.
- **Android deployment** — iOS over Wi-Fi is done; Android skeleton in place.
- **Remote orchestration** — WebSocket layer is ready for running the server on a different machine than the client.

## Getting started

PixelCode is two processes — a Flutter client and a Node.js server ([server/](server/)) that wraps the Claude Agent SDK. On desktop (macOS / Windows / Linux) the client **auto-starts the server** as a child process via `npm run dev` ([lib/services/server_process_service.dart](lib/services/server_process_service.dart)) — that's the only supported path today. On iOS/Android the app cannot spawn a Node process (OS sandbox), so mobile clients connect to a server already running on a desktop. On the same LAN the client auto-discovers the server over Bonjour/mDNS; if Tailscale is up on the Mac, the server also publishes itself on a public HTTPS endpoint via Funnel, so a mobile client can connect from any Wi-Fi or mobile network.

### 1. Prerequisites

**Common (any platform):**
- **Flutter SDK** with Dart ≥ 3.11.4 ([pubspec.yaml](pubspec.yaml)) — [install guide](https://docs.flutter.dev/get-started/install)
- **Node.js 20+** and `npm` ([nvm](https://github.com/nvm-sh/nvm) recommended)
- **Git**
- Claude access — pick one:
  - **A (recommended):** install [Claude Code CLI](https://claude.ai/download) (or the `anthropic.claude-code` VS Code extension) and sign in; the server will pick up OAuth from your Claude Pro / Max subscription automatically.
  - **B:** `export ANTHROPIC_API_KEY=sk-ant-…` (key from [console.anthropic.com](https://console.anthropic.com/)).

**Building on macOS or targeting iOS:**
- Xcode 15+ and Command Line Tools (`xcode-select --install`)
- CocoaPods: `brew install cocoapods` (or `sudo gem install cocoapods`)

**Deploying to a physical iPhone / iPad:**
- **Apple ID / Apple Developer account.** A free Apple ID works (personal team → sideload, re-sign every 7 days). Paid account — up to 1 year without re-signing.
- **Configure signing in Xcode — MANDATORY when you fork.** Open `ios/Runner.xcworkspace`, select the `Runner` target → `Signing & Capabilities`:
  - `Team` — your own. The repo pins a placeholder `DEVELOPMENT_TEAM = YOUR_TEAM_ID` (real format is 10 alphanumeric chars, e.g. `ABCD1234EF`); replace it via Xcode, which rewrites [ios/Runner.xcodeproj/project.pbxproj](ios/Runner.xcodeproj/project.pbxproj).
  - `Bundle Identifier` — unique (the current `com.example.pixelCode` is a placeholder; Apple won't sign someone else's bundle ID, so use e.g. `com.<your-handle>.pixelcode`).
  - `Automatically manage signing` — on; Xcode provisions a profile for you.
- **Tailscale — if you want to install from any network (no USB needed).** `brew install tailscale && sudo tailscale up` on the Mac. The server enables `tailscale funnel` on startup ([server/src/server.ts:1872](server/src/server.ts#L1872)) so the device can install the `.ipa` over public HTTPS from any Wi-Fi or mobile network. Without Tailscale, only the silent-install path via `xcrun devicectl` remains (requires a one-time pairing of the device with this Mac through Xcode).
- Details & troubleshooting: [docs/iOS_DEPLOYMENT.md](docs/iOS_DEPLOYMENT.md).

**Android:**
- Android Studio + Android SDK (API 34+); `ANDROID_HOME` or `ANDROID_SDK_ROOT` in your environment (or the default `~/Library/Android/sdk` / `~/Android/Sdk`)
- JDK 17+
- Tailscale (optional) — if you want to hand a download link to a device on a different network; without it, the fallback install URL points at your LAN IP only
- The APK is debug-signed by default (Flutter's default) — enough for sideloading via "Install from unknown sources"

### 2. First run

```bash
git clone <repo-url> pixelcode
cd pixelcode

# Flutter deps
flutter pub get

# Server deps (one-time)
(cd server && npm install)

# Only when building for macOS or iOS
(cd macos && pod install)   # or (cd ios && pod install)

# Run the desktop client — the server auto-starts
flutter run -d macos        # or windows / linux
```

The server comes up on `localhost:9720`, advertises itself over mDNS as `_pixelcode._tcp`, and is killed when the client exits.

### 3. Running the server standalone (for mobile clients or debugging)

```bash
cd server
npm run dev                 # tsx watch, reloads on file changes
# or explicit env:
PORT=9720 PROJECT_CWD=/path/to/your/repo npm run dev
```

Then launch a mobile client — it will auto-discover the server over Bonjour on the LAN, or connect via the Tailscale Funnel URL if you're on a different network:

```bash
flutter run -d <device-id>                # iPhone over USB, or Android device/emulator
```

For **one-click install of a prebuilt `.ipa` / `.apk` onto a device**, open the **Deploy to device** popover in the hub (phone icon in the top bar). Pick the iOS or Android tab and hit **Install** — the server builds, tries a silent install via `xcrun devicectl` / `adb`, and falls back to an OTA URL served over the Tailscale Funnel if the device isn't directly reachable. Details: [docs/iOS_DEPLOYMENT.md](docs/iOS_DEPLOYMENT.md).

### 4. Sanity check after first launch

- Hub screen renders with the animated office and at least one agent.
- Diagnostics panel (⚙ → **Diagnostics**) — all checks green: `node`, `claude-auth`, port `9720`, LAN.
- Smoke test: create a task on the board, assign it to an agent — it should reach `done` / `error` without hanging.

### 5. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `server/ directory not found at …` in logs | Flutter launched from the wrong `cwd` | Run `flutter run` from the repo root, not from `macos/` or `ios/`. |
| `Unauthenticated` / 401 in server logs | No OAuth session and no `ANTHROPIC_API_KEY` | Run `claude` in a terminal and complete OAuth, or `export ANTHROPIC_API_KEY=…` and relaunch the client. |
| Mobile client can't see the server | Devices on different Wi-Fi, or macOS firewall blocking `node` | System Settings → Network → Firewall → allow incoming for `node`; verify both devices share a network. |
| `pod install` fails | Outdated CocoaPods | `brew upgrade cocoapods` or `sudo gem install cocoapods`. |
| `EADDRINUSE :9720` | A previous server process is still alive | `lsof -ti:9720 \| xargs kill -9`, or start with `PORT=9721 npm run dev`. |
| `npm` / `node` not found when launched from Finder | PATH not inherited | Server launches via `/bin/zsh -l`, so `node`/`npm` must be on the PATH set in your `~/.zshrc` / `~/.zprofile`. |
| iOS build: `No profiles for 'com.example.pixelCode' were found` | Placeholder Bundle ID and/or someone else's Team ID | Open `ios/Runner.xcworkspace` → `Signing & Capabilities` → set `Team` to your own and `Bundle Identifier` to something unique. |
| iOS deploy: `Tailscale Funnel inactive — OTA unavailable from another network` | Tailscale isn't running or Funnel isn't on | `brew install tailscale && sudo tailscale up`; restart the server — it enables `tailscale funnel` itself. |
| iOS deploy: silent install fails, falls back to OTA | Device not paired with this Mac in Xcode | Connect the iPhone once via USB, accept the pairing prompt in Xcode → Window → Devices and Simulators. After that you can stay cable-free. |
| Android deploy: `adb not found` | Missing Android SDK or platform-tools | Install Android Studio and Platform Tools, or `brew install --cask android-platform-tools`. Set `ANDROID_HOME`. |

## License

PixelCode is distributed under the [PolyForm Noncommercial License 1.0.0](LICENSE) — a source-available license that permits any **noncommercial** use. In short:

- You're free to use, modify, fork, and share the code — for personal projects, learning, research, hobby use, as well as within charitable, educational, and government organizations.
- **Commercial use by third parties is not permitted** — you can't sell the code, products built on it, SaaS offerings, or paid services around PixelCode without a separate commercial license.
- The author retains the right to offer PixelCode under a commercial license on request — open an issue or reach out via the contact info on the profile.
- Forks and derivatives must keep the license text and a link to the original.

Full text: [LICENSE](LICENSE).
