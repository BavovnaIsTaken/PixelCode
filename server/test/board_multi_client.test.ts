/**
 * Multi-client board sync — verifies that any board mutation produced by
 * one client lands on every other connected client.
 *
 * Builds a minimal fake `wss.clients` set on top of the pure board handler
 * and replays the exact `broadcastBoardState` semantics from server.ts:
 * iterate `wss.clients`, skip non-OPEN sockets, JSON-stringify the
 * snapshot. This exercises the same code path Flutter clients hit when
 * multiple devices are paired to the same server.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { TaskQueue } from "../src/task_queue.ts";
import {
  handleBoardMessage,
  buildBoardSnapshot,
  type BoardHandlerDeps,
} from "../src/board_handler.ts";
import type { ClientMessage, TaskCardData } from "../src/protocol.ts";

// ─── Fake WebSocket + WebSocketServer ────────────────────────────────────

const OPEN = 1;
const CLOSED = 3;

class FakeSocket {
  readyState: number = OPEN;
  readonly received: string[] = [];
  send(payload: string) {
    if (this.readyState !== OPEN) return;
    this.received.push(payload);
  }
  close() {
    this.readyState = CLOSED;
  }
  decodeLast(): { type: string; tasks: TaskCardData[] } {
    return JSON.parse(this.received[this.received.length - 1]);
  }
}

interface World {
  clients: Set<FakeSocket>;
  boardTasks: Map<string, TaskCardData>;
  taskQueue: TaskQueue;
  deps: BoardHandlerDeps;
}

function makeWorld(numClients: number): { world: World; sockets: FakeSocket[] } {
  const sockets = Array.from({ length: numClients }, () => new FakeSocket());
  const clients = new Set<FakeSocket>(sockets);
  const boardTasks = new Map<string, TaskCardData>();
  const taskQueue = new TaskQueue();
  let counter = 0;

  const broadcastBoardState = (): void => {
    const payload = JSON.stringify(buildBoardSnapshot(boardTasks));
    for (const c of clients) {
      if (c.readyState === OPEN) c.send(payload);
    }
  };

  const deps: BoardHandlerDeps = {
    boardTasks,
    nextTaskId: () => `task_${++counter}`,
    send: (ws, msg) => (ws as unknown as FakeSocket).send(JSON.stringify(msg)),
    broadcastBoardState,
    taskQueue,
    sendQueueStatus: () => {},
    processQueue: () => {},
    getProjectCwd: () => "/projects/demo",
    dbg: () => {},
  };

  return { world: { clients, boardTasks, taskQueue, deps }, sockets };
}

function dispatch(world: World, from: FakeSocket, msg: ClientMessage) {
  // The handler accepts a `WebSocket` — our fake satisfies the structural
  // members it actually touches (readyState + send). Cast through unknown.
  handleBoardMessage(world.deps, from as unknown as never, msg);
}

// ─── Tests ───────────────────────────────────────────────────────────────

test("multi-client: create from A reaches B and C", () => {
  const { world, sockets } = makeWorld(3);
  const [a, b, c] = sockets;

  dispatch(world, a, {
    type: "board_create_task",
    title: "Розбити фічу логіну",
    difficulty: 3,
    allowedRoles: ["coder"],
    taskType: "coding",
  });

  for (const s of [a, b, c]) {
    assert.equal(s.received.length, 1, "each client should get one broadcast");
    const snap = s.decodeLast();
    assert.equal(snap.type, "board_state");
    assert.equal(snap.tasks.length, 1);
    assert.equal(snap.tasks[0].title, "Розбити фічу логіну");
  }
});

test("multi-client: move from B reaches A and C with new column", () => {
  const { world, sockets } = makeWorld(3);
  const [a, b, c] = sockets;

  dispatch(world, a, {
    type: "board_create_task",
    title: "T",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });
  // Reset counters to focus on the move broadcast.
  for (const s of [a, b, c]) s.received.length = 0;

  const id = Array.from(world.boardTasks.keys())[0];
  dispatch(world, b, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });

  for (const s of [a, b, c]) {
    assert.equal(s.received.length, 1);
    assert.equal(s.decodeLast().tasks[0].column, "in_progress");
  }
});

test("multi-client: assignment from one client visible to all (delegation sync)", () => {
  const { world, sockets } = makeWorld(2);
  const [a, b] = sockets;

  dispatch(world, a, {
    type: "board_create_task",
    title: "T",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });
  const id = Array.from(world.boardTasks.keys())[0];
  for (const s of [a, b]) s.received.length = 0;

  dispatch(world, a, {
    type: "board_assign_agent",
    taskId: id,
    agentId: "coder#1",
    assign: true,
  });

  for (const s of [a, b]) {
    assert.deepEqual(s.decodeLast().tasks[0].assignedAgents, ["coder#1"]);
  }
});

test("multi-client: closed socket no longer receives broadcasts (graceful disconnect)", () => {
  const { world, sockets } = makeWorld(2);
  const [a, b] = sockets;

  // B disconnects.
  b.close();
  b.received.length = 0;

  dispatch(world, a, {
    type: "board_create_task",
    title: "After B left",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });

  assert.equal(a.received.length, 1, "A still receives");
  assert.equal(b.received.length, 0, "B should not receive after close");
});

test("multi-client: late joiner sees full state via board_get_state, not broadcast", () => {
  const { world, sockets } = makeWorld(1);
  const [a] = sockets;

  // Seed the board with two cards from A.
  dispatch(world, a, {
    type: "board_create_task",
    title: "task one",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });
  dispatch(world, a, {
    type: "board_create_task",
    title: "task two",
    difficulty: 2,
    allowedRoles: ["coder"],
    taskType: "coding",
  });

  // B connects after the fact — emulate by adding to the clients set.
  const b = new FakeSocket();
  world.clients.add(b);

  // B requests the snapshot.
  dispatch(world, b, { type: "board_get_state" });

  assert.equal(b.received.length, 1);
  const snap = b.decodeLast();
  assert.equal(snap.type, "board_state");
  assert.equal(snap.tasks.length, 2);
});

test("multi-client: rapid sequence of mutations broadcasts in order to every client", () => {
  const { world, sockets } = makeWorld(2);
  const [a, b] = sockets;

  for (let i = 0; i < 5; i++) {
    dispatch(world, a, {
      type: "board_create_task",
      title: `T${i}`,
      difficulty: 1,
      allowedRoles: ["coder"],
      taskType: "coding",
    });
  }

  assert.equal(a.received.length, 5);
  assert.equal(b.received.length, 5);
  // Final snapshot for both = 5 tasks.
  assert.equal(a.decodeLast().tasks.length, 5);
  assert.equal(b.decodeLast().tasks.length, 5);
});

test("multi-client: in_progress move enqueues exactly once (regardless of client count)", () => {
  const { world, sockets } = makeWorld(3);
  const [a] = sockets;

  dispatch(world, a, {
    type: "board_create_task",
    title: "Q",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });
  const id = Array.from(world.boardTasks.keys())[0];

  dispatch(world, a, {
    type: "board_move_task",
    taskId: id,
    column: "in_progress",
  });

  // Manager dispatch is per-mutation, not per-client.
  assert.equal(world.taskQueue.size, 1);
});

test("multi-client: deletion broadcasts and removes from snapshot for every client", () => {
  const { world, sockets } = makeWorld(2);
  const [a, b] = sockets;

  dispatch(world, a, {
    type: "board_create_task",
    title: "X",
    difficulty: 1,
    allowedRoles: ["coder"],
    taskType: "coding",
  });
  const id = Array.from(world.boardTasks.keys())[0];
  for (const s of [a, b]) s.received.length = 0;

  dispatch(world, b, { type: "board_delete_task", taskId: id });

  for (const s of [a, b]) {
    assert.equal(s.received.length, 1);
    assert.equal(s.decodeLast().tasks.length, 0);
  }
});
