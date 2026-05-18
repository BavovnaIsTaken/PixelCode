# Empirical Baselines — Audit Log

> Журнал щоденного спостереження за `usage_log.jsonl` і дослідницьких нотаток
> навколо empirical-baselines арки. Існує тому, що **проект C.2 не довіряє
> instrumentation pipeline-у наосліп**: замість того щоб писати analyzer через
> 30 днів і сподіватись що дані добрі, ми пишемо analyzer одразу і щодня
> перевіряємо health signals — будь-який broken-pipeline ловиться за 24 години,
> не за 30.
>
> **Тригер до full-analysis checkpoint:** 2026-06-17 (C.2 ship-day +30d).

## Контекст

| Артефакт | Шлях |
|---|---|
| Raw data | `~/.pixelcode/projects/{projectKey}/usage_log.jsonl` |
| Writer (chat) | [server/src/server.ts](../server/src/server.ts) `runQuery` — runId `chat_*` |
| Writer (dispatch) | [server/src/agent_runner.ts](../server/src/agent_runner.ts) `runAgent` — runId `dispatch_*` |
| Analyzer | [server/src/usage_baseline.ts](../server/src/usage_baseline.ts) (pure, no I/O) |
| WS endpoint | `get_usage_baselines` → `usage_baselines` |
| Daily-control UI | Settings → "Використання" tab |

`MIN_CONFIDENT_SAMPLES = 10` — нижче того bucket рендериться (видно growth), але
не використовується для warning-ів і не позначається `confident`. Якщо хочеш
змінити поріг — оновлюй const у analyzer-і + згадай тут чому.

### Health signals — що вони означають

| Code | Severity | Що означає |
|---|---|---|
| `no_entries` | info | Лог порожній. На ship-day це норма; через 3+ дні — підозріло. |
| `unknown_role_leak` | warn | run-и пишуться з `role="unknown"` чи `""`. Хтось викликав `runQuery`/`dispatch` без `roleTypeOf(agentId, gameState)`. |
| `all_zero_tool_calls` | warn | Усі ≥5 dispatch-run-ів мають `numToolCalls=0`. `CircuitBreaker.observeAssistantMessage` зламаний, не помічає `tool_use`. |
| `all_zero_duration` | warn | Усі ≥5 run-ів з `durationMs=0`. SDK не повертає duration, або хук його губить. |
| `single_dominant_bucket` | info | Один bucket >90% даних (мінімум 20 entries). Solo-dev сценарій — норма. Якщо несподівано — role-plumbing collapsed. |
| `non_finite_metric` | warn | NaN / Infinity у метриці. Race у instrumentation. |

## Розклад

- **Щодня** (поки accumulating): відкрити Settings → Використання, refresh,
  занотувати у "Daily glance log" нижче. Якщо є `warn` — розбиратися одразу,
  не чекати checkpoint-у.
- **2026-06-17** (30d після C.2 ship 2026-05-18): full-analysis checkpoint,
  заповнити секцію нижче. Якщо >80% активних buckets `confident=true` — open
  follow-up row "Outlier warning у facilitator UI" з ROADMAP. Якщо ні — defer.

## Daily glance log

Формат рядка: одна короткая нотатка на день. Якщо нічого цікавого — `OK`.
Якщо warn — описати + посилання на коміт фіксу.

| Дата | totalEntries | bucketsConfident | health | Нотатка |
|---|---|---|---|---|
| 2026-05-18 | — | — | — | C.2 + analyzer ship-day. Pipeline тільки що приземлився, перший справжній log запишеться з наступним dispatch-ем. Очікую `no_entries` info на старті. |

<!-- Шаблон для нового рядка:
| YYYY-MM-DD | <totalEntries> | <countConfident>/<totalBuckets> | <code1, code2, ...> або OK | <коротка нотатка> |
-->

## 30-day full-analysis checkpoint (2026-06-17)

Заповнюється на checkpoint-day. Поки що шаблон.

```
Загальні цифри
- totalEntries:
- Унікальних buckets:
- Buckets з count ≥ 10 (confident):  /
- Найбільше навантаження (top-3 buckets за count):
   1. role=___ taskType=___ n=___
   2. ...
   3. ...

Distribution sanity (per top bucket)
- cost p50 / p95 / max:
- duration p50 / p95 / max:
- numToolCalls p50 / p95:
- numTurns p50 / p95:
   → виглядає правдоподібно? так / ні + чому

Health signals за 30 днів
- Скільки днів з warn:
- Які найчастіші warn-коди:
- Коли усувались, посилання на коміти:

Рішення
[ ] Ready: > 80% активних buckets confident → відкрити "Outlier warning у
    facilitator UI" з ROADMAP (Q3 2026 + 30d), починати імплементацію.
[ ] Not ready: < 80% confident → defer ще на +30d, додати запис у Daily
    glance log про defer + чому. Які bucket-и розріджені і чи можна їх
    fold-нути (наприклад роль X завжди має < 3 dispatch/тиждень).
[ ] Pipeline broken: warn-сигнал не зник за 30 днів → не відкривати
    outlier-warning; писати fix instrumentation окремим PR; перевизначити
    checkpoint після фіксу.

Findings / surprises
- (відкриті питання, гіпотези про патерни в датах)
```

## Findings — журнал дослідницьких знахідок

Пиши сюди те що варто памʼятати у наступні рази коли торкатимешся empirical-
baselines арки. Наприклад "median cost для `coder|dispatch` стабілізувалась на
$0.04 через 50 entries" — цінна emrpicial константа, яку інакше доведеться
шукати наново.

<!-- Шаблон:
### YYYY-MM-DD — короткий заголовок
Що помічено, чому має значення, що з тим робити (або null якщо просто факт).
-->
