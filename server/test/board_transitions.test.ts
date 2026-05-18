import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  advanceOnDispatchSuccess,
  findOrphanActiveCards,
  kSpecializationCritBonus,
} from "../src/board_transitions.js";
import { mulberry32 } from "../src/task_outcome.js";
import type { AgentInstanceData } from "../src/agents.js";
import type { TaskCardData, TaskColumnKey } from "../src/protocol.js";

function makeTask(overrides: Partial<TaskCardData> = {}): TaskCardData {
  return {
    id: "task_1",
    title: "Test task",
    description: "",
    column: "in_progress",
    priority: "normal",
    color: "yellow",
    assignedAgents: ["coder#1"],
    createdAt: new Date(0).toISOString(),
    updatedAt: new Date(0).toISOString(),
    difficulty: 2,
    taskType: "coding",
    ...overrides,
  };
}

function makeAgent(overrides: Partial<AgentInstanceData> = {}): AgentInstanceData {
  return {
    roleType: "coder",
    nickname: "Maistry",
    hardware: 2,
    // speed=0, precision=1, creativity=2, insight=3, reliability=4
    skills: { "0": 5, "1": 10, "2": 5, "3": 5, "4": 15 },
    ...overrides,
  };
}

// ─── Column gating ────────────────────────────────────────────────────────────

describe("advanceOnDispatchSuccess — column gating", () => {
  test("in_progress → testing without rolling", () => {
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "in_progress" }),
      agent: makeAgent(),
      lessonCount: 0,
      rng: () => 0.5,
    });
    assert.equal(decision.nextColumn, "testing");
    assert.equal(decision.changed, true);
    assert.equal(decision.outcome, undefined);
  });

  test("backlog dispatch finish is a no-op (manager beat us to it, or weird state)", () => {
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "backlog" }),
      agent: makeAgent(),
      lessonCount: 0,
      rng: () => 0.5,
    });
    assert.equal(decision.nextColumn, "backlog");
    assert.equal(decision.changed, false);
  });

  test("done dispatch finish is a no-op (manager pushed to done already)", () => {
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "done" }),
      agent: makeAgent(),
      lessonCount: 0,
      rng: () => 0.0,
    });
    assert.equal(decision.nextColumn, "done");
    assert.equal(decision.changed, false);
    assert.equal(decision.outcome, undefined);
  });
});

// ─── testing → ? routing ──────────────────────────────────────────────────────

describe("advanceOnDispatchSuccess — testing → ?", () => {
  test("clean outcome routes to done", () => {
    const task = makeTask({ column: "testing" });
    const decision = advanceOnDispatchSuccess({
      task,
      // precision 15 → bugChance 0; reliability 15 → completionSuccessChance 1.0
      agent: makeAgent({ skills: { "1": 15, "2": 0, "4": 15 } }),
      lessonCount: 0,
      rng: mulberry32(1),
    });
    assert.equal(decision.outcome, "clean");
    assert.equal(decision.nextColumn, "done");
    assert.equal(decision.changed, true);
  });

  test("incomplete outcome routes back to backlog", () => {
    // Force incomplete with a sequence that exceeds adjustedSuccess on first roll
    let i = 0;
    const seq = [0.99, 0.0, 0.0];
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing" }),
      agent: makeAgent({ skills: { "1": 10, "2": 0, "4": 0 } }), // reliability 0 → 0.85 success
      lessonCount: 0,
      rng: () => seq[i++]!,
    });
    assert.equal(decision.outcome, "incomplete");
    assert.equal(decision.nextColumn, "backlog");
  });

  test("bug outcome bounces to in_progress", () => {
    let i = 0;
    const seq = [0.0, 0.0, 0.0]; // pass success, fail bug-check (0.0 < 0.4)
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing" }),
      agent: makeAgent({ skills: { "1": 0, "2": 0, "4": 15 } }), // precision 0 → 0.4 bug
      lessonCount: 0,
      rng: () => seq[i++]!,
    });
    assert.equal(decision.outcome, "bug");
    assert.equal(decision.nextColumn, "in_progress");
  });

  test("crit outcome on divergent task routes to done", () => {
    let i = 0;
    const seq = [0.0, 0.99, 0.0]; // pass success, pass bug-check, crit roll < 1.0
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing", taskType: "architecture" }),
      agent: makeAgent({ skills: { "1": 15, "2": 50, "4": 15 } }),
      lessonCount: 0,
      rng: () => seq[i++]!,
    });
    assert.equal(decision.outcome, "crit");
    assert.equal(decision.nextColumn, "done");
  });
});

// ─── Bonus plumbing — skills sourced from index map ───────────────────────────

describe("advanceOnDispatchSuccess — bonus plumbing", () => {
  test("specializations grant the crit bonus on matching taskType", () => {
    const agent = makeAgent({
      skills: { "1": 15, "2": 0, "4": 15 }, // creativity 0 → base crit chance 0
      specializations: ["architecture"],
    });
    const task = makeTask({ column: "testing", taskType: "architecture" });
    // 0.0 success roll, 0.99 bug skip, 0.0 crit roll < kSpecializationCritBonus.
    let i = 0;
    const seq = [0.0, 0.99, kSpecializationCritBonus - 0.01];
    const decision = advanceOnDispatchSuccess({
      task,
      agent,
      lessonCount: 0,
      rng: () => seq[i++]!,
    });
    assert.equal(decision.outcome, "crit", "specialization bonus should push crit chance above 0");
  });

  test("lessonCount narrows the incomplete gap", () => {
    // reliability 0 → 0.85 base; with 20 lessons → +0.10 → 0.95 success
    // rng() = 0.94 → still passes
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing" }),
      agent: makeAgent({ skills: { "1": 15, "2": 0, "4": 0 } }),
      lessonCount: 20,
      rng: () => 0.94,
    });
    assert.notEqual(decision.outcome, "incomplete");
  });

  test("project memory bonus applies on architecture only", () => {
    const agent = makeAgent({
      skills: { "1": 15, "2": 0, "4": 15 },
      taskCompletionsByType: { coding: 50, review: 25 }, // total 75 → cap 0.15
    });
    // 0.0 success, 0.99 bug skip, 0.14 crit roll.
    // Architecture: crit chance = 0 + 0 + 0.15 = 0.15 → 0.14 < 0.15 → crit
    let i = 0;
    const seqA = [0.0, 0.99, 0.14];
    const archDecision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing", taskType: "architecture" }),
      agent,
      lessonCount: 0,
      rng: () => seqA[i++]!,
    });
    assert.equal(archDecision.outcome, "crit");

    // product-spec gets no memory bonus → crit chance = 0 + 0 = 0 → 0.14 > 0 → no crit
    i = 0;
    const seqB = [0.0, 0.99, 0.14];
    const specDecision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing", taskType: "product-spec" }),
      agent,
      lessonCount: 0,
      rng: () => seqB[i++]!,
    });
    assert.equal(specDecision.outcome, "clean");
  });

  test("missing agent defaults skills to 1 (gracefully)", () => {
    // With precision/reliability=1 the roll still works; verify it doesn't throw.
    const decision = advanceOnDispatchSuccess({
      task: makeTask({ column: "testing" }),
      agent: undefined,
      lessonCount: 0,
      rng: mulberry32(99),
    });
    // Any outcome is fine — pin shape, not value.
    assert.ok(
      ["clean", "crit", "bug", "incomplete"].includes(decision.outcome!),
      `unexpected outcome=${decision.outcome}`,
    );
  });
});

// ─── Orphan reset ─────────────────────────────────────────────────────────────

describe("findOrphanActiveCards", () => {
  function tasks(states: Array<{ id: string; column: TaskColumnKey; assigned: string[] }>): TaskCardData[] {
    return states.map((s) =>
      makeTask({ id: s.id, column: s.column, assignedAgents: s.assigned }),
    );
  }

  test("flags in_progress card with empty assignedAgents", () => {
    const t = tasks([
      { id: "a", column: "in_progress", assigned: [] },
      { id: "b", column: "in_progress", assigned: ["coder#1"] },
    ]);
    assert.deepEqual(findOrphanActiveCards(t), ["a"]);
  });

  test("flags testing card with empty assignedAgents", () => {
    const t = tasks([
      { id: "a", column: "testing", assigned: [] },
      { id: "b", column: "testing", assigned: ["coder#1"] },
    ]);
    assert.deepEqual(findOrphanActiveCards(t), ["a"]);
  });

  test("does NOT flag backlog or done cards (even orphaned)", () => {
    const t = tasks([
      { id: "a", column: "backlog", assigned: [] },
      { id: "b", column: "done", assigned: [] },
    ]);
    assert.deepEqual(findOrphanActiveCards(t), []);
  });

  test("does NOT flag active cards that have an agent", () => {
    const t = tasks([
      { id: "a", column: "in_progress", assigned: ["coder#1"] },
      { id: "b", column: "testing", assigned: ["coder#2"] },
    ]);
    assert.deepEqual(findOrphanActiveCards(t), []);
  });

  test("handles empty iterable", () => {
    assert.deepEqual(findOrphanActiveCards([]), []);
  });
});
