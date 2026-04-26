# PixelCode

**Візуальний оркестратор для Claude Agent SDK** — Android/iOS/MacOS аппка в стилі піксель-арт, яка перетворює роботу з AI-агентами на гру. Наймаєш команду агентів, даєш їм задачі, дивишся як вони працюють у маленькому офісі, і прокачуєш їх через реальні комміти та dungeon-челенджі.

> 🇬🇧 [English version below](#pixelcode-en)

<div style="display: flex; align-items: center; justify-content: center; gap: 10px;">
  <kbd>
    <img src="https://github.com/user-attachments/assets/91ab0aa9-68f7-41d0-ba40-86ad9b2683c7" height="500" />
  </kbd>
  <kbd>
    <img src="https://github.com/user-attachments/assets/b8ec3b59-af9c-41d6-b49c-3f06a419e59e" height="400" />
  </kbd>
</div>

---

## Що вирізняє

- **Повне real-time віддзеркалення на всіх платформах.** Запустив аппку на macOS, Windows, Linux, iOS, Android — усе синхронізовано в реальному часі. Почав задачу на ноуті, продовжив з телефона, стежиш за офісом з планшета — стан команди, прогрес задач, чат, активність агентів однакові скрізь у ту саму секунду.
- **Встановлення `.apk` / `.ipa` прямо з мобільного.** Можеш вести розробку безпосередньо з телефона чи планшета — збірка під Android або iOS ставиться з того ж самого пристрою, без кабелю, без ноутбука поруч. Працює навіть на мобільному інтернеті — нічого не потрібно, крім самого пристрою.

## Що це

PixelCode обгортає Claude Agent SDK у Flutter UI. Замість терміналу маєш:
- hub-екран з анімованим офісом,
- команду агентів за ролями (tech-lead, coder, reviewer, tester, security, UI/UX, manager),
- борд задач, чат, економіку з валютою та магазином.

Node.js-сервер ([server/](server/)) зв'язує Flutter-клієнт із Claude Agent SDK через WebSocket. Сервером керує **launcher**-демон, який сам тримає процес, переживає краші, веде структурні логи й приймає start/stop/restart по HTTP — або з CLI `pixelcode-server`, або з **PixelDock** ([server_admin/](server_admin/)) — окремої Flutter-десктоп-аппки для адміністрування сервера. PixelCode-клієнт сам сервер не запускає — він до нього лише під'єднується по WebSocket (як і мобільні білди завжди робили).

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
- **launcher daemon** ([server/src/launcher.ts](server/src/launcher.ts)) — always-on супервізор, який тримає `server.ts`, респавнить на exit-code 75, веде ring-buffer boot-логів і виставляє `/launcher/*` HTTP-API на `:9719` (loopback)
- **`pixelcode-server` CLI** ([server/bin/pixelcode-server.mjs](server/bin/pixelcode-server.mjs)) — `start` піднімає launcher, `status` / `logs` / `config` ходять у `/admin/api/*` сервера
- **Layered config** ([server/src/config.ts](server/src/config.ts)) — defaults → `~/.pixelcode/server.json` → ENV → CLI; live-edit через `/admin/api/config`

**PixelDock (адмін-панель сервера, окрема Flutter аппка)**
- **Flutter** desktop app у `server_admin/` ([server_admin/lib/main.dart](server_admin/lib/main.dart))
- Polling HTTP-клієнт до launcher (`:9719`) і admin-surface (`:9720/admin/api`)
- start / stop / restart, live-edit конфігу (port, projectCwd, OTA hostname), стрім логів — серверних і boot
- Pixel-art тема узгоджена з основною аппкою (`PIXEL DOCK`, glow-індикатор стану, золото-cyan акценти)
- Платформи: macOS / iOS (запуск з `.vscode/launch.json` → "PixelDock (macOS / iOS)")

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
- **Сервер Claude Agent SDK** — локальний Node.js WebSocket-сервер керує сесіями, диспатчить команду, робить виклики SDK. [server/src/server.ts](server/src/server.ts). Запускається не клієнтом, а окремо — через `pixelcode-server start` або з PixelDock; перезапуски/краші тримає launcher-демон ([server/src/launcher.ts](server/src/launcher.ts)).
- **PixelDock — адмін-панель сервера** — окрема Flutter desktop аппка ([server_admin/](server_admin/)) для start / stop / restart, live-конфігу й перегляду логів через `/launcher/*` та `/admin/api/*`. Запускається разом з PixelCode або окремо.
- **Мультипроєктність і сесії** — перемикання між Git-репами; іменовані сесії зберігаються per-project; SDK-сесія тримається спільно між реконнектами клієнтів і рестартами сервера. [lib/models/session_profile.dart](lib/models/session_profile.dart).
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
- **Agent personalization system** — персистентні "уроки" з минулих запусків для тюнінгу промптів. Бекенд уже зібрано в пайплайн: пер-агент profile cache + execution hooks ([server/src/profile_cache.ts](server/src/profile_cache.ts), [server/src/hooks/](server/src/hooks/)), memory lifecycle зі score / decay / capacity-tier eviction ([server/src/memory_lifecycle.ts](server/src/memory_lifecycle.ts)), lesson extractor ([server/src/lesson_extractor.ts](server/src/lesson_extractor.ts)), prompt cache manager для system prompt + learned-context ([server/src/prompt_cache_manager.ts](server/src/prompt_cache_manager.ts)), agent context preparer ([server/src/agent_context.ts](server/src/agent_context.ts)) і cross-project profile migration ([server/src/project_context_manager.ts](server/src/project_context_manager.ts)). Дизайн і план — [docs/AGENT_PERSONALIZATION_SYSTEM.md](docs/AGENT_PERSONALIZATION_SYSTEM.md), [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md). UI-інтеграція ще попереду.
- **Android-деплой** — iOS через Wi-Fi вже готовий; для Android є скелет.
- **Віддалена оркестрація** — WebSocket-шар готовий запускати сервер на іншій машині, не там де клієнт.

## Як запустити

PixelCode складається з трьох процесів:

1. **PixelCode-клієнт** — Flutter-аппка (macOS / Windows / Linux / iOS / Android), у якій ти граєш.
2. **Node.js-сервер** ([server/](server/)) — обгортає Claude Agent SDK і зв'язує з клієнтом по WebSocket. Сам себе не тримає — над ним сидить **launcher**-демон, який слідкує за процесом і виставляє `/launcher/*` HTTP-API на `:9719`.
3. **PixelDock** ([server_admin/](server_admin/)) — окрема Flutter desktop-аппка для start/stop/restart, live-конфігу й перегляду логів. Опційна, якщо тобі вистачає CLI.

PixelCode-клієнт **не запускає сервер сам** — у попередніх версіях так було, тепер ні (commit [952fd24](../../commit/952fd24)). Сервер потрібно один раз підняти через `pixelcode-server start` (або з PixelDock), після чого він живе у фоні навіть коли аппка закрита. У локальній мережі клієнт знаходить сервер автоматично через Bonjour/mDNS; якщо на Mac піднято Tailscale, сервер додатково публікує себе на публічному HTTPS-endpoint через Funnel — і мобільний клієнт може під'єднатися з будь-якої Wi-Fi чи мобільної мережі.

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

# Flutter-залежності для основної аппки
flutter pub get

# Серверні залежності + глобальний CLI `pixelcode-server`
(cd server && npm install && npm link)

# Тільки якщо збираєш під macOS або iOS
(cd macos && pod install)   # або (cd ios && pod install)

# 1) Підняти сервер (launcher :9719 + server :9720, тримається у фоні)
pixelcode-server start

# 2) Запустити PixelCode-клієнт
flutter run -d macos        # або windows / linux / <device-id>
```

Клієнт автоматично знайде сервер у LAN через Bonjour/mDNS (`_pixelcode._tcp`); індикатор підключення в хед-барі покаже стан з'єднання. Сервер живе у фоні незалежно від клієнта; зупинити: `pixelcode-server stop`.

### 3. Керування сервером

#### 3a. Глобальний CLI `pixelcode-server`

`npm link` у `server/` (див. вище) створює symlink на [server/bin/pixelcode-server.mjs](server/bin/pixelcode-server.mjs). Команди:

```bash
pixelcode-server start      # піднімає launcher (:9719) + server (:9720)
pixelcode-server stop       # зупиняє server, launcher лишається жити
pixelcode-server restart    # respawn server без втрати launcher-стану
pixelcode-server status     # phase, PID, порти, uptime, mDNS, Tailscale URL
pixelcode-server logs       # tail структурного лог-рингу
pixelcode-server config     # show/edit ~/.pixelcode/server.json (port, projectCwd, otaHostname)
pixelcode-server --help
```

Symlink вказує на робочу копію в репо — якщо переміщуєш/перейменовуєш папку, виконай `npm link` ще раз. Зняти: `npm unlink -g pixel-code-server`. Перенесення на іншу машину: `git clone … && cd server && npm install && npm link`.

Альтернативно для дебагу можна запустити сервер без launcher (без `:9719`, без CLI-керування):
```bash
cd server
npm run dev                 # tsx watch, перезапуск при зміні файлів
PORT=9720 PROJECT_CWD=/path/to/your/repo npm run dev
```

#### 3b. PixelDock — Flutter-десктоп для адміністрування

[PixelDock](server_admin/) — окрема Flutter-аппка зі списком процесів, інлайн-конфігом і перегляданням логів. Запуск:

```bash
cd server_admin
flutter pub get
flutter run -d macos        # або з VS Code: ▶ "PixelDock (macOS)" / "PixelDock (iOS)"
```

PixelDock пулить launcher на `http://127.0.0.1:9719` і admin-surface на `http://127.0.0.1:9720/admin/api`. Якщо launcher не запущений — у хедері побачиш `LAUNCHER UNREACHABLE` і підказку запустити `pixelcode-server start`.

#### 3c. Мобільний клієнт

Після `pixelcode-server start` запускаєш мобільний білд PixelCode — він сам знайде сервер у LAN через Bonjour, або через Tailscale Funnel, якщо ти не в тій самій мережі:

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
| PixelDock: `LAUNCHER UNREACHABLE` / `zsh: command not found: pixelcode-server` | Глобальний CLI не встановлений | `cd server && npm link` (див. §3a). Після цього `pixelcode-server start`. |
| iOS-білд: `No profiles for 'com.example.pixelCode' were found` | Bundle ID плейсхолдер і/або Team ID чужий | Відкрий `ios/Runner.xcworkspace` → `Signing & Capabilities` → заміни `Team` на свій і `Bundle Identifier` на унікальний. |
| iOS-деплой: `Tailscale Funnel не активний — OTA недоступний з іншої мережі` | Tailscale не запущений або Funnel не ввімкнений | `brew install tailscale && sudo tailscale up`; рестартани сервер — він сам увімкне `tailscale funnel`. |
| iOS-деплой: сайлент встановлення не працює, одразу OTA | Пристрій не спарений з цим Mac через Xcode | Одноразово під'єднай iPhone по USB, у Xcode → Window → Devices and Simulators прийми pairing. Після цього можна лишатись без кабелю. |
| Android-деплой: `adb не знайдено` | Відсутній Android SDK чи `platform-tools` | Встанови Android Studio й поставь Platform Tools, або `brew install --cask android-platform-tools`. Виставити `ANDROID_HOME`. |

## Версії

| Гілка | Версія | Опис |
|-------|--------|------|
| [`alpha-test`](../../tree/alpha-test) | `0.3.0+1` | Поточний реліз-кандидат для тестерів. Артефакти macOS — у [GitHub Releases](../../releases). |
| [`develop`](../../tree/develop) | `0.3.1-dev+1` | Активна розробка, попереду `alpha-test`. |

### v0.3.0-alpha.1 — 2026-04-26

**Architecture**
- Сервер відокремлено від клієнта: PixelCode-аппка більше не спавнить Node.js — стала чистим WebSocket-клієнтом ([952fd24](../../commit/952fd24)). `lib/services/server_process_service.dart` видалено; за життям сервера тепер відповідає launcher-демон.
- **Launcher daemon** ([server/src/launcher.ts](server/src/launcher.ts)) — always-on супервізор сервера з respawn-on-75, ring-buffer boot-логів і `/launcher/*` HTTP-API на `:9719`.
- **`pixelcode-server` CLI** — глобальний бінарник (`npm link` в `server/`) з командами `start` / `stop` / `restart` / `status` / `logs` / `config`.
- **Layered config** — defaults → `~/.pixelcode/server.json` → ENV → CLI; live-edit через `/admin/api/config`.
- SDK-сесія тепер тримається спільно між реконнектами клієнтів, рестартами сервера і зміною пристроїв.

**Features — PixelDock (нова аппка)**
- Окрема Flutter desktop / iOS аппка `server_admin/` для адміністрування сервера: start / stop / restart, інлайн-конфіг (port, projectCwd, OTA hostname), стрім серверних і boot-логів.
- Pixel-art ребрендинг: glow-індикатор стану, золото-cyan акценти, узгоджена тема з основною аппкою.
- VS Code launch-конфіги "PixelDock (macOS)" / "PixelDock (iOS)" поряд з PixelCode-конфігами.

**Features — Agent Personalization System (бекенд-скелет)**
- Memory lifecycle: score / decay / capacity-tier eviction ([memory_lifecycle.ts](server/src/memory_lifecycle.ts)).
- Lesson extractor — pattern recognition + apply with eviction ([lesson_extractor.ts](server/src/lesson_extractor.ts)).
- Prompt cache manager: system prompt + learned-context fragment ([prompt_cache_manager.ts](server/src/prompt_cache_manager.ts)).
- Agent context preparer: fragment + cacheKey + recent messages ([agent_context.ts](server/src/agent_context.ts)).
- Project context manager — cross-project profile migration ([project_context_manager.ts](server/src/project_context_manager.ts)).
- Profile cache + execution hooks ([profile_cache.ts](server/src/profile_cache.ts), [hooks/](server/src/hooks/)).
- Дизайн-документ і план імплементації — [docs/AGENT_PERSONALIZATION_SYSTEM.md](docs/AGENT_PERSONALIZATION_SYSTEM.md), [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md).

**Features — Client UX**
- Connection terminal indicator у хедері хаба — наочний статус WS-з'єднання.

**Docs / Infra**
- README перероблено під split server/client + PixelDock + новий getting-started flow.
- `.vscode/launch.json` тепер у репо: PixelCode (macOS / iOS profile) + PixelDock (macOS / iOS).

### v0.2.1-alpha.1 — 2026-04-25

**Features**
- Agent-level XP + `skillCap` progression — замінює per-skill XP, кап на 20-му рівні.
- Capability-oriented 5-stat skill model: `precision` / `insight` / `reliability` / `creativity` / `speed` — визначає маршрутизацію на Haiku / Sonnet / Opus.
- Energy meter — daily token meter як явний ігровий ресурс, прив'язаний до витрат субагентів.
- Task outcome: roll bug / crit / incomplete на testing-done з XP та crit-бонусом.
- Board assign gating — перевірка ролі + рівня агента при призначенні задачі (з SnackBar-фідбеком).
- Role-biased initial skills при наймі — замість рівномірних 1/1/1/1/1.
- Diegetic build / upgrade entry — вхід у магазин апгрейдів через ігровий світ.

**Fixes**
- Server: завжди надсилає `chat_history` snapshot при підключенні клієнта.
- Energy коректно прив'язано до subagent cost, виправлено copy у тостах.
- Chat merge fix, переробка контуру notch.
- `difficulty` / `roles` тепер пробрасуються в task creation на сервер.

**Docs / Infra**
- OSS readiness: `LICENSE` (PolyForm Noncommercial 1.0.0), `CONTRIBUTING.md`, розширений README.
- Переписана документація з iOS deployment.
- Tailscale Funnel health-probe на сервері.
- Pod checksum refresh для macOS.

## Натхнення

Ідея PixelCode виросла з VS Code-розширення [Pixel Agents](https://marketplace.visualstudio.com/items?itemName=pablodelucca.pixel-agents) ([github](https://github.com/pablodelucca/pixel-agents)) автора **pablodelucca** — воно першим показало AI-агентів як піксель-арт персонажів у маленькому офісі прямо в редакторі. PixelCode переосмислює цю ідею як окрему кросплатформну аппку поверх Claude Agent SDK з власною грою (XP, прокачка, економіка, dungeon-челенджі, мультидевайс real-time).

Дякуємо також **JIK-A-4** за пак [MetroCity Free Topdown Character Pack](https://jik-a-4.itch.io/metrocity-free-topdown-character-pack) (CC0), який Pixel Agents використовує як основу персонажів, і який нас надихнув на власну 6-тирову систему спрайтів.

Повні ліцензійні нотиси третіх сторін — у [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

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

The Node.js server ([server/](server/)) bridges the Flutter client to the Claude Agent SDK over WebSocket. The server is supervised by a **launcher** daemon that owns the process, survives crashes, keeps a structured log, and accepts start/stop/restart over HTTP — driven either from the `pixelcode-server` CLI or from **PixelDock** ([server_admin/](server_admin/)), a separate Flutter desktop app dedicated to managing the server. The PixelCode client itself never spawns the server — it just connects over WebSocket (the way mobile builds always have).

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
- **Launcher daemon** ([server/src/launcher.ts](server/src/launcher.ts)) — always-on supervisor that owns `server.ts`, respawns on exit-code 75, keeps a ring buffer of boot logs, and exposes `/launcher/*` HTTP API on `:9719` (loopback)
- **`pixelcode-server` CLI** ([server/bin/pixelcode-server.mjs](server/bin/pixelcode-server.mjs)) — `start` boots the launcher; `status` / `logs` / `config` talk to the server's `/admin/api/*`
- **Layered config** ([server/src/config.ts](server/src/config.ts)) — defaults → `~/.pixelcode/server.json` → ENV → CLI; live-edited via `/admin/api/config`

**PixelDock (server admin panel, separate Flutter app)**
- **Flutter** desktop app under `server_admin/` ([server_admin/lib/main.dart](server_admin/lib/main.dart))
- Polling HTTP client for the launcher (`:9719`) and the server's admin surface (`:9720/admin/api`)
- Start / stop / restart, live-edit config (port, projectCwd, OTA hostname), tail server logs and boot logs
- Pixel-art theme matched to the main app (`PIXEL DOCK`, glow status dot, gold/cyan accents)
- Targets: macOS / iOS (launch from `.vscode/launch.json` → "PixelDock (macOS / iOS)")

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
- **Claude Agent SDK server** — local Node.js WebSocket server manages sessions, team dispatch, and SDK calls. See [server/src/server.ts](server/src/server.ts). The server runs as its own process, started via `pixelcode-server start` or PixelDock — the launcher daemon ([server/src/launcher.ts](server/src/launcher.ts)) supervises it across crashes and restarts.
- **PixelDock — server admin panel** — separate Flutter desktop app ([server_admin/](server_admin/)) for start / stop / restart, live config edits, and log tailing via `/launcher/*` and `/admin/api/*`. Runs alongside PixelCode or on its own.
- **Multi-project / multi-session** — switch between Git repos; named session profiles persist per project; the SDK session is now shared across client reconnects, server restarts, and devices. See [lib/models/session_profile.dart](lib/models/session_profile.dart).
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
- **Agent personalization system** — persistent lessons from past runs to tune prompts. Backend pipeline is wired: per-agent profile cache + execution hooks ([server/src/profile_cache.ts](server/src/profile_cache.ts), [server/src/hooks/](server/src/hooks/)), memory lifecycle with score / decay / capacity-tier eviction ([server/src/memory_lifecycle.ts](server/src/memory_lifecycle.ts)), lesson extractor ([server/src/lesson_extractor.ts](server/src/lesson_extractor.ts)), prompt cache manager for system prompt + learned-context fragment ([server/src/prompt_cache_manager.ts](server/src/prompt_cache_manager.ts)), agent context preparer ([server/src/agent_context.ts](server/src/agent_context.ts)), and cross-project profile migration ([server/src/project_context_manager.ts](server/src/project_context_manager.ts)). Design + plan: [docs/AGENT_PERSONALIZATION_SYSTEM.md](docs/AGENT_PERSONALIZATION_SYSTEM.md), [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md). UI integration still pending.
- **Android deployment** — iOS over Wi-Fi is done; Android skeleton in place.
- **Remote orchestration** — WebSocket layer is ready for running the server on a different machine than the client.

## Getting started

PixelCode is three processes:

1. **PixelCode client** — the Flutter app you actually play (macOS / Windows / Linux / iOS / Android).
2. **Node.js server** ([server/](server/)) — wraps the Claude Agent SDK and bridges to the client over WebSocket. It doesn't manage itself; a **launcher** daemon supervises it and exposes `/launcher/*` HTTP API on `:9719`.
3. **PixelDock** ([server_admin/](server_admin/)) — separate Flutter desktop app for start/stop/restart, live config, and logs. Optional, if the CLI is enough for you.

The PixelCode client **does not start the server itself** — earlier versions did, that's gone (commit [952fd24](../../commit/952fd24)). You bring up the server once via `pixelcode-server start` (or via PixelDock) and it stays alive in the background even when the app is closed. On the same LAN the client auto-discovers the server over Bonjour/mDNS; if Tailscale is up on the Mac, the server also publishes itself on a public HTTPS endpoint via Funnel, so a mobile client can connect from any Wi-Fi or mobile network.

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

# Flutter deps for the main app
flutter pub get

# Server deps + global `pixelcode-server` CLI
(cd server && npm install && npm link)

# Only when building for macOS or iOS
(cd macos && pod install)   # or (cd ios && pod install)

# 1) Bring the server up (launcher :9719 + server :9720, lives in the background)
pixelcode-server start

# 2) Run the PixelCode client
flutter run -d macos        # or windows / linux / <device-id>
```

The client auto-discovers the server on the LAN over Bonjour/mDNS (`_pixelcode._tcp`); the connection indicator in the hub header reflects WS state. The server lives in the background independently of the client; stop it with `pixelcode-server stop`.

### 3. Managing the server

#### 3a. Global `pixelcode-server` CLI

`npm link` inside `server/` (above) creates a symlink to [server/bin/pixelcode-server.mjs](server/bin/pixelcode-server.mjs). Commands:

```bash
pixelcode-server start      # boots launcher (:9719) + server (:9720)
pixelcode-server stop       # stops the server; the launcher stays alive
pixelcode-server restart    # respawns the server without losing launcher state
pixelcode-server status     # phase, PID, ports, uptime, mDNS, Tailscale URL
pixelcode-server logs       # tail the structured log ring
pixelcode-server config     # show/edit ~/.pixelcode/server.json (port, projectCwd, otaHostname)
pixelcode-server --help
```

The symlink points at the working copy in the repo — if you move/rename the folder, run `npm link` again. Remove with `npm unlink -g pixel-code-server`. To port to another machine: `git clone … && cd server && npm install && npm link`.

Alternatively for debugging you can run the server without the launcher (no `:9719`, no CLI control):
```bash
cd server
npm run dev                 # tsx watch, reloads on file changes
PORT=9720 PROJECT_CWD=/path/to/your/repo npm run dev
```

#### 3b. PixelDock — Flutter desktop admin app

[PixelDock](server_admin/) is a standalone Flutter app with process status, inline config editing, and log views. To run it:

```bash
cd server_admin
flutter pub get
flutter run -d macos        # or via VS Code: ▶ "PixelDock (macOS)" / "PixelDock (iOS)"
```

PixelDock polls the launcher at `http://127.0.0.1:9719` and the admin surface at `http://127.0.0.1:9720/admin/api`. If the launcher isn't running you'll see `LAUNCHER UNREACHABLE` in the header and a hint to run `pixelcode-server start`.

#### 3c. Mobile client

Once `pixelcode-server start` is up, run a mobile build of PixelCode — it will auto-discover the server over Bonjour on the LAN, or connect via the Tailscale Funnel URL if you're on a different network:

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
| PixelDock: `LAUNCHER UNREACHABLE` / `zsh: command not found: pixelcode-server` | Global CLI not installed | `cd server && npm link` (see §3a). Then `pixelcode-server start`. |
| iOS build: `No profiles for 'com.example.pixelCode' were found` | Placeholder Bundle ID and/or someone else's Team ID | Open `ios/Runner.xcworkspace` → `Signing & Capabilities` → set `Team` to your own and `Bundle Identifier` to something unique. |
| iOS deploy: `Tailscale Funnel inactive — OTA unavailable from another network` | Tailscale isn't running or Funnel isn't on | `brew install tailscale && sudo tailscale up`; restart the server — it enables `tailscale funnel` itself. |
| iOS deploy: silent install fails, falls back to OTA | Device not paired with this Mac in Xcode | Connect the iPhone once via USB, accept the pairing prompt in Xcode → Window → Devices and Simulators. After that you can stay cable-free. |
| Android deploy: `adb not found` | Missing Android SDK or platform-tools | Install Android Studio and Platform Tools, or `brew install --cask android-platform-tools`. Set `ANDROID_HOME`. |

## Versions

| Branch | Version | Description |
|--------|---------|-------------|
| [`alpha-test`](../../tree/alpha-test) | `0.3.0+1` | Current release candidate for testers. macOS artifacts in [GitHub Releases](../../releases). |
| [`develop`](../../tree/develop) | `0.3.1-dev+1` | Active development, ahead of `alpha-test`. |

### v0.3.0-alpha.1 — 2026-04-26

**Architecture**
- Server split off from the client: the PixelCode app no longer spawns Node.js — it became a pure WebSocket client ([952fd24](../../commit/952fd24)). `lib/services/server_process_service.dart` is gone; the launcher daemon owns the server's lifecycle.
- **Launcher daemon** ([server/src/launcher.ts](server/src/launcher.ts)) — always-on supervisor with respawn-on-75, ring-buffer boot logs, and `/launcher/*` HTTP API on `:9719`.
- **`pixelcode-server` CLI** — global binary (via `npm link` in `server/`) with `start` / `stop` / `restart` / `status` / `logs` / `config`.
- **Layered config** — defaults → `~/.pixelcode/server.json` → ENV → CLI; live-edited via `/admin/api/config`.
- The SDK session is now shared across client reconnects, server restarts, and device switches.

**Features — PixelDock (new app)**
- Standalone Flutter desktop / iOS app under `server_admin/` for managing the server: start / stop / restart, inline config (port, projectCwd, OTA hostname), tail of server logs and boot logs.
- Pixel-art rebrand: glow status dot, gold/cyan accents, theme matched to the main app.
- VS Code launch configs "PixelDock (macOS)" / "PixelDock (iOS)" alongside PixelCode configs.

**Features — Agent Personalization System (backend skeleton)**
- Memory lifecycle: score / decay / capacity-tier eviction ([memory_lifecycle.ts](server/src/memory_lifecycle.ts)).
- Lesson extractor — pattern recognition + apply with eviction ([lesson_extractor.ts](server/src/lesson_extractor.ts)).
- Prompt cache manager: system prompt + learned-context fragment ([prompt_cache_manager.ts](server/src/prompt_cache_manager.ts)).
- Agent context preparer: fragment + cacheKey + recent messages ([agent_context.ts](server/src/agent_context.ts)).
- Project context manager — cross-project profile migration ([project_context_manager.ts](server/src/project_context_manager.ts)).
- Profile cache + execution hooks ([profile_cache.ts](server/src/profile_cache.ts), [hooks/](server/src/hooks/)).
- Design doc + implementation plan: [docs/AGENT_PERSONALIZATION_SYSTEM.md](docs/AGENT_PERSONALIZATION_SYSTEM.md), [docs/IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md).

**Features — Client UX**
- Connection terminal indicator in the hub header — visible WS connection state at a glance.

**Docs / Infra**
- README rewritten around the server/client split + PixelDock + new getting-started flow.
- `.vscode/launch.json` is now in the repo: PixelCode (macOS / iOS profile) + PixelDock (macOS / iOS).

### v0.2.1-alpha.1 — 2026-04-25

**Features**
- Agent-level XP + `skillCap` progression — replaces per-skill XP, capped at level 20.
- Capability-oriented 5-stat skill model: `precision` / `insight` / `reliability` / `creativity` / `speed` — drives routing to Haiku / Sonnet / Opus.
- Energy meter — daily token meter as an explicit game resource, wired to subagent cost.
- Task outcome: bug / crit / incomplete rolls at testing-done, with XP and crit bonus.
- Board assign gating — role + level checks at task assignment (with SnackBar feedback).
- Role-biased initial skills at hire — instead of uniform 1/1/1/1/1.
- Diegetic build / upgrade entry — upgrade shop accessed through the in-game world.

**Fixes**
- Server: always sends `chat_history` snapshot on client connect.
- Energy properly wired to subagent cost, toast copy fixed.
- Chat merge fix, notch outline rework.
- `difficulty` / `roles` now piped through to server task creation.

**Docs / Infra**
- OSS readiness: `LICENSE` (PolyForm Noncommercial 1.0.0), `CONTRIBUTING.md`, expanded README.
- iOS deployment doc rewrite.
- Tailscale Funnel health probe on the server.
- Pod checksum refresh for macOS.

## Inspiration

PixelCode grew out of the VS Code extension [Pixel Agents](https://marketplace.visualstudio.com/items?itemName=pablodelucca.pixel-agents) ([github](https://github.com/pablodelucca/pixel-agents)) by **pablodelucca** — it was the first to render AI agents as pixel-art characters working in a tiny office right inside the editor. PixelCode reimagines that idea as a standalone cross-platform app on top of the Claude Agent SDK, with its own game layer (XP, progression, economy, dungeon challenges, real-time multi-device mirroring).

Thanks also to **JIK-A-4** for the [MetroCity Free Topdown Character Pack](https://jik-a-4.itch.io/metrocity-free-topdown-character-pack) (CC0), which Pixel Agents uses as the base for its characters and which inspired our own 6-tier sprite system.

Full third-party license notices: [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

## License

PixelCode is distributed under the [PolyForm Noncommercial License 1.0.0](LICENSE) — a source-available license that permits any **noncommercial** use. In short:

- You're free to use, modify, fork, and share the code — for personal projects, learning, research, hobby use, as well as within charitable, educational, and government organizations.
- **Commercial use by third parties is not permitted** — you can't sell the code, products built on it, SaaS offerings, or paid services around PixelCode without a separate commercial license.
- The author retains the right to offer PixelCode under a commercial license on request — open an issue or reach out via the contact info on the profile.
- Forks and derivatives must keep the license text and a link to the original.

Full text: [LICENSE](LICENSE).
