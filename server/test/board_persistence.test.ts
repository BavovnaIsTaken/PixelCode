import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, existsSync, readdirSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  BOARD_SCHEMA_VERSION,
  BoardWriter,
  boardFile,
  loadBoard,
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
