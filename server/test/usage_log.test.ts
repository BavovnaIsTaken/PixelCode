import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  UsageLogger,
  usageLogFile,
  newRunId,
  type UsageLogEntry,
} from "../src/usage_log.js";

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
      warn: (msg: string) => warned.push(msg),
    },
  };
}

function mkEntry(over: Partial<UsageLogEntry> = {}): UsageLogEntry {
  return {
    runId: "chat_1_111",
    role: "coder",
    taskType: "chat",
    agentId: "coder#1",
    inputTokens: 1200,
    outputTokens: 800,
    cacheCreationTokens: 0,
    cacheReadTokens: 500,
    costUsd: 0.0234,
    durationMs: 12345,
    numTurns: 4,
    numToolCalls: 2,
    startedAt: "2026-05-16T10:00:00Z",
    completedAt: "2026-05-16T10:00:12Z",
    ...over,
  };
}

describe("UsageLogger.record", () => {
  test("appends a JSONL line and round-trips through readAllEntries", () => {
    const fs = inMemoryFs();
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", fs.deps);
    log.record(mkEntry({ runId: "chat_1" }));
    log.record(mkEntry({ runId: "dispatch_1", taskType: "dispatch", role: "reviewer" }));

    const persisted = fs.files.get("/tmp/x/usage_log.jsonl") ?? "";
    const lines = persisted.split("\n").filter((l) => l.length > 0);
    assert.equal(lines.length, 2, "two newline-delimited entries written");

    const parsed = JSON.parse(lines[0]);
    assert.equal(parsed.runId, "chat_1");
    assert.equal(parsed.taskType, "chat");
    assert.equal(parsed.inputTokens, 1200);

    const read = log.readAllEntries();
    assert.equal(read.length, 2);
    assert.equal(read[0].runId, "chat_1");
    assert.equal(read[1].taskType, "dispatch");
    assert.equal(read[1].role, "reviewer");
  });

  test("disk failure is swallowed via warn (one bad write does not throw)", () => {
    const fs = inMemoryFs();
    const breaking = {
      ...fs.deps,
      appendLine: () => {
        throw new Error("ENOSPC");
      },
    };
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", breaking);
    log.record(mkEntry());
    // Returned without throwing; warning recorded.
    assert.equal(fs.warned.length, 1);
    assert.match(fs.warned[0], /append failed: ENOSPC/);
  });

  test("readAllEntries returns [] when file is missing", () => {
    const fs = inMemoryFs();
    const log = new UsageLogger("/tmp/nope.jsonl", fs.deps);
    assert.deepEqual(log.readAllEntries(), []);
  });

  test("readAllEntries skips corrupt JSON lines but keeps valid ones", () => {
    const corrupted =
      JSON.stringify(mkEntry({ runId: "good_a" })) +
      "\n" +
      "{not-json" +
      "\n" +
      JSON.stringify(mkEntry({ runId: "good_b" })) +
      "\n";
    const fs = inMemoryFs({ "/tmp/x/usage_log.jsonl": corrupted });
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", fs.deps);
    const entries = log.readAllEntries();
    assert.equal(entries.length, 2);
    assert.deepEqual(
      entries.map((e) => e.runId),
      ["good_a", "good_b"],
    );
    assert.equal(fs.warned.length, 1);
    assert.match(fs.warned[0], /skipped 1 corrupt/);
  });

  test("readAllEntries drops well-formed-but-wrong-shape lines", () => {
    // Missing required fields → should be skipped, not crash.
    const bad = JSON.stringify({ runId: "x", role: "coder" }) + "\n";
    const fs = inMemoryFs({ "/tmp/x/usage_log.jsonl": bad });
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", fs.deps);
    assert.deepEqual(log.readAllEntries(), []);
  });

  test("readAllEntries tolerates trailing whitespace and blank lines", () => {
    const raw =
      "\n" + JSON.stringify(mkEntry({ runId: "a" })) + "\n\n   \n" + JSON.stringify(mkEntry({ runId: "b" })) + "\n";
    const fs = inMemoryFs({ "/tmp/x/usage_log.jsonl": raw });
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", fs.deps);
    const entries = log.readAllEntries();
    assert.deepEqual(entries.map((e) => e.runId), ["a", "b"]);
  });

  test("read failure on existing file returns [] and warns", () => {
    const fs = inMemoryFs({ "/tmp/x/usage_log.jsonl": "ignored" });
    const log = new UsageLogger("/tmp/x/usage_log.jsonl", {
      ...fs.deps,
      readAll: () => {
        throw new Error("EIO");
      },
    });
    assert.deepEqual(log.readAllEntries(), []);
    assert.equal(fs.warned.length, 1);
    assert.match(fs.warned[0], /read failed: EIO/);
  });
});

describe("UsageLogger path layout + runId", () => {
  test("usageLogFile mirrors board_persistence project key layout", () => {
    const path = usageLogFile("/Users/x/proj", "/fake-home");
    // Format: {root}/.pixelcode/projects/{key}/usage_log.jsonl
    assert.match(path, /\/\.pixelcode\/projects\/.+\/usage_log\.jsonl$/);
    assert.ok(path.startsWith("/fake-home/.pixelcode/projects/"));
  });

  test("newRunId returns monotonically distinct ids with the requested prefix", () => {
    const a = newRunId("chat");
    const b = newRunId("chat");
    const c = newRunId("dispatch");
    assert.notEqual(a, b);
    assert.ok(a.startsWith("chat_"));
    assert.ok(c.startsWith("dispatch_"));
  });
});
