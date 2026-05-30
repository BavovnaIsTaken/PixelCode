# Галерея офісна — Картування кольорів до елементів

## 7-кольорова схема → Елементи палуби

### 🎨 Палітра
| # | Назва | HEX | Dart const | Використання |
|---|-------|-----|-----------|--------------|
| 1 | Стіни | #E8E8E8 | `_wallLight` | Стіни, світлі поверхні |
| 2 | Підлога | #D4C8A8 | `_floorDark` | Дошки палуби, дуб |
| 3 | Двері | #4A4A4A | `_doorDark` | Двері, обрізи, рейки |
| 4 | Меблі | #8B6F47 | `_furnBrown` | Столи, крісла, шафи |
| 5a | Акцент (цян) | #0A8FD1 | `_accentCyan` | Монітори, лампи, деталі |
| 5b | Акцент (помаранч) | #FF8C42 | `_accentOrange` | Попередження, виділення |
| 6 | Метал | #5A5A5A | `_metalMid` | Болти, скріпи, рейлс |
| 7 | Тінь | #3A3A3A | `_metalDark` | Глибина, контрастні лінії |

---

## 🏗️ Елементи → Кольори

### Мачта та вітрила
- **Мачта** → `_furnBrownDark` (#6B4F2A)
- **Вітрила** (база) → `_wallLight` (#E8E8E8)
- **Вітрила** (тінь) → `_doorDark` (#4A4A4A)
- **Штанги** → `_furnBrown` (#8B6F47)
- **Мотузки** → `_floorDark` (#D4C8A8)

### Корабельна оснастка
- **Кований обід** → `_metalMid` (#5A5A5A)
- **Болти** → `_metalHi` (#7A7A7A)
- **Подібрання ржави** → `_accentOrange` (#FF8C42)

### Палубні меблі
- **Стілець (навколишній район)** → `_doorDark` (#4A4A4A)
- **Стіл (верх)** → `_furnBrown` (#8B6F47)
- **Ящик** → `_furnBrownDark` (#6B4F2A)
- **Акцент меблі** → `_accentCyan` (#0A8FD1)

### Деталі та аксесуари
- **Фонарик** (скло) → `_accentCyanBright` (#1FA8E8)
- **Щит** (поле) → `_accentOrange` (#FF8C42)
- **Щит** (обід) → `_metalMid` (#5A5A5A)
- **Якорь** → `_metalDark` (#3A3A3A)
- **Барабан** (корпус) → `_accentOrange` (#FF8C42)
- **Барабан** (шкіра) → `_wallLight` (#E8E8E8)

### Вода та морські елементи (тепер офісні!)
- **Глибина** → `_accentCyan` (#0A8FD1)
- **Хвиля** (вершина) → `_accentCyanBright` (#1FA8E8)
- **Піна** → `_wallLight` (#E8E8E8)
- **Відбиття** → `_floorDark` (#D4C8A8)

---

## 💾 Dart константи (Копіпастити)

```dart
// 7-Color Bright Office Palette
const _wallLight = Color(0xFFE8E8E8);
const _floorDark = Color(0xFFD4C8A8);
const _floorSeam = Color(0xFFC0B494);
const _doorDark = Color(0xFF4A4A4A);
const _furnBrown = Color(0xFF8B6F47);
const _furnBrownDark = Color(0xFF6B4F2A);
const _accentCyan = Color(0xFF0A8FD1);
const _accentCyanBright = Color(0xFF1FA8E8);
const _accentOrange = Color(0xFFFF8C42);
const _metalDark = Color(0xFF3A3A3A);
const _metalMid = Color(0xFF5A5A5A);
const _metalHi = Color(0xFF7A7A7A);
```

---

## 🎯 Контрастні пари (найбільш читаемі комбінації)

| Передній план | Фон | Контрастність | Примітка |
|---------------|-----|---------------|---------|
| `_metalDark` (#3A3A3A) | `_wallLight` (#E8E8E8) | ★★★★★ (максимум) | Деталі, текст |
| `_doorDark` (#4A4A4A) | `_wallLight` (#E8E8E8) | ★★★★★ | Двері, линії |
| `_accentCyan` (#0A8FD1) | `_wallLight` (#E8E8E8) | ★★★★☆ | Яскраві елементи |
| `_furnBrown` (#8B6F47) | `_wallLight` (#E8E8E8) | ★★★☆☆ | Меблі (читаемо) |
| `_metalMid` (#5A5A5A) | `_floorDark` (#D4C8A8) | ★★★☆☆ | Болти на дубі |
| `_accentOrange` (#FF8C42) | `_wallLight` (#E8E8E8) | ★★★★☆ | Попередження |

---

## 🚀 Швидкий запуск

1. **Замініть весь `galley_sprites.dart`** палітрою (уже зроблено ✓)
2. **Оновіть `room_themes.dart`** на `_galley` тему (уже зроблено ✓)
3. **Тестуйте**: Запустіть гру, відкрийте палубу
4. **Коригуйте**: Якщо якийсь елемент не читаємий, змініть його колір відповідно до таблиці вище

---

**Готово до впровадження!** ✅
