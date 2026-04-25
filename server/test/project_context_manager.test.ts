import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ProjectContextManager } from "../src/project_context_manager.ts";
import {
  ProfileCacheService,
  type AgentProfile,
} from "../src/profile_cache.ts";

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

function makeWeakness(
  overrides: Partial<AgentProfile["weaknesses"][number]> = {}
): AgentProfile["weaknesses"][number] {
  const now = new Date().toISOString();
  return {
    pitfall: "default",
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
  const dir = mkdtempSync(join(tmpdir(), "proj-test-"));
  try {
    return await body(new ProfileCacheService(dir));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ─── migrateProfileToNewProject ────────────────────────────────────────────

test("migrate — drops old project's context, initializes new one as {}", async () => {
  await withTempCache(async (cache) => {
    const profile = await cache.loadAgentProfile("a1");
    profile.contextPatterns.projectSpecific["OldProj"] = { rule: "alpha" };
    await cache.saveAgentProfile(profile);

    await new ProjectContextManager(cache).migrateProfileToNewProject(
      "a1",
      "OldProj",
      "NewProj"
    );

    const after = await cache.loadAgentProfile("a1");
    assert.equal(
      after.contextPatterns.projectSpecific["OldProj"],
      undefined,
      "old project context must be removed"
    );
    assert.deepEqual(
      after.contextPatterns.projectSpecific["NewProj"],
      {},
      "new project must be initialized to {}"
    );
  });
});

test("migrate — preserves universal patterns + strengths + weaknesses", async () => {
  await withTempCache(async (cache) => {
    const profile = await cache.loadAgentProfile("a2");
    profile.contextPatterns.universal = { rule: "always-check" };
    profile.contextPatterns.projectSpecific["Proj1"] = { foo: "bar" };
    profile.strengths = [makeStrength({ skill: "Async dispatch" })];
    profile.weaknesses = [makeWeakness({ pitfall: "Flaky retries" })];
    await cache.saveAgentProfile(profile);

    await new ProjectContextManager(cache).migrateProfileToNewProject(
      "a2",
      "Proj1",
      "Proj2"
    );

    const after = await cache.loadAgentProfile("a2");
    assert.deepEqual(after.contextPatterns.universal, { rule: "always-check" });
    assert.equal(after.strengths.length, 1);
    assert.equal(after.strengths[0].skill, "Async dispatch");
    assert.equal(after.weaknesses.length, 1);
    assert.equal(after.weaknesses[0].pitfall, "Flaky retries");
  });
});

test("migrate — does NOT overwrite existing newProject context", async () => {
  await withTempCache(async (cache) => {
    const profile = await cache.loadAgentProfile("a3");
    profile.contextPatterns.projectSpecific["Old"] = { x: 1 };
    profile.contextPatterns.projectSpecific["New"] = { existing: "data" };
    await cache.saveAgentProfile(profile);

    await new ProjectContextManager(cache).migrateProfileToNewProject(
      "a3",
      "Old",
      "New"
    );

    const after = await cache.loadAgentProfile("a3");
    assert.deepEqual(after.contextPatterns.projectSpecific["New"], {
      existing: "data",
    });
  });
});

test("migrate — clears promptCacheV1 to force regeneration", async () => {
  await withTempCache(async (cache) => {
    const profile = await cache.loadAgentProfile("a4");
    profile.promptCacheV1 = "some-cached-blob-base64";
    await cache.saveAgentProfile(profile);

    await new ProjectContextManager(cache).migrateProfileToNewProject(
      "a4",
      "Old",
      "New"
    );

    const after = await cache.loadAgentProfile("a4");
    assert.equal(after.promptCacheV1, "");
  });
});

test("migrate — handles no-prior-state agent gracefully (default profile)", async () => {
  await withTempCache(async (cache) => {
    // No save — agent profile has never been written. Migration must still work.
    await new ProjectContextManager(cache).migrateProfileToNewProject(
      "brand-new",
      "Old",
      "New"
    );

    const after = await cache.loadAgentProfile("brand-new");
    assert.deepEqual(after.contextPatterns.projectSpecific["New"], {});
    assert.equal(after.contextPatterns.projectSpecific["Old"], undefined);
  });
});

// ─── detectProjectChange ───────────────────────────────────────────────────

test("detectProjectChange — same path returns false", () => {
  const mgr = new ProjectContextManager();
  assert.equal(mgr.detectProjectChange("/a/b", "/a/b"), false);
});

test("detectProjectChange — different path returns true", () => {
  const mgr = new ProjectContextManager();
  assert.equal(mgr.detectProjectChange("/a/b", "/x/y"), true);
});
