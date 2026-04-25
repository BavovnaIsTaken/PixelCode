import { test } from "node:test";
import assert from "node:assert/strict";
import {
  computeScore,
  memoryLifecycleConfig,
  findStrength,
  findWeakness,
  buildStrengthIndex,
  buildWeaknessIndex,
  CAPACITY_TIERS,
  tierForAgent,
} from "../src/memory_lifecycle.ts";
import type { AgentProfile } from "../src/profile_cache.ts";

const daysAgoIso = (days: number) =>
  new Date(Date.now() - days * 86_400_000).toISOString();

function makeStrength(
  overrides: Partial<AgentProfile["strengths"][number]> = {}
): AgentProfile["strengths"][number] {
  const now = new Date().toISOString();
  return {
    skill: "test-skill",
    context: "ctx",
    observedCount: 1,
    appliedCount: 0,
    confidence: 0.5,
    lastObservedAt: now,
    lastAppliedAt: now,
    createdAt: now,
    ...overrides,
  };
}

function makeWeakness(
  overrides: Partial<AgentProfile["weaknesses"][number]> = {}
): AgentProfile["weaknesses"][number] {
  const now = new Date().toISOString();
  return {
    pitfall: "test-pitfall",
    impact: "imp",
    observedCount: 1,
    avoidedCount: 0,
    avoidanceScore: 0.5,
    lastObservedAt: now,
    lastAvoidedAt: now,
    createdAt: now,
    ...overrides,
  };
}

function makeProfile(
  overrides: Partial<AgentProfile> = {}
): AgentProfile {
  return {
    agentId: "test-agent",
    version: "1.0",
    strengths: [],
    weaknesses: [],
    contextPatterns: { universal: {}, projectSpecific: {} },
    promptCacheV1: "",
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

// ─── computeScore ──────────────────────────────────────────────────────────

test("computeScore — fresh entry at default affinity ≈ confidence", () => {
  const score = computeScore(
    { confidence: 0.8, lastObservedAt: new Date().toISOString() },
    memoryLifecycleConfig.defaultTopicAffinity
  );
  // decay ≈ 1; weight = 0.5 + 0.5 = 1.0 → score ≈ 0.8
  assert.ok(
    Math.abs(score - 0.8) < 0.005,
    `expected ~0.8, got ${score}`
  );
});

test("computeScore — entry at one half-life decays by e^-1", () => {
  // affinity 0 → τ = 30 days; lastObservedAt 30 days ago → Δt/τ = 1
  const score = computeScore(
    { confidence: 1.0, lastObservedAt: daysAgoIso(30) },
    0
  );
  const expected = Math.exp(-1) * 0.5; // weight = 0.5 + 0 = 0.5
  assert.ok(
    Math.abs(score - expected) < 0.001,
    `expected ~${expected}, got ${score}`
  );
});

test("computeScore — high topic affinity dramatically beats low affinity for same age", () => {
  const lastObservedAt = daysAgoIso(30);
  const lowAff = computeScore({ confidence: 1.0, lastObservedAt }, 0.0);
  const highAff = computeScore({ confidence: 1.0, lastObservedAt }, 1.0);
  // High affinity: τ=60, decay≈exp(-0.5)≈0.607, weight=1.5 → ≈0.91
  // Low affinity:  τ=30, decay≈exp(-1.0)≈0.368, weight=0.5 → ≈0.18
  assert.ok(
    highAff > lowAff * 4,
    `highAff ${highAff} should >> lowAff ${lowAff}`
  );
});

test("computeScore — fresh lastAppliedAt dominates a stale lastObservedAt", () => {
  // Even with a 180-day-old lastObservedAt, a fresh lastAppliedAt should
  // pin the score near full strength — the older field is never consulted.
  const score = computeScore(
    {
      confidence: 1.0,
      lastAppliedAt: daysAgoIso(0),
      lastObservedAt: daysAgoIso(180),
    },
    memoryLifecycleConfig.defaultTopicAffinity
  );
  // decay ≈ 1, weight = 1.0 (default affinity 0.5) → score ≈ 1.0
  assert.ok(
    Math.abs(score - 1.0) < 0.005,
    `expected ~1.0 (precedence picks lastAppliedAt), got ${score}`
  );
});

test("computeScore — weakness path uses avoidanceScore + lastAvoidedAt", () => {
  const score = computeScore({
    avoidanceScore: 0.6,
    lastAvoidedAt: new Date().toISOString(),
    lastObservedAt: daysAgoIso(180), // ignored because lastAvoidedAt is fresher
  });
  assert.ok(
    Math.abs(score - 0.6) < 0.005,
    `expected ~0.6, got ${score}`
  );
});

test("computeScore — entry with no confidence/avoidanceScore returns 0", () => {
  const score = computeScore({
    lastObservedAt: new Date().toISOString(),
  });
  assert.equal(score, 0);
});

// ─── find helpers ──────────────────────────────────────────────────────────

test("findStrength returns matching entry, undefined for miss", () => {
  const profile = makeProfile({
    strengths: [
      makeStrength({ skill: "Async dispatch" }),
      makeStrength({ skill: "Tool gating" }),
    ],
  });
  assert.equal(
    findStrength(profile, "Async dispatch")?.skill,
    "Async dispatch"
  );
  assert.equal(findStrength(profile, "Nothing here"), undefined);
});

test("findWeakness returns matching entry, undefined for miss", () => {
  const profile = makeProfile({
    weaknesses: [makeWeakness({ pitfall: "Flaky retries" })],
  });
  assert.equal(
    findWeakness(profile, "Flaky retries")?.pitfall,
    "Flaky retries"
  );
  assert.equal(findWeakness(profile, "Nope"), undefined);
});

// ─── transient indexes ────────────────────────────────────────────────────

test("buildStrengthIndex — Map shares references; mutations propagate to array", () => {
  const profile = makeProfile({
    strengths: [makeStrength({ skill: "X", confidence: 0.5 })],
  });
  const idx = buildStrengthIndex(profile);
  const entry = idx.get("X");
  assert.ok(entry, "X should be present in index");
  entry!.confidence = 0.9;
  assert.equal(profile.strengths[0].confidence, 0.9);
});

test("buildWeaknessIndex — keys by pitfall, retains all entries", () => {
  const profile = makeProfile({
    weaknesses: [
      makeWeakness({ pitfall: "A" }),
      makeWeakness({ pitfall: "B" }),
    ],
  });
  const idx = buildWeaknessIndex(profile);
  assert.equal(idx.size, 2);
  assert.ok(idx.has("A") && idx.has("B"));
});

// ─── capacity tiers ────────────────────────────────────────────────────────

test("tierForAgent — defaults to sonnet tier", () => {
  assert.deepEqual(tierForAgent("any-id"), CAPACITY_TIERS.sonnet);
});

test("CAPACITY_TIERS — opus > sonnet > haiku across all caps", () => {
  const keys = [
    "topK_strengths",
    "topK_weaknesses",
    "MAX_STRENGTHS",
    "MAX_WEAKNESSES",
  ] as const;
  for (const key of keys) {
    assert.ok(
      CAPACITY_TIERS.opus[key] > CAPACITY_TIERS.sonnet[key],
      `opus.${key} must exceed sonnet.${key}`
    );
    assert.ok(
      CAPACITY_TIERS.sonnet[key] > CAPACITY_TIERS.haiku[key],
      `sonnet.${key} must exceed haiku.${key}`
    );
  }
});
