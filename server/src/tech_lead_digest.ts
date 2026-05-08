/**
 * Tech-lead digest — append-only log of what the team finished, plus a
 * bounded in-memory ring buffer that the WS layer hands to a tech-lead
 * agent as system context.
 *
 * Why this exists: the core loop "agent finishes → tech-lead notices and
 * reacts" was missing. Without a per-completion record there is nothing
 * for the tech-lead role to ground its replies in, and the user never
 * gets the feeling that someone is watching the architecture. This
 * module is the wire between board completions and tech-lead awareness.
 *
 * Pure module: file system + clock are injected so unit tests are
 * deterministic. Errors writing to disk are swallowed (digest is
 * best-effort — losing one entry must never break the board).
 *
 * On disk: ~/.pixelcode/projects/{key}/tech_lead_digest.jsonl
 * Append-only newline-delimited JSON. Replays into the ring on startup.
 */

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from "fs";
import { dirname, join } from "path";
import { homedir } from "os";
import { projectKey } from "./board_persistence.js";

export interface DigestEntry {
  taskId: string;
  title: string;
  agentId: string;
  /** Role id from `roleCatalog`, e.g. "coder", "tech-lead". */
  role: string;
  /** Column transition that produced the entry. Currently always "done". */
  outcome: "done";
  /** ISO 8601 timestamp. */
  ts: string;
}

const DEFAULT_CAPACITY = 50;

export interface DigestStoreDeps {
  capacity?: number;
  /** ISO timestamp factory — defaults to `() => new Date().toISOString()`. */
  now?: () => string;
  /** Append a single line (newline appended internally). Defaults to fs. */
  appendLine?: (path: string, line: string) => void;
  /** Read the whole file. Defaults to fs.readFileSync utf8. */
  readAll?: (path: string) => string;
  /** existence probe. Defaults to fs.existsSync. */
  exists?: (path: string) => boolean;
  /** ensureDir for the parent of a target path. Defaults to mkdirSync recursive. */
  ensureDir?: (dir: string) => void;
  /** Logger for swallowed write errors. */
  warn?: (msg: string) => void;
}

/**
 * Bounded ring buffer of recent completions. The newest entry is at the
 * end; appending past `capacity` drops the oldest. Pure data structure,
 * no I/O.
 */
export class DigestStore {
  private readonly _entries: DigestEntry[] = [];
  private readonly capacity: number;

  constructor(capacity: number = DEFAULT_CAPACITY) {
    this.capacity = Math.max(1, capacity);
  }

  /** Append an entry; oldest is evicted past capacity. */
  add(entry: DigestEntry): void {
    this._entries.push(entry);
    if (this._entries.length > this.capacity) {
      this._entries.splice(0, this._entries.length - this.capacity);
    }
  }

  /** Most recent N entries (default: all), newest LAST. */
  recent(limit?: number): DigestEntry[] {
    if (limit === undefined || limit >= this._entries.length) {
      return [...this._entries];
    }
    return this._entries.slice(this._entries.length - limit);
  }

  get size(): number {
    return this._entries.length;
  }

  clear(): void {
    this._entries.length = 0;
  }
}

/** Shape we accept from the input — keep it flexible (tests pass partials). */
export interface CompletionInput {
  taskId: string;
  title: string;
  agentId: string;
  role?: string;
}

/**
 * Coordinator that writes digest entries to disk as JSONL and keeps the
 * ring buffer in sync. One per project. Stateless beyond the in-memory
 * store and the configured file path.
 */
export class TechLeadDigest {
  readonly store: DigestStore;
  private readonly filePath: string;
  private readonly now: () => string;
  private readonly appendLine: (path: string, line: string) => void;
  private readonly readAll: (path: string) => string;
  private readonly exists: (path: string) => boolean;
  private readonly ensureDir: (dir: string) => void;
  private readonly warn: (msg: string) => void;

  constructor(filePath: string, deps: DigestStoreDeps = {}) {
    this.filePath = filePath;
    this.store = new DigestStore(deps.capacity);
    this.now = deps.now ?? (() => new Date().toISOString());
    this.appendLine =
      deps.appendLine ??
      ((p, line) => appendFileSync(p, line + "\n", "utf8"));
    this.readAll = deps.readAll ?? ((p) => readFileSync(p, "utf8"));
    this.exists = deps.exists ?? existsSync;
    this.ensureDir = deps.ensureDir ?? ((d) => mkdirSync(d, { recursive: true }));
    this.warn =
      deps.warn ?? ((msg) => console.warn(`[tech_lead_digest] ${msg}`));
  }

  /**
   * Replay JSONL from disk into the ring. Tolerates corrupt lines —
   * skips them, keeps going. Called once at server boot.
   */
  loadFromDisk(): void {
    if (!this.exists(this.filePath)) return;
    let raw: string;
    try {
      raw = this.readAll(this.filePath);
    } catch (e) {
      this.warn(`load failed: ${(e as Error).message}`);
      return;
    }
    const lines = raw.split("\n").filter((l) => l.trim().length > 0);
    let recovered = 0;
    let skipped = 0;
    for (const line of lines) {
      try {
        const parsed = JSON.parse(line) as DigestEntry;
        if (
          typeof parsed?.taskId === "string" &&
          typeof parsed?.title === "string" &&
          typeof parsed?.agentId === "string" &&
          typeof parsed?.role === "string" &&
          parsed?.outcome === "done" &&
          typeof parsed?.ts === "string"
        ) {
          this.store.add(parsed);
          recovered++;
        } else {
          skipped++;
        }
      } catch {
        skipped++;
      }
    }
    if (skipped > 0) {
      this.warn(`replayed ${recovered} entries, skipped ${skipped} corrupt lines`);
    }
  }

  /**
   * Record a task completion. Pushes to the ring AND appends to JSONL.
   * Disk failures are swallowed — the in-memory entry still exists so
   * the running server keeps working.
   */
  recordCompletion(input: CompletionInput): DigestEntry {
    const entry: DigestEntry = {
      taskId: input.taskId,
      title: input.title,
      agentId: input.agentId,
      role: input.role ?? input.agentId,
      outcome: "done",
      ts: this.now(),
    };
    this.store.add(entry);
    try {
      this.ensureDir(dirname(this.filePath));
      this.appendLine(this.filePath, JSON.stringify(entry));
    } catch (e) {
      this.warn(`append failed: ${(e as Error).message}`);
    }
    return entry;
  }

  /** Recent N entries (newest last), for tech-lead context injection. */
  recent(limit?: number): DigestEntry[] {
    return this.store.recent(limit);
  }

  /**
   * Render entries as a system-prompt block. Newest first for relevance,
   * a single line per entry. Returns empty string when nothing recorded
   * (callers can detect and skip the section).
   */
  renderForPrompt(limit: number = 10): string {
    const recent = this.recent(limit);
    if (recent.length === 0) return "";
    const lines: string[] = ["## Recent team activity"];
    for (let i = recent.length - 1; i >= 0; i--) {
      const e = recent[i];
      lines.push(`- [${e.ts}] ${e.role} (${e.agentId}) finished "${e.title}" (${e.taskId})`);
    }
    return lines.join("\n");
  }
}

/** Default JSONL path — mirrors board_persistence layout. */
export function digestFile(projectPath: string, baseDir?: string): string {
  const key = projectKey(projectPath);
  const root = baseDir ?? homedir();
  return join(root, ".pixelcode", "projects", key, "tech_lead_digest.jsonl");
}
