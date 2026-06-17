import { test } from "node:test";
import assert from "node:assert/strict";
import { TaskQueue, type QueuedTask, type TaskPriority } from "../src/task_queue.js";

// ─── Mock WebSocket ────────────────────────────────────────────────────────

const mockWs = {} as any;
const mockWs2 = {} as any;
const mockWs3 = {} as any;

// ─── Helpers ────────────────────────────────────────────────────────────────

function makeTask(
  id: string,
  priority: TaskPriority,
  ws: any = mockWs
): QueuedTask {
  return {
    id,
    priority,
    type: "chat",
    userMessage: `task ${id}`,
    enqueuedAt: Date.now(),
    ws,
    projectCwd: "/projects/demo",
  };
}

// ─── Basic operations ──────────────────────────────────────────────────────

test("TaskQueue starts empty", () => {
  const queue = new TaskQueue();
  assert.ok(queue.isEmpty);
  assert.equal(queue.size, 0);
});

test("TaskQueue is not empty after enqueue", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal"));
  assert.ok(!queue.isEmpty);
  assert.equal(queue.size, 1);
});

test("TaskQueue dequeue removes and returns task", () => {
  const queue = new TaskQueue();
  const task = makeTask("t1", "normal");
  queue.enqueue(task);

  const dequeued = queue.dequeue();
  assert.equal(dequeued?.id, "t1");
  assert.ok(queue.isEmpty);
});

test("TaskQueue dequeue from empty returns undefined", () => {
  const queue = new TaskQueue();
  const result = queue.dequeue();
  assert.equal(result, undefined);
});

test("TaskQueue peek returns task without removing", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal"));

  const peeked = queue.peek();
  assert.equal(peeked?.id, "t1");
  assert.equal(queue.size, 1); // Still in queue
});

test("TaskQueue peek on empty returns undefined", () => {
  const queue = new TaskQueue();
  assert.equal(queue.peek(), undefined);
});

// ─── Priority ordering ────────────────────────────────────────────────────

test("critical priority dequeues before high", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("high-1", "high"));
  queue.enqueue(makeTask("critical-1", "critical"));

  const first = queue.dequeue();
  assert.equal(first?.id, "critical-1");
});

test("high priority dequeues before normal", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("normal-1", "normal"));
  queue.enqueue(makeTask("high-1", "high"));

  const first = queue.dequeue();
  assert.equal(first?.id, "high-1");
});

test("normal priority dequeues before low", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("low-1", "low"));
  queue.enqueue(makeTask("normal-1", "normal"));

  const first = queue.dequeue();
  assert.equal(first?.id, "normal-1");
});

test("full priority order: critical > high > normal > low", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("low-1", "low"));
  queue.enqueue(makeTask("normal-1", "normal"));
  queue.enqueue(makeTask("high-1", "high"));
  queue.enqueue(makeTask("critical-1", "critical"));

  const order = [
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
  ];

  assert.deepEqual(order, ["critical", "high", "normal", "low"]);
});

test("interleaved enqueue maintains priority order", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("normal-1", "normal"));
  queue.enqueue(makeTask("low-1", "low"));
  queue.enqueue(makeTask("critical-1", "critical"));
  queue.enqueue(makeTask("high-1", "high"));

  const order = [
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
    queue.dequeue()?.priority,
  ];

  assert.deepEqual(order, ["critical", "high", "normal", "low"]);
});

// ─── FIFO within same priority ──────────────────────────────────────────────

test("FIFO: same priority tasks dequeue in enqueue order", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal"));
  queue.enqueue(makeTask("t2", "normal"));
  queue.enqueue(makeTask("t3", "normal"));

  const order = [
    queue.dequeue()?.id,
    queue.dequeue()?.id,
    queue.dequeue()?.id,
  ];

  assert.deepEqual(order, ["t1", "t2", "t3"]);
});

test("FIFO: critical tasks maintain enqueue order among themselves", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("c1", "critical"));
  queue.enqueue(makeTask("c2", "critical"));
  queue.enqueue(makeTask("c3", "critical"));

  assert.equal(queue.dequeue()?.id, "c1");
  assert.equal(queue.dequeue()?.id, "c2");
  assert.equal(queue.dequeue()?.id, "c3");
});

test("FIFO: new high-priority task goes after existing high-priority tasks", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("h1", "high"));
  queue.enqueue(makeTask("h2", "high"));
  queue.enqueue(makeTask("h3", "high"));

  const order = [
    queue.dequeue()?.id,
    queue.dequeue()?.id,
    queue.dequeue()?.id,
  ];

  assert.deepEqual(order, ["h1", "h2", "h3"]);
});

// ─── Size tracking ─────────────────────────────────────────────────────────

test("size increases with each enqueue", () => {
  const queue = new TaskQueue();
  assert.equal(queue.size, 0);
  queue.enqueue(makeTask("t1", "normal"));
  assert.equal(queue.size, 1);
  queue.enqueue(makeTask("t2", "normal"));
  assert.equal(queue.size, 2);
  queue.enqueue(makeTask("t3", "normal"));
  assert.equal(queue.size, 3);
});

test("size decreases with each dequeue", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal"));
  queue.enqueue(makeTask("t2", "normal"));
  queue.enqueue(makeTask("t3", "normal"));
  assert.equal(queue.size, 3);

  queue.dequeue();
  assert.equal(queue.size, 2);
  queue.dequeue();
  assert.equal(queue.size, 1);
  queue.dequeue();
  assert.equal(queue.size, 0);
});

// ─── removeForClient ───────────────────────────────────────────────────────

test("removeForClient removes all tasks for a client", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal", mockWs));
  queue.enqueue(makeTask("t2", "normal", mockWs2));
  queue.enqueue(makeTask("t3", "normal", mockWs));

  const removed = queue.removeForClient(mockWs);

  assert.equal(removed, 2);
  assert.equal(queue.size, 1);
  assert.equal(queue.dequeue()?.id, "t2");
});

test("removeForClient returns 0 when client has no tasks", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal", mockWs));

  const removed = queue.removeForClient(mockWs2);

  assert.equal(removed, 0);
  assert.equal(queue.size, 1);
});

test("removeForClient on empty queue returns 0", () => {
  const queue = new TaskQueue();
  const removed = queue.removeForClient(mockWs);
  assert.equal(removed, 0);
});

test("removeForClient preserves priority ordering of remaining tasks", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("critical", "critical", mockWs));
  queue.enqueue(makeTask("high-keep", "high", mockWs2));
  queue.enqueue(makeTask("normal", "normal", mockWs));
  queue.enqueue(makeTask("low-keep", "low", mockWs2));

  queue.removeForClient(mockWs);

  assert.equal(queue.size, 2);
  const first = queue.dequeue();
  const second = queue.dequeue();
  assert.equal(first?.id, "high-keep");
  assert.equal(second?.id, "low-keep");
});

// ─── Snapshot ────────────────────────────────────────────────────────────

test("snapshot returns all tasks in priority order", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("n1", "normal"));
  queue.enqueue(makeTask("c1", "critical"));
  queue.enqueue(makeTask("l1", "low"));

  const snap = queue.snapshot();

  assert.equal(snap.length, 3);
  assert.equal(snap[0].priority, "critical");
  assert.equal(snap[1].priority, "normal");
  assert.equal(snap[2].priority, "low");
});

test("snapshot does not remove items from queue", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("t1", "normal"));
  queue.enqueue(makeTask("t2", "high"));

  queue.snapshot();

  assert.equal(queue.size, 2);
});

test("snapshot includes id, type, priority, and agentId fields", () => {
  const queue = new TaskQueue();
  const task: QueuedTask = {
    id: "t1",
    priority: "high",
    type: "subagent_result",
    agentId: "coder#1",
    enqueuedAt: Date.now(),
    ws: mockWs,
    projectCwd: "/projects/demo",
  };
  queue.enqueue(task);

  const snap = queue.snapshot();

  assert.equal(snap[0].id, "t1");
  assert.equal(snap[0].type, "subagent_result");
  assert.equal(snap[0].priority, "high");
  assert.equal(snap[0].agentId, "coder#1");
});

test("snapshot of empty queue returns empty array", () => {
  const queue = new TaskQueue();
  const snap = queue.snapshot();
  assert.deepEqual(snap, []);
});

// ─── Edge cases ───────────────────────────────────────────────────────────

test("single item enqueue/dequeue round-trips correctly", () => {
  const queue = new TaskQueue();
  const original = makeTask("single", "critical");
  queue.enqueue(original);

  const result = queue.dequeue();
  assert.equal(result?.id, "single");
  assert.equal(result?.priority, "critical");
  assert.ok(queue.isEmpty);
});

test("all tasks same priority: queue is stable FIFO", () => {
  const queue = new TaskQueue();
  for (let i = 0; i < 10; i++) {
    queue.enqueue(makeTask(`t${i}`, "high"));
  }

  const order = [];
  while (!queue.isEmpty) {
    order.push(queue.dequeue()?.id);
  }

  assert.deepEqual(order, ["t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t9"]);
});

test("critical inserted last still dequeues first", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("low-1", "low"));
  queue.enqueue(makeTask("normal-1", "normal"));
  queue.enqueue(makeTask("high-1", "high"));
  queue.enqueue(makeTask("critical-1", "critical")); // inserted last

  assert.equal(queue.dequeue()?.id, "critical-1");
});

// ─── projectCwd stamping ─────────────────────────────────────────────────

test("projectCwd survives the enqueue/dequeue round-trip", () => {
  const queue = new TaskQueue();
  queue.enqueue({
    id: "t1",
    priority: "normal",
    type: "chat",
    userMessage: "hi",
    enqueuedAt: Date.now(),
    ws: mockWs,
    projectCwd: "/projects/worktree-a",
  });

  const dequeued = queue.dequeue();
  assert.equal(dequeued?.projectCwd, "/projects/worktree-a");
});

// ─── clear (project-switch path) ───────────────────────────────────────────

test("clear() drops every task regardless of priority or owning ws", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("c", "critical", mockWs));
  queue.enqueue(makeTask("h", "high", mockWs2));
  queue.enqueue(makeTask("n", "normal", mockWs));
  queue.enqueue(makeTask("l", "low", mockWs3));

  const dropped = queue.clear();
  assert.equal(dropped, 4);
  assert.ok(queue.isEmpty);
  assert.equal(queue.size, 0);
  assert.equal(queue.dequeue(), undefined);
});

test("clear() on an empty queue is a no-op and returns 0", () => {
  const queue = new TaskQueue();
  assert.equal(queue.clear(), 0);
  assert.ok(queue.isEmpty);
});

test("clear() leaves the queue usable for fresh enqueues", () => {
  const queue = new TaskQueue();
  queue.enqueue(makeTask("a", "high"));
  queue.enqueue(makeTask("b", "high"));
  queue.clear();
  queue.enqueue(makeTask("c", "high"));
  assert.equal(queue.dequeue()?.id, "c");
  assert.ok(queue.isEmpty);
});
