/**
 * Status-emission invariant (C.2.6) — pin "every agent registry cleanup is
 * paired with a fresh `agent_status: idle` emission so chat-header indicators
 * never go stale" as a structural rule.
 *
 * Background: a 2026-05-18 incident showed chat panel sticking on "Reading
 * char_0.png — 172m" while Settings → Активні агенти correctly displayed
 * "Зараз ніхто не працює". Root cause: `chatQueryRegistry.unregister()`
 * cleared the registry and `broadcastActiveAgents` cleared the Settings
 * tab, but no corresponding `agent_status: idle` push was emitted — so the
 * sticky `agentsProvider` cache on the client kept rendering the last
 * non-idle status forever.
 *
 * This test scans `server/src/server.ts` and asserts that every function
 * body containing a registry-cleanup call also contains an idle status
 * emission (literal `status: "idle"`) and a `broadcastActiveAgents` call.
 *
 * Add to WHITELIST only if the cleanup is deliberately bare (e.g. the
 * cleanup is part of a per-agent loop that emits idle for each iteration
 * outside the function-body window the regex sees).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const SERVER_TS = fileURLToPath(new URL("../src/server.ts", import.meta.url));

interface CleanupSite {
  /** Call that mutates the active-agents registry */
  call: RegExp;
  /** Human label for failure messages */
  label: string;
}

const CLEANUP_SITES: CleanupSite[] = [
  { call: /chatQueryRegistry\.unregister\s*\(/g, label: "chatQueryRegistry.unregister" },
  { call: /chatQueryRegistry\.cancel\s*\(/g, label: "chatQueryRegistry.cancel" },
  { call: /chatQueryRegistry\.cancelForWs\s*\(/g, label: "chatQueryRegistry.cancelForWs" },
  { call: /agentRunner\.cancel\s*\(/g, label: "agentRunner.cancel" },
  { call: /agentRunner\.cancelAll\s*\(/g, label: "agentRunner.cancelAll" },
];

/** Lines whose enclosing block is allowed to skip the idle/broadcast pair.
 *  Add a paired explanation when adding entries — the goal is to fail loud
 *  by default, not to grow exemptions silently. */
const WHITELIST: ReadonlyArray<{ snippet: string; reason: string }> = [
  // chat_query cancel propagates into runQuery's AbortController → the
  // outer catch there emits idle. No second emission at the WS handler.
  {
    snippet: "chatQueryRegistry.cancel(msg.queryId)",
    reason: "cancel propagates to runQuery's outer catch, which emits idle",
  },
  // chatQueryRegistry.cancelForWs inside cancel_all_active is symmetric:
  // each cancelled chat query routes through runQuery's catch which emits
  // idle for its own agentId. The dispatch-side cancels emit idle via the
  // explicit per-agentId loop in the same handler.
  {
    snippet: "chatQueryRegistry.cancelForWs(ws)",
    reason: "per-agent idle emission lives in dispatchAgentIds loop above",
  },
  // Project switch: after agentRunner.cancelAll() with no args, every peer
  // is hard-reset via a fresh `init` push + roster wipe (see the
  // for-peer loop ~30 lines below). That counts as a stronger reset than
  // a per-agent idle emission.
  {
    snippet: "Dropped ${dropped} queued task(s) on project switch",
    reason: "project-switch issues fresh init to every peer downstream",
  },
];

/** Extract the brace-balanced block that contains an offset. Returns the
 *  source slice from the opening `{` of the closest enclosing function /
 *  case body / for-block. Simple line-based heuristic: walk backwards to
 *  the most recent unmatched `{`, then forward to its matching `}`. */
function enclosingBlock(src: string, offset: number): string {
  let depth = 0;
  let openAt = -1;
  for (let i = offset; i >= 0; i--) {
    const c = src[i];
    if (c === "}") depth++;
    else if (c === "{") {
      if (depth === 0) {
        openAt = i;
        break;
      }
      depth--;
    }
  }
  if (openAt < 0) return src.slice(Math.max(0, offset - 500), offset + 500);

  let close = openAt;
  let d = 0;
  for (let i = openAt; i < src.length; i++) {
    const c = src[i];
    if (c === "{") d++;
    else if (c === "}") {
      d--;
      if (d === 0) {
        close = i;
        break;
      }
    }
  }
  return src.slice(openAt, close + 1);
}

function lineOf(src: string, offset: number): number {
  return src.slice(0, offset).split("\n").length;
}

test("every active-agents cleanup site in server.ts pairs with idle emission", () => {
  const src = readFileSync(SERVER_TS, "utf8");
  const violations: string[] = [];

  for (const site of CLEANUP_SITES) {
    site.call.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = site.call.exec(src)) !== null) {
      const block = enclosingBlock(src, m.index);
      const whitelisted = WHITELIST.some((w) => block.includes(w.snippet));
      if (whitelisted) continue;

      const hasIdle = /status\s*:\s*"idle"/.test(block);
      const hasBroadcast = /broadcastActiveAgents\s*\(/.test(block);
      // Cleanup that does both: a call to runQuery from elsewhere will
      // route through its own catch + finally which emit idle. Recognise
      // by the runQuery / runAgent surroundings.
      const insideRunQueryOrAgent =
        /function\s+runQuery\s*\(/.test(block) ||
        /private\s+async\s+runAgent\s*\(/.test(block);

      if (insideRunQueryOrAgent && hasIdle && hasBroadcast) continue;
      if (!insideRunQueryOrAgent && hasIdle && hasBroadcast) continue;

      const line = lineOf(src, m.index);
      const missing = [
        hasIdle ? null : "agent_status: idle emission",
        hasBroadcast ? null : "broadcastActiveAgents",
      ].filter(Boolean);
      violations.push(
        `server.ts:${line} → ${site.label} without ${missing.join(" + ")}`,
      );
    }
  }

  assert.deepEqual(
    violations,
    [],
    "C.2.6 status-emission invariant broken. Each registry-cleanup site MUST " +
      "be paired with a fresh `agent_status: idle` push AND a " +
      "`broadcastActiveAgents` call, otherwise client UI surfaces diverge " +
      "(chat header stays on 'Reading' while Settings shows 'no one working'). " +
      "Add to WHITELIST only with a justification.\n\n" +
      violations.map((v) => "  - " + v).join("\n"),
  );
});
