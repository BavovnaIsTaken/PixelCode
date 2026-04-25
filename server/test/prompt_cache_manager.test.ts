import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { PromptCacheManager } from "../src/prompt_cache_manager.ts";
import {
  ProfileCacheService,
  type AgentProfile,
  type UserProfile,
} from "../src/profile_cache.ts";
import { CAPACITY_TIERS } from "../src/memory_lifecycle.ts";

const daysAgoIso = (days: number) =>
  new Date(Date.now() - days * 86_400_000).toISOString();

function makeFreshUserProfile(userId = "u1"): UserProfile {
  return {
    userId,
    version: "1.0",
    communicationStyle: {
      language: "uk",
      verbosity: "concise",
      technicalLevel: "advanced",
    },
    preferences: {
      parallelizeWork: true,
      preferDelegation: true,
      errorTolerance: "medium",
    },
    globalPatterns: {
      successfulApproaches: [],
      avoidedMistakes: [],
      topicAffinities: {},
    },
    updatedAt: new Date().toISOString(),
  };
}

function makeStrength(
  overrides: Partial<AgentProfile["strengths"][number]> = {}
): AgentProfile["strengths"][number] {
  const now = new Date().toISOString();
  return {
    skill: "default-skill",
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
    pitfall: "default-pitfall",
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

async function withTempCache<T>(
  body: (cache: ProfileCacheService) => Promise<T>
): Promise<T> {
  const dir = mkdtempSync(join(tmpdir(), "pcm-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ─── basics ────────────────────────────────────────────────────────────────

test("buildSystemPrompt — returns systemPrompt + cacheKey", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile("u1"));
    const mgr = new PromptCacheManager(cache);
    const built = await mgr.buildSystemPrompt("a1", "u1", "PixelCode");

    assert.ok(built.systemPrompt.length > 0);
    assert.match(built.systemPrompt, /You are agent: a1/);
    assert.match(built.systemPrompt, /Communication style: uk\/concise/);
    assert.ok(built.cacheKey.startsWith("a1-PixelCode-"));
  });
});

test("buildSystemPrompt — empty profile renders 'None yet' for both lists", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const mgr = new PromptCacheManager(cache);
    const built = await mgr.buildSystemPrompt("a-empty", "u1", "Proj");

    assert.match(built.systemPrompt, /## Your Learned Strengths\nNone yet/);
    assert.match(built.systemPrompt, /## Your Known Weaknesses\nNone yet/);
  });
});

test("buildSystemPrompt — top-K respects tier (haiku=2)", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-tier");
    profile.strengths = [
      makeStrength({ skill: "S1", confidence: 0.9 }),
      makeStrength({ skill: "S2", confidence: 0.8 }),
      makeStrength({ skill: "S3", confidence: 0.7 }),
      makeStrength({ skill: "S4", confidence: 0.6 }),
    ];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    const built = await mgr.buildSystemPrompt("a-tier", "u1", "Proj");

    assert.match(built.systemPrompt, /S1/);
    assert.match(built.systemPrompt, /S2/);
    assert.doesNotMatch(built.systemPrompt, /S3/);
    assert.doesNotMatch(built.systemPrompt, /S4/);
  });
});

// ─── score-based ranking ───────────────────────────────────────────────────

test("buildSystemPrompt — fresh-low ranks above ancient-high (decay-aware)", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-rank");
    profile.strengths = [
      makeStrength({
        skill: "fresh-low",
        confidence: 0.6,
        lastObservedAt: daysAgoIso(0),
        lastAppliedAt: daysAgoIso(0),
      }),
      makeStrength({
        skill: "ancient-high",
        confidence: 1.0,
        lastObservedAt: daysAgoIso(365),
        lastAppliedAt: daysAgoIso(365),
      }),
    ];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    const built = await mgr.buildSystemPrompt("a-rank", "u1", "Proj");

    const idxFresh = built.systemPrompt.indexOf("fresh-low");
    const idxAncient = built.systemPrompt.indexOf("ancient-high");
    assert.ok(idxFresh > -1 && idxAncient > -1);
    assert.ok(
      idxFresh < idxAncient,
      "fresh-low must appear before ancient-high"
    );
  });
});

// ─── apply-boost (spaced repetition) ───────────────────────────────────────

test("buildSystemPrompt — applies spaced-repetition boost to top-K strengths", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-boost");
    profile.strengths = [
      makeStrength({ skill: "selected", confidence: 0.5 }),
      // Push another so we have something not selected at haiku tier (top-K=2 selects both)
    ];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    await mgr.buildSystemPrompt("a-boost", "u1", "Proj");

    const after = await cache.loadAgentProfile("a-boost");
    const s = after.strengths.find((x) => x.skill === "selected")!;
    // 0.5 + 0.10 (confidenceApplyBoost) = 0.60
    assert.ok(Math.abs(s.confidence - 0.6) < 1e-9);
    assert.equal(s.appliedCount, 1);
  });
});

test("buildSystemPrompt — does NOT boost entries outside top-K", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-skip");
    profile.strengths = [
      makeStrength({ skill: "A", confidence: 0.95 }),
      makeStrength({ skill: "B", confidence: 0.9 }),
      makeStrength({ skill: "C", confidence: 0.3 }), // lowest score, won't make haiku top-2
    ];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    await mgr.buildSystemPrompt("a-skip", "u1", "Proj");

    const after = await cache.loadAgentProfile("a-skip");
    const c = after.strengths.find((x) => x.skill === "C")!;
    assert.equal(c.confidence, 0.3, "C should not have been boosted");
    assert.equal(c.appliedCount, 0);
  });
});

test("buildSystemPrompt — apply-boost clamps at 1.0", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-clamp");
    profile.strengths = [makeStrength({ skill: "X", confidence: 0.95 })];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    // Build twice — second build should not push past 1.0
    await mgr.buildSystemPrompt("a-clamp", "u1", "Proj");
    await mgr.buildSystemPrompt("a-clamp", "u1", "Proj");

    const after = await cache.loadAgentProfile("a-clamp");
    assert.equal(after.strengths[0].confidence, 1.0);
    assert.equal(after.strengths[0].appliedCount, 2);
  });
});

test("buildSystemPrompt — applies boost to weaknesses too", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-w");
    profile.weaknesses = [
      makeWeakness({ pitfall: "Flaky retries", avoidanceScore: 0.5 }),
    ];
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku);
    await mgr.buildSystemPrompt("a-w", "u1", "Proj");

    const after = await cache.loadAgentProfile("a-w");
    const w = after.weaknesses[0];
    assert.ok(Math.abs(w.avoidanceScore - 0.6) < 1e-9);
    assert.equal(w.avoidedCount, 1);
  });
});

// ─── project-specific patterns ─────────────────────────────────────────────

test("buildSystemPrompt — renders project-specific patterns when present", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-proj");
    profile.contextPatterns.projectSpecific["PixelCode"] = {
      reviewRule: "always check for typos",
    };
    await cache.saveAgentProfile(profile);

    const mgr = new PromptCacheManager(cache);
    const built = await mgr.buildSystemPrompt("a-proj", "u1", "PixelCode");

    assert.match(built.systemPrompt, /Project-Specific Patterns \(PixelCode\)/);
    assert.match(built.systemPrompt, /always check for typos/);
  });
});

test("buildSystemPrompt — omits project block when no patterns for project", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const mgr = new PromptCacheManager(cache);
    const built = await mgr.buildSystemPrompt("a", "u1", "UnknownProject");

    assert.doesNotMatch(built.systemPrompt, /Project-Specific Patterns/);
  });
});

// ─── cacheKey ──────────────────────────────────────────────────────────────

test("cacheKey — encodes agent + project + loaded updatedAt", async () => {
  await withTempCache(async (cache) => {
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-key");
    profile.updatedAt = "2026-01-01T00:00:00.000Z";
    await cache.saveAgentProfile(profile); // saveAgentProfile bumps updatedAt to now

    const mgr = new PromptCacheManager(cache);
    const built = await mgr.buildSystemPrompt("a-key", "u1", "ProjX");

    // cacheKey reflects the timestamp at LOAD time (which is the "now" set by save above)
    const parts = built.cacheKey.split("-");
    assert.equal(parts[0], "a");
    assert.equal(parts[1], "key");
    assert.equal(parts[2], "ProjX");
    // remaining parts form the ISO timestamp
    const ts = parts.slice(3).join("-");
    assert.ok(!Number.isNaN(new Date(ts).getTime()), `ts looks invalid: ${ts}`);
  });
});
