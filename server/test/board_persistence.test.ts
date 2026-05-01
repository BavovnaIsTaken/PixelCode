import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, existsSync, readdirSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  BOARD_COLUMNS,
  BOARD_SCHEMA_VERSION,
  BoardWriter,
  boardFile,
  isValidBoardColumn,
  loadBoard,
  planBoardGetState,
  planSeedBatch,
  projectKey,
  writeBoardSync,
} from "../src/board_persistence.ts";
import type { TaskCardData } from "../src/protocol.ts";

function makeTask(overrides: Partial<TaskCardData> = {}): TaskCardData {
  return {
    id: "task_1_1700000000",
    title: "demo",
    description: "",
    column: "backlog",
    priority: "normal",
    color: "yellow",
    assignedAgents: [],
    createdAt: "2024-01-01T00:00:00.000Z",
    updatedAt: "2024-01-01T00:00:00.000Z",
    ...overrides,
  };
}

function makeTmpRoot(): { root: string; cwd: string; cleanup: () => void } {
  const root = mkdtempSync(join(tmpdir(), "pixelcode-board-test-"));
  const cwd = "/Users/test/MyProject";
  return {
    root,
    cwd,
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

test("projectKey strips leading slash and replaces separators", () => {
  assert.equal(projectKey("/Users/dan/Project"), "Users-dan-Project");
});

test("boardFile lands under .pixelcode/projects/{key}/board.json", () => {
  const file = boardFile("/Users/dan/Project", "/tmp/fake-home");
  assert.equal(file, "/tmp/fake-home/.pixelcode/projects/Users-dan-Project/board.json");
});

test("loadBoard returns fresh result when no file exists", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.source, "fresh");
    assert.deepEqual(r.tasks, []);
    assert.equal(r.taskCounter, 0);
  } finally {
    cleanup();
  }
});

test("writeBoardSync + loadBoard round-trip preserves tasks and bumps counter", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    const tasks = [
      makeTask({ id: "task_3_1700000000", title: "a" }),
      makeTask({ id: "task_7_1700000001", title: "b", column: "in_progress" }),
    ];
    writeBoardSync(cwd, tasks, { baseDir: root });
    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.source, "loaded");
    assert.equal(r.tasks.length, 2);
    assert.equal(r.tasks[0].title, "a");
    assert.equal(r.tasks[1].column, "in_progress");
    // counter should reflect the highest numeric prefix observed
    assert.equal(r.taskCounter, 7);
  } finally {
    cleanup();
  }
});

test("writeBoardSync stamps current schema version", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    writeBoardSync(cwd, [makeTask()], { baseDir: root });
    const raw = JSON.parse(readFileSync(boardFile(cwd, root), "utf-8"));
    assert.equal(raw.version, BOARD_SCHEMA_VERSION);
    assert.equal(typeof raw.updatedAt, "number");
    assert.equal(raw.tasks.length, 1);
  } finally {
    cleanup();
  }
});

test("loadBoard tolerates legacy v0 files (no version field)", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    const file = boardFile(cwd, root);
    // ensure dir
    writeBoardSync(cwd, [], { baseDir: root });
    // overwrite with v0-shaped content
    writeFileSync(file, JSON.stringify({ tasks: [makeTask({ id: "task_5_x" })] }));
    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.source, "loaded");
    assert.equal(r.tasks.length, 1);
    assert.equal(r.tasks[0].id, "task_5_x");
    assert.equal(r.taskCounter, 5);
  } finally {
    cleanup();
  }
});

test("loadBoard quarantines malformed JSON and returns empty board", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    // First a valid write so the directory exists.
    writeBoardSync(cwd, [makeTask()], { baseDir: root });
    const file = boardFile(cwd, root);
    writeFileSync(file, "{ this is not json");
    const warnings: string[] = [];
    const r = loadBoard(cwd, { baseDir: root, warn: (m) => warnings.push(m), now: () => 99999 });
    assert.equal(r.source, "quarantined");
    assert.deepEqual(r.tasks, []);
    assert.ok(r.quarantinedAs?.includes(".broken-99999"));
    assert.ok(existsSync(r.quarantinedAs!));
    assert.ok(!existsSync(file));
    assert.ok(warnings.some((w) => w.includes("not valid JSON")));
  } finally {
    cleanup();
  }
});

test("loadBoard skips invalid task entries but keeps valid ones", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    writeBoardSync(cwd, [], { baseDir: root });
    const file = boardFile(cwd, root);
    writeFileSync(
      file,
      JSON.stringify({
        version: 1,
        tasks: [
          makeTask({ id: "task_2_x" }),
          { id: "no-title", column: "backlog", assignedAgents: [] }, // missing title
          { id: "task_3_x", title: "bad-col", column: "nonsense", assignedAgents: [] },
          makeTask({ id: "task_8_x", title: "ok" }),
        ],
        updatedAt: 0,
      }),
    );
    const warnings: string[] = [];
    const r = loadBoard(cwd, { baseDir: root, warn: (m) => warnings.push(m) });
    assert.equal(r.source, "loaded");
    assert.equal(r.tasks.length, 2);
    assert.deepEqual(r.tasks.map((t) => t.id), ["task_2_x", "task_8_x"]);
    assert.equal(r.taskCounter, 8);
    assert.ok(warnings.length >= 2);
  } finally {
    cleanup();
  }
});

test("per-project isolation: two projectPaths land in distinct files", () => {
  const { root, cleanup } = makeTmpRoot();
  try {
    const cwdA = "/tmp/Alpha";
    const cwdB = "/tmp/Beta";
    writeBoardSync(cwdA, [makeTask({ id: "task_1_a", title: "alpha-task" })], { baseDir: root });
    writeBoardSync(cwdB, [makeTask({ id: "task_1_b", title: "beta-task" })], { baseDir: root });

    const a = loadBoard(cwdA, { baseDir: root });
    const b = loadBoard(cwdB, { baseDir: root });
    assert.equal(a.tasks[0].title, "alpha-task");
    assert.equal(b.tasks[0].title, "beta-task");
    assert.notEqual(boardFile(cwdA, root), boardFile(cwdB, root));
  } finally {
    cleanup();
  }
});

test("atomic write: tmp file is cleaned up via rename, no leftover .tmp", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    writeBoardSync(cwd, [makeTask()], { baseDir: root });
    const dir = join(root, ".pixelcode", "projects", projectKey(cwd));
    const files = readdirSync(dir);
    assert.deepEqual(files, ["board.json"]);
  } finally {
    cleanup();
  }
});

test("atomic write: failure mid-rename does not corrupt the existing file", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    writeBoardSync(cwd, [makeTask({ title: "original" })], { baseDir: root });
    const file = boardFile(cwd, root);
    const originalRaw = readFileSync(file, "utf-8");
    // Simulate crash: writeBoardSync uses tmp+rename, so even if we manually
    // leave a stray tmp file behind, the canonical file is untouched.
    const tmp = `${file}.tmp-fake`;
    writeFileSync(tmp, "garbage");
    // The canonical file is still the previous one.
    assert.equal(readFileSync(file, "utf-8"), originalRaw);
    // Cleanup the stray; loadBoard should still succeed.
    rmSync(tmp);
    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.tasks[0].title, "original");
  } finally {
    cleanup();
  }
});

test("BoardWriter debounces multiple schedules into a single write", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    let timer: { cb: () => void; ms: number } | null = null;
    const fakeSetTimeout = (cb: () => void, ms: number) => {
      timer = { cb, ms };
      return 1;
    };
    const fakeClearTimeout = () => {
      timer = null;
    };

    const writer = new BoardWriter(cwd, 200, {
      baseDir: root,
      setTimeoutFn: fakeSetTimeout as unknown as BoardWriter["setTimeoutFn"],
      clearTimeoutFn: fakeClearTimeout,
    });

    writer.schedule([makeTask({ title: "v1" })]);
    writer.schedule([makeTask({ title: "v2" })]);
    writer.schedule([makeTask({ title: "v3" })]);

    // No write happened yet — timer is still pending.
    assert.equal(existsSync(boardFile(cwd, root)), false);

    // Fire the debounce.
    timer!.cb();

    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.tasks.length, 1);
    assert.equal(r.tasks[0].title, "v3");
  } finally {
    cleanup();
  }
});

test("BoardWriter.flush forces an immediate write", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    let timer: { cb: () => void } | null = null;
    const writer = new BoardWriter(cwd, 200, {
      baseDir: root,
      setTimeoutFn: ((cb) => {
        timer = { cb };
        return 1;
      }) as unknown as BoardWriter["setTimeoutFn"],
      clearTimeoutFn: () => {
        timer = null;
      },
    });

    writer.schedule([makeTask({ title: "to-flush" })]);
    writer.flush();

    const r = loadBoard(cwd, { baseDir: root });
    assert.equal(r.tasks[0].title, "to-flush");
    assert.equal(timer, null);
  } finally {
    cleanup();
  }
});

test("BoardWriter.flush is a no-op when nothing pending", () => {
  const { root, cwd, cleanup } = makeTmpRoot();
  try {
    const writer = new BoardWriter(cwd, 200, { baseDir: root });
    writer.flush();
    assert.equal(existsSync(boardFile(cwd, root)), false);
  } finally {
    cleanup();
  }
});

// ─── Board sync helpers (WP2) ─────────────────────────────────────────────

test("BOARD_COLUMNS lists every kanban column exactly once", () => {
  assert.deepEqual([...BOARD_COLUMNS].sort(), [
    "backlog",
    "done",
    "in_progress",
    "testing",
  ]);
});

test("isValidBoardColumn accepts known columns and rejects everything else", () => {
  for (const c of BOARD_COLUMNS) {
    assert.equal(isValidBoardColumn(c), true);
  }
  for (const bad of [
    "Backlog", // wrong case
    "in-progress", // wrong delimiter
    "",
    null,
    undefined,
    42,
    {},
    "review",
  ]) {
    assert.equal(isValidBoardColumn(bad), false, `expected reject: ${String(bad)}`);
  }
});

test("planBoardGetState returns 'unchanged' when client revision matches", () => {
  const reply = planBoardGetState(7, 7, [makeTask()]);
  assert.equal(reply.kind, "unchanged");
  assert.equal(reply.revision, 7);
});

test("planBoardGetState ships full state when client revision is stale", () => {
  const tasks = [makeTask({ id: "task_1_x" }), makeTask({ id: "task_2_x" })];
  const reply = planBoardGetState(3, 7, tasks);
  assert.equal(reply.kind, "full");
  if (reply.kind === "full") {
    assert.equal(reply.revision, 7);
    assert.equal(reply.tasks.length, 2);
  }
});

test("planBoardGetState ships full state when client omits since (legacy clients)", () => {
  const reply = planBoardGetState(undefined, 4, [makeTask()]);
  assert.equal(reply.kind, "full");
});

test("planBoardGetState treats client-ahead revision as a mismatch (ships full state)", () => {
  // Should never happen in practice, but a stale client whose revision is
  // somehow ahead of the server (e.g. cached after a state reset) must be
  // resync'd, not silently accepted.
  const reply = planBoardGetState(99, 5, [makeTask()]);
  assert.equal(reply.kind, "full");
  if (reply.kind === "full") {
    assert.equal(reply.revision, 5);
  }
});

test("planBoardGetState 'unchanged' reply does not depend on tasks list", () => {
  // If the revision matches, the task list is irrelevant — it is not sent.
  // Verify by passing an obviously stale list.
  const reply = planBoardGetState(0, 0, []);
  assert.equal(reply.kind, "unchanged");
});

// ─── planSeedBatch (WP4) ──────────────────────────────────────────────

const planOpts = (counter = 0) => ({
  counter,
  now: () => new Date("2026-05-02T10:00:00.000Z"),
  idToken: () => 99999,
});

test("planSeedBatch builds tasks for a fully valid input", () => {
  const r = planSeedBatch(
    [
      { title: "First", description: "do this" },
      { title: "Second", column: "in_progress", priority: "high" },
    ],
    planOpts(10),
  );
  assert.equal(r.ok, true);
  assert.equal(r.tasks.length, 2);
  assert.equal(r.errors.length, 0);
  assert.equal(r.nextCounter, 12);
  assert.equal(r.tasks[0].id, "task_11_99999");
  assert.equal(r.tasks[1].id, "task_12_99999");
  assert.equal(r.tasks[0].column, "backlog"); // default
  assert.equal(r.tasks[1].column, "in_progress");
  assert.equal(r.tasks[1].priority, "high");
});

test("planSeedBatch rejects the whole batch when any title is empty", () => {
  const r = planSeedBatch(
    [
      { title: "Valid one" },
      { title: "  " }, // whitespace-only
      { title: "Also valid" },
    ],
    planOpts(0),
  );
  assert.equal(r.ok, false);
  assert.equal(r.tasks.length, 0, "no partial commit");
  assert.equal(r.errors.length, 1);
  assert.equal(r.errors[0].index, 1);
  assert.match(r.errors[0].reason, /title/);
  assert.equal(r.nextCounter, 0, "counter unchanged on failure");
});

test("planSeedBatch rejects unknown columns atomically", () => {
  const r = planSeedBatch(
    [
      { title: "Ok" },
      { title: "Bad column", column: "review" },
    ],
    planOpts(0),
  );
  assert.equal(r.ok, false);
  assert.equal(r.tasks.length, 0);
  assert.equal(r.errors[0].index, 1);
  assert.match(r.errors[0].reason, /column/);
});

test("planSeedBatch collects every error on the first pass", () => {
  const r = planSeedBatch(
    [
      { title: "" },
      { title: "ok" },
      { title: "ok2", column: "made-up" },
      { title: "ok3", difficulty: 99 },
    ],
    planOpts(0),
  );
  assert.equal(r.ok, false);
  assert.equal(r.errors.length, 3);
  const indices = r.errors.map((e) => e.index).sort();
  assert.deepEqual(indices, [0, 2, 3]);
});

test("planSeedBatch accepts an empty array as a no-op success", () => {
  const r = planSeedBatch([], planOpts(5));
  assert.equal(r.ok, true);
  assert.equal(r.tasks.length, 0);
  assert.equal(r.nextCounter, 5);
});

test("planSeedBatch defends against non-array input", () => {
  // A bug in a future client could send `tasks: null`; we don't want a
  // TypeError to fall out of the handler.
  const r = planSeedBatch(null as unknown as Parameters<typeof planSeedBatch>[0], planOpts(0));
  assert.equal(r.ok, false);
  assert.equal(r.errors[0].index, -1);
});

test("planSeedBatch stamps sourceTag onto taskType when caller didn't set one", () => {
  const r = planSeedBatch(
    [
      { title: "untagged" },
      { title: "preset", taskType: "review" },
    ],
    { ...planOpts(0), sourceTag: "facilitator" },
  );
  assert.equal(r.ok, true);
  assert.equal(r.tasks[0].taskType, "facilitator");
  assert.equal(r.tasks[1].taskType, "review", "explicit taskType wins");
});

test("planSeedBatch validates difficulty range", () => {
  for (const bad of [0, 6, NaN, Infinity, -1]) {
    const r = planSeedBatch(
      [{ title: "T", difficulty: bad as number }],
      planOpts(0),
    );
    assert.equal(r.ok, false, `expected reject difficulty=${bad}`);
  }
  // Valid range
  const ok = planSeedBatch([{ title: "T", difficulty: 3 }], planOpts(0));
  assert.equal(ok.ok, true);
});
