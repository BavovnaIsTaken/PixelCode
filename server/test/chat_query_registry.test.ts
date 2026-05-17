/**
 * Tests for ChatQueryRegistry — the runtime-scoped store of in-flight main
 * manager queries that the "Active agents" Settings tab uses to surface
 * and cancel chat work without relying on ws disconnect.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { ChatQueryRegistry } from "../src/chat_query_registry.js";

const wsA = { id: "A" } as any;
const wsB = { id: "B" } as any;

function reg(now: () => number = () => 1_000) {
  return { r: new ChatQueryRegistry(), now };
}

test("register returns unique id and exposes via list()", () => {
  const { r, now } = reg();
  const ac = new AbortController();
  const id = r.register({ ws: wsA, agentId: "manager#1", userMessage: "fix login", abortController: ac, now });

  assert.equal(typeof id, "string");
  assert.equal(id.length > 0, true);

  const items = r.list({ ws: wsA, now: () => 1_500 });
  assert.equal(items.length, 1);
  assert.equal(items[0].queryId, id);
  assert.equal(items[0].agentId, "manager#1");
  assert.equal(items[0].userMessage, "fix login");
  assert.equal(items[0].elapsedMs, 500);
});

test("register truncates userMessage to 200 chars to bound UI payload", () => {
  const { r, now } = reg();
  const long = "x".repeat(500);
  const id = r.register({ ws: wsA, agentId: "manager#1", userMessage: long, abortController: new AbortController(), now });
  const item = r.list().find((q) => q.queryId === id)!;
  assert.equal(item.userMessage.length, 200);
});

test("cancel(id) aborts the controller and removes the entry", () => {
  const { r, now } = reg();
  const ac = new AbortController();
  const id = r.register({ ws: wsA, agentId: "manager#1", userMessage: "x", abortController: ac, now });

  assert.equal(r.cancel(id), true);
  assert.equal(ac.signal.aborted, true);
  assert.equal(r.list().length, 0);
  // Second cancel is a no-op.
  assert.equal(r.cancel(id), false);
});

test("cancelForWs(ws) cancels only that ws's queries, leaves peer ws untouched", () => {
  const { r, now } = reg();
  const acA1 = new AbortController();
  const acA2 = new AbortController();
  const acB1 = new AbortController();
  r.register({ ws: wsA, agentId: "manager#1", userMessage: "a1", abortController: acA1, now });
  r.register({ ws: wsA, agentId: "manager#2", userMessage: "a2", abortController: acA2, now });
  r.register({ ws: wsB, agentId: "manager#1", userMessage: "b1", abortController: acB1, now });

  const n = r.cancelForWs(wsA);

  assert.equal(n, 2);
  assert.equal(acA1.signal.aborted, true);
  assert.equal(acA2.signal.aborted, true);
  assert.equal(acB1.signal.aborted, false, "peer ws's query MUST survive");
  const remaining = r.list();
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].userMessage, "b1");
});

test("cancelForAgent(ws, agentId) targets only the matching agent on that ws", () => {
  const { r, now } = reg();
  const acA1 = new AbortController();
  const acA2 = new AbortController();
  const acB1 = new AbortController();
  r.register({ ws: wsA, agentId: "manager#1", userMessage: "a1", abortController: acA1, now });
  r.register({ ws: wsA, agentId: "tech-lead#1", userMessage: "a2", abortController: acA2, now });
  r.register({ ws: wsB, agentId: "manager#1", userMessage: "b1", abortController: acB1, now });

  const n = r.cancelForAgent(wsA, "manager#1");

  assert.equal(n, 1);
  assert.equal(acA1.signal.aborted, true);
  assert.equal(acA2.signal.aborted, false, "same ws, different agent must survive");
  assert.equal(acB1.signal.aborted, false, "other ws same agent must survive");
});

test("list({ ws }) filters to only that ws's queries", () => {
  const { r, now } = reg();
  r.register({ ws: wsA, agentId: "manager#1", userMessage: "a", abortController: new AbortController(), now });
  r.register({ ws: wsB, agentId: "manager#1", userMessage: "b", abortController: new AbortController(), now });

  assert.equal(r.list({ ws: wsA }).length, 1);
  assert.equal(r.list({ ws: wsB }).length, 1);
  assert.equal(r.list().length, 2);
});

test("unregister(id) removes entry without aborting controller (natural-completion path)", () => {
  const { r, now } = reg();
  const ac = new AbortController();
  const id = r.register({ ws: wsA, agentId: "manager#1", userMessage: "x", abortController: ac, now });

  r.unregister(id);

  assert.equal(ac.signal.aborted, false, "natural completion does NOT abort");
  assert.equal(r.list().length, 0);
});

test("size reflects current entry count", () => {
  const { r, now } = reg();
  assert.equal(r.size, 0);
  const id1 = r.register({ ws: wsA, agentId: "manager#1", userMessage: "x", abortController: new AbortController(), now });
  assert.equal(r.size, 1);
  r.register({ ws: wsB, agentId: "manager#1", userMessage: "y", abortController: new AbortController(), now });
  assert.equal(r.size, 2);
  r.cancel(id1);
  assert.equal(r.size, 1);
});
