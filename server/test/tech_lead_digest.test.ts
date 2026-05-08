import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  DigestStore,
  TechLeadDigest,
  type DigestEntry,
} from "../src/tech_lead_digest.js";

// ─── DigestStore (ring buffer) ─────────────────────────────────────────────

describe("DigestStore", () => {
  const mk = (id: string): DigestEntry => ({
    taskId: id,
    title: `t-${id}`,
    agentId: "coder-1",
    role: "coder",
    outcome: "done",
    ts: "2026-05-08T10:00:00Z",
  });

  test("appends entries in order, newest last", () => {
    const s = new DigestStore(5);
    s.add(mk("a"));
    s.add(mk("b"));
    s.add(mk("c"));
    assert.deepEqual(s.recent().map((e) => e.taskId), ["a", "b", "c"]);
  });

  test("evicts oldest when capacity exceeded", () => {
    const s = new DigestStore(3);
    for (const id of ["a", "b", "c", "d", "e"]) s.add(mk(id));
    assert.equal(s.size, 3);
    assert.deepEqual(s.recent().map((e) => e.taskId), ["c", "d", "e"]);
  });

  test("recent(N) returns last N, full when N >= size", () => {
    const s = new DigestStore(10);
    for (const id of ["a", "b", "c", "d"]) s.add(mk(id));
    assert.deepEqual(s.recent(2).map((e) => e.taskId), ["c", "d"]);
    assert.deepEqual(s.recent(99).map((e) => e.taskId), ["a", "b", "c", "d"]);
  });

  test("capacity floors at 1 even if 0 or negative supplied", () => {
    const s = new DigestStore(0);
    s.add(mk("a"));
    s.add(mk("b"));
    assert.equal(s.size, 1);
    assert.equal(s.recent()[0].taskId, "b");
  });
});

// ─── TechLeadDigest (JSONL persist + replay) ───────────────────────────────

describe("TechLeadDigest persistence", () => {
  function inMemoryFs(initial: string = "") {
    const files = new Map<string, string>();
    if (initial) files.set("/tmp/x/digest.jsonl", initial);
    return {
      files,
      deps: {
        appendLine: (path: string, line: string) => {
          files.set(path, (files.get(path) ?? "") + line + "\n");
        },
        readAll: (path: string) => files.get(path) ?? "",
        exists: (path: string) => files.has(path),
        ensureDir: () => {},
        warn: () => {},
        now: (() => {
          let n = 0;
          return () => `2026-05-08T00:00:${String(n++).padStart(2, "0")}Z`;
        })(),
      },
    };
  }

  test("recordCompletion persists JSONL line and updates ring", () => {
    const fs = inMemoryFs();
    const d = new TechLeadDigest("/tmp/x/digest.jsonl", fs.deps);
    d.recordCompletion({
      taskId: "task_1_x",
      title: "Add auth",
      agentId: "coder-1",
      role: "coder",
    });
    d.recordCompletion({
      taskId: "task_2_x",
      title: "Wire tests",
      agentId: "tester-1",
      role: "tester",
    });
    assert.equal(d.recent().length, 2);
    const persisted = fs.files.get("/tmp/x/digest.jsonl") ?? "";
    const lines = persisted.split("\n").filter((l) => l.length > 0);
    assert.equal(lines.length, 2);
    assert.equal(JSON.parse(lines[0]).taskId, "task_1_x");
    assert.equal(JSON.parse(lines[1]).role, "tester");
  });

  test("loadFromDisk replays valid lines and skips corrupt ones", () => {
    const goodA: DigestEntry = {
      taskId: "a", title: "A", agentId: "coder-1", role: "coder",
      outcome: "done", ts: "2026-05-08T10:00:00Z",
    };
    const goodB: DigestEntry = {
      taskId: "b", title: "B", agentId: "tester-1", role: "tester",
      outcome: "done", ts: "2026-05-08T10:00:01Z",
    };
    const initial =
      JSON.stringify(goodA) + "\n" +
      "{ corrupt json\n" +
      JSON.stringify(goodB) + "\n" +
      JSON.stringify({ ...goodA, outcome: "weird" }) + "\n"; // wrong outcome → skipped
    const fs = inMemoryFs(initial);
    const d = new TechLeadDigest("/tmp/x/digest.jsonl", fs.deps);
    d.loadFromDisk();
    assert.deepEqual(d.recent().map((e) => e.taskId), ["a", "b"]);
  });

  test("loadFromDisk noop when file missing", () => {
    const fs = inMemoryFs();
    const d = new TechLeadDigest("/tmp/x/missing.jsonl", fs.deps);
    d.loadFromDisk();
    assert.equal(d.recent().length, 0);
  });

  test("disk write failure is swallowed; in-memory entry still added", () => {
    const fs = inMemoryFs();
    const failingDeps = {
      ...fs.deps,
      appendLine: () => {
        throw new Error("disk full");
      },
    };
    const d = new TechLeadDigest("/tmp/x/digest.jsonl", failingDeps);
    const entry = d.recordCompletion({
      taskId: "t1", title: "X", agentId: "coder-1", role: "coder",
    });
    assert.equal(d.recent().length, 1);
    assert.equal(entry.taskId, "t1");
  });

  test("renderForPrompt returns block with newest first; empty when no entries", () => {
    const fs = inMemoryFs();
    const d = new TechLeadDigest("/tmp/x/digest.jsonl", fs.deps);
    assert.equal(d.renderForPrompt(), "");
    d.recordCompletion({ taskId: "a", title: "First", agentId: "coder-1", role: "coder" });
    d.recordCompletion({ taskId: "b", title: "Second", agentId: "tester-1", role: "tester" });
    const block = d.renderForPrompt(10);
    assert.match(block, /^## Recent team activity/);
    const aIdx = block.indexOf("First");
    const bIdx = block.indexOf("Second");
    assert.ok(bIdx < aIdx, "newest entry must appear before older one");
  });

  test("renderForPrompt respects the limit", () => {
    const fs = inMemoryFs();
    const d = new TechLeadDigest("/tmp/x/digest.jsonl", fs.deps);
    for (let i = 0; i < 12; i++) {
      d.recordCompletion({
        taskId: `t${i}`, title: `T${i}`, agentId: "coder-1", role: "coder",
      });
    }
    const block = d.renderForPrompt(3);
    const matches = block.match(/finished "T\d+"/g) ?? [];
    assert.equal(matches.length, 3);
  });
});
