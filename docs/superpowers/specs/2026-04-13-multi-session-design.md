# Multi-Session: перемикання між серверами з будь-якого пристрою

## Проблема

Два MacBook (робочий і домашній), кожен з окремим Claude API key. З iPhone або з будь-якого MacBook потрібно:
- бачити в реальному часі що відбувається на кожному сервері
- перемикатися між серверами
- відповідати на питання агентів

## Рішення

Додаємо **Session Profile** — іменований профіль підключення до сервера. Користувач створює профілі ("Робочий MacBook", "Домашній MacBook"), вказуючи адресу і порт. На MacBook додатково можна вказати API key — тоді при виборі профілю сервер перезапускається з цим ключем.

На iPhone профілі працюють як пульт — підключаємося до вже запущеного сервера на MacBook.

## Що змінюється

### 1. Модель даних — SessionProfile

Новий клас для зберігання профілю сесії:

```dart
class SessionProfile {
  final String id;       // UUID, генерується при створенні
  final String name;     // "Робочий MacBook"
  final String host;     // "100.x.y.z" (Tailscale IP)
  final int port;        // 9720
  final String? apiKey;  // ANTHROPIC_API_KEY, тільки для локального сервера
}
```

Зберігається в `SharedPreferences` як JSON-масив. API key зберігається в `SharedPreferences` поруч — для single-user local tool це прийнятно. При переході до Phase 2 (multi-user) варто мігрувати API keys у `flutter_secure_storage` (Keychain).

Також зберігається `activeProfileId` — ID поточного активного профілю.

### 2. Provider — SessionProfilesProvider

Новий Riverpod `NotifierProvider` який:
- Завантажує список профілів з SharedPreferences при старті
- Надає CRUD-операції: add, update, delete, setActive
- Зберігає зміни в SharedPreferences
- При зміні активного профілю — тригерить перепідключення WebSocket

### 3. Зміни в ServerProcessService

При виборі профілю з `apiKey != null` (локальна сесія на MacBook):
- Зупиняє поточний сервер
- Перезапускає з `ANTHROPIC_API_KEY` з профілю в environment
- WebSocket підключається до `ws://localhost:{port}`

При виборі профілю без apiKey (віддалена сесія, або iPhone):
- Зупиняє локальний сервер (якщо був)
- WebSocket підключається до `ws://{host}:{port}`

На iOS сервер не запускається взагалі (вже є ця перевірка).

### 4. Зміни в AgentWsService

- `connect()` бере URL з активного профілю замість `defaultServerUrl`
- При зміні профілю: disconnect → connect до нового URL
- Reconnect логіка залишається тією ж, але використовує URL активного профілю

### 5. Зміни в Settings (settings_provider.dart)

- Видаляємо `serverUrl` з AppSettings — його замінює активний профіль
- Додаємо `activeProfileId` в AppSettings

### 6. UI — Session Picker

**Місце**: верхня частина HubScreen (app bar / header area), поруч з назвою проєкту.

**Вигляд**: компактний dropdown/chip з назвою активної сесії та кольоровим індикатором стану:
- Зелена крапка = підключено
- Жовта крапка = підключення...
- Червона крапка = немає зʼєднання

**По тапу**: розкривається список профілів з тими ж індикаторами. Внизу списку — кнопка "+ Додати сесію".

**На мобільному (iPhone)**: той самий елемент, адаптований під мобільний app bar.

### 7. UI — Управління профілями

В **Settings** (Налаштування) додається секція "Сесії" між "Зʼєднання" та "Ергономіка":
- Список існуючих профілів з можливістю редагувати/видалити
- Кнопка створення нового профілю
- Форма профілю: назва, хост (IP), порт, API key (опціонально, показується тільки на macOS)
- API key поле має toggle видимості (показати/сховати) і masked display (**\*\*\*\*...xyz**)

Стару секцію "Зʼєднання" (одне поле URL сервера) прибираємо — її замінюють профілі.

### 8. Зміни в main.dart

При старті:
1. Завантажити профілі та активний профіль
2. Якщо є активний профіль з apiKey і ми на macOS — запустити сервер з цим ключем
3. Підключити WebSocket до адреси активного профілю
4. Якщо профілів немає — показати wizard створення першого профілю

### 9. First-run wizard

Коли профілів немає (перший запуск або після очищення):
- Показується простий діалог "Додати сесію"
- На macOS: пропонує створити локальну сесію (з API key)
- На iOS: пропонує підключитися до існуючого сервера (host + port)

## Що НЕ змінюється

- **Серверна частина** (server.ts) — не потребує змін. API key вже береться з environment.
- **Протокол WebSocket** — жодних нових типів повідомлень.
- **Chat history, traits, game state** — залишаються привʼязаними до сервера, не до клієнта.
- **Broadcast модель** — всі підключені клієнти бачать однаковий стан.

## Порядок міграції

Для існуючих користувачів (тобто для тебе):
- Якщо вже є збережений `serverUrl` в SharedPreferences — автоматично створюється профіль "Default" з цією адресою
- Старий `serverUrl` key видаляється з SharedPreferences

## Файли які будуть створені або змінені

### Нові файли:
- `lib/models/session_profile.dart` — модель SessionProfile
- `lib/providers/session_provider.dart` — SessionProfilesProvider
- `lib/widgets/session/session_picker.dart` — dropdown в header
- `lib/widgets/session/session_form_dialog.dart` — форма створення/редагування профілю

### Змінені файли:
- `lib/providers/settings_provider.dart` — прибрати serverUrl, додати activeProfileId
- `lib/services/agent_ws_service.dart` — брати URL з профілю
- `lib/services/server_process_service.dart` — приймати apiKey в environment
- `lib/widgets/settings/settings_dialog.dart` — нова секція "Сесії", прибрати стару секцію "Зʼєднання"
- `lib/screens/hub/hub_screen.dart` — session picker в header
- `lib/main.dart` — логіка першого запуску
- `lib/providers/agent_provider.dart` — wsServiceProvider залежить від активного профілю
