import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  AgentRunStore,
  agentRunsFile,
  isTerminalStatus,
  type AgentRun,
  type AgentRunStartInit,
} from "../src/agent_run.js";

function inMemoryFs(initial?: Record<string, string>) {
  const files = new Map<string, string>();
  if (initial) {
    for (const [k, v] of Object.entries(initial)) files.set(k, v);
  }
  const warned: string[] = [];
  return {
    files,
    warned,
    deps: {
      appendLine: (path: string, line: string) => {
        files.set(path, (files.get(path) ?? "") + line + "\n");
      },
      readAll: (path: string) => {
        const v = files.get(path);
        if (v === undefined) throw new Error(`ENOENT: ${path}`);
        return v;
      },
      exists: (path: string) => files.has(path),
      ensureDir: () => {},
      writeAll: (path: string, content: string) => {
        files.set(path, content);
      },
      warn: (msg: string) => warned.push(msg),
    },
  };
}

/** Deterministic clock helper — every call advances by 1 ms so terminal
 *  status auto-stamps a monotonic completedAt for assertions. */
function fakeClock(start: number) {
  let t = start;
  return () => new Date(t++);
}

const baseInit: AgentRunStartInit = {
  runId: "chat_1_111",
  agentId: "coder#1",
  taskType: "chat",
  userMessageId: "msg-abc",
  userMessageSnippet: "Fix the build",
  startedAt: "2026-05-17T10:00:00.000Z",
};

describe("AgentRunStore.start + update lifecycle", () => {
  test("start writes a running snapshot and caches it", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    const run = store.start(baseInit);

    assert.equal(run.status, "running");
    assert.equal(run.runId, "chat_1_111");
    assert.equal(run.userMessageSnippet, "Fix the build");
    assert.deepEqual(run.toolCalls, []);

    const persisted = fs.files.get("/tmp/x/agent_runs.jsonl") ?? "";
    assert.equal(persisted.split("\n").filter((l) => l).length, 1);
  });

  test("update appends a new snapshot — last line wins on replay", () => {
    const fs = inMemoryFs();
    const clock = fakeClock(Date.UTC(2026, 4, 17, 10, 0, 5));
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", {
      ...fs.deps,
      now: clock,
    });
    store.start(baseInit);
    store.update("chat_1_111", { partialOutput: "Hello, looking..." });
    const final = store.update("chat_1_111", {
      status: "completed",
      finalOutput: "Build is fixed.",
      usage: {
        inputTokens: 1200,
        outputTokens: 800,
        cacheCreationTokens: 0,
        cacheReadTokens: 500,
        costUsd: 0.0234,
        numTurns: 4,
        numToolCalls: 2,
      },
    });

    assert.equal(final?.status, "completed");
    assert.equal(final?.finalOutput, "Build is fixed.");
    assert.ok(final?.completedAt, "completedAt auto-stamped on terminal");

    const lines = (fs.files.get("/tmp/x/agent_runs.jsonl") ?? "")
      .split("\n")
      .filter((l) => l);
    assert.equal(lines.length, 3, "start + 2 updates → 3 snapshot rows");

    // Replay → latest row wins
    const replay = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    replay.load();
    const got = replay.get("chat_1_111");
    assert.equal(got?.status, "completed");
    assert.equal(got?.finalOutput, "Build is fixed.");
    assert.equal(got?.usage?.numTurns, 4);
  });

  test("update on unknown runId is a no-op + warn (does not throw)", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    const r = store.update("nope", { status: "completed" });
    assert.equal(r, null);
    assert.equal(fs.warned.length, 1);
    assert.match(fs.warned[0], /unknown runId=nope/);
  });

  test("terminal status auto-stamps completedAt only when missing", () => {
    const fs = inMemoryFs();
    const explicit = "2026-05-17T10:00:42.000Z";
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start(baseInit);
    const r = store.update("chat_1_111", {
      status: "interrupted",
      completedAt: explicit,
      reason: "circuit-breaker",
    });
    assert.equal(r?.completedAt, explicit, "caller-provided value preserved");
  });

  test("appendToolCall threads through update without clobbering history", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start(baseInit);
    store.appendToolCall("chat_1_111", { name: "Read", id: "tu1", at: "t1" });
    store.appendToolCall("chat_1_111", { name: "Edit", id: "tu2", at: "t2" });
    const got = store.get("chat_1_111");
    assert.equal(got?.toolCalls.length, 2);
    assert.equal(got?.toolCalls[0].name, "Read");
    assert.equal(got?.toolCalls[1].name, "Edit");
  });
});

describe("AgentRunStore disk failure tolerance", () => {
  test("append failure is swallowed; in-memory state still advances", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", {
      ...fs.deps,
      appendLine: () => {
        throw new Error("ENOSPC");
      },
    });
    store.start(baseInit);
    const updated = store.update("chat_1_111", { status: "completed" });
    assert.equal(updated?.status, "completed", "memory caches even when disk fails");
    assert.ok(fs.warned.some((w) => /append failed: ENOSPC/.test(w)));
  });

  test("load tolerates corrupt + wrong-shape lines and warns once", () => {
    const good1 = JSON.stringify({
      runId: "a",
      agentId: "coder#1",
      taskType: "chat",
      status: "running",
      startedAt: "t1",
      toolCalls: [],
    });
    const good2 = JSON.stringify({
      runId: "b",
      agentId: "tester#1",
      taskType: "dispatch",
      status: "completed",
      startedAt: "t2",
      toolCalls: [],
      completedAt: "t3",
    });
    const corrupted =
      good1 +
      "\n" +
      "{not-json" +
      "\n" +
      // well-formed JSON, wrong shape → must be skipped
      JSON.stringify({ runId: "c", foo: "bar" }) +
      "\n" +
      good2 +
      "\n";
    const fs = inMemoryFs({ "/tmp/x/agent_runs.jsonl": corrupted });
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.load();
    assert.deepEqual(
      store.all().map((r) => r.runId),
      ["a", "b"],
    );
    assert.ok(fs.warned.some((w) => /skipped 2 corrupt/.test(w)));
  });

  test("load on missing file is a silent no-op", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/missing.jsonl", fs.deps);
    store.load();
    assert.equal(fs.warned.length, 0);
    assert.deepEqual(store.all(), []);
  });

  test("load is idempotent — calling twice does not duplicate runs", () => {
    const line = JSON.stringify({
      runId: "a",
      agentId: "coder#1",
      taskType: "chat",
      status: "running",
      startedAt: "t1",
      toolCalls: [],
    });
    const fs = inMemoryFs({ "/tmp/x/agent_runs.jsonl": line + "\n" });
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.load();
    store.load();
    assert.equal(store.all().length, 1);
  });
});

describe("AgentRunStore load-time compaction + retention", () => {
  function runLine(runId: string, status = "completed"): string {
    return JSON.stringify({
      runId,
      agentId: "coder#1",
      taskType: "chat",
      status,
      startedAt: "t1",
      toolCalls: [],
    });
  }

  test("redundant transition rows are folded into one line per run", () => {
    const file = "/tmp/x/agent_runs.jsonl";
    // Run "a" went through 3 transitions, run "b" through 2.
    const raw = [
      runLine("a", "running"),
      runLine("a", "running"),
      runLine("b", "running"),
      runLine("a", "completed"),
      runLine("b", "failed"),
    ].join("\n") + "\n";
    const fs = inMemoryFs({ [file]: raw });
    const store = new AgentRunStore(file, fs.deps);
    store.load();

    const lines = (fs.files.get(file) ?? "").split("\n").filter((l) => l.trim());
    assert.equal(lines.length, 2);
    assert.equal(store.get("a")?.status, "completed");
    assert.equal(store.get("b")?.status, "failed");
    // Compacted file replays to the identical state.
    const replay = new AgentRunStore(file, inMemoryFs({ [file]: fs.files.get(file)! }).deps);
    replay.load();
    assert.deepEqual(replay.all(), store.all());
  });

  test("runs beyond maxRetainedRuns are evicted oldest-first", () => {
    const file = "/tmp/x/agent_runs.jsonl";
    const raw = ["a", "b", "c", "d", "e"].map((id) => runLine(id)).join("\n") + "\n";
    const fs = inMemoryFs({ [file]: raw });
    const store = new AgentRunStore(file, { ...fs.deps, maxRetainedRuns: 3 });
    store.load();

    assert.deepEqual(store.all().map((r) => r.runId), ["c", "d", "e"]);
    const lines = (fs.files.get(file) ?? "").split("\n").filter((l) => l.trim());
    assert.equal(lines.length, 3);
    assert.ok(fs.warned.some((w) => /evicted 2 old run/.test(w)));
  });

  test("already-compact file is left untouched", () => {
    const file = "/tmp/x/agent_runs.jsonl";
    const raw = runLine("a") + "\n" + runLine("b") + "\n";
    const fs = inMemoryFs({ [file]: raw });
    let rewrites = 0;
    const store = new AgentRunStore(file, {
      ...fs.deps,
      writeAll: () => {
        rewrites++;
      },
    });
    store.load();
    assert.equal(rewrites, 0);
    assert.equal(fs.files.get(file), raw);
  });

  test("compaction write failure is non-fatal — memory state intact", () => {
    const file = "/tmp/x/agent_runs.jsonl";
    const raw = runLine("a", "running") + "\n" + runLine("a", "completed") + "\n";
    const fs = inMemoryFs({ [file]: raw });
    const store = new AgentRunStore(file, {
      ...fs.deps,
      writeAll: () => {
        throw new Error("disk full");
      },
    });
    store.load();
    assert.equal(store.get("a")?.status, "completed");
    assert.ok(fs.warned.some((w) => /compaction failed: disk full/.test(w)));
  });
});

describe("AgentRunStore boot sweep — markRunningAsInterrupted", () => {
  test("promotes every running snapshot to interrupted with reason", () => {
    const fs = inMemoryFs();
    const clock = fakeClock(Date.UTC(2026, 4, 17, 10, 0, 0));
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", {
      ...fs.deps,
      now: clock,
    });
    store.start({ ...baseInit, runId: "a" });
    store.start({ ...baseInit, runId: "b", agentId: "tester#1" });
    store.update("a", { status: "completed" });
    // 'b' is still running.

    const swept = store.markRunningAsInterrupted("server-respawn");
    assert.equal(swept.length, 1);
    assert.equal(swept[0].runId, "b");
    assert.equal(swept[0].status, "interrupted");
    assert.equal(swept[0].reason, "server-respawn");
    assert.ok(swept[0].completedAt, "completedAt stamped");

    // 'a' is already terminal → untouched.
    assert.equal(store.get("a")?.status, "completed");
  });

  test("sweep is a no-op when nothing is running", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    assert.deepEqual(store.markRunningAsInterrupted("any"), []);
  });
});

describe("AgentRunStore.since (runs?since= API)", () => {
  test("null cursor returns every run in insertion order", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start({ ...baseInit, runId: "a" });
    store.start({ ...baseInit, runId: "b" });
    store.start({ ...baseInit, runId: "c" });
    assert.deepEqual(
      store.since(null).map((r) => r.runId),
      ["a", "b", "c"],
    );
  });

  test("known cursor returns the strictly newer suffix", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start({ ...baseInit, runId: "a" });
    store.start({ ...baseInit, runId: "b" });
    store.start({ ...baseInit, runId: "c" });
    assert.deepEqual(
      store.since("a").map((r) => r.runId),
      ["b", "c"],
    );
    assert.deepEqual(store.since("c").map((r) => r.runId), []);
  });

  test("unknown cursor falls back to full list (do not lose data)", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start({ ...baseInit, runId: "a" });
    store.start({ ...baseInit, runId: "b" });
    assert.deepEqual(
      store.since("missing").map((r) => r.runId),
      ["a", "b"],
    );
  });

  test("since reflects the latest snapshot, not the start row", () => {
    const fs = inMemoryFs();
    const store = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    store.start({ ...baseInit, runId: "a" });
    store.update("a", { status: "completed", finalOutput: "done" });
    const got = store.since(null);
    assert.equal(got[0].status, "completed");
    assert.equal(got[0].finalOutput, "done");
  });
});

describe("isTerminalStatus", () => {
  test("running is not terminal; everything else is", () => {
    assert.equal(isTerminalStatus("running"), false);
    for (const s of ["completed", "failed", "interrupted", "cancelled"] as const) {
      assert.equal(isTerminalStatus(s), true, `${s} should be terminal`);
    }
  });
});

describe("agentRunsFile path layout", () => {
  test("mirrors usage_log / board_persistence project key layout", () => {
    const path = agentRunsFile("/Users/x/proj", "/fake-home");
    assert.match(path, /\/\.pixelcode\/projects\/.+\/agent_runs\.jsonl$/);
    assert.ok(path.startsWith("/fake-home/.pixelcode/projects/"));
  });
});

describe("AgentRunStore replay → boot sweep flow", () => {
  test("after restart, leftover running rows are promoted on sweep", () => {
    // First session: start two runs, finish one, leave one running.
    const fs = inMemoryFs();
    const s1 = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    s1.start({ ...baseInit, runId: "alpha" });
    s1.start({ ...baseInit, runId: "beta", agentId: "tester#1" });
    s1.update("alpha", { status: "completed", finalOutput: "ok" });

    // Server "restart" — fresh store on the same disk content.
    const s2 = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    s2.load();
    const stillRunning = s2.running();
    assert.equal(stillRunning.length, 1);
    assert.equal(stillRunning[0].runId, "beta");

    const swept = s2.markRunningAsInterrupted("server-respawn");
    assert.equal(swept.length, 1);

    // After sweep, replay reflects both terminal states.
    const s3 = new AgentRunStore("/tmp/x/agent_runs.jsonl", fs.deps);
    s3.load();
    assert.equal(s3.get("alpha")?.status, "completed");
    assert.equal(s3.get("beta")?.status, "interrupted");
    assert.equal(s3.get("beta")?.reason, "server-respawn");
    assert.equal(s3.running().length, 0);
  });
});

// Type-only: verify the AgentRun export is structurally what we expect.
// If a future PR drops a required field, this file fails to compile.
const _typeCheck: AgentRun = {
  runId: "x",
  agentId: "coder#1",
  taskType: "chat",
  status: "running",
  toolCalls: [],
  startedAt: "t",
};
void _typeCheck;
