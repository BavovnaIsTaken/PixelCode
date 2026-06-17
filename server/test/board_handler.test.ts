/**
 * Pure-handler tests for the team-collaboration board flows:
 *   • create / move / update / delete / assign
 *   • broadcast on every mutation (multi-client sync proxy)
 *   • manager auto-enqueue on in_progress
 *   • attachment size cap
 *   • negative cases: unknown taskId, oversized attachment
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { TaskQueue } from "../src/task_queue.ts";
import {
  handleBoardMessage,
  buildBoardSnapshot,
  type BoardHandlerDeps,
} from "../src/board_handler.ts";
import type {
  ClientMessage,
  ServerMessage,
  TaskCardData,
} from "../src/protocol.ts";
import type { WebSocket } from "ws";

// ─── Test harness ────────────────────────────────────────────────────────

interface Harness {
  deps: BoardHandlerDeps;
  boardTasks: Map<string, TaskCardData>;
  taskQueue: TaskQueue;
  broadcasts: number;
  sentToClient: ServerMessage[];
  queueStatusCalls: number;
  processQueueCalls: number;
  logs: Array<{ level: string; msg: string }>;
  ws: WebSocket;
}

function makeHarness(opts: { now?: () => Date } = {}): Harness {
  const boardTasks = new Map<string, TaskCardData>();
  const taskQueue = new TaskQueue();
  const sentToClient: ServerMessage[] = [];
  const logs: Array<{ level: string; msg: string }> = [];
  let counter = 0;
  let broadcasts = 0;
  let queueStatusCalls = 0;
  let processQueueCalls = 0;

  const ws = { readyState: 1 } as unknown as WebSocket;

  const deps: BoardHandlerDeps = {
    boardTasks,
    nextTaskId: () => `task_${++counter}`,
    send: (_ws, m) => sentToClient.push(m),
    broadcastBoardState: () => {
      broadcasts += 1;
    },
    taskQueue,
    sendQueueStatus: () => {
      queueStatusCalls += 1;
    },
    processQueue: () => {
      processQueueCalls += 1;
    },
    getProjectCwd: () => "/projects/demo",
    dbg: (level, _cat, msg) => logs.push({ level, msg }),
    now: opts.now,
  };

  return {
    deps,
    boardTasks,
    taskQueue,
    sentToClient,
    logs,
    ws,
    get broadcasts() {
      return broadcasts;
    },
    get queueStatusCalls() {
      return queueStatusCalls;
    },
    get processQueueCalls() {
      return processQueueCalls;
    },
  } as unknown as Harness;
}

function createCard(
  h: Harness,
  partial: Partial<{ title: string; difficulty: number; allowedRoles: string[]; taskType: string }> = {},
): string {
  const before = h.boardTasks.size;
  handleBoardMessage(h.deps, h.ws, {
    type: "board_create_task",
    title: partial.title ?? "T",
    difficulty: partial.difficulty ?? 2,
    allowedRoles: partial.allowedRoles ?? ["coder"],
    taskType: partial.taskType ?? "coding",
  } as ClientMessage);
  // Newest entry is the freshly-added one.
  const all = Array.from(h.boardTasks.values());
  assert.equal(all.length, before + 1);
  return all[all.length - 1].id;
}

// ─── board_get_state ─────────────────────────────────────────────────────

test("board_get_state — sends snapshot only to the requesting client (no broadcast)", () => {
  const h = makeHarness();
  createCard(h);

  const beforeBroadcasts = h.broadcasts;
  h.sentToClient.length = 0;

  handleBoardMessage(h.deps, h.ws, { type: "board_get_state" });

  assert.equal(h.sentToClient.length, 1);
  const msg = h.sentToClient[0] as Extract<ServerMessage, { type: "board_state" }>;
  assert.equal(msg.type, "board_state");
  assert.equal(msg.tasks.length, 1);
  // Snapshot delivery is point-to-point — no broadcast triggered.
  assert.equal(h.broadcasts, beforeBroadcasts);
});

test("buildBoardSnapshot — returns every task in the map", () => {
  const map = new Map<string, TaskCardData>();
  map.set("a", {
    id: "a",
    title: "A",
    description: "",
    column: "backlog",
    priority: "normal",
    color: "yellow",
    assignedAgents: [],
    createdAt: "2026-05-01T00:00:00Z",
    updatedAt: "2026-05-01T00:00:00Z",
    attachments: [],
  });
  const snap = buildBoardSnapshot(map);
  assert.equal(snap.type, "board_state");
  // @ts-expect-error narrowed above
  assert.equal(snap.tasks.length, 1);
});

// ─── board_create_task ───────────────────────────────────────────────────

test("board_create_task — adds task and broadcasts to all clients", () => {
  const h = makeHarness({ now: () => new Date("2026-05-01T00:00:00Z") });

  handleBoardMessage(h.deps, h.ws, {
    type: "board_create_task",
    title: "Розбити логін на підзадачі",
    difficulty: 3,
    allowedRoles: ["coder", "tester"],
    taskType: "coding",
  });

  assert.equal(h.boardTasks.size, 1);
  assert.equal(h.broadcasts, 1);
  const [task] = h.boardTasks.values();
  assert.equal(task.title, "Розбити логін на підзадачі");
  assert.equal(task.column, "backlog");
  assert.equal(task.priority, "normal"); // default
  assert.equal(task.color, "yellow"); // default
  assert.deepEqual(task.allowedRoles, ["coder", "tester"]);
  assert.equal(task.difficulty, 3);
  assert.equal(task.assignedAgents.length, 0);
  assert.equal(task.attachments.length, 0);
});

test("board_create_task — uses explicit priority and color when provided", () => {
  const h = makeHarness();

  handleBoardMessage(h.deps, h.ws, {
    type: "board_create_task",
    title: "T",
    priority: "urgent",
    color: "pink",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });

  const [task] = h.boardTasks.values();
  assert.equal(task.priority, "urgent");
  assert.equal(task.color, "pink");
});

test("board_create_task — every create yields a unique id and bumps broadcast", () => {
  const h = makeHarness();

  for (let i = 0; i < 3; i++) createCard(h, { title: `T${i}` });

  const ids = Array.from(h.boardTasks.keys());
  assert.equal(new Set(ids).size, 3);
  assert.equal(h.broadcasts, 3);
});

// ─── board_move_task ─────────────────────────────────────────────────────

test("board_move_task — updates column and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "testing",
  });

  assert.equal(h.boardTasks.get(id)!.column, "testing");
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_move_task — unknown taskId is a silent no-op (no broadcast, no enqueue)", () => {
  const h = makeHarness();
  createCard(h); // ensure board isn't empty
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: "task_does_not_exist",
    column: "in_progress",
  });

  assert.equal(h.broadcasts, beforeBroadcasts);
  assert.equal(h.taskQueue.size, 0);
});

test("board_move_task → in_progress — enqueues manager dispatch", () => {
  const h = makeHarness();
  const id = createCard(h, { title: "Wire login form" });

  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });

  assert.equal(h.taskQueue.size, 1);
  const queued = h.taskQueue.peek()!;
  assert.equal(queued.type, "board");
  assert.equal(queued.targetAgentId, "manager");
  assert.equal(queued.boardTaskId, id);
  assert.equal(queued.boardTaskTitle, "Wire login form");
  assert.equal(queued.projectCwd, "/projects/demo");
  assert.match(queued.userMessage!, /No specific agents assigned/);
  assert.equal(h.queueStatusCalls, 1);
  assert.equal(h.processQueueCalls, 1);
});

test("board_move_task → in_progress — userMessage lists assignedAgents when present", () => {
  const h = makeHarness();
  const id = createCard(h, { title: "Pair work" });
  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "coder#1",
    assign: true,
  });
  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "tester#1",
    assign: true,
  });

  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });

  const queued = h.taskQueue.peek()!;
  assert.match(queued.userMessage!, /Assigned agents: coder#1, tester#1/);
});

test("board_move_task → backlog/testing/done does NOT enqueue manager", () => {
  for (const target of ["testing", "done", "backlog"] as const) {
    const h = makeHarness();
    const id = createCard(h);

    handleBoardMessage(h.deps, h.ws, {
      type: "board_move_task",
      taskId: id,
      column: target,
    });

    assert.equal(h.taskQueue.size, 0, `column=${target} should not enqueue`);
    assert.equal(h.queueStatusCalls, 0);
  }
});

test("board_move_task → in_progress twice creates two queue entries (no dedup)", () => {
  // Documents current behaviour: re-moving the same card to in_progress
  // double-enqueues. If dedup is added later, this test must be updated.
  const h = makeHarness();
  const id = createCard(h);

  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });
  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "backlog",
  });
  handleBoardMessage(h.deps, h.ws, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });

  assert.equal(h.taskQueue.size, 2);
});

// ─── board_update_task ───────────────────────────────────────────────────

test("board_update_task — patches only provided fields and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h, { title: "Original" });
  const original = { ...h.boardTasks.get(id)! };
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_update_task",
    taskId: id,
    updates: { title: "Renamed", priority: "urgent" },
  });

  const updated = h.boardTasks.get(id)!;
  assert.equal(updated.title, "Renamed");
  assert.equal(updated.priority, "urgent");
  assert.equal(updated.color, original.color); // untouched
  assert.equal(updated.description, original.description);
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_update_task — unknown taskId is a no-op", () => {
  const h = makeHarness();
  createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_update_task",
    taskId: "missing",
    updates: { title: "X" },
  });

  assert.equal(h.broadcasts, beforeBroadcasts);
});

// ─── board_delete_task ───────────────────────────────────────────────────

test("board_delete_task — removes task and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, { type: "board_delete_task", taskId: id });

  assert.equal(h.boardTasks.has(id), false);
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_delete_task — unknown id does NOT broadcast", () => {
  const h = makeHarness();
  createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_delete_task",
    taskId: "missing",
  });

  assert.equal(h.broadcasts, beforeBroadcasts);
});

// ─── board_assign_agent (delegation) ─────────────────────────────────────

test("board_assign_agent — assign=true appends agent and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h);

  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "coder#1",
    assign: true,
  });

  assert.deepEqual(h.boardTasks.get(id)!.assignedAgents, ["coder#1"]);
});

test("board_assign_agent — assign=true is idempotent (no double-add)", () => {
  const h = makeHarness();
  const id = createCard(h);

  for (let i = 0; i < 3; i++) {
    handleBoardMessage(h.deps, h.ws, {
      type: "board_assign_agent",
      taskId: id,
      agentId: "coder#1",
      assign: true,
    });
  }

  assert.deepEqual(h.boardTasks.get(id)!.assignedAgents, ["coder#1"]);
});

test("board_assign_agent — assign=false removes only that agent", () => {
  const h = makeHarness();
  const id = createCard(h);
  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "coder#1",
    assign: true,
  });
  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "tester#1",
    assign: true,
  });

  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "coder#1",
    assign: false,
  });

  assert.deepEqual(h.boardTasks.get(id)!.assignedAgents, ["tester#1"]);
});

test("board_assign_agent — assign=false on agent never assigned is a no-op-ish (broadcast still fires)", () => {
  // Existing behaviour: filter is unconditional so broadcast still goes out
  // even if no actual change happened. Document it so we notice if it changes.
  const h = makeHarness();
  const id = createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "ghost#1",
    assign: false,
  });

  assert.deepEqual(h.boardTasks.get(id)!.assignedAgents, []);
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_assign_agent — unknown taskId is silent no-op", () => {
  const h = makeHarness();
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_assign_agent",
    taskId: "missing",
    agentId: "coder#1",
    assign: true,
  });

  assert.equal(h.broadcasts, beforeBroadcasts);
});

// ─── Attachments ─────────────────────────────────────────────────────────

test("board_add_attachment — appends within size cap and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_add_attachment",
    taskId: id,
    name: "spec.md",
    mimeType: "text/markdown",
    sizeBytes: 1024,
    dataBase64: "YWJj",
  });

  const atts = h.boardTasks.get(id)!.attachments!;
  assert.equal(atts.length, 1);
  assert.equal(atts[0].name, "spec.md");
  assert.equal(atts[0].sizeBytes, 1024);
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_add_attachment — rejects payload above the cap (no mutation, no broadcast)", () => {
  const h = makeHarness();
  const id = createCard(h);
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_add_attachment",
    taskId: id,
    name: "huge.bin",
    mimeType: "application/octet-stream",
    sizeBytes: 10 * 1024 * 1024, // 10 MB > 5 MB cap
    dataBase64: "x",
  });

  assert.equal(h.boardTasks.get(id)!.attachments?.length ?? 0, 0);
  assert.equal(h.broadcasts, beforeBroadcasts);
  // Warning logged.
  assert.ok(h.logs.some((l) => l.level === "warn" && /Rejected/.test(l.msg)));
});

test("board_add_attachment — unknown taskId is silent no-op", () => {
  const h = makeHarness();
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_add_attachment",
    taskId: "missing",
    name: "x",
    mimeType: "text/plain",
    sizeBytes: 1,
    dataBase64: "x",
  });

  assert.equal(h.broadcasts, beforeBroadcasts);
});

test("board_remove_attachment — removes target and broadcasts", () => {
  const h = makeHarness();
  const id = createCard(h);
  handleBoardMessage(h.deps, h.ws, {
    type: "board_add_attachment",
    taskId: id,
    name: "a",
    mimeType: "text/plain",
    sizeBytes: 1,
    dataBase64: "x",
  });
  const attId = h.boardTasks.get(id)!.attachments![0].id;
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_remove_attachment",
    taskId: id,
    attachmentId: attId,
  });

  assert.equal(h.boardTasks.get(id)!.attachments!.length, 0);
  assert.equal(h.broadcasts, beforeBroadcasts + 1);
});

test("board_remove_attachment — unknown attachmentId does not broadcast", () => {
  const h = makeHarness();
  const id = createCard(h);
  handleBoardMessage(h.deps, h.ws, {
    type: "board_add_attachment",
    taskId: id,
    name: "a",
    mimeType: "text/plain",
    sizeBytes: 1,
    dataBase64: "x",
  });
  const beforeBroadcasts = h.broadcasts;

  handleBoardMessage(h.deps, h.ws, {
    type: "board_remove_attachment",
    taskId: id,
    attachmentId: "att_missing",
  });

  assert.equal(h.boardTasks.get(id)!.attachments!.length, 1);
  assert.equal(h.broadcasts, beforeBroadcasts);
});

// ─── Non-board message ───────────────────────────────────────────────────

test("handleBoardMessage — returns false for non-board messages", () => {
  const h = makeHarness();
  const handled = handleBoardMessage(h.deps, h.ws, {
    type: "interrupt",
  } as ClientMessage);
  assert.equal(handled, false);
  assert.equal(h.broadcasts, 0);
});

test("handleBoardMessage — returns true for every board_* case", () => {
  const h = makeHarness();
  const id = createCard(h); // already covered create
  const cases: ClientMessage[] = [
    { type: "board_get_state" },
    { type: "board_move_task", taskId: id, column: "testing" },
    { type: "board_update_task", taskId: id, updates: { title: "N" } },
    { type: "board_assign_agent", taskId: id, agentId: "x", assign: true },
    {
      type: "board_add_attachment",
      taskId: id,
      name: "a",
      mimeType: "text/plain",
      sizeBytes: 1,
      dataBase64: "x",
    },
    { type: "board_remove_attachment", taskId: id, attachmentId: "missing" },
    { type: "board_delete_task", taskId: id },
  ];
  for (const m of cases) {
    assert.equal(handleBoardMessage(h.deps, h.ws, m), true, `type=${m.type}`);
  }
});
