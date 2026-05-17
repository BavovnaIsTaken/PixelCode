/**
 * Regression net for the C.2 reconnect-resilience invariant:
 *
 *   "Kill the client mid-run → reopen → the assistant text the agent had
 *    already produced is still present."
 *
 * The full e2e path involves a real ws + SDK + breaker; that's covered
 * loosely by sub_agent_persistence + agent_run_protocol shape tests.
 * This file pins the *state-machine* contract on the persistence layer
 * directly — the part most prone to silent regression if someone changes
 * how partials are flushed.
 *
 * Failure modes guarded:
 *  1. Partial text not flushed to the store while running → reconnect
 *     shows nothing even though the agent had typed half a reply.
 *  2. Boot sweep doesn't promote orphaned `running` rows → UI thinks
 *     the run is still alive on a server that has already restarted.
 *  3. since() forgets partials of interrupted runs → banner appears
 *     but the modal is empty.
 */
import { test, describe } from "node:test";
import assert from "node:assert/strict";

import { AgentRunStore } from "../src/agent_run.js";

function inMemFs() {
  const files = new Map<string, string>();
  return {
    files,
    deps: {
      appendLine: (path: string, line: string) =>
        files.set(path, (files.get(path) ?? "") + line + "\n"),
      readAll: (path: string) => {
        const v = files.get(path);
        if (v === undefined) throw new Error(`ENOENT: ${path}`);
        return v;
      },
      exists: (path: string) => files.has(path),
      ensureDir: () => {},
      warn: () => {},
    },
  };
}

describe("kill-ws-mid-run regression — partial output survives", () => {
  test("partial flush during run is retrievable after store reload", () => {
    // ─── First "session": agent starts replying, then the process dies.
    const fs1 = inMemFs();
    const s1 = new AgentRunStore("/p/agent_runs.jsonl", fs1.deps);
    s1.start({
      runId: "chat_1",
      agentId: "manager#1",
      taskType: "chat",
      userMessageSnippet: "diagnose the crash",
    });
    // Simulate the per-assistant-block partial flush that runQuery does.
    s1.update("chat_1", { partialOutput: "Reading the stack trace…" });
    s1.update("chat_1", {
      partialOutput: "Reading the stack trace… The NPE comes from foo()",
    });
    // No terminal update — the process exits here.

    // ─── Server respawn: fresh store on the same disk.
    const s2 = new AgentRunStore("/p/agent_runs.jsonl", fs1.deps);
    s2.load();
    const recovered = s2.get("chat_1");
    assert.ok(recovered, "run row must replay from disk");
    assert.equal(
      recovered!.partialOutput,
      "Reading the stack trace… The NPE comes from foo()",
      "the most recently flushed partial wins on replay (last-write-wins)",
    );
    assert.equal(recovered!.status, "running",
      "without the sweep, status carries forward as-is");
  });

  test("boot sweep promotes the orphan to interrupted and keeps the partial",
    () => {
      const fs = inMemFs();
      const s1 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s1.start({
        runId: "chat_1",
        agentId: "manager#1",
        taskType: "chat",
        userMessageSnippet: "diagnose the crash",
      });
      s1.update("chat_1", { partialOutput: "Reading the stack trace…" });

      const s2 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s2.load();
      const swept = s2.markRunningAsInterrupted("server-respawn");
      assert.equal(swept.length, 1);

      const after = s2.get("chat_1");
      assert.equal(after?.status, "interrupted",
        "orphan must be promoted so UI can surface it");
      assert.equal(
        after?.partialOutput,
        "Reading the stack trace…",
        "sweep MUST NOT drop the partial — that's the only crash-recovery payload the UI shows",
      );
      assert.equal(after?.reason, "server-respawn");
      assert.ok(after?.completedAt, "completedAt stamped on sweep");
    });

  test("since(null) returns the interrupted run with its partial intact",
    () => {
      const fs = inMemFs();
      const s1 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s1.start({
        runId: "chat_1",
        agentId: "manager#1",
        taskType: "chat",
        userMessageSnippet: "diagnose the crash",
      });
      s1.update("chat_1", { partialOutput: "Reading the stack trace…" });

      const s2 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s2.load();
      s2.markRunningAsInterrupted("server-respawn");

      // The client's reconnect call → server's `agentRunStore.since(null)`.
      const list = s2.since(null);
      assert.equal(list.length, 1);
      const wire = list[0];
      assert.equal(wire.status, "interrupted");
      assert.equal(wire.partialOutput, "Reading the stack trace…");
      assert.equal(wire.userMessageSnippet, "diagnose the crash");
    });

  test("multi-run mid-flight: only the interrupted ones surface; completed stays terminal",
    () => {
      const fs = inMemFs();
      const s1 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s1.start({
        runId: "chat_1",
        agentId: "manager#1",
        taskType: "chat",
      });
      s1.update("chat_1", { status: "completed", finalOutput: "Fixed." });

      s1.start({
        runId: "chat_2",
        agentId: "tech-lead#1",
        taskType: "chat",
      });
      s1.update("chat_2", { partialOutput: "Looking at the plan…" });
      // chat_2 left running.

      const s2 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s2.load();
      s2.markRunningAsInterrupted("server-respawn");

      const all = s2.since(null);
      assert.equal(all.length, 2);
      const map = Object.fromEntries(all.map((r) => [r.runId, r]));
      assert.equal(map["chat_1"].status, "completed",
        "already-terminal runs must not be touched by the sweep");
      assert.equal(map["chat_2"].status, "interrupted");
      assert.equal(map["chat_2"].partialOutput, "Looking at the plan…");
    });

  test("since(cursor) on reconnect skips runs the client already has",
    () => {
      // First session: two interrupted runs.
      const fs = inMemFs();
      const s1 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s1.start({ runId: "chat_1", agentId: "manager#1", taskType: "chat" });
      s1.markRunningAsInterrupted("server-respawn");
      s1.start({ runId: "chat_2", agentId: "manager#1", taskType: "chat" });
      s1.update("chat_2", { partialOutput: "more text" });

      const s2 = new AgentRunStore("/p/agent_runs.jsonl", fs.deps);
      s2.load();
      s2.markRunningAsInterrupted("server-respawn");

      // Client had already seen chat_1 last time it was online.
      const delta = s2.since("chat_1");
      assert.deepEqual(delta.map((r) => r.runId), ["chat_2"],
        "cursor delivery is strictly newer than the supplied id");
      assert.equal(delta[0].partialOutput, "more text");
    });
});
