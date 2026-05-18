/**
 * Append-only JSONL of dispatch-lifecycle anomalies (C.2.5).
 *
 * Why this exists separately from `usage_log.jsonl`: usage entries are
 * homogeneous (one shape per row) so `usage_baseline.analyze()` stays
 * pure. Incidents are heterogeneous (different `details` per kind) and
 * exist precisely to track *the unhappy path* — they don't belong in the
 * baseline distribution but they DO belong in the daily-control surface.
 *
 * Scope: record-only. No analysis, no in-memory aggregation, no replay.
 * Failure policy mirrors usage_log: any disk write failure is swallowed
 * via `warn`. Losing one incident line is acceptable; breaking a live
 * agent run because of a full disk is not.
 *
 * On disk: ~/.pixelcode/projects/{key}/incident_log.jsonl
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
import type { UsageTaskType } from "./usage_log.js";

/**
 * The narrow set of incident kinds we currently record. Extend only when
 * a new failure mode lands with both detection logic AND a test. The
 * point of the enum is to make the daily-control surface know what
 * categories to expect.
 */
export type IncidentKind =
  /** Manager turn emitted "Готово:" while at least one dispatch in the same turn had not yet returned a paired subagent_result. C.2.5 invariant I1. */
  | "premature_complete"
  /** Sub-agent run completed with numToolCalls === 0 — either a no-op
   * (manager dispatched something not requiring tool use) or a silent
   * failure mode (subagent hallucinated success without acting). C.2.5
   * cascading-hallucination indicator. */
  | "no_op_run";

export interface IncidentEntry {
  /** Globally unique id within this log (process-counter + ts). */
  incidentId: string;
  kind: IncidentKind;
  /** runId from usage_log this incident is attached to. */
  runId: string;
  /** Role type from `roleCatalog`. */
  role: string;
  taskType: UsageTaskType;
  /** Concrete instance id (e.g. "manager", "character-artist#1"). */
  agentId: string;
  /** ISO 8601. */
  occurredAt: string;
  /**
   * Kind-specific payload. Kept loose on purpose — adding a new field
   * for a new kind doesn't break the JSONL shape for older readers.
   * Schema-per-kind lives in the producer call site.
   */
  details: Record<string, string | number | boolean | string[]>;
}

export interface IncidentLoggerDeps {
  appendLine?: (path: string, line: string) => void;
  readAll?: (path: string) => string;
  exists?: (path: string) => boolean;
  ensureDir?: (dir: string) => void;
  warn?: (msg: string) => void;
}

export class IncidentLogger {
  private readonly filePath: string;
  private readonly appendLine: (path: string, line: string) => void;
  private readonly readAll: (path: string) => string;
  private readonly exists: (path: string) => boolean;
  private readonly ensureDir: (dir: string) => void;
  private readonly warn: (msg: string) => void;

  constructor(filePath: string, deps: IncidentLoggerDeps = {}) {
    this.filePath = filePath;
    this.appendLine =
      deps.appendLine ??
      ((p, line) => appendFileSync(p, line + "\n", "utf8"));
    this.readAll = deps.readAll ?? ((p) => readFileSync(p, "utf8"));
    this.exists = deps.exists ?? existsSync;
    this.ensureDir =
      deps.ensureDir ?? ((d) => mkdirSync(d, { recursive: true }));
    this.warn = deps.warn ?? ((msg) => console.warn(`[incident_log] ${msg}`));
  }

  record(entry: IncidentEntry): IncidentEntry {
    try {
      this.ensureDir(dirname(this.filePath));
      this.appendLine(this.filePath, JSON.stringify(entry));
    } catch (e) {
      this.warn(`append failed: ${(e as Error).message}`);
    }
    return entry;
  }

  readAllEntries(): IncidentEntry[] {
    if (!this.exists(this.filePath)) return [];
    let raw: string;
    try {
      raw = this.readAll(this.filePath);
    } catch (e) {
      this.warn(`read failed: ${(e as Error).message}`);
      return [];
    }
    const entries: IncidentEntry[] = [];
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

function isWellFormed(e: unknown): e is IncidentEntry {
  if (!e || typeof e !== "object") return false;
  const o = e as Record<string, unknown>;
  return (
    typeof o.incidentId === "string" &&
    (o.kind === "premature_complete" || o.kind === "no_op_run") &&
    typeof o.runId === "string" &&
    typeof o.role === "string" &&
    (o.taskType === "chat" || o.taskType === "dispatch") &&
    typeof o.agentId === "string" &&
    typeof o.occurredAt === "string" &&
    typeof o.details === "object" &&
    o.details !== null
  );
}

export function incidentLogFile(projectPath: string, baseDir?: string): string {
  const key = projectKey(projectPath);
  const root = baseDir ?? homedir();
  return join(root, ".pixelcode", "projects", key, "incident_log.jsonl");
}

let incidentCounter = 0;
export function newIncidentId(kind: IncidentKind): string {
  return `${kind}_${++incidentCounter}_${Date.now()}`;
}

/**
 * Decide whether a completed sub-agent run looks like a no-op.
 *
 * Today's rule is simple: zero tool calls = no-op candidate. Kept as a
 * function (not an inline `=== 0`) so future heuristics can land here
 * without combing the call sites — e.g. once we ship structured returns
 * with `filesEdited[]/filesCreated[]`, this is where we check whether
 * the agent at least *claimed* to do something concrete.
 *
 * Returns true when the run merits a no_op_run incident record. Always
 * false for a non-zero tool-call run — those by definition did *something*.
 */
export function isNoOpRun(numToolCalls: number): boolean {
  return numToolCalls === 0;
}

/**
 * Summary rates over a slice of incidents. Pure: pass the entries +
 * the total-run-count divisor; this module does no clock reads.
 *
 * Returns rates as fractions (0.0 - 1.0). UI multiplies by 100 if it
 * wants percent.
 */
export interface IncidentRateSummary {
  prematureCompleteCount: number;
  noOpRunCount: number;
  /** Divisor used (caller-supplied total run count). */
  totalRuns: number;
  /** prematureCompleteCount / totalRuns, or 0 if totalRuns === 0. */
  prematureCompleteRate: number;
  /** noOpRunCount / totalRuns, or 0 if totalRuns === 0. */
  noOpRunRate: number;
}

export function summarizeIncidents(
  entries: IncidentEntry[],
  totalRuns: number,
): IncidentRateSummary {
  let pc = 0;
  let no = 0;
  for (const e of entries) {
    if (e.kind === "premature_complete") pc++;
    else if (e.kind === "no_op_run") no++;
  }
  return {
    prematureCompleteCount: pc,
    noOpRunCount: no,
    totalRuns,
    prematureCompleteRate: totalRuns > 0 ? pc / totalRuns : 0,
    noOpRunRate: totalRuns > 0 ? no / totalRuns : 0,
  };
}
