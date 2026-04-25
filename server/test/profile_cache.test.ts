import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as zlib from "node:zlib";
import {
  ProfileCacheService,
  type UserProfile,
} from "../src/profile_cache.ts";

const daysAgoIso = (days: number) =>
  new Date(Date.now() - days * 86_400_000).toISOString();

function makeFreshUserProfile(
  topicAffinities: Record<string, number> = {}
): UserProfile {
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
      topicAffinities,
    },
    updatedAt: new Date().toISOString(),
  };
}

async function withTempProfileDir<T>(
  body: (svc: ProfileCacheService) => Promise<T>
): Promise<T> {
  const dir = mkdtempSync(join(tmpdir(), "pc-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("compactProfile drops strengths whose score decayed below threshold", async () => {
  await withTempProfileDir(async (svc) => {
    const userProfile = makeFreshUserProfile();
    const profile = await svc.loadAgentProfile("manager#1");
    profile.strengths = [
      // Fresh, high confidence → score ≈ 0.8
      {
        skill: "fresh",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.8,
        lastObservedAt: daysAgoIso(0),
        lastAppliedAt: daysAgoIso(0),
        createdAt: daysAgoIso(0),
      },
      // Very old + low confidence → score ≪ 0.05
      {
        skill: "stale",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.1,
        lastObservedAt: daysAgoIso(1000),
        lastAppliedAt: daysAgoIso(1000),
        createdAt: daysAgoIso(1000),
      },
    ];
    await svc.saveAgentProfile(profile);

    await svc.compactProfile("manager#1", userProfile);

    const after = await svc.loadAgentProfile("manager#1");
    assert.deepEqual(
      after.strengths.map((s) => s.skill),
      ["fresh"]
    );
  });
});

test("compactProfile drops weaknesses whose score decayed below threshold", async () => {
  await withTempProfileDir(async (svc) => {
    const userProfile = makeFreshUserProfile();
    const profile = await svc.loadAgentProfile("manager#2");
    profile.weaknesses = [
      {
        pitfall: "current",
        impact: "",
        observedCount: 1,
        avoidedCount: 0,
        avoidanceScore: 0.7,
        lastObservedAt: daysAgoIso(0),
        lastAvoidedAt: daysAgoIso(0),
        createdAt: daysAgoIso(0),
      },
      {
        pitfall: "ancient",
        impact: "",
        observedCount: 1,
        avoidedCount: 0,
        avoidanceScore: 0.1,
        lastObservedAt: daysAgoIso(1000),
        lastAvoidedAt: daysAgoIso(1000),
        createdAt: daysAgoIso(1000),
      },
    ];
    await svc.saveAgentProfile(profile);

    await svc.compactProfile("manager#2", userProfile);

    const after = await svc.loadAgentProfile("manager#2");
    assert.deepEqual(
      after.weaknesses.map((w) => w.pitfall),
      ["current"]
    );
  });
});

test("generatePromptCache ranks recent low-confidence above ancient high-confidence", async () => {
  await withTempProfileDir(async (svc) => {
    const userProfile = makeFreshUserProfile();
    const profile = await svc.loadAgentProfile("manager#3");
    profile.strengths = [
      {
        skill: "fresh-low",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.6,
        lastObservedAt: daysAgoIso(0),
        lastAppliedAt: daysAgoIso(0),
        createdAt: daysAgoIso(0),
      },
      {
        skill: "old-high",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 1.0,
        lastObservedAt: daysAgoIso(365),
        lastAppliedAt: daysAgoIso(365),
        createdAt: daysAgoIso(365),
      },
    ];

    const compressed = await svc.generatePromptCache(
      userProfile,
      profile,
      "PixelCode"
    );
    const json = zlib
      .gunzipSync(Buffer.from(compressed, "base64"))
      .toString("utf-8");
    const parsed = JSON.parse(json);

    assert.equal(parsed.topStrengths[0].skill, "fresh-low");
    assert.equal(parsed.topStrengths[1].skill, "old-high");
  });
});

test("generatePromptCache does not mutate caller's strengths array order", async () => {
  await withTempProfileDir(async (svc) => {
    const userProfile = makeFreshUserProfile();
    const profile = await svc.loadAgentProfile("manager#4");
    profile.strengths = [
      {
        skill: "A",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.3,
        lastObservedAt: daysAgoIso(0),
        lastAppliedAt: daysAgoIso(0),
        createdAt: daysAgoIso(0),
      },
      {
        skill: "B",
        context: "",
        observedCount: 1,
        appliedCount: 0,
        confidence: 0.9,
        lastObservedAt: daysAgoIso(0),
        lastAppliedAt: daysAgoIso(0),
        createdAt: daysAgoIso(0),
      },
    ];

    await svc.generatePromptCache(userProfile, profile, "PixelCode");

    assert.deepEqual(
      profile.strengths.map((s) => s.skill),
      ["A", "B"],
      "original array order must be preserved (no in-place sort)"
    );
  });
});
