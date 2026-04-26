import { test } from "node:test";
import assert from "node:assert/strict";
import {
  computeScore,
  memoryLifecycleConfig,
  findStrength,
  findWeakness,
  findSimilarStrength,
  findSimilarWeakness,
  tokenJaccard,
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

// ─── tokenJaccard ──────────────────────────────────────────────────────────

test("tokenJaccard — identical strings return 1", () => {
  assert.equal(tokenJaccard("delegation-scope", "delegation-scope"), 1);
});

test("tokenJaccard — fully disjoint strings return 0", () => {
  assert.equal(tokenJaccard("alpha-beta", "gamma-delta"), 0);
});

test("tokenJaccard — partial overlap (1 of 4 unique tokens) = 1/4 = 0.25", () => {
  // {delegation, scope, unclear} ∩ {clear, task, delegation} = {delegation}
  // union = {delegation, scope, unclear, clear, task} = 5 tokens
  // 1/5 = 0.2
  assert.ok(
    Math.abs(tokenJaccard("unclear-delegation-scope", "clear-task-delegation") - 0.2) < 1e-9
  );
});

test("tokenJaccard — synonym variations cross threshold (≥0.5)", () => {
  // {unclear, delegation, scope} vs {vague, delegation, scope}
  // intersect=2, union=4 → 0.5
  const score = tokenJaccard("unclear-delegation-scope", "vague-delegation-scope");
  assert.ok(score >= memoryLifecycleConfig.similarityThreshold);
});

test("tokenJaccard — case-insensitive", () => {
  assert.equal(tokenJaccard("Foo-Bar", "foo-bar"), 1);
});

test("tokenJaccard — handles spaces, hyphens, and underscores as separators", () => {
  assert.equal(tokenJaccard("foo bar", "foo-bar"), 1);
  assert.equal(tokenJaccard("foo_bar", "foo bar"), 1);
});

test("tokenJaccard — token order does not matter (set-based)", () => {
  assert.equal(tokenJaccard("code-quality", "quality-code"), 1);
});

test("tokenJaccard — empty inputs return 0", () => {
  assert.equal(tokenJaccard("", "anything"), 0);
  assert.equal(tokenJaccard("anything", ""), 0);
});

// ─── findSimilarStrength / findSimilarWeakness ─────────────────────────────

test("findSimilarStrength — exact match wins over similar one", () => {
  const profile = makeProfile({
    strengths: [
      makeStrength({ skill: "exact" }),
      makeStrength({ skill: "exact-similar-but-different" }),
    ],
  });
  const found = findSimilarStrength(profile, "exact");
  assert.equal(found?.skill, "exact");
});

test("findSimilarStrength — synonym variation matches above threshold", () => {
  const profile = makeProfile({
    strengths: [makeStrength({ skill: "unclear-delegation-scope" })],
  });
  const found = findSimilarStrength(profile, "vague-delegation-scope");
  assert.equal(found?.skill, "unclear-delegation-scope");
});

test("findSimilarStrength — distant terms return undefined", () => {
  const profile = makeProfile({
    strengths: [makeStrength({ skill: "delegation-scope" })],
  });
  const found = findSimilarStrength(profile, "code-quality-review");
  assert.equal(found, undefined);
});

test("findSimilarStrength — picks the highest-Jaccard candidate", () => {
  // Query: {unclear, delegation, scope}
  // delegation-scope        : intersect=2, union=3 → 0.667 (closer: fewer divergent tokens)
  // vague-delegation-scope  : intersect=2, union=4 → 0.5
  // distant-task-rotation   : intersect=0, union=6 → 0   (below threshold)
  const profile = makeProfile({
    strengths: [
      makeStrength({ skill: "vague-delegation-scope" }),
      makeStrength({ skill: "distant-task-rotation" }),
      makeStrength({ skill: "delegation-scope" }),
    ],
  });
  const found = findSimilarStrength(profile, "unclear-delegation-scope");
  assert.equal(found?.skill, "delegation-scope");
});

test("findSimilarStrength — custom threshold filters out weak matches", () => {
  const profile = makeProfile({
    strengths: [makeStrength({ skill: "delegation-scope" })],
  });
  // Default threshold 0.5 would NOT match (only 2/3 = 0.67 actually does match).
  // With a higher threshold of 0.9, the match is rejected.
  const tight = findSimilarStrength(profile, "vague-delegation-scope", 0.9);
  assert.equal(tight, undefined);
});

test("findSimilarWeakness — same semantics, different field name", () => {
  const profile = makeProfile({
    weaknesses: [makeWeakness({ pitfall: "missing-null-checks" })],
  });
  const found = findSimilarWeakness(profile, "missed-null-check");
  // {missing, null, checks} vs {missed, null, check}
  // intersect = {null} = 1; union = {missing, missed, null, checks, check} = 5
  // = 0.2 — below default 0.5 threshold
  assert.equal(found, undefined);

  // With a lower threshold this should match.
  const loose = findSimilarWeakness(profile, "missed-null-check", 0.15);
  assert.equal(loose?.pitfall, "missing-null-checks");
});

// ─── capacity tiers ────────────────────────────────────────────────────────

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
