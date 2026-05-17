/**
 * Per-role usage log — append-only JSONL of completed SDK queries.
 *
 * Why this exists: C.2 plans empirical baselines per `{role, taskType}`
 * (median / p95 cost / duration / tool-call count) so a future facilitator
 * UI can flag 2× outliers. We do NOT trust LLM self-estimates; we trust
 * the distribution. That distribution needs data — this module is the
 * faucet that fills it.
 *
 * Scope (C.2): record-only. No analysis, no in-memory aggregation, no
 * replay-on-boot. A future analyzer reads the JSONL directly. Keep this
 * module dumb so the hot path of `runQuery` / `agent_runner` never pays
 * for accumulation logic.
 *
 * Failure policy: any disk write failure is swallowed via `warn`. Losing
 * one usage line is acceptable; breaking a live agent run because of a
 * full disk is not.
 *
 * On disk: ~/.pixelcode/projects/{key}/usage_log.jsonl
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

/**
 * Origin of the run. Kept narrow on purpose — adding a new variant should
 * be a deliberate decision, not a typo. Extend when a third real entry
 * point appears (e.g. dungeon, facilitator-direct).
 *
 * - `chat`: top-level user message routed through `runQuery` in server.ts.
 * - `dispatch`: sub-agent invocation through `AgentRunner.dispatch`
 *   (manager / tech-lead delegating work).
 */
export type UsageTaskType = "chat" | "dispatch";

export interface UsageLogEntry {
  runId: string;
  /** Role type from `roleCatalog` (e.g. "coder", "tech-lead"). */
  role: string;
  taskType: UsageTaskType;
  /** Concrete instance id (e.g. "coder#1"). */
  agentId: string;
  inputTokens: number;
  outputTokens: number;
  cacheCreationTokens: number;
  cacheReadTokens: number;
  costUsd: number;
  durationMs: number;
  numTurns: number;
  numToolCalls: number;
  /** ISO 8601. */
  startedAt: string;
  /** ISO 8601. */
  completedAt: string;
}

export interface UsageLoggerDeps {
  appendLine?: (path: string, line: string) => void;
  readAll?: (path: string) => string;
  exists?: (path: string) => boolean;
  ensureDir?: (dir: string) => void;
  warn?: (msg: string) => void;
}

export class UsageLogger {
  private readonly filePath: string;
  private readonly appendLine: (path: string, line: string) => void;
  private readonly readAll: (path: string) => string;
  private readonly exists: (path: string) => boolean;
  private readonly ensureDir: (dir: string) => void;
  private readonly warn: (msg: string) => void;

  constructor(filePath: string, deps: UsageLoggerDeps = {}) {
    this.filePath = filePath;
    this.appendLine =
      deps.appendLine ??
      ((p, line) => appendFileSync(p, line + "\n", "utf8"));
    this.readAll = deps.readAll ?? ((p) => readFileSync(p, "utf8"));
    this.exists = deps.exists ?? existsSync;
    this.ensureDir =
      deps.ensureDir ?? ((d) => mkdirSync(d, { recursive: true }));
    this.warn = deps.warn ?? ((msg) => console.warn(`[usage_log] ${msg}`));
  }

  /** Append one entry. Disk failures are swallowed via `warn`. */
  record(entry: UsageLogEntry): UsageLogEntry {
    try {
      this.ensureDir(dirname(this.filePath));
      this.appendLine(this.filePath, JSON.stringify(entry));
    } catch (e) {
      this.warn(`append failed: ${(e as Error).message}`);
    }
    return entry;
  }

  /**
   * Read every well-formed entry from disk. Returns `[]` on missing file
   * or unreadable content; logs (but does not throw) on corrupt lines.
   * Intended for the future analyzer / tests, not the hot path.
   */
  readAllEntries(): UsageLogEntry[] {
    if (!this.exists(this.filePath)) return [];
    let raw: string;
    try {
      raw = this.readAll(this.filePath);
    } catch (e) {
      this.warn(`read failed: ${(e as Error).message}`);
      return [];
    }
    const entries: UsageLogEntry[] = [];
    let skipped = 0;
    for (const line of raw.split("\n")) {
      const t = line.trim();
      if (!t) continue;
      try {
        const parsed = JSON.parse(t) as unknown;
        if (isWellFormed(parsed)) {
          entries.push(parsed);
        } else {
          skipped++;
        }
      } catch {
        skipped++;
      }
    }
    if (skipped > 0) {
      this.warn(`skipped ${skipped} corrupt line(s)`);
    }
    return entries;
  }
}

function isWellFormed(e: unknown): e is UsageLogEntry {
  if (!e || typeof e !== "object") return false;
  const o = e as Record<string, unknown>;
  return (
    typeof o.runId === "string" &&
    typeof o.role === "string" &&
    (o.taskType === "chat" || o.taskType === "dispatch") &&
    typeof o.agentId === "string" &&
    typeof o.inputTokens === "number" &&
    typeof o.outputTokens === "number" &&
    typeof o.cacheCreationTokens === "number" &&
    typeof o.cacheReadTokens === "number" &&
    typeof o.costUsd === "number" &&
    typeof o.durationMs === "number" &&
    typeof o.numTurns === "number" &&
    typeof o.numToolCalls === "number" &&
    typeof o.startedAt === "string" &&
    typeof o.completedAt === "string"
  );
}

/** Default JSONL path — mirrors board_persistence + tech_lead_digest layout. */
export function usageLogFile(projectPath: string, baseDir?: string): string {
  const key = projectKey(projectPath);
  const root = baseDir ?? homedir();
  return join(root, ".pixelcode", "projects", key, "usage_log.jsonl");
}

/** Counter for runId generation. Module-scoped so tests can observe ordering. */
let runCounter = 0;

/**
 * Generate a unique runId for a single SDK query. Shape mirrors
 * `dispatch_<counter>_<ts>` in agent_runner so logs/grep are consistent
 * across surfaces. Exported so chat-path code shares it instead of
 * inventing its own format.
 */
export function newRunId(prefix: "chat" | "dispatch" = "chat"): string {
  return `${prefix}_${++runCounter}_${Date.now()}`;
}
