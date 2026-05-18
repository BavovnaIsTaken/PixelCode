/**
 * Pure analyzer over `usage_log.jsonl` entries. Produces per-`{role, taskType}`
 * descriptive stats (count / median / p95 / p99 of cost, duration, tool calls,
 * tokens) plus a small bag of "health signals" — anomalies a daily glance
 * should flag (every entry has `numToolCalls=0`, every entry has zero duration,
 * `role="unknown"` leakage, etc).
 *
 * Empirical-baselines arc: this module exists from day-1 of C.2's live use,
 * not "+30 days after ship", so a broken instrumentation path surfaces in the
 * Settings → Usage Baselines tab the same day it starts mis-logging. The
 * outlier-warning consumer that *acts* on these baselines (2× median heuristic
 * in the facilitator UI) is a separate later step — see ROADMAP "Outlier
 * warning у facilitator UI".
 *
 * Strict purity contract: no fs access, no clock reads, no logger. Caller
 * supplies entries + (optional) `now` for the generatedAt timestamp. This is
 * what makes it cheap to unit-test deterministically on a fixture.
 */

import type { UsageLogEntry, UsageTaskType } from "./usage_log.js";

// ─── Configuration ───────────────────────────────────────────────────────────

/**
 * Threshold below which a bucket's stats are marked `confident: false`. Picked
 * to be just-above-typical-noise — < 10 samples and the median / p95 are still
 * dominated by individual outliers. The consumer (UI / outlier-warning) is
 * expected to gate any "this is unusual" claim on this flag.
 *
 * If you change the value, the daily-control surface should still render the
 * bucket (so the user can see growth toward confidence); only the actionable
 * signals should disable themselves.
 */
export const MIN_CONFIDENT_SAMPLES = 10;

// ─── Stats shape ─────────────────────────────────────────────────────────────

export interface NumericStats {
  min: number;
  max: number;
  mean: number;
  median: number; // p50
  p95: number;
  p99: number;
}

export interface BaselineStats {
  /** Number of entries in the bucket. */
  count: number;
  /** True iff `count >= MIN_CONFIDENT_SAMPLES`. */
  confident: boolean;
  costUsd: NumericStats;
  durationMs: NumericStats;
  numToolCalls: NumericStats;
  numTurns: NumericStats;
  inputTokens: NumericStats;
  outputTokens: NumericStats;
}

export interface BaselineBucket {
  /** Composite bucket key `${role}|${taskType}` — kept as a separate field for UI grouping. */
  role: string;
  taskType: UsageTaskType | string; // string fallback in case the log carries an unknown taskType
  /** Stats over the entries in this bucket. */
  stats: BaselineStats;
}

export interface HealthSignal {
  /** Stable tag for the UI to render an icon / explanation. */
  code:
    | "no_entries"
    | "unknown_role_leak"
    | "all_zero_tool_calls"
    | "all_zero_duration"
    | "single_dominant_bucket"
    | "non_finite_metric";
  /** Human-readable hint (Ukrainian, since this surfaces in-app). */
  message: string;
  /** Severity hint for ordering. `info` = "look at this", `warn` = "probably broken". */
  severity: "info" | "warn";
}

export interface BaselineReport {
  /** Caller-provided clock — purity requirement. */
  generatedAt: string; // ISO 8601
  /** Total well-formed entries across all buckets — same number as `entries.length`. */
  totalEntries: number;
  /** Per-`{role, taskType}` bucket, sorted descending by count. */
  buckets: BaselineBucket[];
  /** Cross-bucket anomalies a daily check should flag. Empty when healthy. */
  health: HealthSignal[];
}

// ─── Stats helpers ───────────────────────────────────────────────────────────

function quantile(sorted: number[], q: number): number {
  if (sorted.length === 0) return 0;
  if (sorted.length === 1) return sorted[0]!;
  // Linear interpolation between adjacent ranks (NIST-style); matches what most
  // people mean by "p95" when they have a small sample.
  const idx = (sorted.length - 1) * q;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return sorted[lo]!;
  const frac = idx - lo;
  return sorted[lo]! * (1 - frac) + sorted[hi]! * frac;
}

function numericStats(values: number[]): NumericStats {
  if (values.length === 0) {
    return { min: 0, max: 0, mean: 0, median: 0, p95: 0, p99: 0 };
  }
  const sorted = [...values].sort((a, b) => a - b);
  const sum = sorted.reduce((acc, v) => acc + v, 0);
  return {
    min: sorted[0]!,
    max: sorted[sorted.length - 1]!,
    mean: sum / sorted.length,
    median: quantile(sorted, 0.5),
    p95: quantile(sorted, 0.95),
    p99: quantile(sorted, 0.99),
  };
}

function bucketKey(role: string, taskType: string): string {
  return `${role}|${taskType}`;
}

// ─── Public API ──────────────────────────────────────────────────────────────

/**
 * Summarise a set of entries that belong to the same `{role, taskType}` bucket.
 * Useful in isolation for tests; `analyze` calls it under the hood.
 */
export function summarize(entries: UsageLogEntry[]): BaselineStats {
  return {
    count: entries.length,
    confident: entries.length >= MIN_CONFIDENT_SAMPLES,
    costUsd: numericStats(entries.map((e) => e.costUsd)),
    durationMs: numericStats(entries.map((e) => e.durationMs)),
    numToolCalls: numericStats(entries.map((e) => e.numToolCalls)),
    numTurns: numericStats(entries.map((e) => e.numTurns)),
    inputTokens: numericStats(entries.map((e) => e.inputTokens)),
    outputTokens: numericStats(entries.map((e) => e.outputTokens)),
  };
}

/**
 * Top-level analyzer. Given the parsed JSONL entries, returns:
 *  - per-bucket stats sorted by count
 *  - a `health` list of cross-bucket anomalies for the daily-control surface
 *
 * The function is deterministic given the same `entries` + `now`. No I/O.
 */
export function analyze(entries: UsageLogEntry[], now: Date = new Date()): BaselineReport {
  // Drop entries with non-finite metrics so they don't poison medians. They're
  // counted separately as a health signal so the user can investigate.
  const nonFiniteCount = entries.filter((e) =>
    !Number.isFinite(e.costUsd) ||
    !Number.isFinite(e.durationMs) ||
    !Number.isFinite(e.numToolCalls) ||
    !Number.isFinite(e.numTurns) ||
    !Number.isFinite(e.inputTokens) ||
    !Number.isFinite(e.outputTokens),
  ).length;
  const clean = entries.filter((e) =>
    Number.isFinite(e.costUsd) &&
    Number.isFinite(e.durationMs) &&
    Number.isFinite(e.numToolCalls) &&
    Number.isFinite(e.numTurns) &&
    Number.isFinite(e.inputTokens) &&
    Number.isFinite(e.outputTokens),
  );

  const grouped = new Map<string, UsageLogEntry[]>();
  for (const e of clean) {
    const key = bucketKey(e.role, e.taskType);
    let bucket = grouped.get(key);
    if (!bucket) {
      bucket = [];
      grouped.set(key, bucket);
    }
    bucket.push(e);
  }

  const buckets: BaselineBucket[] = [];
  for (const [, group] of grouped) {
    const first = group[0]!;
    buckets.push({
      role: first.role,
      taskType: first.taskType,
      stats: summarize(group),
    });
  }
  buckets.sort((a, b) => b.stats.count - a.stats.count);

  const health = detectHealthSignals(buckets, clean, nonFiniteCount);

  return {
    generatedAt: now.toISOString(),
    totalEntries: clean.length,
    buckets,
    health,
  };
}

// ─── Health signals (the daily control's eyes) ───────────────────────────────

function detectHealthSignals(
  buckets: BaselineBucket[],
  entries: UsageLogEntry[],
  nonFiniteCount: number,
): HealthSignal[] {
  const signals: HealthSignal[] = [];

  if (entries.length === 0 && nonFiniteCount === 0) {
    signals.push({
      code: "no_entries",
      severity: "info",
      message:
        "Лог використання порожній — жоден chat / dispatch ще не записався. Перевір, що сесія взагалі стартує сервером.",
    });
  }

  if (nonFiniteCount > 0) {
    signals.push({
      code: "non_finite_metric",
      severity: "warn",
      message:
        `${nonFiniteCount} запис(ів) мають NaN / Infinity у метриках і виключені з агрегації. Швидше за все instrumentation race у runQuery / runAgent.`,
    });
  }

  // role="unknown" leakage — dispatcher should always pass `roleTypeOf(agentId, gameState)`
  // for the bucket key. Anything else means an unhired or pre-set-game-state run.
  const unknownEntries = entries.filter((e) => e.role === "unknown" || e.role === "");
  if (unknownEntries.length > 0) {
    signals.push({
      code: "unknown_role_leak",
      severity: "warn",
      message:
        `${unknownEntries.length} run(s) логуються з role="unknown" / "" — bucket-сетка зашумлена. Перевір, що runQuery / dispatch завжди отримують roleTypeOf із поточного gameState.`,
    });
  }

  // Pipeline-broken check: if EVERY dispatch entry has 0 tool calls, the
  // CircuitBreaker probably isn't counting tool_use blocks (instrumentation
  // regression). Tool-using dispatches were the whole point of dispatch.
  const dispatches = entries.filter((e) => e.taskType === "dispatch");
  if (dispatches.length >= 5 && dispatches.every((e) => e.numToolCalls === 0)) {
    signals.push({
      code: "all_zero_tool_calls",
      severity: "warn",
      message:
        `Всі ${dispatches.length} dispatch-run-и записують numToolCalls=0 — CircuitBreaker.observeAssistantMessage, певно, не помічає tool_use блоки.`,
    });
  }

  // 0-ms durations across the board → SDK result message isn't carrying
  // duration_ms, or we're stamping completedAt before reading it.
  if (entries.length >= 5 && entries.every((e) => e.durationMs === 0)) {
    signals.push({
      code: "all_zero_duration",
      severity: "warn",
      message:
        `Всі ${entries.length} записи мають durationMs=0 — SDK result message не повертає duration або хук пропустив його.`,
    });
  }

  // One bucket > 90% of all entries → either we have a single-role workflow
  // (informational) or the role plumbing collapsed everything into one key
  // (worth a glance).
  if (buckets.length > 0 && entries.length >= 20) {
    const top = buckets[0]!;
    if (top.stats.count / entries.length > 0.9) {
      signals.push({
        code: "single_dominant_bucket",
        severity: "info",
        message:
          `Bucket "${top.role}|${top.taskType}" утримує ${top.stats.count}/${entries.length} run-ів (>90%). Очікувано якщо ти один єдиний агент — інакше перевір role-plumbing.`,
      });
    }
  }

  return signals;
}
