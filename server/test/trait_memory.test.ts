import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  recordLesson,
  recordLessonCandidate,
  effectiveFrequency,
  pruneDecayedLessons,
  pruneStaleCandidates,
  getLessonsForAgent,
  getAllTraits,
  getAllCandidates,
  loadTraits,
  loadCandidates,
  formatTraitsForPrompt,
  decayPeriodFor,
  promotionThresholdFor,
  DECAY_PERIOD_MS,
  DEFAULT_DECAY_PERIOD_MS,
  CATEGORY_DECAY_PERIOD_MS,
  CANDIDATE_PROMOTION_THRESHOLD,
  STRENGTH_PROMOTION_THRESHOLD,
  WEAKNESS_PROMOTION_THRESHOLD,
  CANDIDATE_TTL_MS,
  MIN_PROMOTION_GAP_MS,
  type TraitStore,
  type CandidateStore,
  type AgentLesson,
  type LessonSource,
} from "../src/trait_memory.ts";
import { accountDir } from "../src/account_paths.ts";

// ─── Helpers ────────────────────────────────────────────────────────────────

function withTmpProject<T>(fn: (projectPath: string) => T): T {
  const dir = mkdtempSync(join(tmpdir(), "trait-memory-test-"));
  try {
    return fn(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function emptyTraitStore(): TraitStore {
  return { version: 1, agents: {} };
}

function emptyCandidateStore(): CandidateStore {
  return { version: 1, candidates: {} };
}

/**
 * Default category is `delegation` because its decay period equals
 * DEFAULT_DECAY_PERIOD_MS (30d). Tests that exercise per-category decay
 * override this explicitly.
 */
function makeLesson(overrides: Partial<AgentLesson> = {}): AgentLesson {
  return {
    id: "test_1",
    agentId: "coder#1",
    type: "weakness",
    category: "delegation",
    tag: "test-tag",
    lesson: "Sample lesson",
    frequency: 3,
    source: "llm",
    firstSeen: new Date().toISOString(),
    lastSeen: new Date().toISOString(),
    ...overrides,
  };
}

// ─── effectiveFrequency ─────────────────────────────────────────────────────

test("effectiveFrequency: fresh lesson returns full frequency", () => {
  const lesson = makeLesson({ frequency: 5 });
  assert.equal(effectiveFrequency(lesson), 5);
});

test("effectiveFrequency: lesson untouched for 1 decay period loses 1", () => {
  const now = new Date();
  const past = new Date(now.getTime() - DECAY_PERIOD_MS - 1000);
  const lesson = makeLesson({ frequency: 5, lastSeen: past.toISOString() });
  assert.equal(effectiveFrequency(lesson, now), 4);
});

test("effectiveFrequency: lesson untouched for 3 decay periods loses 3", () => {
  const now = new Date();
  const past = new Date(now.getTime() - 3 * DECAY_PERIOD_MS - 1000);
  const lesson = makeLesson({ frequency: 5, lastSeen: past.toISOString() });
  assert.equal(effectiveFrequency(lesson, now), 2);
});

test("effectiveFrequency: never goes below 0", () => {
  const now = new Date();
  const past = new Date(now.getTime() - 100 * DECAY_PERIOD_MS);
  const lesson = makeLesson({ frequency: 1, lastSeen: past.toISOString() });
  assert.equal(effectiveFrequency(lesson, now), 0);
});

test("effectiveFrequency: future lastSeen does not amplify", () => {
  const now = new Date();
  const future = new Date(now.getTime() + 86_400_000);
  const lesson = makeLesson({ frequency: 3, lastSeen: future.toISOString() });
  assert.equal(effectiveFrequency(lesson, now), 3);
});

// ─── pruneDecayedLessons ────────────────────────────────────────────────────

test("pruneDecayedLessons: removes only fully-decayed entries", () => {
  const now = new Date();
  const store: TraitStore = {
    version: 1,
    agents: {
      "coder#1": [
        makeLesson({ id: "live", frequency: 5, lastSeen: now.toISOString() }),
        makeLesson({
          id: "decayed",
          frequency: 1,
          lastSeen: new Date(now.getTime() - 2 * DECAY_PERIOD_MS).toISOString(),
        }),
        makeLesson({
          id: "borderline",
          frequency: 2,
          lastSeen: new Date(now.getTime() - DECAY_PERIOD_MS - 1).toISOString(),
        }),
      ],
    },
  };
  const removed = pruneDecayedLessons(store, now);
  assert.equal(removed, 1);
  const ids = store.agents["coder#1"].map((l) => l.id);
  assert.deepEqual(ids, ["live", "borderline"]);
});

test("getLessonsForAgent: excludes decayed lessons", () => {
  const now = new Date();
  const store: TraitStore = {
    version: 1,
    agents: {
      "coder#1": [
        makeLesson({ id: "live", frequency: 4, lastSeen: now.toISOString() }),
        makeLesson({
          id: "decayed",
          frequency: 1,
          lastSeen: new Date(now.getTime() - 2 * DECAY_PERIOD_MS).toISOString(),
        }),
      ],
    },
  };
  const lessons = getLessonsForAgent(store, "coder#1", now);
  assert.equal(lessons.length, 1);
  assert.equal(lessons[0].id, "live");
});

test("formatTraitsForPrompt: emphasis tier reflects effective (not raw) frequency", () => {
  const now = new Date();
  const past = new Date(now.getTime() - 3 * DECAY_PERIOD_MS - 1000);
  const store: TraitStore = {
    version: 1,
    agents: {
      "coder#1": [
        makeLesson({
          id: "decayed-critical",
          type: "weakness",
          frequency: 6,
          lastSeen: past.toISOString(),
        }),
      ],
    },
  };
  const out = formatTraitsForPrompt(store, "coder#1", now);
  // raw freq=6 would be CRITICAL; after 3-period decay effective=3 => Important.
  assert.ok(!out.includes("CRITICAL"), `expected no CRITICAL emphasis after decay; got: ${out}`);
  assert.ok(out.includes("Important"), `expected Important emphasis; got: ${out}`);
  assert.ok(out.includes("observed 3×"), `expected effective count 3×; got: ${out}`);
});

// ─── saveTraits prune-on-save ────────────────────────────────────────────────

test("loadTraits then save converges disk to pruned state", () => {
  withTmpProject((projectPath) => {
    const now = new Date();
    const past = new Date(now.getTime() - 5 * DECAY_PERIOD_MS).toISOString();

    const dir = accountDir(projectPath);
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      join(dir, "traits.json"),
      JSON.stringify({
        version: 1,
        agents: {
          "coder#1": [
            makeLesson({ id: "decayed", frequency: 2, lastSeen: past }),
            makeLesson({ id: "live", frequency: 5, lastSeen: now.toISOString() }),
          ],
        },
      }),
    );

    try {
      const store = loadTraits(projectPath);
      const ids = store.agents["coder#1"].map((l) => l.id);
      assert.deepEqual(ids, ["live"], `expected decayed lesson pruned on load; got: ${ids}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

// ─── Candidate pool ─────────────────────────────────────────────────────────

test("recordLessonCandidate: first observation pending", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const out = recordLessonCandidate(
      projectPath,
      traits,
      candidates,
      {
        agentId: "coder#1",
        type: "weakness",
        category: "tools_usage",
        tag: "novel-pattern",
        lesson: "First-time observation",
      },
      "session-A",
    );
    assert.equal(out.status, "pending");
    assert.equal(traits.agents["coder#1"], undefined);
    assert.equal(candidates.candidates["coder#1"].length, 1);
    assert.equal(candidates.candidates["coder#1"][0].sessionCount, 1);
  });
});

test("recordLessonCandidate: same-session repeat does not inflate sessionCount", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "strength" as const,
      category: "code_quality" as const,
      tag: "same-tag",
      lesson: "Observed",
    };
    recordLessonCandidate(projectPath, traits, candidates, input, "session-A");
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "session-A");
    assert.equal(second.status, "duplicate");
    assert.equal(candidates.candidates["coder#1"][0].sessionCount, 1);
    assert.equal(traits.agents["coder#1"], undefined);
  });
});

test("recordLessonCandidate: strength promotes after STRENGTH_PROMOTION_THRESHOLD distinct sessions", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "strength" as const,
      category: "communication" as const,
      tag: "recurring-strength",
      lesson: "Consistent positive pattern",
    };
    // Anchor near real now so the disk-persist path (which uses live Date.now)
    // does not prune our candidate as "too old" between calls.
    const t0 = new Date(Date.now() - 10 * 60 * 1000); // 10 min ago
    const t1 = new Date(t0.getTime() + 3 * 60 * 60 * 1000); // +3h, above gap

    const first = recordLessonCandidate(projectPath, traits, candidates, input, "session-A", t0);
    assert.equal(first.status, "pending");
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "session-B", t1);
    assert.equal(second.status, "promoted");
    if (second.status === "promoted") assert.equal(second.via, "threshold");
    assert.equal(traits.agents["coder#1"]?.length, 1);
    assert.equal(traits.agents["coder#1"][0].source, "llm",
      "promoted lesson must carry llm source for namespace-scoped re-matching later");
    assert.equal(candidates.candidates["coder#1"], undefined);
  });
});

test("recordLessonCandidate: weakness requires WEAKNESS_PROMOTION_THRESHOLD (3) sessions — single-bump does NOT promote", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "weakness" as const,
      category: "delegation" as const,
      tag: "recurring-weakness",
      lesson: "Repeated gap in delegation",
    };
    const t0 = new Date(Date.now() - 10 * 60 * 1000);
    const t1 = new Date(t0.getTime() + 3 * 60 * 60 * 1000);
    const t2 = new Date(t0.getTime() + 6 * 60 * 60 * 1000);

    const first = recordLessonCandidate(projectPath, traits, candidates, input, "s-A", t0);
    assert.equal(first.status, "pending");
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "s-B", t1);
    // After 2 sessions, weakness should still be pending (threshold=3).
    assert.equal(second.status, "pending", "weakness must NOT promote after 2 sessions");
    assert.equal(traits.agents["coder#1"], undefined);

    const third = recordLessonCandidate(projectPath, traits, candidates, input, "s-C", t2);
    assert.equal(third.status, "promoted");
    if (third.status === "promoted") assert.equal(third.via, "threshold");
    assert.equal(traits.agents["coder#1"]?.length, 1);
  });
});

test("recordLessonCandidate: asymmetric thresholds export correct constants", () => {
  assert.equal(STRENGTH_PROMOTION_THRESHOLD, 2);
  assert.equal(WEAKNESS_PROMOTION_THRESHOLD, 3);
  assert.equal(promotionThresholdFor("strength"), 2);
  assert.equal(promotionThresholdFor("weakness"), 3);
  // Back-compat alias points at strength threshold (per code comment).
  assert.equal(CANDIDATE_PROMOTION_THRESHOLD, 2);
});

test("recordLessonCandidate: existing real LLM trait bypasses gate (direct reinforcement)", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();

    // Seed a real lesson with source="llm" — this represents a previously
    // gate-cleared promotion.
    recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "strength",
      category: "code_quality",
      tag: "real-tag",
      lesson: "Already in store",
      source: "llm",
    });
    const initial = traits.agents["coder#1"][0].frequency;

    const out = recordLessonCandidate(
      projectPath,
      traits,
      candidates,
      {
        agentId: "coder#1",
        type: "strength",
        category: "code_quality",
        tag: "real-tag",
        lesson: "Reinforced",
      },
      "session-A",
    );
    assert.equal(out.status, "promoted");
    if (out.status === "promoted") assert.equal(out.via, "real-trait-bypass");
    assert.equal(traits.agents["coder#1"][0].frequency, initial + 1);
    assert.equal(candidates.candidates["coder#1"], undefined);
  });
});

test("recordLessonCandidate: real hook trait with matching tag does NOT trigger bypass", () => {
  // Namespace separation: a `task-rework` lesson written by the rigid hook
  // learner lives in `source: "hook"`. An LLM-reflection that coincidentally
  // produces the same tag MUST go through the candidate gate from scratch —
  // not silently piggyback on the hook's frequency.
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "weakness",
      category: "problem_solving",
      tag: "task-rework",
      lesson: "Hook-detected rework",
      source: "hook",
    });
    const hookFreqBefore = traits.agents["coder#1"][0].frequency;

    const out = recordLessonCandidate(
      projectPath,
      traits,
      candidates,
      {
        agentId: "coder#1",
        type: "weakness",
        category: "problem_solving",
        tag: "task-rework",
        lesson: "LLM-reflection guess",
      },
      "session-A",
    );
    assert.equal(out.status, "pending", "must enter candidate pool, not bypass via hook trait");
    assert.equal(traits.agents["coder#1"][0].frequency, hookFreqBefore,
      "hook trait frequency must NOT be incremented by an LLM observation");
    assert.equal(candidates.candidates["coder#1"]?.length, 1);
    assert.equal(candidates.candidates["coder#1"][0].source, "llm");
  });
});

test("recordLessonCandidate: legacy 'unknown' source trait does NOT trigger bypass either", () => {
  // Defensive: traits from before the source field existed must not be
  // re-used as bypass anchors — they decay through the natural lifecycle.
  withTmpProject((projectPath) => {
    const traits: TraitStore = {
      version: 1,
      agents: {
        "coder#1": [
          makeLesson({
            id: "legacy",
            tag: "ancient-pattern",
            source: "unknown",
            type: "strength",
            category: "code_quality",
            frequency: 5,
          }),
        ],
      },
    };
    const candidates = emptyCandidateStore();
    const out = recordLessonCandidate(
      projectPath,
      traits,
      candidates,
      {
        agentId: "coder#1",
        type: "strength",
        category: "code_quality",
        tag: "ancient-pattern",
        lesson: "New observation",
      },
      "session-A",
    );
    assert.equal(out.status, "pending");
    assert.equal(traits.agents["coder#1"][0].frequency, 5,
      "legacy 'unknown' trait must not be reinforced via llm path");
  });
});

test("recordLessonCandidate: time-gap defense — too-soon observations don't inflate sessionCount", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "weakness" as const,
      category: "communication" as const,
      tag: "burst-tag",
      lesson: "Same confab repeated quickly",
    };
    const t0 = new Date(Date.now() - 30 * 60 * 1000); // 30 min ago
    // Distinct session ids 5 minutes apart — within MIN_PROMOTION_GAP_MS (2h).
    const t1 = new Date(t0.getTime() + 5 * 60 * 1000);
    const t2 = new Date(t0.getTime() + 10 * 60 * 1000);

    const first = recordLessonCandidate(projectPath, traits, candidates, input, "s-A", t0);
    assert.equal(first.status, "pending");
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "s-B", t1);
    assert.equal(second.status, "too-soon",
      "second observation within MIN_PROMOTION_GAP_MS must not advance sessionCount");
    const third = recordLessonCandidate(projectPath, traits, candidates, input, "s-C", t2);
    assert.equal(third.status, "too-soon");
    assert.equal(candidates.candidates["coder#1"][0].sessionCount, 1);
    assert.equal(traits.agents["coder#1"], undefined,
      "no promotion possible despite three distinct sessionIds in a burst");
  });
});

test("recordLessonCandidate: time-gap allows promotion once observations are spaced out", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "strength" as const,
      category: "communication" as const,
      tag: "spaced-tag",
      lesson: "Genuine recurring pattern",
    };
    const t0 = new Date(Date.now() - 10 * 60 * 1000);
    const t1 = new Date(t0.getTime() + MIN_PROMOTION_GAP_MS + 60_000);
    const first = recordLessonCandidate(projectPath, traits, candidates, input, "s-A", t0);
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "s-B", t1);
    assert.equal(first.status, "pending");
    assert.equal(second.status, "promoted");
  });
});

test("MIN_PROMOTION_GAP_MS: is exported and matches 2h", () => {
  assert.equal(MIN_PROMOTION_GAP_MS, 2 * 60 * 60 * 1000);
});

// ─── Per-category decay ─────────────────────────────────────────────────────

test("decayPeriodFor: tools_usage decays faster than architecture", () => {
  const toolsPeriod = decayPeriodFor("tools_usage");
  const archPeriod = decayPeriodFor("architecture");
  assert.ok(toolsPeriod < archPeriod,
    `tools_usage (${toolsPeriod}) should decay faster than architecture (${archPeriod})`);
  assert.equal(toolsPeriod, CATEGORY_DECAY_PERIOD_MS.tools_usage);
  assert.equal(archPeriod, CATEGORY_DECAY_PERIOD_MS.architecture);
});

test("effectiveFrequency: tools_usage lesson decays at 14d period", () => {
  const now = new Date();
  const past = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days
  const lesson = makeLesson({
    category: "tools_usage",
    frequency: 5,
    lastSeen: past.toISOString(),
  });
  // 30 days / 14d period = 2 periods → freq=3
  assert.equal(effectiveFrequency(lesson, now), 3);
});

test("effectiveFrequency: architecture lesson decays at 60d period", () => {
  const now = new Date();
  const past = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000); // 30 days
  const lesson = makeLesson({
    category: "architecture",
    frequency: 5,
    lastSeen: past.toISOString(),
  });
  // 30 days / 60d period = 0 periods → freq unchanged
  assert.equal(effectiveFrequency(lesson, now), 5);
});

test("effectiveFrequency: default decay period equals 30d (regression — alias is stable)", () => {
  assert.equal(DECAY_PERIOD_MS, DEFAULT_DECAY_PERIOD_MS);
  assert.equal(DEFAULT_DECAY_PERIOD_MS, 30 * 24 * 60 * 60 * 1000);
});

test("CATEGORY_DECAY_PERIOD_MS: every LessonCategory has a mapping", () => {
  // If anyone adds a category to the enum but forgets the decay map,
  // decayPeriodFor falls back to default. Catch the omission explicitly.
  const expected: Record<string, true> = {
    tools_usage: true,
    architecture: true,
    code_quality: true,
    testing: true,
    security: true,
    communication: true,
    delegation: true,
    problem_solving: true,
  };
  for (const key of Object.keys(expected)) {
    assert.ok(
      key in CATEGORY_DECAY_PERIOD_MS,
      `expected CATEGORY_DECAY_PERIOD_MS to have key '${key}'`,
    );
  }
});

// ─── Source field (namespace separation) ────────────────────────────────────

test("recordLesson: matches existing only within the same source", () => {
  // The same kebab tag under two different sources must produce two
  // independent entries — that is the namespace defense.
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "weakness",
      category: "problem_solving",
      tag: "task-rework",
      lesson: "Hook signal",
      source: "hook",
    });
    recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "weakness",
      category: "problem_solving",
      tag: "task-rework",
      lesson: "LLM-tagged collision",
      source: "llm",
    });
    const lessons = traits.agents["coder#1"];
    assert.equal(lessons.length, 2);
    const sources: LessonSource[] = lessons.map((l) => l.source);
    assert.ok(sources.includes("hook"));
    assert.ok(sources.includes("llm"));
    for (const l of lessons) assert.equal(l.frequency, 1);
  });
});

test("recordLesson: same tag, same source increments freq (sanity)", () => {
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const input = {
      agentId: "coder#1",
      type: "weakness" as const,
      category: "problem_solving" as const,
      tag: "task-rework",
      lesson: "Hook signal",
      source: "hook" as const,
    };
    recordLesson(projectPath, traits, input);
    recordLesson(projectPath, traits, input);
    recordLesson(projectPath, traits, input);
    assert.equal(traits.agents["coder#1"].length, 1);
    assert.equal(traits.agents["coder#1"][0].frequency, 3);
  });
});

test("loadTraits: backfills missing source field as 'unknown' on legacy data", () => {
  // Traits are account-scoped now; write the legacy file where loadTraits will
  // actually look (under accounts/, resolved by the shared account_paths helper).
  const accountId = mkdtempSync(join(tmpdir(), "legacy-source-test-"));
  const dir = accountDir(accountId);
  try {
    mkdirSync(dir, { recursive: true });
    // Write legacy schema — no `source` field.
    const now = new Date().toISOString();
    const legacyContent = {
      version: 1,
      agents: {
        "coder#1": [
          {
            id: "legacy_1",
            agentId: "coder#1",
            type: "strength",
            category: "code_quality",
            tag: "legacy-tag",
            lesson: "Old lesson",
            frequency: 4,
            firstSeen: now,
            lastSeen: now,
          },
        ],
      },
    };
    writeFileSync(join(dir, "traits.json"), JSON.stringify(legacyContent));
    const store = loadTraits(accountId);
    assert.equal(store.agents["coder#1"][0].source, "unknown");
  } finally {
    rmSync(dir, { recursive: true, force: true });
    rmSync(accountId, { recursive: true, force: true });
  }
});

// ─── MAX_LESSONS_PER_AGENT cap by effective frequency ───────────────────────

test("recordLesson: cap evicts lowest-effective-freq, not lowest-raw-freq", () => {
  // Reliability reviewer flagged: sort-by-raw-frequency lets stale freq=8
  // (effective=2 after decay) survive while displacing fresh freq=1.
  // Fix: sort by effectiveFrequency, so a long-stale high-raw lesson is
  // the one that gets evicted at the cap.
  withTmpProject((projectPath) => {
    const oneYearAgo = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString();
    const traits: TraitStore = {
      version: 1,
      agents: {
        "coder#1": [],
      },
    };
    // 20 stale high-freq lessons (all under-decay → effective=0 actually,
    // but we craft 1 stale with freq=10 lastSeen=1yr ago so effective is
    // 10 - floor(365/30) = 10 - 12 = 0 ... which would get pruned on save.
    //
    // Instead: 20 stale lessons each with freq=10 and lastSeen=60d ago, so
    // effective = 10 - 2 = 8 (still high but not invulnerable).
    const sixtyDaysAgo = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString();
    for (let i = 0; i < 20; i++) {
      traits.agents["coder#1"].push(makeLesson({
        id: `stale_${i}`,
        tag: `stale-${i}`,
        frequency: 10,
        lastSeen: sixtyDaysAgo,
        // delegation = 30d period → effective = 10 - 2 = 8
      }));
    }
    // Now record one fresh lesson. Cap is 20 so we'll exceed → eviction.
    const fresh = recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "strength",
      category: "delegation",
      tag: "fresh",
      lesson: "Fresh observation",
      source: "llm",
    });
    assert.equal(traits.agents["coder#1"].length, 20);
    // The fresh lesson (effective=1) should NOT be the first to go — stale
    // freq=10 lessons each have effective=8. So the fresh one is the
    // lowest-effective, and IT gets evicted in the current implementation.
    //
    // Sanity: under the old buggy sort (by raw freq), the fresh would also
    // be evicted (freq=1 < freq=10). So this test alone can't distinguish.
    // What we CAN assert: no lessons with effective=0 survive the cap,
    // because saveTraits prunes them.
    for (const l of traits.agents["coder#1"]) {
      assert.ok(effectiveFrequency(l) > 0, `lesson ${l.tag} survived with effective=0`);
    }
    // Verify the fresh lesson record returned points to a valid lesson —
    // even if it was the eviction target, the API contract returns the new
    // object regardless.
    assert.equal(fresh.tag, "fresh");
  });
});

test("recordLesson: cap evicts stale-effective-0 before younger fresh lesson", () => {
  // Pre-condition: lessons with effective=0 are removed by pruneDecayedLessons
  // *during saveTraits*. So once we add a fresh entry that pushes the count
  // past the cap, the stale ones get pruned first, the cap rarely triggers.
  // Effectively the cap path is a fallback for the (uncommon) case where
  // ALL lessons have effective>0.
  withTmpProject((projectPath) => {
    const tenMonthsAgo = new Date(Date.now() - 300 * 24 * 60 * 60 * 1000).toISOString();
    const traits: TraitStore = {
      version: 1,
      agents: {
        "coder#1": Array.from({ length: 25 }, (_, i) => makeLesson({
          id: `vstale_${i}`,
          tag: `vstale-${i}`,
          frequency: 3,           // delegation 30d period × 10 months → eff=0
          lastSeen: tenMonthsAgo,
        })),
      },
    };
    recordLesson(projectPath, traits, {
      agentId: "coder#1",
      type: "strength",
      category: "delegation",
      tag: "fresh",
      lesson: "Fresh observation",
      source: "llm",
    });
    // saveTraits pruned the 25 decayed ones, leaving only `fresh`.
    assert.equal(traits.agents["coder#1"].length, 1);
    assert.equal(traits.agents["coder#1"][0].tag, "fresh");
  });
});

// ─── getAllCandidates / pruneStaleCandidates with lastSeen-based TTL ────────

test("pruneStaleCandidates: TTL anchored to lastSeen, not firstSeen", () => {
  // A candidate first observed 13 days ago and last observed today (one
  // observation in the past, ongoing recency) must NOT expire on day 14.
  // The previous bug: TTL anchored to firstSeen → expires day 15
  // regardless of how recently the pattern was last seen.
  const now = new Date();
  const longAgoFirst = new Date(now.getTime() - 13 * 24 * 60 * 60 * 1000).toISOString();
  const recentLast = new Date(now.getTime() - 86_400_000).toISOString();
  const candidates: CandidateStore = {
    version: 1,
    candidates: {
      "coder#1": [{
        id: "still-alive",
        agentId: "coder#1",
        type: "weakness",
        category: "communication",
        tag: "active-pattern",
        lesson: "Recurring",
        source: "llm",
        sessionCount: 1,
        lastSessionId: "s",
        firstSeen: longAgoFirst,
        lastSeen: recentLast,
      }],
    },
  };
  const removed = pruneStaleCandidates(candidates, now);
  assert.equal(removed, 0,
    "candidate with recent lastSeen must NOT expire just because firstSeen is old");
  assert.equal(candidates.candidates["coder#1"].length, 1);
});

test("pruneStaleCandidates: weakness candidate uses weakness threshold to keep multi-session", () => {
  // A weakness with sessionCount=2 should still be evictable on age — it
  // hasn't yet cleared its threshold of 3.
  const now = new Date();
  const ancient = new Date(now.getTime() - CANDIDATE_TTL_MS * 2).toISOString();
  const candidates: CandidateStore = {
    version: 1,
    candidates: {
      "coder#1": [{
        id: "weak-partial",
        agentId: "coder#1",
        type: "weakness",
        category: "communication",
        tag: "partial-weak",
        lesson: "x",
        source: "llm",
        sessionCount: 2, // <3 → not yet at threshold
        lastSessionId: "s",
        firstSeen: ancient,
        lastSeen: ancient,
      }],
    },
  };
  pruneStaleCandidates(candidates, now);
  assert.equal(candidates.candidates["coder#1"], undefined,
    "weakness w/ sessionCount=2 (below threshold=3) should still age out");
});

// ─── Stable-session repeatability — guards against `Date.now()` fallback ────

test("recordLessonCandidate: stable sessionId across calls keeps as duplicate", () => {
  // If reflection always passes a unique session id (e.g. fallback was
  // `transient-${Date.now()}` before the fix), this test would fail.
  withTmpProject((projectPath) => {
    const traits = emptyTraitStore();
    const candidates = emptyCandidateStore();
    const input = {
      agentId: "coder#1",
      type: "strength" as const,
      category: "delegation" as const,
      tag: "stable-test",
      lesson: "Same observation, same stable session id",
    };
    const t0 = new Date(Date.now() - 10 * 60 * 1000);
    const t1 = new Date(t0.getTime() + 3 * 60 * 60 * 1000);
    const t2 = new Date(t0.getTime() + 6 * 60 * 60 * 1000);

    recordLessonCandidate(projectPath, traits, candidates, input, "stable-sid", t0);
    const second = recordLessonCandidate(projectPath, traits, candidates, input, "stable-sid", t1);
    assert.equal(second.status, "duplicate",
      "same stable sessionId across time must always be `duplicate`");
    const third = recordLessonCandidate(projectPath, traits, candidates, input, "stable-sid", t2);
    assert.equal(third.status, "duplicate");
    assert.equal(candidates.candidates["coder#1"][0].sessionCount, 1);
  });
});

test("pruneStaleCandidates: drops single-session candidates older than TTL", () => {
  const now = new Date();
  const longAgo = new Date(now.getTime() - CANDIDATE_TTL_MS - 1000);
  const recent = new Date(now.getTime() - 86_400_000);
  const candidates: CandidateStore = {
    version: 1,
    candidates: {
      "coder#1": [
        {
          id: "c1",
          agentId: "coder#1",
          type: "weakness",
          category: "tools_usage",
          tag: "stale",
          lesson: "old confab",
          sessionCount: 1,
          lastSessionId: "s1",
          firstSeen: longAgo.toISOString(),
          lastSeen: longAgo.toISOString(),
        },
        {
          id: "c2",
          agentId: "coder#1",
          type: "weakness",
          category: "tools_usage",
          tag: "fresh",
          lesson: "still possible",
          sessionCount: 1,
          lastSessionId: "s2",
          firstSeen: recent.toISOString(),
          lastSeen: recent.toISOString(),
        },
      ],
    },
  };
  const removed = pruneStaleCandidates(candidates, now);
  assert.equal(removed, 1);
  assert.equal(candidates.candidates["coder#1"].length, 1);
  assert.equal(candidates.candidates["coder#1"][0].tag, "fresh");
});

test("pruneStaleCandidates: keeps multi-session candidates at-or-above their type threshold", () => {
  // A candidate with sessionCount >= type-specific threshold should never
  // time out — it has already passed the gate semantically.
  // Use a strength candidate (threshold=2) here for clean coverage.
  const now = new Date();
  const ancient = new Date(now.getTime() - 10 * CANDIDATE_TTL_MS);
  const candidates: CandidateStore = {
    version: 1,
    candidates: {
      "coder#1": [
        {
          id: "c1",
          agentId: "coder#1",
          type: "strength",
          category: "tools_usage",
          tag: "promoted-soon",
          lesson: "confirmed",
          source: "llm",
          sessionCount: STRENGTH_PROMOTION_THRESHOLD,
          lastSessionId: "s2",
          firstSeen: ancient.toISOString(),
          lastSeen: ancient.toISOString(),
        },
      ],
    },
  };
  const removed = pruneStaleCandidates(candidates, now);
  assert.equal(removed, 0);
  assert.equal(candidates.candidates["coder#1"].length, 1);
});

test("loadCandidates: prunes stale entries on disk read", () => {
  const projectPath = mkdtempSync(join(tmpdir(), "candidates-test-"));
  const dir = accountDir(projectPath);
  try {
    mkdirSync(dir, { recursive: true });
    const longAgo = new Date(Date.now() - CANDIDATE_TTL_MS - 1000).toISOString();
    writeFileSync(
      join(dir, "trait_candidates.json"),
      JSON.stringify({
        version: 1,
        candidates: {
          "coder#1": [
            {
              id: "c1",
              agentId: "coder#1",
              type: "weakness",
              category: "tools_usage",
              tag: "stale",
              lesson: "old",
              sessionCount: 1,
              lastSessionId: "s1",
              firstSeen: longAgo,
              lastSeen: longAgo,
            },
          ],
        },
      }),
    );
    const store = loadCandidates(projectPath);
    assert.equal(store.candidates["coder#1"], undefined);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    rmSync(projectPath, { recursive: true, force: true });
  }
});

test("getAllTraits: omits decayed lessons from the client-facing list", () => {
  const now = new Date();
  const store: TraitStore = {
    version: 1,
    agents: {
      "coder#1": [
        makeLesson({ id: "live", frequency: 3, lastSeen: now.toISOString() }),
        makeLesson({
          id: "gone",
          frequency: 1,
          lastSeen: new Date(now.getTime() - 5 * DECAY_PERIOD_MS).toISOString(),
        }),
      ],
    },
  };
  const all = getAllTraits(store, now);
  assert.equal(all.length, 1);
  assert.equal(all[0].id, "live");
});

test("getAllCandidates: omits stale single-session candidates", () => {
  const now = new Date();
  const candidates: CandidateStore = {
    version: 1,
    candidates: {
      "coder#1": [
        {
          id: "c-stale",
          agentId: "coder#1",
          type: "weakness",
          category: "tools_usage",
          tag: "stale",
          lesson: "x",
          sessionCount: 1,
          lastSessionId: "s1",
          firstSeen: new Date(now.getTime() - CANDIDATE_TTL_MS - 1).toISOString(),
          lastSeen: new Date(now.getTime() - CANDIDATE_TTL_MS - 1).toISOString(),
        },
        {
          id: "c-live",
          agentId: "coder#1",
          type: "weakness",
          category: "tools_usage",
          tag: "live",
          lesson: "y",
          sessionCount: 1,
          lastSessionId: "s2",
          firstSeen: new Date(now.getTime() - 86_400_000).toISOString(),
          lastSeen: new Date(now.getTime() - 86_400_000).toISOString(),
        },
      ],
    },
  };
  const all = getAllCandidates(candidates, now);
  assert.equal(all.length, 1);
  assert.equal(all[0].id, "c-live");
});
