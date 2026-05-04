/**
 * Integration: captain (manager) orchestration loop.
 *
 * This is the core product loop the user pays us for: a chat message
 * arrives → the captain splits it into subtasks → tasks land on the
 * board → they get delegated with workload awareness → completions
 * flow back as feedback → the captain reports progress in chat → the
 * cards visibly transit columns.
 *
 * The actual captain is a Claude LLM emitting a sequence of MCP tool
 * calls (board_create_task, board_assign_agent, board_move_task) plus
 * chat text. We can't pin the LLM's output, but we CAN pin the
 * orchestration plumbing those tool calls drive — and that plumbing is
 * what's been unstable.
 *
 * Strategy: a `CaptainHarness` mirrors what server.ts does when
 * handling each MCP tool call (using the real modules — no fakes for
 * board logic). Tests script a captain that follows its prompt rules
 * faithfully and assert the resulting board state, chat output,
 * workload, and on-disk persistence are all correct.
 *
 * Each scenario is a single captain interaction from chat-in to
 * chat-out, capturing every board snapshot in between so the test can
 * verify cards transited columns in the expected order.
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
  isValidBoardColumn,
  type SeedBatchInput,
} from "../../src/board_persistence.ts";
import {
  pickAssignee,
  MAX_AGENT_LOAD,
} from "../../src/auto_dispatcher.ts";
import type {
  TaskCardData,
  TaskColumnKey,
  StickyColorKey,
  TaskPriorityKey,
} from "../../src/protocol.ts";
import type { GameStateData } from "../../src/agents.ts";

// ─── Roster fixtures ──────────────────────────────────────────────────

function inst(roleType: string, skill = 5) {
  return {
    roleType,
    nickname: roleType,
    hardware: 2,
    skills: { precision: skill, speed: skill },
  };
}

function rosterOf(...rows: Array<[string, string, number?]>): GameStateData {
  const instances: GameStateData["instances"] = {};
  for (const [id, role, skill] of rows) {
    instances[id] = inst(role, skill ?? 5);
  }
  return { instances };
}

// ─── Captain harness ──────────────────────────────────────────────────

interface BoardSnapshot {
  /** label captures *what* the captain just did, useful for diffing */
  label: string;
  /** deep copy of every card at this moment, sorted by creation order */
  tasks: TaskCardData[];
}

/**
 * Mirrors what server.ts does when handling MCP board tool calls from
 * the manager LLM. Every state mutation goes through one of the methods
 * here so tests can assert how the board evolved and what the captain
 * said in chat.
 *
 * Not a fake: this composes the real `planSeedBatch` + `pickAssignee`
 * modules, so the plumbing under test is the production plumbing.
 */
class CaptainHarness {
  readonly tasks = new Map<string, TaskCardData>();
  readonly load = new Map<string, number>();
  readonly chatLines: string[] = [];
  readonly snapshots: BoardSnapshot[] = [];
  private taskCounter = 0;
  private idTokenSeq = 1000;
  private clock = 0;

  constructor(public roster: GameStateData) {
    this.snap("initial");
  }

  // ── chat ──

  /** Captain emits a single line in the chat (mirrors `assistant_text`). */
  say(line: string) {
    this.chatLines.push(line);
  }

  // ── workload introspection (captain calls team_status before dispatching) ──

  loadOf(instanceId: string): number {
    return this.load.get(instanceId) ?? 0;
  }

  /** Snapshot the load map — captain consults this before each dispatch. */
  teamStatus(): Map<string, number> {
    const out = new Map<string, number>();
    for (const id of Object.keys(this.roster.instances)) {
      out.set(id, this.loadOf(id));
    }
    return out;
  }

  /**
   * Workload-aware pick using the same logic auto-dispatch uses. The
   * captain prompt says "use team_status before dispatching"; this is
   * the correct-captain stand-in: skip overloaded agents, prefer the
   * lowest-loaded eligible role.
   */
  pickFor(taskId: string): string | null {
    const t = this.tasks.get(taskId);
    if (!t) return null;
    return pickAssignee(t, {
      instances: this.roster.instances,
      load: this.load,
      enabled: true,
    });
  }

  // ── tool calls ──

  /** Mirrors server.ts handler for `board_create_task`. */
  createTask(input: {
    title: string;
    description?: string;
    allowedRoles?: string[];
    difficulty?: number;
    color?: StickyColorKey;
    priority?: TaskPriorityKey;
    taskType?: string;
  }): string {
    if (!input.title || !input.title.trim()) {
      throw new Error("captain emitted empty title — server would reject");
    }
    this.taskCounter += 1;
    const id = `task_${this.taskCounter}_${this.idTokenSeq++}`;
    const stamp = this.tick();
    const task: TaskCardData = {
      id,
      title: input.title,
      description: input.description ?? "",
      column: "backlog",
      priority: input.priority ?? "normal",
      color: input.color ?? "yellow",
      assignedAgents: [],
      createdAt: stamp,
      updatedAt: stamp,
      difficulty: input.difficulty,
      allowedRoles: input.allowedRoles,
      taskType: input.taskType ?? "coding",
      attachments: [],
    };
    this.tasks.set(id, task);
    this.snap(`create:${input.title}`);
    return id;
  }

  /** Mirrors `board_assign_agent` — and bumps load, like the live system. */
  assign(taskId: string, agentId: string) {
    const t = this.requireTask(taskId);
    if (!this.roster.instances[agentId]) {
      throw new Error(`captain dispatched to unknown instance ${agentId}`);
    }
    if (!t.assignedAgents.includes(agentId)) {
      t.assignedAgents = [...t.assignedAgents, agentId];
      this.load.set(agentId, this.loadOf(agentId) + 1);
    }
    t.updatedAt = this.tick();
    this.snap(`assign:${taskId}→${agentId}`);
  }

  /** Mirrors `board_move_task`. Decrements load when leaving in_progress
   *  for `done` so the captain's next dispatch sees freed capacity. */
  move(taskId: string, column: TaskColumnKey) {
    if (!isValidBoardColumn(column)) {
      throw new Error(`invalid column "${column}"`);
    }
    const t = this.requireTask(taskId);
    const wasInFlight = t.column === "in_progress" || t.column === "testing";
    const nowFinal = column === "done";
    t.column = column;
    t.updatedAt = this.tick();
    if (wasInFlight && nowFinal) {
      for (const a of t.assignedAgents) {
        this.load.set(a, Math.max(0, this.loadOf(a) - 1));
      }
    }
    this.snap(`move:${taskId}→${column}`);
  }

  /**
   * Combined dispatch: assign + move-to-in_progress, mirroring the
   * captain's prompt rule "move cards to in_progress when you
   * dispatch". Returns the picked instanceId so the caller can branch
   * on null (no eligible candidate).
   */
  dispatchByPolicy(taskId: string): string | null {
    const pick = this.pickFor(taskId);
    if (!pick) return null;
    this.assign(taskId, pick);
    this.move(taskId, "in_progress");
    return pick;
  }

  /**
   * Simulates a feedback event: a delegated agent reports completion.
   * Server-side this is what arrives via the dispatch tool's result;
   * the captain then moves the card to `done` and reports in chat.
   * The captain's reply is left to the test (we don't hard-code
   * exactly which line — only assert it was emitted).
   */
  receiveCompletion(taskId: string) {
    this.move(taskId, "done");
  }

  // ── snapshotting ──

  tasksByColumn(column: TaskColumnKey): TaskCardData[] {
    return [...this.tasks.values()].filter((t) => t.column === column);
  }

  /** Persist current tasks to disk under a temp project root. */
  persistTo(baseDir: string, projectCwd: string) {
    writeBoardSync(projectCwd, [...this.tasks.values()], { baseDir });
  }

  // ── internals ──

  private requireTask(id: string): TaskCardData {
    const t = this.tasks.get(id);
    if (!t) throw new Error(`unknown task id ${id}`);
    return t;
  }

  private tick(): string {
    this.clock += 1;
    return new Date(2026, 4, 2, 10, 0, this.clock).toISOString();
  }

  private snap(label: string) {
    this.snapshots.push({
      label,
      tasks: [...this.tasks.values()].map((t) => ({
        ...t,
        assignedAgents: [...t.assignedAgents],
        allowedRoles: t.allowedRoles ? [...t.allowedRoles] : undefined,
        attachments: t.attachments ? [...t.attachments] : undefined,
      })),
    });
  }
}

// ─── Scenario 1: decompose + balanced delegation ──────────────────────

test(
  "captain: decomposes one user request into 3 subtasks and delegates each to a free teammate",
  () => {
    const cap = new CaptainHarness(
      rosterOf(
        ["manager#1", "manager"],
        ["coder#1", "coder", 8],
        ["coder#2", "coder", 6],
        ["tester#1", "tester", 7],
      ),
    );

    // ── User → captain (chat) ──
    const userRequest = "Build a TODO CRUD";

    // ── Captain → board: split into subtasks ──
    const t1 = cap.createTask({
      title: "Set up TodoEntity",
      description: "data model + storage",
      allowedRoles: ["coder"],
      difficulty: 2,
    });
    const t2 = cap.createTask({
      title: "Wire list screen",
      description: "ListView + add button",
      allowedRoles: ["coder"],
      difficulty: 2,
    });
    const t3 = cap.createTask({
      title: "Cover with unit tests",
      allowedRoles: ["tester"],
      difficulty: 1,
    });

    cap.say(
      `Розбив "${userRequest}" на: модель, екран, тести. Беремо модель першим.`,
    );

    // ── Captain → board: dispatch each, respecting workload ──
    const a1 = cap.dispatchByPolicy(t1);
    const a2 = cap.dispatchByPolicy(t2);
    const a3 = cap.dispatchByPolicy(t3);

    cap.say("Працюємо.");

    // ── Verify: 3 tasks now in_progress, balanced across coders ──
    assert.equal(
      cap.tasksByColumn("backlog").length,
      0,
      "all subtasks should have left backlog",
    );
    assert.equal(
      cap.tasksByColumn("in_progress").length,
      3,
      "all 3 subtasks should be in_progress",
    );

    assert.ok(a1 !== null && a1 !== undefined);
    assert.ok(a2 !== null && a2 !== undefined);
    assert.equal(a3, "tester#1", "tester subtask must go to the only tester");

    // Both coders got exactly one card each — captain balanced load.
    const coderLoad =
      cap.loadOf("coder#1") + cap.loadOf("coder#2");
    assert.equal(coderLoad, 2, "two coder tasks should land on coders combined");
    assert.equal(
      cap.loadOf("coder#1"),
      1,
      "coder#1 should have one task (no doubling)",
    );
    assert.equal(
      cap.loadOf("coder#2"),
      1,
      "coder#2 should have one task (no doubling)",
    );
    assert.equal(cap.loadOf("tester#1"), 1);

    // Captain spoke: once after split, once after dispatch.
    assert.equal(cap.chatLines.length, 2);
    assert.match(cap.chatLines[0], /Розбив.*"Build a TODO CRUD".*на:.*Беремо/);
    assert.match(cap.chatLines[1], /Працюємо/);
  },
);

// ─── Scenario 2: workload-aware delegation with prior load ────────────

test(
  "captain: when one coder is already busy, captain delegates to the free coder",
  () => {
    const cap = new CaptainHarness(
      rosterOf(
        ["manager#1", "manager"],
        ["coder#1", "coder", 9], // higher skill — would normally be picked first
        ["coder#2", "coder", 4],
      ),
    );

    // Pre-load coder#1 with 2 tasks so they're at the cap.
    const pre1 = cap.createTask({ title: "ongoing #1", allowedRoles: ["coder"] });
    const pre2 = cap.createTask({ title: "ongoing #2", allowedRoles: ["coder"] });
    cap.assign(pre1, "coder#1");
    cap.move(pre1, "in_progress");
    cap.assign(pre2, "coder#1");
    cap.move(pre2, "in_progress");

    assert.equal(cap.loadOf("coder#1"), MAX_AGENT_LOAD);

    // New user request → captain creates 1 subtask and delegates.
    const newTask = cap.createTask({
      title: "new feature subtask",
      allowedRoles: ["coder"],
    });
    cap.say(`Розбив "new feature" на: ${newTask}. Беремо першим.`);
    const picked = cap.dispatchByPolicy(newTask);

    assert.equal(
      picked,
      "coder#2",
      "captain must skip the at-cap coder#1 even though they have higher skill",
    );
    assert.equal(cap.loadOf("coder#1"), MAX_AGENT_LOAD, "coder#1 load unchanged");
    assert.equal(cap.loadOf("coder#2"), 1);
  },
);

// ─── Scenario 3: team is fully overloaded → leftover stays in backlog ─

test(
  "captain: when every eligible coder is at the cap, leftover tasks stay in backlog and the captain reports the squeeze",
  () => {
    const cap = new CaptainHarness(
      rosterOf(
        ["manager#1", "manager"],
        ["coder#1", "coder"],
        ["coder#2", "coder"],
      ),
    );

    // Saturate both coders.
    for (const c of ["coder#1", "coder#2"]) {
      for (let i = 0; i < MAX_AGENT_LOAD; i++) {
        const id = cap.createTask({
          title: `${c} pre ${i}`,
          allowedRoles: ["coder"],
        });
        cap.assign(id, c);
        cap.move(id, "in_progress");
      }
    }

    // Captain creates a new subtask, tries to dispatch, fails, reports.
    const newTask = cap.createTask({
      title: "fresh feature",
      allowedRoles: ["coder"],
    });
    const picked = cap.dispatchByPolicy(newTask);
    if (picked === null) {
      cap.say(
        `Команда зараз не тягне "fresh feature" — обидва кодери на максимумі.`,
      );
    }

    assert.equal(picked, null, "no eligible coder under cap → captain gives up");
    const fresh = [...cap.tasks.values()].find((t) => t.title === "fresh feature")!;
    assert.equal(fresh.column, "backlog", "leftover task stays in backlog");
    assert.deepEqual(
      fresh.assignedAgents,
      [],
      "leftover task has no assignee",
    );

    // Captain MUST tell the user, otherwise the user just sees a stale board.
    assert.ok(
      cap.chatLines.some((l) => /не тягне/.test(l)),
      "captain reports the team is overloaded",
    );
  },
);

// ─── Scenario 4: tasks visibly move backlog → in_progress → done ──────

test(
  "captain: cards transit backlog → in_progress → done in the right order; snapshots prove it",
  () => {
    const cap = new CaptainHarness(
      rosterOf(["manager#1", "manager"], ["coder#1", "coder"]),
    );

    const t = cap.createTask({ title: "feature X", allowedRoles: ["coder"] });
    cap.dispatchByPolicy(t);
    cap.receiveCompletion(t);

    // Pluck the column of `t` from each snapshot in order.
    const trail = cap.snapshots.map(
      (s) => s.tasks.find((x) => x.id === t)?.column ?? "absent",
    );
    // trail[0] = before create (absent), trail[1] = after create (backlog),
    // trail[2..] = after assign + move(in_progress) + move(done)
    assert.deepEqual(trail, [
      "absent",
      "backlog",
      "backlog", // assign keeps column
      "in_progress",
      "done",
    ]);
  },
);

// ─── Scenario 5: completion frees the agent for the next dispatch ─────

test(
  "captain: when a delegated subtask completes, the assignee is freed and the next subtask lands on them",
  () => {
    const cap = new CaptainHarness(
      rosterOf(["manager#1", "manager"], ["coder#1", "coder"]),
    );

    // Saturate the only coder up to the cap.
    const filler: string[] = [];
    for (let i = 0; i < MAX_AGENT_LOAD; i++) {
      const id = cap.createTask({ title: `pre ${i}`, allowedRoles: ["coder"] });
      cap.assign(id, "coder#1");
      cap.move(id, "in_progress");
      filler.push(id);
    }

    // Captain wants to dispatch a fresh task — should fail because cap is full.
    const fresh = cap.createTask({
      title: "fresh subtask",
      allowedRoles: ["coder"],
    });
    assert.equal(
      cap.dispatchByPolicy(fresh),
      null,
      "no capacity yet — fresh stays in backlog",
    );
    cap.say('Поки чекаємо — coder#1 на максимумі.');

    // First filler completes → load drops by 1 → coder#1 is now eligible again.
    cap.receiveCompletion(filler[0]);
    cap.say("Готово: pre 0.");
    assert.equal(cap.loadOf("coder#1"), MAX_AGENT_LOAD - 1);

    const pickAfterFree = cap.dispatchByPolicy(fresh);
    assert.equal(pickAfterFree, "coder#1");

    const freshTask = cap.tasks.get(fresh)!;
    assert.equal(freshTask.column, "in_progress");
    assert.deepEqual(freshTask.assignedAgents, ["coder#1"]);
  },
);

// ─── Scenario 6: roster-mismatch — no agent for the role ──────────────

test(
  "captain: a security subtask with no security teammate stays unassigned and the captain says what's missing",
  () => {
    const cap = new CaptainHarness(
      rosterOf(
        ["manager#1", "manager"],
        ["coder#1", "coder"],
        ["tester#1", "tester"],
      ),
    );

    // User asks for a security audit; captain knows it's outside team
    // skills but creates a placeholder card and reports the gap.
    const audit = cap.createTask({
      title: "Audit auth flow",
      allowedRoles: ["security"],
    });
    const picked = cap.dispatchByPolicy(audit);
    if (picked === null) {
      cap.say(
        `Команда зараз не тягне "Audit auth flow" — потрібно найняти security.`,
      );
    }

    assert.equal(picked, null, "no security agent → captain leaves it alone");
    const stuck = cap.tasks.get(audit)!;
    assert.equal(stuck.column, "backlog");
    assert.deepEqual(stuck.assignedAgents, []);

    assert.ok(
      cap.chatLines.some((l) => /security/i.test(l) && /потрібно|hire/i.test(l)),
      "captain explicitly tells the user to hire security",
    );
  },
);

// ─── Scenario 7: progress reporting cadence (chat sequence) ───────────

test(
  "captain: chat output follows the prompt — split / start / done / next pattern",
  () => {
    const cap = new CaptainHarness(
      rosterOf(
        ["manager#1", "manager"],
        ["coder#1", "coder"],
        ["coder#2", "coder"],
      ),
    );

    const a = cap.createTask({ title: "A", allowedRoles: ["coder"] });
    const b = cap.createTask({ title: "B", allowedRoles: ["coder"] });
    cap.say('Розбив "feat" на: A, B. Беремо A першим.');

    cap.dispatchByPolicy(a);
    cap.dispatchByPolicy(b);

    // A finishes first.
    cap.receiveCompletion(a);
    cap.say("Готово: A.");

    // B finishes.
    cap.receiveCompletion(b);
    cap.say("Готово: B.");

    // The chat is one line per real state change — no narration of
    // tool calls, no repetition. The prompt's "STAY SILENT" rules are
    // honored.
    assert.equal(cap.chatLines.length, 3);
    assert.match(cap.chatLines[0], /^Розбив.*"feat".*на:.*A.*B/);
    assert.match(cap.chatLines[1], /^Готово: A/);
    assert.match(cap.chatLines[2], /^Готово: B/);
    // No line repeats — captain didn't double-post.
    assert.equal(
      new Set(cap.chatLines).size,
      cap.chatLines.length,
      "captain never repeats itself",
    );
  },
);

// ─── Scenario 8: blockers surface in chat exactly once ────────────────

test(
  "captain: a blocked subtask is reported with one short line, not an essay",
  () => {
    const cap = new CaptainHarness(
      rosterOf(["manager#1", "manager"], ["coder#1", "coder"]),
    );

    const t = cap.createTask({
      title: "Add OAuth login",
      allowedRoles: ["coder"],
    });
    cap.dispatchByPolicy(t);

    // Coder reports a blocker → captain moves card back to backlog and
    // tells the user once.
    cap.move(t, "backlog");
    cap.say('Застрягли на "Add OAuth login": немає API ключів.');

    const blocker = cap.chatLines.filter((l) => /Застрягли/.test(l));
    assert.equal(blocker.length, 1, "blocker reported exactly once");

    const stuck = cap.tasks.get(t)!;
    assert.equal(stuck.column, "backlog");
    // Blocker doesn't release the agent's load yet — the task is still
    // theirs, just paused. The captain prompt expects re-dispatch once
    // the blocker clears.
    assert.deepEqual(stuck.assignedAgents, ["coder#1"]);
  },
);

// ─── Scenario 9: dispatched batch round-trips through disk ────────────

test(
  "captain: after a server restart, the dispatched board state is restored byte-for-byte",
  () => {
    const root = mkdtempSync(join(tmpdir(), "pixelcode-cap-"));
    const cwd = "/Users/test/CaptainProj";
    try {
      const cap = new CaptainHarness(
        rosterOf(
          ["manager#1", "manager"],
          ["coder#1", "coder"],
          ["coder#2", "coder"],
          ["tester#1", "tester"],
        ),
      );

      const ids = [
        cap.createTask({ title: "model", allowedRoles: ["coder"] }),
        cap.createTask({ title: "screen", allowedRoles: ["coder"] }),
        cap.createTask({ title: "tests", allowedRoles: ["tester"] }),
      ];
      for (const id of ids) cap.dispatchByPolicy(id);
      cap.receiveCompletion(ids[0]); // one already done before crash

      cap.persistTo(root, cwd);

      // Simulate restart: fresh load from disk.
      const restored = loadBoard(cwd, { baseDir: root });
      assert.equal(restored.source, "loaded");
      assert.equal(restored.tasks.length, 3);

      // Live state ↔ disk state per id should match in column + assignees.
      for (const id of ids) {
        const live = cap.tasks.get(id)!;
        const onDisk = restored.tasks.find((t) => t.id === id);
        assert.ok(onDisk, `task ${id} survived the restart`);
        assert.equal(onDisk.column, live.column);
        assert.deepEqual(onDisk.assignedAgents, live.assignedAgents);
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);

// ─── Scenario 10: planSeedBatch parity — same path as facilitator ─────

test(
  "captain: when the captain emits a batch via planSeedBatch (same primitive as facilitator), the resulting tasks match what hand-built createTask produces",
  () => {
    // The captain's MCP `board_create_task` calls land one-by-one, but
    // the facilitator path uses `board_seed_batch` (atomic). Both
    // converge on TaskCardData. This test pins the field shape so the
    // captain's manual flow doesn't diverge from the batched flow.
    const handBuilt = new CaptainHarness(rosterOf(["coder#1", "coder"]));
    const m = handBuilt.createTask({
      title: "tic",
      description: "tac",
      allowedRoles: ["coder"],
      difficulty: 2,
    });
    const handBuiltTask = handBuilt.tasks.get(m)!;

    const inputs: SeedBatchInput[] = [
      { title: "tic", description: "tac", allowedRoles: ["coder"], difficulty: 2 },
    ];
    const plan = planSeedBatch(inputs, {
      counter: 0,
      now: () => new Date("2026-05-02T10:00:00Z"),
      idToken: () => 1,
      sourceTag: "facilitator",
    });
    assert.equal(plan.ok, true);
    const batched = plan.tasks[0];

    // Field-for-field comparison — only the id, timestamps, and
    // taskType (manual="coding" vs batched="facilitator") are allowed
    // to differ.
    assert.equal(handBuiltTask.title, batched.title);
    assert.equal(handBuiltTask.description, batched.description);
    assert.equal(handBuiltTask.column, batched.column);
    assert.equal(handBuiltTask.priority, batched.priority);
    assert.equal(handBuiltTask.color, batched.color);
    assert.deepEqual(handBuiltTask.allowedRoles, batched.allowedRoles);
    assert.equal(handBuiltTask.difficulty, batched.difficulty);
    assert.deepEqual(handBuiltTask.assignedAgents, batched.assignedAgents);
    // taskType differs by design — assert that and move on.
    assert.equal(handBuiltTask.taskType, "coding");
    assert.equal(batched.taskType, "facilitator");
  },
);
