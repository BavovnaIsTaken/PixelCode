import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  LessonExtractor,
  type Lesson,
} from "../src/lesson_extractor.ts";
import {
  ProfileCacheService,
  type UserProfile,
} from "../src/profile_cache.ts";
import { CAPACITY_TIERS } from "../src/memory_lifecycle.ts";

const daysAgoIso = (days: number) =>
  new Date(Date.now() - days * 86_400_000).toISOString();

function makeFreshUserProfile(): UserProfile {
  return {
    userId: "test-user",
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

async function withTempCache<T>(
  body: (cache: ProfileCacheService) => Promise<T>
): Promise<T> {
  const dir = mkdtempSync(join(tmpdir(), "le-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ─── extractLessons ────────────────────────────────────────────────────────

test("extractLessons — pattern 1 (async dispatch success)", () => {
  const lessons = new LessonExtractor().extractLessons({
    action: "dispatch",
    result: "success",
    taskCount: 4,
  });
  assert.equal(lessons.length, 1);
  assert.equal(lessons[0].category, "strength");
  assert.equal(lessons[0].title, "Async dispatch effectiveness");
  assert.match(lessons[0].context, /4 tasks/);
});

test("extractLessons — pattern 2 (avoided tool-check pitfall)", () => {
  const lessons = new LessonExtractor().extractLessons({
    avoided: "tool-check",
  });
  assert.equal(lessons.length, 1);
  assert.equal(lessons[0].category, "strength");
  assert.equal(lessons[0].title, "Tool availability verification");
});

test("extractLessons — pattern 3 (error + recovery → weakness)", () => {
  const lessons = new LessonExtractor().extractLessons({
    error: "Tool not available",
    recovery: "Used Task tool instead",
  });
  assert.equal(lessons.length, 1);
  assert.equal(lessons[0].category, "weakness");
  assert.equal(lessons[0].title, "Tool not available");
  assert.match(lessons[0].context, /Used Task tool/);
});

test("extractLessons — empty payload returns []", () => {
  const lessons = new LessonExtractor().extractLessons({});
  assert.deepEqual(lessons, []);
});

test("extractLessons — combined payload yields multiple lessons", () => {
  const lessons = new LessonExtractor().extractLessons({
    action: "dispatch",
    result: "success",
    taskCount: 2,
    avoided: "tool-check",
    error: "Network timeout",
    recovery: "Retried with backoff",
  });
  assert.equal(lessons.length, 3);
  const categories = lessons.map((l) => l.category).sort();
  assert.deepEqual(categories, ["strength", "strength", "weakness"]);
});

test("extractLessons — error without recovery does not fire pattern 3", () => {
  const lessons = new LessonExtractor().extractLessons({
    error: "Network timeout",
  });
  assert.equal(lessons.length, 0);
});

// ─── applyLessons ──────────────────────────────────────────────────────────

test("applyLessons — adds a new strength with all lifecycle fields", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    const lesson: Lesson = {
      category: "strength",
      title: "X",
      context: "ctx",
      confidence: 0.85,
    };

    await extractor.applyLessons("agent#1", [lesson], makeFreshUserProfile());

    const profile = await cache.loadAgentProfile("agent#1");
    assert.equal(profile.strengths.length, 1);
    const s = profile.strengths[0];
    assert.equal(s.skill, "X");
    assert.equal(s.confidence, 0.85);
    assert.equal(s.observedCount, 1);
    assert.equal(s.appliedCount, 0);
    assert.ok(s.lastObservedAt);
    assert.ok(s.lastAppliedAt);
    assert.ok(s.createdAt);
  });
});

test("applyLessons — reinforces existing strength (observedCount++, boost, timestamp)", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    const userProfile = makeFreshUserProfile();
    const lesson: Lesson = {
      category: "strength",
      title: "X",
      context: "ctx",
      confidence: 0.5,
    };

    await extractor.applyLessons("a", [lesson], userProfile);
    const beforeTs = (await cache.loadAgentProfile("a")).strengths[0]
      .lastObservedAt;
    // Force a millisecond gap so timestamps differ.
    await new Promise((r) => setTimeout(r, 5));
    await extractor.applyLessons("a", [lesson], userProfile);

    const profile = await cache.loadAgentProfile("a");
    assert.equal(profile.strengths.length, 1, "no duplicate entry");
    assert.equal(profile.strengths[0].observedCount, 2);
    // 0.5 + 0.05 boost (confidenceObserveBoost) = 0.55
    assert.ok(Math.abs(profile.strengths[0].confidence - 0.55) < 1e-9);
    assert.ok(
      new Date(profile.strengths[0].lastObservedAt).getTime() >
        new Date(beforeTs).getTime(),
      "lastObservedAt must advance"
    );
  });
});

test("applyLessons — clamps confidence at 1.0 across many reinforcements", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    const userProfile = makeFreshUserProfile();
    const lesson: Lesson = {
      category: "strength",
      title: "X",
      context: "ctx",
      confidence: 0.85,
    };

    // 30 reinforcements: 0.85 + 29 × 0.05 = 2.30 (would overflow without clamp)
    for (let i = 0; i < 30; i++) {
      await extractor.applyLessons("a", [lesson], userProfile);
    }

    const profile = await cache.loadAgentProfile("a");
    assert.equal(profile.strengths.length, 1);
    assert.equal(profile.strengths[0].confidence, 1.0);
    assert.equal(profile.strengths[0].observedCount, 30);
  });
});

test("applyLessons — adds and reinforces weaknesses analogously", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    const userProfile = makeFreshUserProfile();
    const lesson: Lesson = {
      category: "weakness",
      title: "Flaky retries",
      context: "Backed off and retried",
      confidence: 0.6,
    };

    await extractor.applyLessons("a", [lesson], userProfile);
    await extractor.applyLessons("a", [lesson], userProfile);

    const profile = await cache.loadAgentProfile("a");
    assert.equal(profile.weaknesses.length, 1);
    const w = profile.weaknesses[0];
    assert.equal(w.pitfall, "Flaky retries");
    assert.equal(w.observedCount, 2);
    assert.ok(Math.abs(w.avoidanceScore - 0.65) < 1e-9);
    assert.equal(w.avoidedCount, 0);
  });
});

test("applyLessons — empty lessons array is a no-op", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache);
    await extractor.applyLessons("a", [], makeFreshUserProfile());
    const profile = await cache.loadAgentProfile("a");
    assert.equal(profile.strengths.length, 0);
    assert.equal(profile.weaknesses.length, 0);
  });
});

test("applyLessons — evicts the lowest-scored entry when over MAX_STRENGTHS", async () => {
  await withTempCache(async (cache) => {
    // Use haiku tier (MAX_STRENGTHS=30) so we don't have to push 76 entries.
    const extractor = new LessonExtractor(cache, () => CAPACITY_TIERS.haiku);
    const userProfile = makeFreshUserProfile();
    const now = new Date().toISOString();

    const profile = await cache.loadAgentProfile("a");
    // 29 fresh, high-confidence entries
    for (let i = 0; i < 29; i++) {
      profile.strengths.push({
        skill: `fresh-${i}`,
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.9,
        lastObservedAt: now,
        lastAppliedAt: now,
        createdAt: now,
      });
    }
    // 1 ancient, low-confidence entry — guaranteed lowest score
    profile.strengths.push({
      skill: "ancient",
      context: "",
      observedCount: 1,
      appliedCount: 0,
      confidence: 0.2,
      lastObservedAt: daysAgoIso(1000),
      lastAppliedAt: daysAgoIso(1000),
      createdAt: daysAgoIso(1000),
    });
    await cache.saveAgentProfile(profile);

    // Adding a 31st entry pushes us over → eviction kicks in.
    await extractor.applyLessons(
      "a",
      [
        {
          category: "strength",
          title: "newcomer",
          context: "",
          confidence: 0.85,
        },
      ],
      userProfile
    );

    const after = await cache.loadAgentProfile("a");
    assert.equal(after.strengths.length, 30, "must be capped at MAX_STRENGTHS");
    assert.ok(
      !after.strengths.some((s) => s.skill === "ancient"),
      "ancient entry should be evicted"
    );
    assert.ok(
      after.strengths.some((s) => s.skill === "newcomer"),
      "newcomer should remain"
    );
  });
});

test("applyLessons — evicts the lowest-scored entry when over MAX_WEAKNESSES", async () => {
  await withTempCache(async (cache) => {
    const extractor = new LessonExtractor(cache, () => CAPACITY_TIERS.haiku);
    const userProfile = makeFreshUserProfile();
    const now = new Date().toISOString();

    const profile = await cache.loadAgentProfile("a");
    for (let i = 0; i < 29; i++) {
      profile.weaknesses.push({
        pitfall: `fresh-w-${i}`,
        impact: "",
        observedCount: 1,
        avoidedCount: 0,
        avoidanceScore: 0.9,
        lastObservedAt: now,
        lastAvoidedAt: now,
        createdAt: now,
      });
    }
    profile.weaknesses.push({
      pitfall: "ancient-w",
      impact: "",
      observedCount: 1,
      avoidedCount: 0,
      avoidanceScore: 0.2,
      lastObservedAt: daysAgoIso(1000),
      lastAvoidedAt: daysAgoIso(1000),
      createdAt: daysAgoIso(1000),
    });
    await cache.saveAgentProfile(profile);

    await extractor.applyLessons(
      "a",
      [
        {
          category: "weakness",
          title: "newcomer-w",
          context: "",
          confidence: 0.7,
        },
      ],
      userProfile
    );

    const after = await cache.loadAgentProfile("a");
    assert.equal(after.weaknesses.length, 30);
    assert.ok(!after.weaknesses.some((w) => w.pitfall === "ancient-w"));
    assert.ok(after.weaknesses.some((w) => w.pitfall === "newcomer-w"));
  });
});
