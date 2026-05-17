/**
 * Tests for the "periodic partial-assistant flush into ChatHistory" hook.
 *
 * Two surfaces are pinned:
 *   1. ChatHistory.add semantics — runId-keyed idempotence so the boot
 *      sweep and the runtime catch can both fire without producing
 *      duplicates.
 *   2. Source-level wiring — server.ts boot sweep and runQuery catch
 *      block commit the partial into chatHistory via the helper.
 *      Spinning up the whole server for this is overkill (the helper is
 *      pure side-effect on a singleton), and the regression risk is
 *      "someone deletes the call to make a lint warning go away". A
 *      structural assertion on the source pins it; same pattern as
 *      sub_agent_persistence.test.ts.
 */
import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { ChatHistory } from "../src/chat_history.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverSrc = readFileSync(join(__dirname, "..", "src", "server.ts"), "utf8");

describe("ChatHistory.add idempotence on runId-keyed partial", () => {
  test("second add with the same id is dropped (boot sweep + runtime catch can both fire)",
    () => {
      const h = new ChatHistory();
      h.add({
        role: "assistant",
        text: "Reading the stack trace…",
        agentId: "manager#1",
        timestamp: "2026-05-17T10:00:00Z",
        id: "chat_42_111",
      });
      h.add({
        role: "assistant",
        text: "DIFFERENT TEXT",
        agentId: "manager#1",
        timestamp: "2026-05-17T10:00:01Z",
        id: "chat_42_111",
      });
      const snap = h.snapshot();
      assert.equal(snap.type, "chat_history");
      assert.equal((snap as { messages: unknown[] }).messages.length, 1,
        "the second add must be dropped, not appended");
    });

  test("different runIds produce distinct entries", () => {
    const h = new ChatHistory();
    h.add({ role: "assistant", text: "A", agentId: "m#1", timestamp: "t1", id: "chat_a" });
    h.add({ role: "assistant", text: "B", agentId: "m#1", timestamp: "t2", id: "chat_b" });
    const snap = h.snapshot() as { messages: { id?: string }[] };
    assert.deepEqual(
      snap.messages.map((m) => m.id),
      ["chat_a", "chat_b"],
    );
  });

  test("snapshot round-trip preserves the runId so the client can dedupe across reconnect",
    () => {
      const h = new ChatHistory();
      h.add({
        role: "assistant",
        text: "partial",
        agentId: "m#1",
        timestamp: "t",
        id: "chat_42_111",
      });
      const snap = h.snapshot() as { messages: { id?: string }[] };
      assert.equal(snap.messages[0].id, "chat_42_111");
    });
});

describe("server.ts wires partial commit into chatHistory", () => {
  test("commitPartialToChatHistory helper exists and is unconditional", () => {
    assert.match(
      serverSrc,
      /function commitPartialToChatHistory\(/,
      "helper must exist",
    );
    // Helper writes to chatHistory with id=runId so dedupe holds.
    const start = serverSrc.indexOf("function commitPartialToChatHistory(");
    const body = serverSrc.slice(start, start + 1500);
    assert.match(body, /chatHistory\.add\(/, "must call chatHistory.add");
    assert.match(body, /id:\s*runId/, "must key the entry by runId");
    assert.match(body, /broadcastAll\(chatHistory\.snapshot\(\)\)/,
      "must broadcast the new snapshot to live peers");
  });

  test("explicit user cancel does NOT commit a partial (user already gave up)",
    () => {
      const start = serverSrc.indexOf("function commitPartialToChatHistory(");
      const body = serverSrc.slice(start, start + 1500);
      assert.match(
        body,
        /status === "cancelled"[^}]*return/s,
        "cancel must early-return — user explicitly stopped, no point surfacing",
      );
    });

  test("runQuery catch invokes commitPartialToChatHistory after agentRunStore.update",
    () => {
      // The catch block reuses the `completedAt` variable that's set
      // right before the agentRunStore.update call, so the two live
      // close together in the source. Anchor on the call itself rather
      // than re-finding the long runQuery body.
      const callIdx = serverSrc.indexOf("commitPartialToChatHistory(\n        _runId");
      assert.notEqual(
        callIdx,
        -1,
        "runQuery catch must call commitPartialToChatHistory(_runId, ...) so interrupted partials land in chat",
      );
      // The agentRunStore.update for the catch sits within ~600 chars
      // before the call (status flip + usage write + commit).
      const window = serverSrc.slice(Math.max(0, callIdx - 1500), callIdx);
      assert.match(
        window,
        /agentRunStore\.update\(_runId,\s*\{[^}]*status/s,
        "commitPartialToChatHistory must follow the agentRunStore.update that flips status to terminal",
      );
    });

  test("boot sweep folds partial outputs into chatHistory.add for each orphan",
    () => {
      const sweepIdx = serverSrc.indexOf("markRunningAsInterrupted(\"server-respawn\")");
      assert.notEqual(sweepIdx, -1, "boot sweep must exist");
      const after = serverSrc.slice(sweepIdx, sweepIdx + 1500);
      assert.match(after, /for \(const r of orphaned\)/,
        "boot sweep iterates orphans for partial commit");
      assert.match(after, /chatHistory\.add\(/,
        "each orphan with partialOutput must be folded into chatHistory");
      assert.match(after, /id:\s*r\.runId/,
        "orphan entry must key by runId for idempotence");
    });
});
