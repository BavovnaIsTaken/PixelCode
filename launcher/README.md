# PixelCode Launcher

Мініма UI для управління Node.js сервером PixelCode.

## Запуск

```bash
# З VS Code — Shift+Cmd+D → вибери "🚀 🖥️ macOS"
flutter run -d macos

# Або з терміналу
cd launcher
flutter run -d macos
```

## Функціональність

- **Автоматичне налаштування** на першому запуску
  - Перевірка Node.js + npm
  - `npm install` в `server/`
  - Створення `.env` файлу
- **Історія кроків** з timestamp'ами
- **Reset** — доступна тільки коли встановлення не запущене
- **Стабільна обробка помилок** — кожна помилка логується + показується користувачу

## Архітектура

- `services/setup_service.dart` — оркестрація процесів, стан кроків
- `main.dart` — UI з Provider для state management
