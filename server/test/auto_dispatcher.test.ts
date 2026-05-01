import { test } from "node:test";
import assert from "node:assert/strict";
import {
  MAX_AGENT_LOAD,
  pickAssignee,
  shouldAutoDispatch,
} from "../src/auto_dispatcher.ts";
import type { TaskCardData } from "../src/protocol.ts";
import type { GameStateData } from "../src/agents.ts";

function makeTask(overrides: Partial<TaskCardData> = {}): TaskCardData {
  return {
    id: "task_1",
    title: "do the thing",
    description: "",
    column: "backlog",
    priority: "normal",
    color: "yellow",
    assignedAgents: [],
    createdAt: "2026-05-02T00:00:00.000Z",
    updatedAt: "2026-05-02T00:00:00.000Z",
    ...overrides,
  };
}

function makeInst(
  roleType: string,
  skills: Record<string, number> = {},
): GameStateData["instances"][string] {
  return { roleType, nickname: roleType, hardware: 2, skills };
}

const ctx = (
  instances: GameStateData["instances"],
  load: Record<string, number> = {},
  enabled = true,
) => ({ instances, load: new Map(Object.entries(load)), enabled });

// ─── pickAssignee — happy paths ──────────────────────────────────────

test("pickAssignee — single eligible candidate is chosen", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx({ "coder#1": makeInst("coder") }),
  );
  assert.equal(id, "coder#1");
});

test("pickAssignee — empty allowedRoles means any role is fine", () => {
  // Tasks without allowedRoles should land on whoever is free; first by
  // skill / id sort.
  const id = pickAssignee(
    makeTask({ allowedRoles: [] }),
    ctx({ "manager#1": makeInst("manager"), "coder#1": makeInst("coder") }),
  );
  assert.ok(id !== null);
});

test("pickAssignee — picks lowest current load among eligible", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx(
      {
        "coder#1": makeInst("coder", { precision: 5 }),
        "coder#2": makeInst("coder", { precision: 5 }),
        "coder#3": makeInst("coder", { precision: 5 }),
      },
      { "coder#1": 1, "coder#2": 0, "coder#3": 1 },
    ),
  );
  assert.equal(id, "coder#2");
});

test("pickAssignee — ties broken by total skill (highest wins)", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx({
      "coder#1": makeInst("coder", { precision: 1, speed: 1 }), // total 2
      "coder#2": makeInst("coder", { precision: 5, speed: 4 }), // total 9
      "coder#3": makeInst("coder", { precision: 3, speed: 3 }), // total 6
    }),
  );
  assert.equal(id, "coder#2");
});

test("pickAssignee — final tiebreak is instanceId so picks are deterministic", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx({
      "coder#z": makeInst("coder", { p: 5 }),
      "coder#a": makeInst("coder", { p: 5 }),
    }),
  );
  // localeCompare: "a" < "z"
  assert.equal(id, "coder#a");
});

// ─── pickAssignee — rejection paths ──────────────────────────────────

test("pickAssignee — returns null when no role matches", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["security"] }),
    ctx({ "coder#1": makeInst("coder"), "tester#1": makeInst("tester") }),
  );
  assert.equal(id, null);
});

test("pickAssignee — returns null when allowedRoles asks for manager but roster has none", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["manager"] }),
    ctx({ "coder#1": makeInst("coder") }),
  );
  assert.equal(id, null);
});

test(`pickAssignee — returns null when every candidate is at the load cap (${MAX_AGENT_LOAD})`, () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx(
      {
        "coder#1": makeInst("coder"),
        "coder#2": makeInst("coder"),
      },
      { "coder#1": MAX_AGENT_LOAD, "coder#2": MAX_AGENT_LOAD + 5 },
    ),
  );
  assert.equal(id, null);
});

test("pickAssignee — returns null when disabled", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx({ "coder#1": makeInst("coder") }, {}, false),
  );
  assert.equal(id, null);
});

test("pickAssignee — returns null when task is already assigned", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"], assignedAgents: ["coder#1"] }),
    ctx({ "coder#1": makeInst("coder"), "coder#2": makeInst("coder") }),
  );
  assert.equal(id, null);
});

test("pickAssignee — returns null when roster is empty", () => {
  const id = pickAssignee(makeTask({ allowedRoles: ["coder"] }), ctx({}));
  assert.equal(id, null);
});

test("pickAssignee — load cap is per-agent, not global; one capped agent doesn't poison others", () => {
  const id = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    ctx(
      {
        "coder#1": makeInst("coder"),
        "coder#2": makeInst("coder"),
      },
      { "coder#1": MAX_AGENT_LOAD },
    ),
  );
  assert.equal(id, "coder#2");
});

// ─── pickAssignee — sequential dispatch (no real race in event loop) ──

test("pickAssignee — sequential picks update load to spread work", () => {
  // Simulating two consecutive board_create_task calls: caller bumps the
  // load between picks. We expect both coders to get one task each.
  const instances = {
    "coder#1": makeInst("coder", { p: 5 }),
    "coder#2": makeInst("coder", { p: 4 }),
  };
  const load = new Map<string, number>();
  const id1 = pickAssignee(
    makeTask({ allowedRoles: ["coder"] }),
    { instances, load, enabled: true },
  );
  assert.equal(id1, "coder#1"); // higher skill wins on tie load=0

  load.set(id1!, (load.get(id1!) ?? 0) + 1);

  const id2 = pickAssignee(
    makeTask({ id: "task_2", allowedRoles: ["coder"] }),
    { instances, load, enabled: true },
  );
  assert.equal(id2, "coder#2"); // coder#1 now has load=1, coder#2 has 0
});

// ─── shouldAutoDispatch ──────────────────────────────────────────────

test("shouldAutoDispatch — facilitator-tagged backlog task with no assignees → true", () => {
  assert.equal(
    shouldAutoDispatch(
      makeTask({ taskType: "facilitator", column: "backlog", assignedAgents: [] }),
    ),
    true,
  );
});

test("shouldAutoDispatch — manually-tagged tasks are not touched", () => {
  for (const taskType of [undefined, "coding", "review", "testing", "facilitatorlike"]) {
    assert.equal(
      shouldAutoDispatch(
        makeTask({ taskType, column: "backlog", assignedAgents: [] }),
      ),
      false,
      `expected false for taskType=${String(taskType)}`,
    );
  }
});

test("shouldAutoDispatch — non-backlog facilitator tasks are skipped", () => {
  for (const column of ["in_progress", "testing", "done"] as const) {
    assert.equal(
      shouldAutoDispatch(
        makeTask({ taskType: "facilitator", column, assignedAgents: [] }),
      ),
      false,
    );
  }
});

test("shouldAutoDispatch — already-assigned facilitator tasks are skipped", () => {
  assert.equal(
    shouldAutoDispatch(
      makeTask({
        taskType: "facilitator",
        column: "backlog",
        assignedAgents: ["coder#1"],
      }),
    ),
    false,
  );
});
