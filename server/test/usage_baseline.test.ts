import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  analyze,
  summarize,
  MIN_CONFIDENT_SAMPLES,
  type BaselineReport,
} from "../src/usage_baseline.js";
import type { UsageLogEntry } from "../src/usage_log.js";

// ─── Fixture helpers ─────────────────────────────────────────────────────────

let counter = 0;
function entry(over: Partial<UsageLogEntry> = {}): UsageLogEntry {
  counter += 1;
  return {
    runId: `run_${counter}`,
    role: "coder",
    taskType: "dispatch",
    agentId: "coder#1",
    inputTokens: 100,
    outputTokens: 50,
    cacheCreationTokens: 0,
    cacheReadTokens: 0,
    costUsd: 0.05,
    durationMs: 1000,
    numTurns: 3,
    numToolCalls: 2,
    startedAt: "2026-05-18T08:00:00.000Z",
    completedAt: "2026-05-18T08:00:01.000Z",
    ...over,
  };
}

const FIXED_NOW = new Date("2026-05-18T12:00:00.000Z");

function bucketCounts(report: BaselineReport): Record<string, number> {
  const out: Record<string, number> = {};
  for (const b of report.buckets) {
    out[`${b.role}|${b.taskType}`] = b.stats.count;
  }
  return out;
}

function healthCodes(report: BaselineReport): string[] {
  return report.health.map((h) => h.code).sort();
}

// ─── summarize ───────────────────────────────────────────────────────────────

describe("summarize", () => {
  test("count + confident flag respect MIN_CONFIDENT_SAMPLES", () => {
    const few = Array.from({ length: MIN_CONFIDENT_SAMPLES - 1 }, () => entry());
    const enough = Array.from({ length: MIN_CONFIDENT_SAMPLES }, () => entry());
    assert.equal(summarize(few).confident, false);
    assert.equal(summarize(enough).confident, true);
    assert.equal(summarize(few).count, MIN_CONFIDENT_SAMPLES - 1);
    assert.equal(summarize(enough).count, MIN_CONFIDENT_SAMPLES);
  });

  test("median / p95 / p99 over a uniform sample", () => {
    const sample = Array.from({ length: 100 }, (_, i) =>
      entry({ costUsd: (i + 1) / 100 }), // 0.01 … 1.00
    );
    const s = summarize(sample).costUsd;
    assert.ok(Math.abs(s.median - 0.505) < 1e-6, `median=${s.median}`);
    assert.ok(s.p95 > 0.94 && s.p95 < 0.96, `p95=${s.p95}`);
    assert.ok(s.p99 > 0.98 && s.p99 <= 1.0, `p99=${s.p99}`);
    assert.equal(s.min, 0.01);
    assert.equal(s.max, 1.0);
  });

  test("single-entry stats collapse to that single value", () => {
    const s = summarize([entry({ costUsd: 0.42, durationMs: 1234 })]);
    assert.equal(s.costUsd.median, 0.42);
    assert.equal(s.costUsd.p95, 0.42);
    assert.equal(s.costUsd.p99, 0.42);
    assert.equal(s.durationMs.mean, 1234);
  });

  test("empty entries → zero-valued stats (defensive)", () => {
    const s = summarize([]);
    assert.equal(s.count, 0);
    assert.equal(s.confident, false);
    assert.equal(s.costUsd.median, 0);
    assert.equal(s.durationMs.p99, 0);
  });
});

// ─── analyze — bucketing ─────────────────────────────────────────────────────

describe("analyze — bucketing", () => {
  test("groups by {role, taskType}", () => {
    const entries = [
      entry({ role: "coder", taskType: "dispatch" }),
      entry({ role: "coder", taskType: "dispatch" }),
      entry({ role: "coder", taskType: "chat" }),
      entry({ role: "manager", taskType: "chat" }),
      entry({ role: "manager", taskType: "chat" }),
      entry({ role: "manager", taskType: "chat" }),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.deepEqual(bucketCounts(report), {
      "coder|dispatch": 2,
      "coder|chat": 1,
      "manager|chat": 3,
    });
  });

  test("sorts buckets descending by count", () => {
    const entries = [
      ...Array.from({ length: 1 }, () => entry({ role: "tester" })),
      ...Array.from({ length: 7 }, () => entry({ role: "coder" })),
      ...Array.from({ length: 3 }, () => entry({ role: "reviewer" })),
    ];
    const report = analyze(entries, FIXED_NOW);
    const order = report.buckets.map((b) => b.role);
    assert.deepEqual(order, ["coder", "reviewer", "tester"]);
  });

  test("generatedAt is the caller-supplied clock", () => {
    const report = analyze([entry()], FIXED_NOW);
    assert.equal(report.generatedAt, FIXED_NOW.toISOString());
  });

  test("totalEntries matches entry count when all are clean", () => {
    const entries = Array.from({ length: 5 }, () => entry());
    const report = analyze(entries, FIXED_NOW);
    assert.equal(report.totalEntries, 5);
  });

  test("empty entries → empty buckets, no_entries health signal", () => {
    const report = analyze([], FIXED_NOW);
    assert.deepEqual(report.buckets, []);
    assert.equal(report.totalEntries, 0);
    assert.ok(report.health.some((h) => h.code === "no_entries"));
  });
});

// ─── analyze — non-finite filtering ──────────────────────────────────────────

describe("analyze — non-finite metric filter", () => {
  test("drops entries with NaN / Infinity from aggregation", () => {
    const entries = [
      entry({ costUsd: 0.10 }),
      entry({ costUsd: 0.20 }),
      entry({ costUsd: Number.NaN }),
      entry({ durationMs: Number.POSITIVE_INFINITY }),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.equal(report.totalEntries, 2, "only the 2 finite entries count");
    assert.ok(report.health.some((h) => h.code === "non_finite_metric"));
  });

  test("zero non-finite count → no non_finite_metric signal", () => {
    const report = analyze([entry(), entry()], FIXED_NOW);
    assert.equal(
      report.health.find((h) => h.code === "non_finite_metric"),
      undefined,
    );
  });
});

// ─── analyze — health signals (daily control) ────────────────────────────────

describe("analyze — health signals", () => {
  test('role="unknown" leak triggers warn signal', () => {
    const entries = [
      entry({ role: "coder" }),
      entry({ role: "unknown" }),
      entry({ role: "" }),
    ];
    const report = analyze(entries, FIXED_NOW);
    const s = report.health.find((h) => h.code === "unknown_role_leak");
    assert.ok(s, "expected unknown_role_leak signal");
    assert.equal(s?.severity, "warn");
    assert.match(s!.message, /role="unknown"/);
  });

  test("all-zero tool calls across >= 5 dispatches → warn", () => {
    const entries = Array.from({ length: 6 }, () =>
      entry({ taskType: "dispatch", numToolCalls: 0 }),
    );
    const report = analyze(entries, FIXED_NOW);
    assert.ok(report.health.some((h) => h.code === "all_zero_tool_calls"));
  });

  test("a single dispatch with non-zero tool calls clears the signal", () => {
    const entries = [
      ...Array.from({ length: 5 }, () =>
        entry({ taskType: "dispatch", numToolCalls: 0 }),
      ),
      entry({ taskType: "dispatch", numToolCalls: 1 }),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.equal(
      report.health.find((h) => h.code === "all_zero_tool_calls"),
      undefined,
    );
  });

  test("all-zero duration across all entries → warn", () => {
    const entries = Array.from({ length: 5 }, () => entry({ durationMs: 0 }));
    const report = analyze(entries, FIXED_NOW);
    assert.ok(report.health.some((h) => h.code === "all_zero_duration"));
  });

  test("dominant bucket > 90% triggers info signal", () => {
    const entries = [
      ...Array.from({ length: 19 }, () => entry({ role: "coder" })),
      entry({ role: "manager" }),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.ok(report.health.some((h) => h.code === "single_dominant_bucket"));
  });

  test("dominant-bucket signal does NOT fire below 20 entries (noise floor)", () => {
    const entries = [
      ...Array.from({ length: 18 }, () => entry({ role: "coder" })),
      entry({ role: "manager" }),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.equal(
      report.health.find((h) => h.code === "single_dominant_bucket"),
      undefined,
    );
  });

  test("healthy mid-volume load → empty health array", () => {
    const entries = [
      ...Array.from({ length: 10 }, () => entry({ role: "coder" })),
      ...Array.from({ length: 10 }, () => entry({ role: "manager" })),
    ];
    const report = analyze(entries, FIXED_NOW);
    assert.deepEqual(healthCodes(report), []);
  });
});

// ─── Determinism / purity ────────────────────────────────────────────────────

describe("analyze — purity", () => {
  test("same input + same now → identical output", () => {
    const entries = [entry({ role: "a" }), entry({ role: "b" })];
    const a = analyze(entries, FIXED_NOW);
    const b = analyze(entries, FIXED_NOW);
    assert.deepEqual(a, b);
  });

  test("input is not mutated", () => {
    const entries = [entry({ role: "x" }), entry({ role: "y" })];
    const snapshot = JSON.stringify(entries);
    analyze(entries, FIXED_NOW);
    assert.equal(JSON.stringify(entries), snapshot);
  });
});
