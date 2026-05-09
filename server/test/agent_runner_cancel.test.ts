/**
 * Pin the per-ws semantics of `AgentRunner.cancelAll(ws)`. The bug was
 * that `cancelAll(ws?)` ignored its argument and aborted EVERY running
 * agent — so when one peer disconnected, the disconnect handler took
 * down agents owned by every other connected device too.
 *
 * Tests seed the private `running` map directly via the public-API
 * trapdoor (cast to `any`) instead of going through `dispatch()`, which
 * would require booting the Claude SDK + a real ws. The cancellation
 * logic itself is what we want under test, not the dispatch plumbing.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { AgentRunner, type RunningAgent } from "../src/agent_runner.js";

const wsA = { id: "A" } as any;
const wsB = { id: "B" } as any;

function fakeRunningAgent(id: string, ws: any): RunningAgent {
  return {
    dispatchId: id,
    agentId: `coder#${id}`,
    task: "fake",
    abortController: new AbortController(),
    startedAt: Date.now(),
    promise: Promise.resolve(),
    ws,
  };
}

function seed(runner: AgentRunner, entries: RunningAgent[]): void {
  const inner = (runner as any).running as Map<string, RunningAgent>;
  for (const e of entries) inner.set(e.dispatchId, e);
}

test("cancelAll(ws) cancels ONLY that ws's running agents, leaves peers running", () => {
  const runner = new AgentRunner();
  const a1 = fakeRunningAgent("a1", wsA);
  const a2 = fakeRunningAgent("a2", wsA);
  const b1 = fakeRunningAgent("b1", wsB);
  seed(runner, [a1, a2, b1]);

  runner.cancelAll(wsA);

  assert.equal(a1.abortController.signal.aborted, true, "wsA agent a1 aborted");
  assert.equal(a2.abortController.signal.aborted, true, "wsA agent a2 aborted");
  assert.equal(b1.abortController.signal.aborted, false, "wsB agent must NOT be touched on wsA disconnect");

  // Internal map: only b1 should remain.
  const remaining = runner.getRunning().map((r) => r.dispatchId).sort();
  assert.deepEqual(remaining, ["b1"]);
});

test("cancelAll() with no arg cancels everything (project-switch / shutdown path)", () => {
  const runner = new AgentRunner();
  const a1 = fakeRunningAgent("a1", wsA);
  const b1 = fakeRunningAgent("b1", wsB);
  seed(runner, [a1, b1]);

  runner.cancelAll();

  assert.equal(a1.abortController.signal.aborted, true);
  assert.equal(b1.abortController.signal.aborted, true);
  assert.equal(runner.getRunning().length, 0);
});

test("cancelAll(ws) for a ws with no running agents is a no-op", () => {
  const runner = new AgentRunner();
  const b1 = fakeRunningAgent("b1", wsB);
  seed(runner, [b1]);

  runner.cancelAll(wsA);
  assert.equal(b1.abortController.signal.aborted, false);
  assert.equal(runner.getRunning().length, 1);
});
