# Як долучитися до PixelCode

Привіт 👋 Радий що ти зазирнув. PixelCode — проєкт із відкритим вихідним кодом під [PolyForm Noncommercial 1.0.0](LICENSE) (використання вільне для некомерційних цілей), і будь-яка допомога цінується — від виправлення типу у README до великої фічі. Надсилаючи PR, ти погоджуєшся, що твій вклад ліцензується на тих самих умовах, що й решта проєкту.

> 🇬🇧 [English version below](#contributing-en)

---

## Швидкий старт

1. Глянь [Як запустити](README.md#як-запустити) — це онбординг за ~10 хвилин.
2. Якщо щось зламалося на цьому етапі — це вже привід для issue. Не мовчи, напиши.

## Workflow для змін

1. **Форкни** репо і склонуй свій форк.
2. **Створи бранч** з описовою назвою: `feat/task-board-filters`, `fix/mdns-timeout-ios`, `docs/readme-install`.
3. **Коміть часто**, невеликими логічними шматками. Повідомлення в теперішньому часі, починай з дієслова: `Add …`, `Fix …`, `Refactor …`. Українською або англійською — обидві ок.
4. **Перевір перед PR:**
   ```bash
   dart format lib test
   flutter analyze
   flutter test
   (cd server && npm test)
   ```
5. **Відкрий PR проти `develop`** (не `main`). У описі:
   - що змінив і чому,
   - як перевіряв (екран / лог / сценарій),
   - якщо UI — прикріпи скріншот або GIF.

## Стиль коду

- **Dart:** `dart format` + правила з [analysis_options.yaml](analysis_options.yaml).
- **TypeScript:** строгий режим, без `any` без коментаря-виправдання.
- **Файли:** одна тема = один файл. Не клади два неспоріднених класи разом.
- **Коментарі:** пояснюй *чому*, а не *що*. Якщо код очевидний — не пиши коментар.

## Баг-репорти

Гарний баг-репорт містить:
- ОС і версію (`sw_vers` / `uname -a`),
- `flutter --version`, `node --version`,
- кроки відтворення — мінімально необхідні,
- що ти очікував і що сталося,
- логи з панелі **Діагностика** (⚙ → Діагностика → Скопіювати логи).

## Нові фічі

Перед тим як писати код — відкрий issue з тегом `enhancement` і коротко опиши ідею. Так уникнемо дубля і можна звіритися по напрямку до того, як ти витратиш час.

## Питання

Не соромся відкривати issue навіть для «дурних» питань. Краще запитати, ніж сидіти в тупику на годину.

---

<a id="contributing-en"></a>

# Contributing to PixelCode 🇬🇧

Hi 👋 Glad you're here. PixelCode is source-available under [PolyForm Noncommercial 1.0.0](LICENSE) (free for any noncommercial use), and every bit of help matters — from a README typo to a big feature. By submitting a PR, you agree that your contribution is licensed on the same terms as the rest of the project.

## Quick start

1. Follow [Getting started](README.md#getting-started) — it's about a 10-minute onboarding.
2. If anything breaks along the way, that's already a valid issue. Please open one.

## Change workflow

1. **Fork** the repo and clone your fork.
2. **Create a branch** with a descriptive name: `feat/task-board-filters`, `fix/mdns-timeout-ios`, `docs/readme-install`.
3. **Commit often**, in small logical chunks. Use present tense starting with a verb: `Add …`, `Fix …`, `Refactor …`. English or Ukrainian — both fine.
4. **Before opening a PR:**
   ```bash
   dart format lib test
   flutter analyze
   flutter test
   (cd server && npm test)
   ```
5. **Open the PR against `develop`** (not `main`). In the description include:
   - what changed and why,
   - how you verified it (screen / log / scenario),
   - a screenshot or GIF for any UI change.

## Code style

- **Dart:** `dart format` + rules from [analysis_options.yaml](analysis_options.yaml).
- **TypeScript:** strict mode, no `any` without a justifying comment.
- **Files:** one topic per file. Don't co-locate unrelated classes.
- **Comments:** explain *why*, not *what*. If the code is obvious, leave the comment out.

## Bug reports

A good bug report contains:
- OS and version (`sw_vers` / `uname -a`),
- `flutter --version`, `node --version`,
- minimal reproduction steps,
- expected vs. actual behavior,
- logs from the **Diagnostics** panel (⚙ → Diagnostics → Copy logs).

## Feature ideas

Before writing code — open an `enhancement` issue and describe the idea briefly. Avoids duplicate work and lets us align direction before you invest time.

## Questions

Don't hesitate to open an issue even for "silly" questions. Better to ask than spin for an hour.
