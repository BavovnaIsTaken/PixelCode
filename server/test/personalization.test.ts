import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { injectLearnedContext } from "../src/personalization.ts";
import { AgentContextPreparer } from "../src/agent_context.ts";
import {
  ProfileCacheService,
  type AgentProfile,
  type UserProfile,
} from "../src/profile_cache.ts";
import { ChatHistory } from "../src/chat_history.ts";
import { PromptCacheManager } from "../src/prompt_cache_manager.ts";
import { CAPACITY_TIERS } from "../src/memory_lifecycle.ts";

const ARGS = {
  agentId: "a1",
  userId: "u1",
  sessionId: "s1",
  currentProject: "ProjX",
};

// ─── Stubbed-preparer unit tests (pure logic) ──────────────────────────────

test("injectLearnedContext — disabled returns base unchanged AND skips preparer", async () => {
  let prepareCalled = false;
  const stub = {
    prepare: async () => {
      prepareCalled = true;
      return {
        learnedContextFragment: "should not see this",
        cacheKey: "k",
        recentMessages: [],
      };
    },
  } as unknown as AgentContextPreparer;

  const result = await injectLearnedContext(
    "BASE",
    { preparer: stub, enabled: false },
    ARGS
  );

  assert.equal(result, "BASE");
  assert.equal(prepareCalled, false, "preparer must not be called when disabled");
});

test("injectLearnedContext — enabled + non-empty fragment appends with double newline", async () => {
  const stub = {
    prepare: async () => ({
      learnedContextFragment: "## Strengths\n- X",
      cacheKey: "k",
      recentMessages: [],
    }),
  } as unknown as AgentContextPreparer;

  const result = await injectLearnedContext(
    "BASE",
    { preparer: stub, enabled: true },
    ARGS
  );

  assert.equal(result, "BASE\n\n## Strengths\n- X");
});

test("injectLearnedContext — enabled + empty fragment returns base unchanged", async () => {
  const stub = {
    prepare: async () => ({
      learnedContextFragment: "",
      cacheKey: "k",
      recentMessages: [],
    }),
  } as unknown as AgentContextPreparer;

  const result = await injectLearnedContext(
    "BASE",
    { preparer: stub, enabled: true },
    ARGS
  );

  assert.equal(result, "BASE");
});

test("injectLearnedContext — preparer throws → base returned + onError invoked", async () => {
  let captured: unknown = null;
  const stub = {
    prepare: async () => {
      throw new Error("prepare exploded");
    },
  } as unknown as AgentContextPreparer;

  const result = await injectLearnedContext(
    "BASE",
    {
      preparer: stub,
      enabled: true,
      onError: (err) => {
        captured = err;
      },
    },
    ARGS
  );

  assert.equal(result, "BASE", "must fall back to base prompt on error");
  assert.ok(captured instanceof Error);
  assert.match((captured as Error).message, /prepare exploded/);
});

test("injectLearnedContext — preparer throws + no onError → silent fallback (does not throw)", async () => {
  const stub = {
    prepare: async () => {
      throw new Error("oops");
    },
  } as unknown as AgentContextPreparer;

  const result = await injectLearnedContext(
    "BASE",
    { preparer: stub, enabled: true },
    ARGS
  );

  assert.equal(result, "BASE");
});

test("injectLearnedContext — preparer args are forwarded verbatim", async () => {
  let capturedArgs: unknown[] | null = null;
  const stub = {
    prepare: async (...args: unknown[]) => {
      capturedArgs = args;
      return { learnedContextFragment: "F", cacheKey: "k", recentMessages: [] };
    },
  } as unknown as AgentContextPreparer;

  await injectLearnedContext(
    "BASE",
    { preparer: stub, enabled: true },
    {
      agentId: "manager#1",
      userId: "user-42",
      sessionId: "sess-abc",
      currentProject: "/abs/path/to/proj",
    }
  );

  assert.deepEqual(capturedArgs, [
    "manager#1",
    "user-42",
    "sess-abc",
    "/abs/path/to/proj",
  ]);
});

// ─── End-to-end with a real AgentContextPreparer ───────────────────────────

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
    skill: "Async dispatch",
    context: "ctx",
    observedCount: 1,
    appliedCount: 0,
    confidence: 0.7,
    lastObservedAt: now,
    lastAppliedAt: now,
    createdAt: now,
    ...overrides,
  };
}

async function withTempCache<T>(
  body: (cache: ProfileCacheService) => Promise<T>
): Promise<T> {
  const dir = mkdtempSync(join(tmpdir(), "pinj-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("injectLearnedContext — end-to-end with real preparer + populated profile", async () => {
  await withTempCache(async (cache) => {
    const ch = new ChatHistory();
    await cache.saveUserProfile(makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a1");
    profile.strengths = [makeStrength({ skill: "Async dispatch" })];
    await cache.saveAgentProfile(profile);

    const preparer = new AgentContextPreparer(
      ch,
      cache,
      new PromptCacheManager(cache, () => CAPACITY_TIERS.haiku)
    );

    const result = await injectLearnedContext(
      "OUTER_PROMPT",
      { preparer, enabled: true },
      ARGS
    );

    assert.ok(
      result.startsWith("OUTER_PROMPT\n\n"),
      "fragment must be appended after base + double newline"
    );
    assert.match(result, /## Your Learned Strengths/);
    assert.match(result, /Async dispatch/);
  });
});
