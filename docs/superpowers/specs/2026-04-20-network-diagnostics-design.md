# Діагностика мережі

**Дата:** 2026-04-20
**Автор:** Danylo Oliinyk

## Мета

Коли мережа/Tailscale/OTA не працює — юзер має відкрити одне місце, побачити що зламано, і (де можливо) виправити кліком. Сьогодні сервер мовчки падає у "працює локально" без жодного індикатора, що віддалені сценарії не функціонують.

## Розташування

Окрема секція "Діагностика" внизу вкладки Налаштування → Мережа, під існуючими секціями (Сесії / Tailscale / OTA).

## Перевірки

**Завжди видно (core — 5):**

| # | Назва | Метод | Автофікс |
|---|-------|-------|----------|
| 1 | Tailscale CLI встановлений | `which tailscale` на сервері | ні (інструкція `brew install tailscale`) |
| 2 | Tailscale демон запущений | `tailscale status --json` → `BackendState == Running` | так (`tailscale up`) |
| 3 | Funnel активний для порту сервера | `tailscale funnel status` парс | так (`tailscale funnel --bg <PORT>`) |
| 4 | Сервер слухає порт локально | існуючий стан http-сервера | ні (сервер уже запущений, якщо це відбувається) |
| 5 | Клієнт підключений до сервера | клієнтський `connectionStatusProvider` | ні (юзер має сам налагодити з'єднання) |

**Розгортається "Додаткові перевірки" — 4:**

| # | Назва | Метод | Автофікс |
|---|-------|-------|----------|
| 6 | iOS signing identity в Keychain | `security find-identity -v -p codesigning` → перевірка "Apple Development" або "iPhone Developer" | ні (інструкція, як додати в Xcode) |
| 7 | Xcode Command Line Tools | `xcode-select -p` → існує шлях | ні (інструкція `xcode-select --install`) |
| 8 | Android SDK / adb | `which adb` і `$ANDROID_HOME` | ні (інструкція) |
| 9 | Bonjour/mDNS активний | серверний прапорець з Bonjour provider | так (перезапустити провайдер) |

## UX

**Компонент:** `_DiagnosticsSection` — кінцева секція у вкладці Мережа.

Заголовок "Діагностика" + кнопка "Оновити" справа.

**Рядок пункту:**

```
[🟢/🔴/⚪] Назва пункту              [Виправити] або [Інструкція]
          підпис (коротка деталь, опційно)
```

- 🟢 зелений — усе ок, справа порожньо
- 🔴 червоний — справа або кнопка "Виправити" (якщо автофікс доступний), або кнопка "Інструкція" (розгортає пояснення з командою для копіювання)
- ⚪ сіре/спіннер — "перевіряється" або "виконується fix"
- Якщо сервер недоступний: пункт #5 червоний, решта 🔴 з підписом "Сервер недоступний"

**Порядок виконання:**

1. Користувач відкриває вкладку Мережа → сторінка прокручується до секції Діагностика → автоматичний запит `health-check-request` → сервер виконує всі чеки паралельно → повертає `health-check-result` з масивом статусів.
2. Клік "Оновити" — те саме ще раз.
3. Клік "Виправити" на пункті — `health-fix-request {id}` → сервер намагається виправити → після завершення (або таймауту 15с) перезапускає саме цей чек і шле `health-item-update`. Плюс клієнт сам переопитує цей пункт кожні 2-3 сек протягом ~15с, щоб дати візуальний фідбек процесу.
4. Клік "Інструкція" — розгортає inline-панельку з текстом і командою (з кнопкою копіювання).

## Протокол (WS)

**Клієнт → сервер:**

```ts
{ type: 'health-check-request' }
{ type: 'health-fix-request', id: HealthItemId }
```

**Сервер → клієнт:**

```ts
{
  type: 'health-check-result',
  items: Array<{
    id: HealthItemId;
    status: 'ok' | 'fail' | 'checking';
    detail?: string;      // коротке пояснення ("daemon stopped", "funnel not configured")
    fixable: boolean;     // чи доступний автофікс
    instruction?: string; // якщо не fixable — markdown інструкція з командою
  }>
}

{ type: 'health-item-update', item: { ... } } // окремий пункт оновився
```

`HealthItemId` — літеральний union:
`'tailscaleInstalled' | 'tailscaleRunning' | 'funnelActive' | 'serverListening' | 'clientConnected' | 'iosSigning' | 'xcodeTools' | 'androidSdk' | 'mdnsActive'`

## Серверна реалізація

Новий модуль `server/src/health.ts`:

- `runAllChecks(ctx): Promise<HealthItem[]>` — запускає всі чеки паралельно через `Promise.all`, повертає масив.
- Один `checkX()` функція на пункт, кожна повертає `HealthItem`.
- `runFix(id): Promise<void>` — мапа id → handler для fixable пунктів.
- Спільний util `execAsync(binary, args, timeout)` — обгортка над `execFile`.

Інтеграція у `server.ts`:
- Новий handler для `health-check-request` — виклик `runAllChecks` + відправка результату.
- Новий handler для `health-fix-request` — виклик `runFix` → `runCheck(id)` → `health-item-update`.

Клієнтський пункт #5 (`clientConnected`) не запитується у сервера — клієнт сам підставляє значення з `connectionStatusProvider`. Сервер не знає і не повертає його в `health-check-result`.

## Клієнтська реалізація

**Моделі** (`lib/models/agent_message.dart`):
- `HealthItem` — data class: id (enum), status, detail, fixable, instruction
- `HealthCheckResultMessage extends ServerMessage` з `List<HealthItem>`
- `HealthItemUpdateMessage extends ServerMessage` з одним `HealthItem`

**Провайдер** (`lib/providers/health_provider.dart`):
- `healthProvider: StateNotifierProvider<HealthNotifier, Map<HealthItemId, HealthItem>>`
- Методи: `refreshAll()`, `fix(id)`, `_subscribe()` — слухає `wsServiceProvider.messages` для `HealthCheck*`
- Мерджить клієнтський `clientConnected` у мапу на основі `connectionStatusProvider`

**Widget** (`lib/widgets/settings/diagnostics_section.dart` — щоб не роздути `settings_dialog.dart`):
- `_DiagnosticsSection extends ConsumerStatefulWidget`
- Core-список (5 пунктів) + `ExpansionTile` "Додаткові перевірки" з 4 пунктами
- Рядок пункту — окремий компонент `_HealthRow` (іконка/статус/назва/дія)
- Клік "Інструкція" — розгортає inline-панельку (локальний bool state у рядку)

**Виклик з `_buildNetwork`:** додати `const SizedBox(height: 24), _DiagnosticsSection()` у кінець.

## Не входить у цю роботу

- Проактивні індикатори на головному екрані (юзер явно вибрав варіант "тільки за запитом").
- Поллінг у фоні.
- Збереження останнього відомого стану між сесіями.
- Діагностика LAN (ping конкретних айпі, pingability між клієнтом і сервером поза WS).
- Full автофікс-майстер (встановлення Tailscale / Xcode Tools через аппку).

## Критерії готовності

- Відкриття вкладки Мережа → автоматично заповнюються всі 9 пунктів діагностики зі своїми статусами.
- Якщо `tailscale` демон зупинений — пункт #2 червоний із кнопкою "Виправити"; клік запускає `tailscale up`, протягом ~15с пункт стає зеленим (або червоним, якщо fix не спрацював).
- Те саме для funnel (пункт #3) і mDNS (пункт #9).
- Для не-fixable пунктів кнопка "Інструкція" розгортає команду з копіюванням.
- Якщо сервер недоступний — пункт #5 червоний, решта позначені "Сервер недоступний".
- `flutter analyze` і `tsc` чисті, застосунок і сервер збираються.
