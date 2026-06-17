/**
 * Persistent agent-run entity — append-only JSONL store of every SDK query
 * the server starts, with status lifecycle (running → completed / failed /
 * interrupted / cancelled).
 *
 * Why this exists (C.2): server-owned runs survive ws disconnect, but the
 * server itself can still crash or be restarted. Without persistence we
 * lose the answer to two questions the UI must answer on reconnect:
 *   1. "Did my last task actually run, or do I need to retry?" — needs
 *      access to the run's terminal status after server respawn.
 *   2. "What happened while I was offline?" — needs a since-cursor so the
 *      client can pick up runs it hasn't seen yet.
 *
 * Storage model: each transition appends a full snapshot row to JSONL —
 * not a delta — so a partial read at any point yields a coherent picture
 * (no half-applied patches). On boot we replay the file and fold by runId,
 * with the last-written line winning. This is intentionally event-sourced-
 * lite: simple to reason about, no migrations, costs are O(n) entries on
 * boot (acceptable for thousands of runs; compaction is a follow-up).
 *
 * Failure policy: disk write failures are swallowed via `warn`. Losing a
 * snapshot line is acceptable; breaking a live run because of a full disk
 * is not. In-memory state is the source of truth during a session — disk
 * is for crash recovery and the `runs?since=` API.
 *
 * On disk: ~/.pixelcode/projects/{key}/agent_runs.jsonl
 */

import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "fs";
import { dirname, join } from "path";
import { homedir } from "os";
import { projectKey } from "./board_persistence.js";

/**
 * Run status. Narrow on purpose — every transition is a deliberate code path.
 *
 * - `running`: SDK loop is in flight. Anything still in this state after a
 *   server restart is a crash victim; the boot sweep promotes it to
 *   `interrupted`.
 * - `completed`: SDK loop returned a `result` message cleanly.
 * - `failed`: An exception escaped the SDK loop that was NOT an explicit
 *   abort (e.g. network, parser).
 * - `interrupted`: Aborted by something other than the user — circuit
 *   breaker trip, query timeout, or boot sweep after server restart.
 * - `cancelled`: Explicit user cancel via the "Активні агенти" Settings tab.
 */
export type AgentRunStatus =
  | "running"
  | "completed"
  | "failed"
  | "interrupted"
  | "cancelled";

const TERMINAL: ReadonlySet<AgentRunStatus> = new Set<AgentRunStatus>([
  "completed",
  "failed",
  "interrupted",
  "cancelled",
]);

export function isTerminalStatus(s: AgentRunStatus): boolean {
  return TERMINAL.has(s);
}

export interface AgentRunUsage {
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
  costUsd: number;
  numTurns: number;
  numToolCalls: number;
}

export interface AgentRunToolCall {
  /** SDK tool name as it appears in `assistant.content[i].name`. */
  name: string;
  /** SDK tool_use id — stable across the partial / result pair. */
  id: string;
  /** ISO 8601 when the tool_use first arrived in the SDK stream. */
  at: string;
}

/**
 * Origin of the run — mirrors usage_log.UsageTaskType so the two streams
 * can be joined on `runId` for an empirical-baseline analyzer.
 */
export type AgentRunTaskType = "chat" | "dispatch";

export interface AgentRun {
  runId: string;
  agentId: string;
  taskType: AgentRunTaskType;
  status: AgentRunStatus;
  /** Optional client-generated id of the triggering user message. */
  userMessageId?: string;
  /** First ~200 chars of the user message — for UI surfacing on reconnect. */
  userMessageSnippet?: string;
  /**
   * Periodically flushed partial assistant text — what the UI would replay
   * if the run was interrupted. Empty for runs that never produced text.
   */
  partialOutput?: string;
  /** Final assistant text. Set on `completed`; may be empty for tool-only runs. */
  finalOutput?: string;
  /** Tool calls observed during the run, in arrival order. */
  toolCalls: AgentRunToolCall[];
  /** ISO 8601. */
  startedAt: string;
  /** ISO 8601 — set the moment status becomes terminal. */
  completedAt?: string;
  /** Cumulative token / cost snapshot at terminal status. */
  usage?: AgentRunUsage;
  /** Free-form short note for interrupted / failed runs (breaker msg, etc). */
  reason?: string;
}

/** Input shape for `AgentRunStore.start`. */
export interface AgentRunStartInit {
  runId: string;
  agentId: string;
  taskType: AgentRunTaskType;
  userMessageId?: string;
  userMessageSnippet?: string;
  /** Optional override — defaults to now. */
  startedAt?: string;
}

/**
 * Patch shape for `AgentRunStore.update`. Status, completedAt, finalOutput,
 * partialOutput, usage, reason, and tool calls are all amendable;
 * structural fields (runId / agentId / taskType / startedAt) are immutable.
 */
export type AgentRunPatch = Partial<
  Pick<
    AgentRun,
    | "status"
    | "completedAt"
    | "finalOutput"
    | "partialOutput"
    | "usage"
    | "reason"
    | "toolCalls"
  >
>;

export interface AgentRunStoreDeps {
  appendLine?: (path: string, line: string) => void;
  readAll?: (path: string) => string;
  exists?: (path: string) => boolean;
  ensureDir?: (dir: string) => void;
  /** Atomic whole-file rewrite — used by load-time compaction. */
  writeAll?: (path: string, content: string) => void;
  warn?: (msg: string) => void;
  /** Override the wall clock — tests pin to deterministic timestamps. */
  now?: () => Date;
  /** Cap on runs kept in memory / on disk after compaction. */
  maxRetainedRuns?: number;
}

/**
 * Default retention cap. Every status transition appends a full snapshot
 * row, so an uncompacted file grows ~10× faster than the run count; without
 * a cap the boot replay is O(all transitions ever) and the in-memory map
 * never shrinks. 500 runs is weeks of history for a single-user server.
 */
const DEFAULT_MAX_RETAINED_RUNS = 500;

export class AgentRunStore {
  private readonly filePath: string;
  private readonly appendLine: (path: string, line: string) => void;
  private readonly readAll: (path: string) => string;
  private readonly exists: (path: string) => boolean;
  private readonly ensureDir: (dir: string) => void;
  private readonly writeAll: (path: string, content: string) => void;
  private readonly warn: (msg: string) => void;
  private readonly now: () => Date;
  private readonly maxRetainedRuns: number;

  /** runId → latest snapshot. Source of truth during a session. */
  private readonly inMem = new Map<string, AgentRun>();
  /** Preserves first-seen order for `since()` traversal — runIds embed a
   *  counter + epoch but we don't trust the format; insertion order keeps
   *  the API contract independent of `newRunId()` shape. */
  private readonly order: string[] = [];

  constructor(filePath: string, deps: AgentRunStoreDeps = {}) {
    this.filePath = filePath;
    this.appendLine =
      deps.appendLine ??
      ((p, line) => appendFileSync(p, line + "\n", "utf8"));
    this.readAll = deps.readAll ?? ((p) => readFileSync(p, "utf8"));
    this.exists = deps.exists ?? existsSync;
    this.ensureDir =
      deps.ensureDir ?? ((d) => mkdirSync(d, { recursive: true }));
    this.writeAll =
      deps.writeAll ??
      ((p, content) => {
        // Atomic tmp+rename so a crash mid-compaction keeps the old file.
        const tmp = `${p}.tmp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        writeFileSync(tmp, content, "utf8");
        renameSync(tmp, p);
      });
    this.warn = deps.warn ?? ((msg) => console.warn(`[agent_run] ${msg}`));
    this.now = deps.now ?? (() => new Date());
    this.maxRetainedRuns = deps.maxRetainedRuns ?? DEFAULT_MAX_RETAINED_RUNS;
  }

  /**
   * Replay JSONL into memory. Idempotent — safe to call again, but normally
   * only invoked once at server boot. Corrupt / wrong-shape lines are
   * skipped with a single aggregated warning so a stray partial write
   * doesn't break recovery.
   *
   * After replay the store is compacted: only the newest
   * `maxRetainedRuns` runs are kept (memory AND disk), and the file is
   * rewritten to one line per run when it carried redundant transition
   * rows. Keeps boot replay O(runs), not O(every transition ever).
   */
  load(): void {
    if (!this.exists(this.filePath)) return;
    let raw: string;
    try {
      raw = this.readAll(this.filePath);
    } catch (e) {
      this.warn(`read failed: ${(e as Error).message}`);
      return;
    }
    let skipped = 0;
    let lineCount = 0;
    for (const line of raw.split("\n")) {
      const t = line.trim();
      if (!t) continue;
      lineCount++;
      try {
        const parsed = JSON.parse(t) as unknown;
        if (isWellFormed(parsed)) {
          if (!this.inMem.has(parsed.runId)) this.order.push(parsed.runId);
          this.inMem.set(parsed.runId, parsed);
        } else {
          skipped++;
        }
      } catch {
        skipped++;
      }
    }
    if (skipped > 0) this.warn(`skipped ${skipped} corrupt line(s) on load`);

    // Retention: evict the oldest runs beyond the cap.
    if (this.order.length > this.maxRetainedRuns) {
      const evicted = this.order.splice(0, this.order.length - this.maxRetainedRuns);
      for (const id of evicted) this.inMem.delete(id);
      this.warn(`evicted ${evicted.length} old run(s) beyond retention cap`);
    }

    // Compaction: rewrite only when the file carries more rows than the
    // retained run count (redundant transitions, corrupt lines, or evicted
    // runs). A clean already-compact file is left untouched.
    if (lineCount > this.order.length) {
      try {
        const lines = this.order
          .map((id) => this.inMem.get(id))
          .filter((r): r is AgentRun => r !== undefined)
          .map((r) => JSON.stringify(r));
        this.ensureDir(dirname(this.filePath));
        this.writeAll(
          this.filePath,
          lines.length > 0 ? lines.join("\n") + "\n" : "",
        );
      } catch (e) {
        // Non-fatal: in-memory state is correct; the next boot retries.
        this.warn(`compaction failed: ${(e as Error).message}`);
      }
    }
  }

  /**
   * Begin a run — writes the initial `running` snapshot. Returns the row
   * so the caller can stash the reference for later updates without a
   * separate `get()` round trip.
   */
  start(init: AgentRunStartInit): AgentRun {
    const startedAt = init.startedAt ?? this.now().toISOString();
    const run: AgentRun = {
      runId: init.runId,
      agentId: init.agentId,
      taskType: init.taskType,
      status: "running",
      userMessageId: init.userMessageId,
      userMessageSnippet: init.userMessageSnippet,
      toolCalls: [],
      startedAt,
    };
    this.appendAndCache(run);
    return run;
  }

  /**
   * Patch an existing run. No-op + warning if the run is unknown — never
   * throws so a partial-flush from inside a hot SDK loop can't take down
   * the manager. Auto-stamps `completedAt` when the patch flips status to
   * a terminal state and the caller didn't set it explicitly.
   */
  update(runId: string, patch: AgentRunPatch): AgentRun | null {
    const cur = this.inMem.get(runId);
    if (!cur) {
      this.warn(`update on unknown runId=${runId}`);
      return null;
    }
    const next: AgentRun = { ...cur, ...patch };
    if (
      patch.status &&
      isTerminalStatus(patch.status) &&
      !next.completedAt
    ) {
      next.completedAt = this.now().toISOString();
    }
    this.appendAndCache(next);
    return next;
  }

  /**
   * Convenience: append one tool_use to an existing run without forcing
   * the caller to clone the array. No-op for unknown runIds.
   */
  appendToolCall(runId: string, call: AgentRunToolCall): AgentRun | null {
    const cur = this.inMem.get(runId);
    if (!cur) return null;
    return this.update(runId, { toolCalls: [...cur.toolCalls, call] });
  }

  get(runId: string): AgentRun | undefined {
    return this.inMem.get(runId);
  }

  /** All currently `running` snapshots — primary use is the boot sweep. */
  running(): AgentRun[] {
    const out: AgentRun[] = [];
    for (const id of this.order) {
      const r = this.inMem.get(id);
      if (r && r.status === "running") out.push(r);
    }
    return out;
  }

  /**
   * Promote every still-`running` snapshot to `interrupted`. Used at server
   * boot to clean up runs orphaned by the previous process exiting mid-
   * flight. Returns the updated rows so the caller can broadcast or log.
   */
  markRunningAsInterrupted(reason: string): AgentRun[] {
    const out: AgentRun[] = [];
    for (const r of this.running()) {
      const u = this.update(r.runId, { status: "interrupted", reason });
      if (u) out.push(u);
    }
    return out;
  }

  /**
   * Runs that started AFTER `sinceRunId`. If `sinceRunId` is null or
   * unknown, returns every run in insertion order. Intended for the
   * `runs?since=` reconnect API — a client passes the last runId it has
   * seen and gets everything new.
   */
  since(sinceRunId: string | null | undefined): AgentRun[] {
    if (!sinceRunId) {
      return this.order
        .map((id) => this.inMem.get(id))
        .filter((r): r is AgentRun => r !== undefined);
    }
    const idx = this.order.indexOf(sinceRunId);
    if (idx === -1) {
      return this.order
        .map((id) => this.inMem.get(id))
        .filter((r): r is AgentRun => r !== undefined);
    }
    return this.order
      .slice(idx + 1)
      .map((id) => this.inMem.get(id))
      .filter((r): r is AgentRun => r !== undefined);
  }

  /** Test-only: read every row currently in memory, in insertion order. */
  all(): AgentRun[] {
    return this.order
      .map((id) => this.inMem.get(id))
      .filter((r): r is AgentRun => r !== undefined);
  }

  private appendAndCache(run: AgentRun): void {
    if (!this.inMem.has(run.runId)) this.order.push(run.runId);
    this.inMem.set(run.runId, run);
    try {
      this.ensureDir(dirname(this.filePath));
      this.appendLine(this.filePath, JSON.stringify(run));
    } catch (e) {
      this.warn(`append failed: ${(e as Error).message}`);
    }
  }
}

function isWellFormed(e: unknown): e is AgentRun {
  if (!e || typeof e !== "object") return false;
  const o = e as Record<string, unknown>;
  const statusOk =
    o.status === "running" ||
    o.status === "completed" ||
    o.status === "failed" ||
    o.status === "interrupted" ||
    o.status === "cancelled";
  const taskOk = o.taskType === "chat" || o.taskType === "dispatch";
  return (
    typeof o.runId === "string" &&
    typeof o.agentId === "string" &&
    taskOk &&
    statusOk &&
    typeof o.startedAt === "string" &&
    Array.isArray(o.toolCalls)
  );
}

/** Default JSONL path — mirrors usage_log + board_persistence layout. */
export function agentRunsFile(projectPath: string, baseDir?: string): string {
  const key = projectKey(projectPath);
  const root = baseDir ?? homedir();
  return join(root, ".pixelcode", "projects", key, "agent_runs.jsonl");
}
