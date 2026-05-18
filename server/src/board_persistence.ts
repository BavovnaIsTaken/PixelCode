/**
 * Persistent storage for the kanban board.
 *
 * The board lived only in RAM until now — server restart wiped every task.
 * This module:
 *   - serializes the board to a JSON file under ~/.pixelcode/projects/{key}/board.json
 *   - writes atomically (tmp + rename) so a crash mid-write cannot corrupt the file
 *   - debounces writes so drag-and-drop bursts produce one IO at most
 *   - reads tolerantly: malformed/legacy files fall back to an empty board and
 *     the bad file is quarantined so the user can inspect it later
 *   - tags the schema with a `version` field so future migrations are explicit
 */

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "fs";
import { dirname, join } from "path";
import { homedir } from "os";
import type { TaskCardData, TaskColumnKey } from "./protocol.js";

export const BOARD_SCHEMA_VERSION = 1;

/** Authoritative list of board columns. Centralised here so handlers and
 * persistence stay in sync. */
export const BOARD_COLUMNS: readonly TaskColumnKey[] = [
  "backlog",
  "in_progress",
  "testing",
  "done",
];

const BOARD_COLUMN_SET: ReadonlySet<TaskColumnKey> = new Set(BOARD_COLUMNS);

/** Type-guard: narrows arbitrary input to a valid column key. */
export function isValidBoardColumn(value: unknown): value is TaskColumnKey {
  return typeof value === "string" && BOARD_COLUMN_SET.has(value as TaskColumnKey);
}

/**
 * Decide what to send in response to `board_get_state{since}`.
 *
 * If the client's `since` matches the current revision we ship a cheap
 * `unchanged` message; otherwise we send the full snapshot. Pure function
 * so the routing logic can be unit-tested without standing up a server.
 */
export type BoardGetStateReply =
  | { kind: "unchanged"; revision: number }
  | { kind: "full"; revision: number; tasks: TaskCardData[] };

export function planBoardGetState(
  since: number | undefined,
  currentRevision: number,
  tasks: TaskCardData[],
): BoardGetStateReply {
  if (typeof since === "number" && since === currentRevision) {
    return { kind: "unchanged", revision: currentRevision };
  }
  return { kind: "full", revision: currentRevision, tasks };
}

// ─── Atomic batch seed (board_seed_batch) ─────────────────────────────

export interface SeedBatchInput {
  title: string;
  description?: string;
  color?: string;
  priority?: string;
  column?: string;
  difficulty?: number;
  allowedRoles?: string[];
  taskType?: string;
  assignedAgents?: string[];
}

export interface SeedBatchPlan {
  ok: boolean;
  /** Built tasks if ok; never partial — empty when validation fails. */
  tasks: TaskCardData[];
  /** Index + reason for the first invalid input. Multiple errors collected
   *  for diagnostics; the batch is still all-or-nothing. */
  errors: Array<{ index: number; reason: string }>;
  /** Counter advanced past the last id used by this batch. Caller updates
   *  its global counter only when ok=true. */
  nextCounter: number;
}

/**
 * Validate every task in a batch and (if ok) build the TaskCardData
 * objects. Pure: no IO, no globals — caller installs the result.
 *
 * Validation:
 *   - title must be a non-empty string after trimming
 *   - column (if present) must be a known board column
 *   - difficulty (if present) must be a finite number in [1,5]
 */
export function planSeedBatch(
  inputs: SeedBatchInput[],
  options: {
    /** Counter to start id allocation from. Each new task uses ++counter. */
    counter: number;
    /** Stable timestamp source for `createdAt`/`updatedAt`. */
    now: () => Date;
    /** Stable id-token source so two id collisions in the same ms don't
     *  trip atomic-rename reuse. */
    idToken: () => number;
    /** Optional `source` value the caller wants stamped on each card.
     *  We don't model this in TaskCardData yet (the field is reserved
     *  for downstream auto-dispatcher work, WP3); the helper records it
     *  via taskType when no taskType was supplied so the data is at
     *  least observable. */
    sourceTag?: string;
  },
): SeedBatchPlan {
  const errors: Array<{ index: number; reason: string }> = [];

  if (!Array.isArray(inputs)) {
    return { ok: false, tasks: [], errors: [{ index: -1, reason: "tasks is not an array" }], nextCounter: options.counter };
  }

  for (let i = 0; i < inputs.length; i++) {
    const t = inputs[i];
    if (!t || typeof t !== "object") {
      errors.push({ index: i, reason: "task is not an object" });
      continue;
    }
    if (typeof t.title !== "string" || t.title.trim().length === 0) {
      errors.push({ index: i, reason: "title must be a non-empty string" });
    }
    if (t.column !== undefined && !isValidBoardColumn(t.column)) {
      errors.push({ index: i, reason: `unknown column "${t.column}"` });
    }
    if (
      t.difficulty !== undefined &&
      (typeof t.difficulty !== "number" ||
        !Number.isFinite(t.difficulty) ||
        t.difficulty < 1 ||
        t.difficulty > 5)
    ) {
      errors.push({ index: i, reason: `difficulty ${t.difficulty} outside [1,5]` });
    }
  }

  if (errors.length > 0) {
    return { ok: false, tasks: [], errors, nextCounter: options.counter };
  }

  let counter = options.counter;
  const tasks: TaskCardData[] = [];
  const stamp = options.now().toISOString();
  for (const t of inputs) {
    counter++;
    const id = `task_${counter}_${options.idToken()}`;
    tasks.push({
      id,
      title: t.title,
      description: t.description ?? "",
      column: (t.column ?? "backlog") as TaskColumnKey,
      priority: (t.priority ?? "normal") as TaskCardData["priority"],
      color: (t.color ?? "yellow") as TaskCardData["color"],
      assignedAgents: t.assignedAgents ?? [],
      createdAt: stamp,
      updatedAt: stamp,
      difficulty: t.difficulty,
      allowedRoles: t.allowedRoles,
      // Stamp the source via taskType when caller didn't set one — this
      // gives the auto-dispatcher in WP3 a hook to recognise facilitator
      // seeds without yet introducing a separate `source` field.
      taskType: t.taskType ?? options.sourceTag,
      attachments: [],
    });
  }
  return { ok: true, tasks, errors: [], nextCounter: counter };
}

export interface BoardSnapshot {
  version: number;
  tasks: TaskCardData[];
  updatedAt: number; // epoch ms
}

export interface LoadResult {
  /** Tasks recovered from disk, possibly empty. */
  tasks: TaskCardData[];
  /** Highest counter ever seen on disk (so we never reuse an id after load). */
  taskCounter: number;
  /** Source so callers can warn the user when their file got quarantined. */
  source: "fresh" | "loaded" | "quarantined";
  /** Filename of the quarantined original, if any. */
  quarantinedAs?: string;
}

export interface BoardPersistenceDeps {
  /** Override the home dir in tests. */
  baseDir?: string;
  /** Override `Date.now()` in tests for deterministic timestamps. */
  now?: () => number;
  /** Logger hook — defaults to console.warn. */
  warn?: (msg: string) => void;
  /** setTimeout override for deterministic debounce in tests. */
  setTimeoutFn?: (cb: () => void, ms: number) => unknown;
  /** clearTimeout override paired with setTimeoutFn. */
  clearTimeoutFn?: (handle: unknown) => void;
}

/** Convert a project cwd into a stable file-system safe key. */
export function projectKey(projectPath: string): string {
  return projectPath.replace(/\//g, "-").replace(/^-/, "");
}

export function boardFile(projectPath: string, baseDir?: string): string {
  const key = projectKey(projectPath);
  const root = baseDir ?? homedir();
  return join(root, ".pixelcode", "projects", key, "board.json");
}

/** Extract the numeric portion from a generated id like `task_42_1700000000`. */
function extractTaskCounter(id: string): number {
  const match = id.match(/^task_(\d+)_/);
  if (!match) return 0;
  const n = Number(match[1]);
  return Number.isFinite(n) ? n : 0;
}

const VALID_COLUMNS = new Set(["backlog", "in_progress", "testing", "done"]);
const VALID_OUTCOMES = new Set(["clean", "crit", "bug", "incomplete"]);

/**
 * Sanity-check a single task entry. Returns the task untouched if the shape
 * is fine, otherwise null so caller can drop it. We are deliberately lenient:
 * old files may miss new fields like `attachments`/`allowedRoles`, and we want
 * those to load. We only reject entries with missing/wrong-typed required
 * fields.
 */
function validateTask(raw: unknown): TaskCardData | null {
  if (!raw || typeof raw !== "object") return null;
  const t = raw as Record<string, unknown>;
  if (typeof t.id !== "string" || !t.id) return null;
  if (typeof t.title !== "string") return null;
  if (typeof t.column !== "string" || !VALID_COLUMNS.has(t.column)) return null;
  if (!Array.isArray(t.assignedAgents)) return null;
  return {
    id: t.id,
    title: t.title,
    description: typeof t.description === "string" ? t.description : "",
    column: t.column as TaskCardData["column"],
    priority: (typeof t.priority === "string" ? t.priority : "normal") as TaskCardData["priority"],
    color: (typeof t.color === "string" ? t.color : "yellow") as TaskCardData["color"],
    assignedAgents: t.assignedAgents.filter((a): a is string => typeof a === "string"),
    createdAt: typeof t.createdAt === "string" ? t.createdAt : new Date(0).toISOString(),
    updatedAt: typeof t.updatedAt === "string" ? t.updatedAt : new Date(0).toISOString(),
    difficulty: typeof t.difficulty === "number" ? t.difficulty : undefined,
    allowedRoles: Array.isArray(t.allowedRoles)
      ? t.allowedRoles.filter((r): r is string => typeof r === "string")
      : undefined,
    taskType: typeof t.taskType === "string" ? t.taskType : undefined,
    attachments: Array.isArray(t.attachments)
      ? (t.attachments as TaskCardData["attachments"])
      : undefined,
    outcome:
      typeof t.outcome === "string" && VALID_OUTCOMES.has(t.outcome)
        ? (t.outcome as TaskCardData["outcome"])
        : undefined,
  };
}

/**
 * Schema migration. v0 is treated as "any file without a version field" —
 * tasks are read as-is and on the next save we'll stamp v1. v1 is the current
 * schema. Future bumps add cases here.
 */
function migrate(parsed: unknown): { version: number; tasks: unknown[] } {
  if (!parsed || typeof parsed !== "object") {
    return { version: BOARD_SCHEMA_VERSION, tasks: [] };
  }
  const obj = parsed as Record<string, unknown>;
  const version = typeof obj.version === "number" ? obj.version : 0;
  const tasks = Array.isArray(obj.tasks) ? obj.tasks : [];
  // No schema-shape changes between v0 and v1 — only the version field is new.
  return { version, tasks };
}

function quarantine(file: string, warn: (msg: string) => void, now: () => number): string | undefined {
  if (!existsSync(file)) return undefined;
  const target = `${file}.broken-${now()}`;
  try {
    renameSync(file, target);
    warn(`Board file at ${file} was unreadable; moved to ${target}`);
    return target;
  } catch (e) {
    warn(`Failed to quarantine ${file}: ${e}`);
    return undefined;
  }
}

/**
 * Read the board file. Never throws — corrupt input becomes an empty board
 * with the original quarantined.
 */
export function loadBoard(projectPath: string, deps: BoardPersistenceDeps = {}): LoadResult {
  const warn = deps.warn ?? ((m: string) => console.warn(m));
  const now = deps.now ?? Date.now;
  const file = boardFile(projectPath, deps.baseDir);

  if (!existsSync(file)) {
    return { tasks: [], taskCounter: 0, source: "fresh" };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(file, "utf-8"));
  } catch (e) {
    warn(`Board file ${file} is not valid JSON: ${e}`);
    const moved = quarantine(file, warn, now);
    return { tasks: [], taskCounter: 0, source: "quarantined", quarantinedAs: moved };
  }

  const { tasks: rawTasks } = migrate(parsed);
  const tasks: TaskCardData[] = [];
  for (const raw of rawTasks) {
    const t = validateTask(raw);
    if (t) tasks.push(t);
    else warn(`Board file ${file} contained an invalid task entry; skipped`);
  }

  let counter = 0;
  for (const t of tasks) {
    const n = extractTaskCounter(t.id);
    if (n > counter) counter = n;
  }

  return { tasks, taskCounter: counter, source: "loaded" };
}

/** Synchronously write the board atomically. Public for tests; production code
 * goes through BoardWriter to get debouncing. */
export function writeBoardSync(
  projectPath: string,
  tasks: TaskCardData[],
  deps: BoardPersistenceDeps = {},
): void {
  const now = deps.now ?? Date.now;
  const file = boardFile(projectPath, deps.baseDir);
  const dir = dirname(file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });

  const snapshot: BoardSnapshot = {
    version: BOARD_SCHEMA_VERSION,
    tasks,
    updatedAt: now(),
  };

  // Atomic: write to a sibling .tmp then rename. fs.renameSync is atomic on
  // POSIX same-fs and Windows ≥ Vista. If the process dies between writeFile
  // and rename, the original file is intact.
  const tmp = `${file}.tmp-${now()}-${Math.random().toString(36).slice(2, 8)}`;
  writeFileSync(tmp, JSON.stringify(snapshot));
  renameSync(tmp, file);
}

/**
 * Debouncing writer. Call `schedule(tasks)` on every board mutation; only the
 * latest snapshot within the debounce window is written. `flush()` is for
 * shutdown hooks and tests.
 */
export class BoardWriter {
  private pending: TaskCardData[] | null = null;
  private timer: unknown = null;
  private readonly debounceMs: number;
  private readonly setTimeoutFn: (cb: () => void, ms: number) => unknown;
  private readonly clearTimeoutFn: (handle: unknown) => void;
  private readonly deps: BoardPersistenceDeps;

  constructor(
    private readonly projectPath: string,
    debounceMs = 250,
    deps: BoardPersistenceDeps = {},
  ) {
    this.debounceMs = debounceMs;
    this.deps = deps;
    this.setTimeoutFn = deps.setTimeoutFn ?? ((cb, ms) => setTimeout(cb, ms));
    this.clearTimeoutFn = deps.clearTimeoutFn ?? ((h) => clearTimeout(h as ReturnType<typeof setTimeout>));
  }

  schedule(tasks: TaskCardData[]): void {
    this.pending = tasks;
    if (this.timer !== null) this.clearTimeoutFn(this.timer);
    this.timer = this.setTimeoutFn(() => this.flush(), this.debounceMs);
  }

  /** Write whatever is pending right now. Idempotent. */
  flush(): void {
    if (this.timer !== null) {
      this.clearTimeoutFn(this.timer);
      this.timer = null;
    }
    if (this.pending === null) return;
    const tasks = this.pending;
    this.pending = null;
    try {
      writeBoardSync(this.projectPath, tasks, this.deps);
    } catch (e) {
      const warn = this.deps.warn ?? ((m: string) => console.warn(m));
      warn(`Failed to persist board: ${e}`);
    }
  }
}
