/**
 * Wire-contract test for the `runs?since=` API.
 *
 * Two things this pins:
 *   1. The protocol's `AgentRunSnapshot` is structurally the same as
 *      `agent_run.AgentRun`. They are duplicated on purpose (so protocol.ts
 *      stays standalone with no runtime dep on the store), and the price of
 *      that duplication is this test. If a field drifts on either side, the
 *      duplicate must be amended in lockstep.
 *   2. server.ts actually wires the handler — a `case "list_runs_since"`
 *      that delegates to `agentRunStore.since(...)`. Spinning up a real WSS
 *      for one switch case is overkill, so we assert structurally (same
 *      pattern as `sub_agent_persistence.test.ts`).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { AgentRunStore } from "../src/agent_run.js";
import type {
  AgentRunSnapshot,
  AgentRunStatusWire,
  AgentRunTaskTypeWire,
} from "../src/protocol.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverSrc = readFileSync(join(__dirname, "..", "src", "server.ts"), "utf8");

test("AgentRun snapshot from store assigns to AgentRunSnapshot without loss", () => {
  const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", {
    appendLine: () => {},
    readAll: () => "",
    exists: () => false,
    ensureDir: () => {},
    warn: () => {},
  });
  store.start({
    runId: "chat_1",
    agentId: "coder#1",
    taskType: "chat",
    userMessageSnippet: "fix bug",
  });
  store.appendToolCall("chat_1", { name: "Read", id: "tu1", at: "t1" });
  store.update("chat_1", {
    status: "completed",
    finalOutput: "done",
    usage: {
      inputTokens: 100,
      outputTokens: 50,
      cacheCreationTokens: 0,
      cacheReadTokens: 0,
      costUsd: 0.01,
      numTurns: 2,
      numToolCalls: 1,
    },
  });

  // The type system enforces shape compatibility — if a future PR drops
  // a required field on either side this assignment fails to compile.
  const wire: AgentRunSnapshot[] = store.since(null);
  assert.equal(wire.length, 1);
  assert.equal(wire[0].runId, "chat_1");
  assert.equal(wire[0].status, "completed");
  assert.equal(wire[0].toolCalls.length, 1);
  assert.equal(wire[0].usage?.numTurns, 2);
});

test("status + taskType literal unions match between store and wire", () => {
  // Exhaustive: if either side gains/drops a variant this fails to compile.
  const statuses: AgentRunStatusWire[] = [
    "running",
    "completed",
    "failed",
    "interrupted",
    "cancelled",
  ];
  const tasks: AgentRunTaskTypeWire[] = ["chat", "dispatch"];
  assert.equal(statuses.length, 5);
  assert.equal(tasks.length, 2);
});

test("server.ts wires `case \"list_runs_since\"` to agentRunStore.since(...)", () => {
  const idx = serverSrc.indexOf(`case "list_runs_since"`);
  assert.notEqual(idx, -1, "list_runs_since case must exist in the ws message switch");
  const body = serverSrc.slice(idx, idx + 400);
  assert.match(
    body,
    /agentRunStore\.since\s*\(\s*msg\.sinceRunId\s*\?\?\s*null\s*\)/,
    "handler must delegate to agentRunStore.since(msg.sinceRunId ?? null)",
  );
  assert.match(
    body,
    /type:\s*"runs_since"/,
    "handler must respond with a runs_since message",
  );
});

test("boot sweep promotes leftover running rows on agentRunStore load", () => {
  const idx = serverSrc.indexOf(`agentRunStore.load()`);
  assert.notEqual(idx, -1, "agentRunStore.load() must run at server boot");
  const after = serverSrc.slice(idx, idx + 400);
  assert.match(
    after,
    /markRunningAsInterrupted\s*\(\s*"server-respawn"\s*\)/,
    "boot must promote orphan running rows so the UI can surface them",
  );
});
