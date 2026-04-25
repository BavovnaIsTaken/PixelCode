import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AgentContextPreparer } from "../src/agent_context.ts";
import {
  ProfileCacheService,
  type AgentProfile,
  type UserProfile,
} from "../src/profile_cache.ts";
import { PromptCacheManager } from "../src/prompt_cache_manager.ts";
import { CAPACITY_TIERS } from "../src/memory_lifecycle.ts";
import { ChatHistory } from "../src/chat_history.ts";

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
    skill: "default",
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

async function withTempCache<T>(
  body: (cache: ProfileCacheService) => Promise<T>
): Promise<T> {
  const dir = mkdtempSync(join(tmpdir(), "ac-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("prepare — returns fragment + cacheKey + recentMessages", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    ch.add({ sender: "user", text: "hi", timestamp: Date.now() });
    ch.add({ sender: "assistant", text: "hello", timestamp: Date.now() + 1 });

    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a1");
    profile.strengths = [makeStrength({ skill: "Async", confidence: 0.7 })];
    await cache.saveAgentProfile(profile);

    const preparer = new AgentContextPreparer(
      ch,
      cache,
      new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku)
    );
    const ctx = await preparer.prepare("a1", "u1", "s1", "ProjX");

    assert.match(ctx.learnedContextFragment, /## Your Learned Strengths/);
    assert.match(ctx.learnedContextFragment, /Async/);
    // Fragment must NOT include the identity/style block — that's outer prompt's job.
    assert.doesNotMatch(ctx.learnedContextFragment, /You are agent:/);
    assert.ok(ctx.cacheKey.startsWith("a1-ProjX-"));
    assert.equal(ctx.recentMessages.length, 2);
  });
});

test("prepare — apply-boost mutations are persisted to disk", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-boost");
    profile.strengths = [makeStrength({ skill: "X", confidence: 0.5 })];
    await cache.saveAgentProfile(profile);

    const preparer = new AgentContextPreparer(
      ch,
      cache,
      new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku)
    );
    await preparer.prepare("a-boost", "u1", "s1", "Proj");

    const after = await cache.loadAgentProfile("a-boost");
    // 0.5 + 0.10 (confidenceApplyBoost)
    assert.ok(Math.abs(after.strengths[0].confidence - 0.6) < 1e-9);
    assert.equal(after.strengths[0].appliedCount, 1);
  });
});

test("prepare — tokenBudget threads through to chatHistory.getContextMessages", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    // 5 messages × 120 chars ≈ 30 tokens each
    for (let i = 0; i < 5; i++) {
      ch.add({
        sender: "user",
        text: "x".repeat(120),
        timestamp: Date.now() + i,
      });
    }
    await cache.saveUserProfile(makeFreshUserProfile());

    const preparer = new AgentContextPreparer(ch, cache);
    const ctx = await preparer.prepare("a", "u", "s", "P", 60);

    // 60 token budget → at most 2 messages (30 tokens each)
    assert.ok(
      ctx.recentMessages.length >= 1 && ctx.recentMessages.length <= 2,
      `got ${ctx.recentMessages.length} messages for budget 60`
    );
  });
});

test("prepare — empty profile yields 'None yet' fragment, still callable", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    await cache.saveUserProfile(makeFreshUserProfile());

    const preparer = new AgentContextPreparer(ch, cache);
    const ctx = await preparer.prepare("brand-new", "u", "s", "P");

    assert.match(ctx.learnedContextFragment, /Strengths\nNone yet/);
    assert.match(ctx.learnedContextFragment, /Weaknesses\nNone yet/);
    assert.equal(ctx.recentMessages.length, 0);
    assert.ok(ctx.cacheKey.startsWith("brand-new-P-"));
  });
});

test("prepare — cacheKey reflects the profile snapshot at load (pre-boost save)", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a-key");
    profile.strengths = [makeStrength({ skill: "X" })];
    await cache.saveAgentProfile(profile);

    const loadedTs = (await cache.loadAgentProfile("a-key")).updatedAt;

    const preparer = new AgentContextPreparer(
      ch,
      cache,
      new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku)
    );
    const ctx = await preparer.prepare("a-key", "u", "s", "P");

    // cacheKey carries the load-time updatedAt, not whatever save() set after.
    // (Sub-millisecond saves can produce identical timestamps, so we don't
    // assert that updatedAt actually advanced — we only pin the key to the
    // value we read at load time.)
    assert.ok(
      ctx.cacheKey.endsWith(loadedTs),
      `key ${ctx.cacheKey} should end with ${loadedTs}`
    );
  });
});
