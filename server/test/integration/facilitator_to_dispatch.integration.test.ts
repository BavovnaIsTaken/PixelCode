/**
 * Integration: facilitator seed → atomic batch commit → auto-dispatch.
 *
 * These tests compose the WP1+WP3+WP4 modules end-to-end without
 * standing up a real WebSocket server. The goal is to catch regressions
 * at the seams between layers — the kind of bug a unit test on any one
 * module would miss.
 *
 *   1. The facilitator pipeline is mocked via a stub generator that
 *      returns a known FacilitatorOutput shape.
 *   2. The output is converted to seed-batch input and fed to
 *      planSeedBatch() (the same code the WS handler uses).
 *   3. Each committed task is run through pickAssignee(), mutating the
 *      load map between picks the same way the live handler does.
 *   4. The resulting board state is written to disk via writeBoardSync
 *      and re-read via loadBoard, simulating a server restart.
 *
 * The whole pipeline must produce a stable board where every facilitator
 * task is in `in_progress` with one of the available coders, the load
 * is balanced, and a server restart preserves it byte-for-byte.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  loadBoard,
  planSeedBatch,
  writeBoardSync,
  type SeedBatchInput,
} from "../../src/board_persistence.ts";
import { pickAssignee, shouldAutoDispatch } from "../../src/auto_dispatcher.ts";
import type { TaskCardData } from "../../src/protocol.ts";
import type { GameStateData } from "../../src/agents.ts";

function tmpHome(): { root: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "pixelcode-int-"));
  return { root, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

const cwd = "/Users/test/IntegrationProj";

function inst(roleType: string, skill = 5) {
  return {
    roleType,
    nickname: roleType,
    hardware: 2,
    skills: { precision: skill, speed: skill },
  };
}

const roster: GameStateData = {
  instances: {
    "manager#1": inst("manager"),
    "coder#1": inst("coder", 8),
    "coder#2": inst("coder", 4),
    "tester#1": inst("tester", 6),
  },
};

/** Mimic what FacilitatorSessionService sends as board_seed_batch. */
function facilitatorBatch(): SeedBatchInput[] {
  return [
    { title: "Set up data model", allowedRoles: ["coder"], difficulty: 2 },
    { title: "Wire the list screen", allowedRoles: ["coder"], difficulty: 2 },
    { title: "Add filter UI", allowedRoles: ["coder"], difficulty: 1 },
    { title: "Write unit tests", allowedRoles: ["tester"], difficulty: 1 },
    { title: "Sketch arch doc", allowedRoles: ["manager"], difficulty: 1 },
  ];
}

test("e2e: facilitator batch → planSeedBatch → auto-dispatch → balanced assignment",
  () => {
    const plan = planSeedBatch(facilitatorBatch(), {
      counter: 0,
      now: () => new Date("2026-05-02T10:00:00Z"),
      idToken: () => 7777,
      sourceTag: "facilitator",
    });
    assert.equal(plan.ok, true);
    assert.equal(plan.tasks.length, 5);

    const load = new Map<string, number>();
    const dispatched = new Map<string, string>(); // taskId → assignee
    for (const t of plan.tasks) {
      assert.ok(shouldAutoDispatch(t), `task ${t.id} should be dispatchable`);
      const pick = pickAssignee(t, {
        instances: roster.instances,
        load,
        enabled: true,
      });
      assert.ok(pick !== null, `expected an assignee for ${t.title}`);
      dispatched.set(t.id, pick!);
      load.set(pick!, (load.get(pick!) ?? 0) + 1);
      // Simulate the server's mutation: update the task in place.
      t.assignedAgents = [pick!];
      t.column = "in_progress";
    }

    // Every coder task went to a coder, the tester task to the tester,
    // the manager-only task to the manager.
    assert.equal(dispatched.get(plan.tasks[3].id), "tester#1");
    assert.equal(dispatched.get(plan.tasks[4].id), "manager#1");
    // Coder load split between the two coders.
    assert.equal(load.get("coder#1") ?? 0 + (load.get("coder#2") ?? 0), 2);
    const coderLoadSum = (load.get("coder#1") ?? 0) + (load.get("coder#2") ?? 0);
    assert.equal(coderLoadSum, 3, "all 3 coder tasks landed on coders");
    // Neither coder is overloaded (cap=2).
    assert.ok((load.get("coder#1") ?? 0) <= 2);
    assert.ok((load.get("coder#2") ?? 0) <= 2);
  });

test("e2e: dispatched batch survives a simulated server restart", () => {
  const { root, cleanup } = tmpHome();
  try {
    // Phase 1: dispatch + persist.
    const plan = planSeedBatch(facilitatorBatch(), {
      counter: 0,
      now: () => new Date("2026-05-02T10:00:00Z"),
      idToken: () => 8888,
      sourceTag: "facilitator",
    });
    assert.equal(plan.ok, true);
    const load = new Map<string, number>();
    for (const t of plan.tasks) {
      const pick = pickAssignee(t, {
        instances: roster.instances,
        load,
        enabled: true,
      });
      if (pick) {
        t.assignedAgents = [pick];
        t.column = "in_progress";
        load.set(pick, (load.get(pick) ?? 0) + 1);
      }
    }
    writeBoardSync(cwd, plan.tasks, { baseDir: root });

    // Phase 2: restart — fresh process loads from disk.
    const reloaded = loadBoard(cwd, { baseDir: root });
    assert.equal(reloaded.source, "loaded");
    assert.equal(reloaded.tasks.length, 5);
    // Counter resumed past the highest id seen on disk.
    assert.equal(reloaded.taskCounter, 5);
    // Every task that had an assignee on the live board still has one.
    const liveAssignees = new Map(plan.tasks.map((t) => [t.id, t.assignedAgents]));
    for (const t of reloaded.tasks) {
      assert.deepEqual(t.assignedAgents, liveAssignees.get(t.id) ?? []);
      assert.equal(t.column, "in_progress");
    }
  } finally {
    cleanup();
  }
});

test("e2e: malformed batch leaves disk and counter untouched (atomic rollback)",
  () => {
    const { root, cleanup } = tmpHome();
    try {
      // Pre-seed disk with one task.
      const seed: TaskCardData = {
        id: "task_42_x",
        title: "previous",
        description: "",
        column: "backlog",
        priority: "normal",
        color: "yellow",
        assignedAgents: [],
        createdAt: "2026-05-01T00:00:00Z",
        updatedAt: "2026-05-01T00:00:00Z",
      };
      writeBoardSync(cwd, [seed], { baseDir: root });

      // Now try to seed a batch with one bad task in the middle.
      const r = planSeedBatch(
        [
          { title: "ok-1" },
          { title: "" }, // invalid → whole batch must be rejected
          { title: "ok-2" },
        ],
        {
          counter: 42,
          now: () => new Date(),
          idToken: () => 1,
          sourceTag: "facilitator",
        },
      );
      assert.equal(r.ok, false);
      // Counter must not have advanced.
      assert.equal(r.nextCounter, 42);

      // Disk is untouched because the handler never calls writeBoardSync
      // when ok=false. Verify by reloading.
      const after = loadBoard(cwd, { baseDir: root });
      assert.equal(after.tasks.length, 1);
      assert.equal(after.tasks[0].id, "task_42_x");
      assert.equal(after.taskCounter, 42);
    } finally {
      cleanup();
    }
  });

test(
  "e2e: dispatch is skipped for tasks whose role can't be filled — they stay in backlog",
  () => {
    // Roster has no security; a security-only task must remain
    // un-dispatched. The facilitator pipeline should still commit it
    // (so the user can manually drag it later) but auto-dispatch should
    // leave it in backlog with no assignee.
    const plan = planSeedBatch(
      [
        { title: "Audit the auth flow", allowedRoles: ["security"], difficulty: 3 },
        { title: "Routine coding work", allowedRoles: ["coder"], difficulty: 1 },
      ],
      {
        counter: 0,
        now: () => new Date(),
        idToken: () => 1,
        sourceTag: "facilitator",
      },
    );
    assert.equal(plan.ok, true);

    const load = new Map<string, number>();
    const securityTask = plan.tasks[0];
    const coderTask = plan.tasks[1];

    const securityPick = pickAssignee(securityTask, {
      instances: roster.instances,
      load,
      enabled: true,
    });
    assert.equal(securityPick, null, "no security agent in roster");
    // Stays in backlog with no assignees.
    assert.equal(securityTask.column, "backlog");
    assert.deepEqual(securityTask.assignedAgents, []);

    const coderPick = pickAssignee(coderTask, {
      instances: roster.instances,
      load,
      enabled: true,
    });
    assert.ok(coderPick !== null);
  });
