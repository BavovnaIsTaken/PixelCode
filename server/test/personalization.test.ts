import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  injectLearnedContext,
  applyLlmLessons,
  type LlmLesson,
} from "../src/personalization.ts";
import { AgentContextPreparer } from "../src/agent_context.ts";
import {
  ProfileCacheService,
  type AgentProfile,
  type UserProfile,
} from "../src/profile_cache.ts";
import { ChatHistory } from "../src/chat_history.ts";
import { PromptCacheManager } from "../src/prompt_cache_manager.ts";
import { CAPACITY_TIERS } from "../src/memory_lifecycle.ts";
import { LessonExtractor } from "../src/lesson_extractor.ts";

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

// ─── applyLlmLessons ───────────────────────────────────────────────────────

test("applyLlmLessons — empty array is a no-op (no I/O)", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await applyLlmLessons([], {
      cache,
      extractor,
      userId: "u1",
    });
    // No throw, no profile saved. Verify no profile was created for any agent.
    const profile = await cache.loadAgentProfile("nobody");
    assert.equal(profile.strengths.length, 0);
    assert.equal(profile.weaknesses.length, 0);
  });
});

test("applyLlmLessons — filters out invalid types and missing fields", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await cache.saveUserProfile(makeFreshUserProfile());

    const lessons: LlmLesson[] = [
      { agentId: "a1", type: "strength", tag: "tag-good", lesson: "ok" },
      { agentId: "a1", type: "neutral", tag: "tag-bad-type", lesson: "x" }, // wrong type
      { agentId: "a1", type: "weakness", tag: "", lesson: "no tag" }, // missing tag
      { agentId: "a1", type: "weakness", tag: "tag", lesson: "" }, // missing lesson
      { agentId: "", type: "strength", tag: "t", lesson: "no agent" }, // missing agentId
    ];

    await applyLlmLessons(lessons, { cache, extractor, userId: "u1" });

    const after = await cache.loadAgentProfile("a1");
    assert.equal(after.strengths.length, 1, "only the valid strength should land");
    assert.equal(after.strengths[0].skill, "tag-good");
    assert.equal(after.weaknesses.length, 0);
  });
});

test("applyLlmLessons — groups by agentId, loads userProfile once, applies per agent", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await cache.saveUserProfile(makeFreshUserProfile());

    const lessons: LlmLesson[] = [
      { agentId: "manager#1", type: "strength", tag: "delegation", lesson: "good calls" },
      { agentId: "coder#1", type: "weakness", tag: "missed-edge", lesson: "off-by-one" },
      { agentId: "manager#1", type: "weakness", tag: "vague-brief", lesson: "underspec" },
    ];

    await applyLlmLessons(lessons, { cache, extractor, userId: "u1" });

    const mgr = await cache.loadAgentProfile("manager#1");
    assert.equal(mgr.strengths.length, 1);
    assert.equal(mgr.strengths[0].skill, "delegation");
    assert.equal(mgr.weaknesses.length, 1);
    assert.equal(mgr.weaknesses[0].pitfall, "vague-brief");

    const coder = await cache.loadAgentProfile("coder#1");
    assert.equal(coder.strengths.length, 0);
    assert.equal(coder.weaknesses.length, 1);
    assert.equal(coder.weaknesses[0].pitfall, "missed-edge");
  });
});

test("applyLlmLessons — initial confidence is 0.7 (per spec baseline)", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await cache.saveUserProfile(makeFreshUserProfile());

    await applyLlmLessons(
      [{ agentId: "a", type: "strength", tag: "t", lesson: "l" }],
      { cache, extractor, userId: "u1" }
    );

    const after = await cache.loadAgentProfile("a");
    assert.equal(after.strengths[0].confidence, 0.7);
  });
});

test("applyLlmLessons — funnels errors through onError, never throws", async () => {
  let captured: unknown = null;

  // Force an error by giving a cache stub that throws on loadUserProfile.
  const exploding = {
    loadUserProfile: async () => {
      throw new Error("disk on fire");
    },
  } as unknown as ProfileCacheService;

  await applyLlmLessons(
    [{ agentId: "a", type: "strength", tag: "t", lesson: "l" }],
    {
      cache: exploding,
      extractor: {} as LessonExtractor,
      userId: "u",
      onError: (err) => {
        captured = err;
      },
    }
  );

  assert.ok(captured instanceof Error);
  assert.match((captured as Error).message, /disk on fire/);
});

test("applyLlmLessons — second invocation reinforces (observedCount++ + confidence boost)", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await cache.saveUserProfile(makeFreshUserProfile());

    const lessons: LlmLesson[] = [
      { agentId: "a", type: "strength", tag: "X", lesson: "first time" },
    ];
    await applyLlmLessons(lessons, { cache, extractor, userId: "u1" });
    await applyLlmLessons(lessons, { cache, extractor, userId: "u1" });

    const after = await cache.loadAgentProfile("a");
    assert.equal(after.strengths.length, 1, "no duplicate entry");
    assert.equal(after.strengths[0].observedCount, 2);
    // 0.7 + 0.05 (confidenceObserveBoost) = 0.75
    assert.ok(Math.abs(after.strengths[0].confidence - 0.75) < 1e-9);
  });
});
