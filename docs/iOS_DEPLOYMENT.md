# iOS-деплой

Як поставити PixelCode на фізичний iPhone чи iPad **без USB-кабеля і без ноутбука поруч** — з твого ж Mac, з будь-якої мережі в світі. Цей документ пояснює флоу з нуля для людини, яка вперше клонує репо.

> 🇬🇧 [English version below](#ios-deploy-en)

---

## Як це працює

Коли ти натискаєш **Install** у попапі **Deploy to device → iOS**, сервер робить наступне ([server/src/server.ts:2010](../server/src/server.ts#L2010)):

1. **Білд:** `flutter build ios --release` — створює `.app` бандл. Цей крок вимагає коректно налаштованого **code signing** у Xcode (Team ID + Bundle ID).
2. **Сайлент-інстал:** `xcrun devicectl list devices` шукає вже спарені iOS-пристрої. Якщо знаходить — ставить бандл напряму через `devicectl device install app`. Це працює, якщо твій iPhone колись під'єднували до цього Mac через Xcode і ти прийняв pairing. Без кабеля, тільки коли обидва пристрої бачать один одного (LAN або USB).
3. **OTA-фолбек:** якщо сайлент не вдався — сервер пакує `.app` в `.ipa`, генерує `manifest.plist`, і віддає `itms-services://…` URL. Цей URL вказує на HTTPS-хост, який Tailscale Funnel публікує в інтернеті. iPhone може бути на будь-якій Wi-Fi чи мобільній мережі — він скачає manifest та IPA, і iOS встановить аппку.

**Ніякого "в одній Wi-Fi мережі" тут немає** — Tailscale Funnel це публічний HTTPS-endpoint на MagicDNS-домені (`*.ts.net`), доступний звідусіль. Локальна мережа потрібна тільки для необов'язкового швидкого сайлент-шляху.

## Що потрібно поставити один раз

### 1. Xcode + CocoaPods (на Mac)

```bash
xcode-select --install
brew install cocoapods
(cd ios && pod install)
```

### 2. Apple ID або Apple Developer account

- **Безкоштовний Apple ID** (будь-який) → sideload на власний пристрій, provisioning-profile діє **7 днів**, після чого треба перебілдити й перевстановити.
- **Платний Apple Developer Program** ($99/рік) → profile діє 1 рік.

Відкрий Xcode → `Settings…` → `Accounts` → `+ Apple ID` → залогінься.

### 3. Підпис у Xcode (обов'язково для форка)

У репо зафіксовані **мої** значення — форку треба замінити на свої, інакше `flutter build ios` впаде з `No profiles for 'com.example.pixelCode' were found`.

1. Відкрий `ios/Runner.xcworkspace` (саме `.xcworkspace`, а не `.xcodeproj`).
2. У лівій панелі вибери корінь `Runner` → таргет `Runner` → вкладка **Signing & Capabilities**.
3. Для обох конфігурацій (`Debug` + `Release`):
   - **Team** → твій (той, що з'явився після логіна Apple ID).
   - **Bundle Identifier** → щось унікальне, напр. `com.<твій-нік>.pixelcode`. Плейсхолдер `com.example.pixelCode` не підійде — Apple не дасть підписати чужий домен.
   - **Automatically manage signing** → увімкнено. Xcode сам випише provisioning profile.
4. Xcode перепише значення в [ios/Runner.xcodeproj/project.pbxproj](../ios/Runner.xcodeproj/project.pbxproj) — закомміть зміну в свій форк.

### 4. Tailscale (для встановлення з будь-якої мережі)

```bash
brew install tailscale
sudo tailscale up          # одноразовий логін через браузер
```

Сервер при старті сам викликає `tailscale funnel --bg <PORT>` ([server/src/server.ts:1860](../server/src/server.ts#L1860)) і бере MagicDNS-ім'я. В консолі побачиш:

```
🌐 Remote access: wss://<your-name>.<tailnet>.ts.net
```

Якщо рядка немає — сервер зафіксував `Tailscale not running — remote access disabled`. OTA в такому разі буде недоступним, лишається тільки сайлент через `devicectl`.

### 5. (Опційно) Спарити пристрій з Mac через Xcode

Щоб був швидкий сайлент-інстал без відкривання посилань на пристрої:

1. Під'єднай iPhone / iPad до Mac кабелем **один раз**.
2. На пристрої прийми «Trust This Computer».
3. У Xcode → `Window → Devices and Simulators` переконайся, що пристрій з'явився зі статусом `Paired`.

Після цього кабель можна відключити. `xcrun devicectl` бачитиме пристрій доки той у тій самій мережі й увімкнений.

## Як встановити аппку — звичайний флоу

1. У хабі натисни іконку телефону у верхній панелі → відкриється попап **Deploy to device**.
2. Вибери вкладку **iOS**.
3. **Install** → сервер почне білдити. Лог тече в реальному часі.
4. Далі один з двох варіантів:
   - **Сайлент-інстал.** Якщо пристрій спарений і доступний — побачиш `Додаток встановлено на пристрій!` і аппка з'явиться на home screen.
   - **OTA.** Якщо сайлент не вдався, у попапі з'явиться посилання виду `itms-services://?action=download-manifest&url=https://<tailnet>.ts.net/manifest.plist`. Відкрий це посилання **на пристрої**:
     - зручно через QR-код, зроблений з будь-якого QR-генератора з цієї адреси,
     - або просто скопіюй URL і відправ собі в iMessage / Telegram та відкрий на iPhone.
5. iOS покаже `Install "PixelCode"?` → підтверджуй.
6. Після першого встановлення треба один раз довірити розробнику: `Settings → General → VPN & Device Management → <твій Apple ID> → Trust`.

## Типові помилки

### `error: No profiles for 'com.example.pixelCode' were found`

Ти не змінив Bundle ID / Team у Xcode. Див. розділ **3. Підпис у Xcode**.

### `Signing for "Runner" requires a development team`

Apple ID не залогінений у Xcode, або Team не вибраний у `Signing & Capabilities`. Залогінься через `Xcode → Settings → Accounts` і вибери Team у таргеті.

### `Tailscale Funnel не активний — OTA недоступний з іншої мережі.`

Tailscale не запущений на цьому Mac. Встав/підніми:

```bash
brew install tailscale
sudo tailscale up
```

Потім рестартани сервер (вихід з PixelCode → запуск знову). У логах має з'явитися `🌐 Remote access: …`.

### Сайлент-інстал пропускається, завжди йде OTA

Пристрій не спарений з цим Mac через Xcode, або спарений але не онлайн. Під'єднай один раз кабелем, прийми pairing у Xcode. Див. розділ **5. Спарити пристрій**.

### На iPhone натискаєш посилання, а Safari показує `itms-services:// is not supported`

Це буває, якщо браузер не iOS Safari (Chrome на iOS теж обробляє, але деякі in-app браузери — ні). Відкривай через довге натискання → `Open in Safari`, або через вбудований браузер iMessage.

### Аппка встановилась, але при запуску каже `Untrusted Developer`

Один раз:  `Settings → General → VPN & Device Management → <твій Apple ID> → Trust "…"`.

### Через 7 днів аппка перестала запускатись

Безкоштовний Apple ID має 7-денний provisioning profile. Просто перебілди — натисни **Install** у попапі знову.

## Ручний білд (для дебагу)

Якщо хочеш бачити що саме відбувається без UI:

```bash
# 1. Білд .app
flutter build ios --release

# 2. Сайлент-інстал (пристрій має бути спарений)
xcrun devicectl list devices        # переконайся що пристрій видно
xcrun devicectl device install app -d "<Device Name>" build/ios/iphoneos/Runner.app

# 3. Пакування в IPA (якщо сайлент не варіант)
mkdir -p /tmp/Payload
cp -R build/ios/iphoneos/Runner.app /tmp/Payload/Runner.app
(cd /tmp && zip -r app.ipa Payload)
```

Далі IPA треба віддати по HTTPS разом із `manifest.plist` — це і робить сервер автоматично.

## Релевантні файли

- [lib/services/ios_deploy_service.dart](../lib/services/ios_deploy_service.dart) — WebSocket-клієнт флоу
- [lib/widgets/deploy/device_deploy_popover.dart](../lib/widgets/deploy/device_deploy_popover.dart) — UI попап Deploy to device
- [server/src/server.ts:1759](../server/src/server.ts#L1759) — `iosDeployStart`, генерація manifest.plist, підйом Tailscale Funnel
- [ios/Runner.xcodeproj/project.pbxproj](../ios/Runner.xcodeproj/project.pbxproj) — Xcode project, сюди потрапляють твої Team / Bundle ID

---

<a id="ios-deploy-en"></a>

# iOS deployment (EN) 🇬🇧

How to install PixelCode on a physical iPhone or iPad **without a USB cable and without a laptop next to the device** — from your Mac, from any network worldwide. This document walks a first-time reader through the full setup.

## How it works

When you hit **Install** in the **Deploy to device → iOS** popover, the server does the following ([server/src/server.ts:2010](../server/src/server.ts#L2010)):

1. **Build:** `flutter build ios --release` produces a `.app` bundle. Requires correct code signing (Team ID + Bundle ID) in Xcode.
2. **Silent install:** `xcrun devicectl list devices` looks for paired iOS devices. If one is found, the bundle is pushed via `devicectl device install app`. Works when the iPhone was paired with this Mac via Xcode at least once and is currently reachable (LAN or USB).
3. **OTA fallback:** if silent fails, the server zips `.app` into an `.ipa`, generates a `manifest.plist`, and returns an `itms-services://…` URL. That URL points at an HTTPS host Tailscale Funnel publishes on the public internet. The iPhone can be on any Wi-Fi or mobile network — it downloads the manifest + IPA, and iOS installs the app.

**No "same Wi-Fi" requirement** — Tailscale Funnel is a public HTTPS endpoint on a MagicDNS domain (`*.ts.net`), reachable from anywhere. The local network only matters for the optional silent-install shortcut.

## One-time setup

### 1. Xcode + CocoaPods (on the Mac)

```bash
xcode-select --install
brew install cocoapods
(cd ios && pod install)
```

### 2. Apple ID or Apple Developer account

- **Free Apple ID** (any account) → sideload on your own device; the provisioning profile lasts **7 days**, after which you must rebuild and reinstall.
- **Paid Apple Developer Program** ($99/year) → profile lasts 1 year.

In Xcode: `Settings…` → `Accounts` → `+ Apple ID` → sign in.

### 3. Signing in Xcode (mandatory for forks)

The repo pins **my** values — forks must replace them, or `flutter build ios` will fail with `No profiles for 'com.example.pixelCode' were found`.

1. Open `ios/Runner.xcworkspace` (the `.xcworkspace`, not the `.xcodeproj`).
2. In the project navigator, pick the `Runner` target → **Signing & Capabilities** tab.
3. For both configurations (`Debug` + `Release`):
   - **Team** → your own (appears after signing in with your Apple ID).
   - **Bundle Identifier** → something unique, e.g. `com.<your-handle>.pixelcode`. The placeholder `com.example.pixelCode` won't work — Apple won't sign someone else's bundle ID.
   - **Automatically manage signing** → on. Xcode will provision a profile for you.
4. Xcode writes the values back into [ios/Runner.xcodeproj/project.pbxproj](../ios/Runner.xcodeproj/project.pbxproj) — commit that change in your fork.

### 4. Tailscale (for installs from any network)

```bash
brew install tailscale
sudo tailscale up          # one-time browser login
```

On startup the server calls `tailscale funnel --bg <PORT>` ([server/src/server.ts:1860](../server/src/server.ts#L1860)) and reads the MagicDNS name. You'll see in the console:

```
🌐 Remote access: wss://<your-name>.<tailnet>.ts.net
```

If that line is missing, the server logged `Tailscale not running — remote access disabled`. OTA won't work from a different network — you'll only get silent install via `devicectl`.

### 5. (Optional) Pair the device with the Mac in Xcode

For a fast silent install without opening links on the phone:

1. Connect the iPhone / iPad via cable **once**.
2. On the device, accept "Trust This Computer".
3. In Xcode → `Window → Devices and Simulators`, verify the device shows up as `Paired`.

After that the cable can go. `xcrun devicectl` will see the device as long as it's on the same network and powered on.

## Installing the app — normal flow

1. In the hub, click the phone icon in the top bar → **Deploy to device** popover opens.
2. Pick the **iOS** tab.
3. Hit **Install** → the server starts building. Logs stream live.
4. One of two outcomes:
   - **Silent install.** If the device is paired and reachable, you'll see `App installed on device!` and the app appears on the home screen.
   - **OTA.** If silent fails, the popover will show a link like `itms-services://?action=download-manifest&url=https://<tailnet>.ts.net/manifest.plist`. Open that link **on the device**:
     - easiest via a QR code generated from this URL,
     - or copy it, send it to yourself in iMessage / Telegram, and tap it on the iPhone.
5. iOS will prompt `Install "PixelCode"?` → confirm.
6. After the first install, trust the developer once: `Settings → General → VPN & Device Management → <your Apple ID> → Trust`.

## Common errors

### `error: No profiles for 'com.example.pixelCode' were found`

You didn't change Bundle ID / Team in Xcode. See **3. Signing in Xcode**.

### `Signing for "Runner" requires a development team`

No Apple ID is signed into Xcode, or no Team is selected under `Signing & Capabilities`. Sign in via `Xcode → Settings → Accounts` and pick a Team on the target.

### `Tailscale Funnel inactive — OTA unavailable from another network.`

Tailscale isn't running on this Mac. Install / bring it up:

```bash
brew install tailscale
sudo tailscale up
```

Then restart the server (quit PixelCode → launch again). The logs should now show `🌐 Remote access: …`.

### Silent install always skipped, goes straight to OTA

The device isn't paired with this Mac in Xcode, or is paired but offline. Connect once via cable, accept the pairing in Xcode. See **5. Pair the device**.

### Tapping the link on iPhone, Safari says `itms-services:// is not supported`

Happens when the browser isn't iOS Safari (Chrome on iOS handles it too, but some in-app browsers don't). Long-press the link → `Open in Safari`, or open it from the built-in iMessage browser.

### App installed, but launching says `Untrusted Developer`

One-time: `Settings → General → VPN & Device Management → <your Apple ID> → Trust "…"`.

### App stopped launching after 7 days

Free Apple IDs give a 7-day provisioning profile. Just rebuild — hit **Install** in the popover again.

## Manual build (for debugging)

When you want to see exactly what happens without the UI:

```bash
# 1. Build .app
flutter build ios --release

# 2. Silent install (device must be paired)
xcrun devicectl list devices        # confirm the device shows up
xcrun devicectl device install app -d "<Device Name>" build/ios/iphoneos/Runner.app

# 3. Pack into an IPA (if silent isn't an option)
mkdir -p /tmp/Payload
cp -R build/ios/iphoneos/Runner.app /tmp/Payload/Runner.app
(cd /tmp && zip -r app.ipa Payload)
```

The IPA then needs to be served over HTTPS alongside a `manifest.plist` — which is exactly what the server does automatically.

## Relevant files

- [lib/services/ios_deploy_service.dart](../lib/services/ios_deploy_service.dart) — WebSocket client flow
- [lib/widgets/deploy/device_deploy_popover.dart](../lib/widgets/deploy/device_deploy_popover.dart) — Deploy to device popover UI
- [server/src/server.ts:1759](../server/src/server.ts#L1759) — `iosDeployStart`, manifest.plist generation, Tailscale Funnel startup
- [ios/Runner.xcodeproj/project.pbxproj](../ios/Runner.xcodeproj/project.pbxproj) — Xcode project, where your Team / Bundle ID land
