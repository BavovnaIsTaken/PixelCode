/**
 * Regression: a sub-agent dispatch must survive its parent ws disconnecting.
 *
 * The C.2.1 rule says in-flight queries keep running on disconnect because
 * results land in `chatHistory` and reach the client on reconnect via the
 * snapshot. A previous version of `handleSubAgentMessage` short-circuited on
 * `ws.readyState !== WebSocket.OPEN`, which broke that contract: every
 * `chatHistory.add(...)` and every `broadcastAll(...)` inside the handler was
 * skipped whenever the original client was gone — even though the SDK kept
 * generating tokens — so the dispatched work effectively vanished.
 *
 * Spinning up a real WSS for this is overkill: the fix is one statement and
 * the regression risk is "someone re-adds a readyState gate to make a lint
 * warning go away". A structural assertion on the source pins it.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const serverSrc = readFileSync(join(__dirname, "..", "src", "server.ts"), "utf8");

function bodyOf(fnName: string): string {
  const head = serverSrc.indexOf(`function ${fnName}`);
  assert.notEqual(head, -1, `${fnName} not found in server.ts — did it move?`);
  // Read enough to cover the early-return region (first few statements).
  return serverSrc.slice(head, head + 800);
}

test("handleSubAgentMessage does not early-return on ws.readyState", () => {
  const body = bodyOf("handleSubAgentMessage");
  assert.doesNotMatch(
    body,
    /readyState\s*!==?\s*WebSocket\.OPEN\s*\)\s*return/,
    "sub-agent persistence must not be gated on the parent ws — chatHistory.add() and broadcastAll() have to keep running so the dispatched work reaches the client on reconnect (C.2.1 contract)",
  );
});

test("ws.on('close') keeps the C.2.1 contract — no agentRunner.cancelAll(ws) call", () => {
  // Locate the close handler attached inside wss.on("connection", ...).
  const closeIdx = serverSrc.indexOf(`ws.on("close"`);
  assert.notEqual(closeIdx, -1, "close handler must exist");
  const closeBody = serverSrc.slice(closeIdx, closeIdx + 1500);
  assert.doesNotMatch(
    closeBody,
    /agentRunner\.cancelAll\s*\(\s*ws\s*\)/,
    "dispatch must survive client disconnect — C.2.1 explicitly forbids cancelling in-flight agents on ws close",
  );
  assert.doesNotMatch(
    closeBody,
    /chatQueryRegistry\.cancelForWs\s*\(\s*ws\s*\)/,
    "main chat queries must survive client disconnect for the same reason",
  );
});
