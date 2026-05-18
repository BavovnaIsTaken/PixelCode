/**
 * Reflection prompt builder + telemetry — pure functions extracted from
 * server.ts so they can be unit-snapshotted without spinning up the SDK.
 *
 * The Haiku-reflection pass turns a session activity buffer into 0–3 typed
 * lessons. To defeat tool-availability confabulations (which previously seeded
 * incorrect long-lived weaknesses in the TraitStore), the prompt includes
 * deterministic ground-truth sections:
 *
 *   <session_activity>  — what the agents actually emitted (capped)
 *   <allowed_tools>     — per-agent toolset wired into the SDK query
 *   <tool_errors>       — raw error tails (the actual SDK message)
 *   <dispatch_log>      — dispatch invocations and delegations
 *
 * Hard constraints forbid Haiku from claiming a tool was "unavailable" when
 * it appears in <allowed_tools>; the source-of-truth is the deterministic
 * block, not Haiku's inference.
 */

import { appendFileSync, mkdirSync, existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import {
  formatTaxonomyForPrompt,
  tagEntropyBits,
  topTagShare,
} from "./reflection_taxonomy.js";

// ─── Input types ───────────────────────────────────────────────────────────

export interface ActivityEntry {
  agentId: string;
  event: string;
  detail: string;
}

export interface ReflectionPromptInput {
  /** Raw event stream from the session, in arrival order. */
  activities: ActivityEntry[];
  /**
   * Authoritative tool allowlist per agent, derived from role + canDelegate.
   * Empty map is OK — the prompt section will render `(none)` and Haiku
   * still gets the constraint about "do not infer availability".
   */
  allowedToolsByAgent: Record<string, string[]>;
  /** Agents that had a rework count > 0 this session. */
  reworkAgents: string[];
  /** True when any activity carried event === "error". */
  hasErrors: boolean;
  /** Hardcoded team roster for context in the prompt. */
  teamRoster?: string[];
}

// ─── Prompt construction ───────────────────────────────────────────────────

const DEFAULT_TEAM_ROSTER = [
  "manager", "tech-lead", "coder", "reviewer",
  "tester", "security", "ui-ux-designer", "llm-specialist",
];

/**
 * Per-agent event cap. The reflection prompt is meant to be cheap (Haiku),
 * so we keep tokens bounded by truncating per-agent stream.
 */
export const MAX_EVENTS_PER_AGENT = 10;

/**
 * Build the Haiku reflection prompt. Pure — same input yields same output.
 *
 * ⚠ LOAD-BEARING WORDING — see CLAUDE.md §5 "Personalization system".
 *
 * The exact constraint phrasing below ("NEVER claim a tool was 'unavailable'",
 * "fallback to Task", section names `<allowed_tools>` etc) governs Haiku's
 * behaviour through prompt-engineering. Verbatim regression coverage lives in
 * test/reflection_prompt.test.ts:
 *   - "keeps hard-constraint wording verbatim"
 *   - "emits all four ground-truth sections"
 *
 * Before editing this function:
 *   1. Add a fixture to test/reflection_prompt.test.ts covering the new wording
 *   2. Re-run the snapshot suite — failures here are intentional invariants
 *   3. Cross-check `allowedToolsForAgent` in server.ts uses the same role+
 *      canDelegate logic as the chat path's `query()` options (~line 2178).
 *      Divergence = Haiku gets a wrong ground-truth toolset and the gate is
 *      defeated for tool-availability confabulations.
 *
 * If you find yourself "cleaning up" the prompt for readability — STOP and
 * read the original incident notes in docs/ROADMAP.md C.1 entry
 * "Personalization hardening v2".
 */
export function buildReflectionPrompt(input: ReflectionPromptInput): string {
  const {
    activities,
    allowedToolsByAgent,
    reworkAgents,
    hasErrors,
    teamRoster = DEFAULT_TEAM_ROSTER,
  } = input;

  // Group events by agent, preserving order within each agent's stream.
  const agentActivities = new Map<string, string[]>();
  const errorLines: string[] = [];
  const dispatchLines: string[] = [];
  for (const a of activities) {
    let bucket = agentActivities.get(a.agentId);
    if (!bucket) {
      bucket = [];
      agentActivities.set(a.agentId, bucket);
    }
    bucket.push(`[${a.event}] ${a.detail}`);
  }

  const summaryLines: string[] = [];
  for (const [agentId, events] of agentActivities) {
    summaryLines.push(`## ${agentId}`);
    for (const e of events.slice(-MAX_EVENTS_PER_AGENT)) {
      summaryLines.push(`  ${e}`);
      if (e.startsWith("[error]")) {
        errorLines.push(`${agentId}: ${e.slice("[error] ".length)}`);
      }
      if (e.includes("mcp__dispatch__") || e.startsWith("[delegated]")) {
        dispatchLines.push(`${agentId}: ${e}`);
      }
    }
  }
  const activitySummary = summaryLines.join("\n");

  // Render allowed-tools block: only for agents that actually participated.
  // If gameState wasn't populated and the caller passed an empty map, we
  // still emit `(none — toolset unknown)` so Haiku can't infer from absence.
  const involvedAgents = Array.from(agentActivities.keys());
  const allowedLines: string[] = [];
  for (const agentId of involvedAgents) {
    const tools = allowedToolsByAgent[agentId];
    if (tools && tools.length > 0) {
      allowedLines.push(`${agentId}: ${tools.join(", ")}`);
    } else {
      allowedLines.push(`${agentId}: (none — toolset unknown for this session)`);
    }
  }
  const allowedToolsBlock = allowedLines.length > 0
    ? allowedLines.join("\n")
    : "(no agents involved)";
  const errorsBlock = errorLines.length > 0 ? errorLines.join("\n") : "(none)";
  const dispatchBlock = dispatchLines.length > 0 ? dispatchLines.join("\n") : "(none)";

  return `Analyze this AI agent team work session and extract learning lessons.

<session_activity>
${activitySummary}
</session_activity>

<allowed_tools>
${allowedToolsBlock}
</allowed_tools>

<tool_errors>
${errorsBlock}
</tool_errors>

<dispatch_log>
${dispatchBlock}
</dispatch_log>

${hasErrors ? "⚠️ The session had errors." : "No errors during session."}
${reworkAgents.length > 0 ? `⚠️ Agents with rework: ${reworkAgents.join(", ")}` : "No rework needed."}

Team agents: ${teamRoster.join(", ")}

Extract 0-3 notable lessons from this session. Each lesson is a pattern that should be remembered for future work.
- A "strength" is something an agent did notably well (thorough analysis, clean code, good delegation, etc.)
- A "weakness" is something an agent struggled with or made a mistake on (missed edge cases, wrong approach, needed rework, etc.)
- Only include genuinely insightful observations, NOT generic platitudes.
- The "tag" MUST be chosen from the canonical list in <canonical_tags>. Do not invent new tags — server-side validation rejects unknown tags. If none of the listed tags fits closely, prefer omitting the lesson over inventing a tag.

<canonical_tags>
${formatTaxonomyForPrompt()}
</canonical_tags>

Hard constraints — do NOT violate:
- NEVER claim a tool was "unavailable" or "missing" if it appears in <allowed_tools> for that agent. <allowed_tools> is authoritative.
- If a tool returned an error, describe what the error message actually said (see <tool_errors>) rather than inferring tool availability.
- If <tool_errors> is empty and <dispatch_log> shows successful dispatches, do not invent a "fallback to Task" or "tool unavailable" narrative.
- Lessons must cite specific behavior observed in <session_activity> — no generic platitudes.

Reply ONLY with a JSON array (no markdown, no explanation):
[{"agentId":"...", "type":"strength|weakness", "category":"code_quality|architecture|testing|security|communication|delegation|problem_solving|tools_usage", "tag":"short-kebab-id", "lesson":"One specific sentence"}]

If nothing notable happened, reply with: []`;
}

// ─── Lightweight post-process check ────────────────────────────────────────

/**
 * Phrases that should never appear in a reflection lesson when the relevant
 * tool was in fact authoritative-listed for the agent. Used as a cheap
 * sanity-monitor — when violations appear, the hard-constraint in the prompt
 * is being ignored by the model.
 */
export const FORBIDDEN_TOOL_AVAILABILITY_PHRASES = [
  "tool was not available",
  "tool was unavailable",
  "tool is unavailable",
  "tool not available",
  "was not available",
  "fell back to task",
  "fallback to task",
  "fell back to the task tool",
];

/**
 * Returns the lower-cased forbidden phrases that appear in the lesson text.
 * Empty result = the lesson does not visibly claim a tool was unavailable.
 *
 * Used both inline (telemetry: count violations) and in evaluation
 * regression suites that re-play fixtures through a real LLM call.
 */
export function detectForbiddenAvailabilityClaims(lessonText: string): string[] {
  const lower = lessonText.toLowerCase();
  const hits: string[] = [];
  for (const phrase of FORBIDDEN_TOOL_AVAILABILITY_PHRASES) {
    if (lower.includes(phrase)) hits.push(phrase);
  }
  return hits;
}

// ─── Telemetry — append-only JSONL ─────────────────────────────────────────

export type ReflectionEvent =
  | { kind: "candidate_submitted"; agentId: string; tag: string; type: string; category: string; status: "pending" | "duplicate" | "too-soon" | "promoted"; via?: "threshold" | "real-trait-bypass"; gapMs?: number; sessionCount?: number }
  | { kind: "candidate_pruned_stale"; count: number }
  | { kind: "traits_decayed_pruned"; count: number }
  | { kind: "constraint_violation"; agentId: string; tag: string; phrases: string[]; lesson: string }
  | { kind: "invalid_tag"; agentId: string; tag: string; type: string; category: string; lesson: string }
  | { kind: "reflection_skipped"; reason: "no_activity" | "no_consent" | "no_lessons" };

function telemetryDir(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "telemetry");
}

function telemetryFile(projectPath: string): string {
  return join(telemetryDir(projectPath), "reflection.jsonl");
}

/**
 * Append a reflection telemetry event to disk. Best-effort: a failed write
 * never blocks the caller (e.g. readonly FS in tests).
 *
 * Records are pre-stamped with ISO timestamp; consumers may post-process or
 * roll up daily without server cooperation.
 */
export function appendReflectionTelemetry(
  projectPath: string,
  event: ReflectionEvent,
): void {
  const dir = telemetryDir(projectPath);
  try {
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    const line = JSON.stringify({ ts: new Date().toISOString(), ...event }) + "\n";
    appendFileSync(telemetryFile(projectPath), line);
  } catch {
    // Telemetry must never break the host call path.
  }
}

/**
 * Compute KPI summary from the on-disk telemetry log. Used by the dashboard
 * (and the [TODO] reflection-model-upgrade decision in 60 days):
 *
 *   promotion_rate = promoted / submitted
 *   bypass_rate    = real-trait-bypass promotions / total promotions
 *   violation_rate = constraint violations / submitted
 *
 * Returns null if the log doesn't exist yet (cold project).
 */
export interface ReflectionKpiSnapshot {
  submitted: number;
  promotedViaThreshold: number;
  promotedViaBypass: number;
  pending: number;
  duplicate: number;
  tooSoon: number;
  prunedStale: number;
  decayedPruned: number;
  constraintViolations: number;
  /** Candidates rejected at submission because the tag fell outside the canonical taxonomy (C.2.6). */
  invalidTagCount: number;
  promotionRate: number;
  bypassRate: number;
  violationRate: number;
  /** Rejected-tag share of all submission attempts: invalidTagCount / (submitted + invalidTagCount). */
  invalidTagRate: number;
  /** Shannon entropy (bits) over the tag distribution of submitted candidates. */
  tagEntropy: number;
  /** Largest single-tag share of submitted candidates (0..1). */
  topTagShare: number;
}

/**
 * Read the on-disk telemetry JSONL for a project and return the parsed
 * events optionally filtered to a rolling window.
 *
 * Best-effort: missing file → []. Malformed lines are skipped (the log is
 * append-only and concurrent writes can produce torn lines).
 */
export function readReflectionEvents(
  projectPath: string,
  sinceDays: number | null = null,
): { events: Array<ReflectionEvent & { ts: string }>; fileExists: boolean } {
  const file = telemetryFile(projectPath);
  if (!existsSync(file)) return { events: [], fileExists: false };

  const cutoffMs = sinceDays !== null && sinceDays > 0
    ? Date.now() - sinceDays * 24 * 60 * 60 * 1000
    : 0;

  const events: Array<ReflectionEvent & { ts: string }> = [];
  let content: string;
  try {
    content = readFileSync(file, "utf-8");
  } catch {
    return { events: [], fileExists: true };
  }
  for (const line of content.split("\n")) {
    if (line.length === 0) continue;
    try {
      const obj = JSON.parse(line) as ReflectionEvent & { ts?: string };
      const ts = typeof obj.ts === "string" ? obj.ts : new Date(0).toISOString();
      if (cutoffMs > 0 && new Date(ts).getTime() < cutoffMs) continue;
      events.push({ ...obj, ts } as ReflectionEvent & { ts: string });
    } catch {
      // skip malformed line
    }
  }
  return { events, fileExists: true };
}

export interface RecentViolation {
  agentId: string;
  tag: string;
  phrases: string[];
  lesson: string;
  ts: string;
}

/**
 * Compose the WS payload for `reflection_kpi`. Pure given the on-disk log
 * state — used by both the WS handler in server.ts and by tests.
 *
 * `recentViolations` is capped at the last 5 entries for UI compactness.
 */
export function buildReflectionKpiMessage(
  projectPath: string,
  sinceDays: number | null = null,
): {
  type: "reflection_kpi";
  windowDays: number | null;
  hasData: boolean;
  submitted: number;
  promotedViaThreshold: number;
  promotedViaBypass: number;
  pending: number;
  duplicate: number;
  tooSoon: number;
  prunedStale: number;
  decayedPruned: number;
  constraintViolations: number;
  invalidTagCount: number;
  promotionRate: number;
  bypassRate: number;
  violationRate: number;
  invalidTagRate: number;
  tagEntropy: number;
  topTagShare: number;
  recentViolations: RecentViolation[];
} {
  const { events, fileExists } = readReflectionEvents(projectPath, sinceDays);
  const summary = summarizeReflectionTelemetry(events.map(({ ts: _ts, ...rest }) => rest as ReflectionEvent));

  const recentViolations: RecentViolation[] = [];
  for (let i = events.length - 1; i >= 0 && recentViolations.length < 5; i--) {
    const e = events[i];
    if (e.kind === "constraint_violation") {
      recentViolations.push({
        agentId: e.agentId,
        tag: e.tag,
        phrases: e.phrases,
        lesson: e.lesson,
        ts: e.ts,
      });
    }
  }

  return {
    type: "reflection_kpi" as const,
    windowDays: sinceDays,
    hasData: fileExists && events.length > 0,
    ...summary,
    recentViolations,
  };
}

export function summarizeReflectionTelemetry(
  events: ReflectionEvent[],
): ReflectionKpiSnapshot {
  let submitted = 0;
  let promotedThreshold = 0;
  let promotedBypass = 0;
  let pending = 0;
  let duplicate = 0;
  let tooSoon = 0;
  let prunedStale = 0;
  let decayedPruned = 0;
  let violations = 0;
  let invalidTags = 0;
  const submittedTags: string[] = [];
  for (const e of events) {
    switch (e.kind) {
      case "candidate_submitted":
        submitted++;
        submittedTags.push(e.tag);
        if (e.status === "promoted") {
          if (e.via === "real-trait-bypass") promotedBypass++;
          else promotedThreshold++;
        } else if (e.status === "pending") pending++;
        else if (e.status === "duplicate") duplicate++;
        else if (e.status === "too-soon") tooSoon++;
        break;
      case "candidate_pruned_stale":
        prunedStale += e.count;
        break;
      case "traits_decayed_pruned":
        decayedPruned += e.count;
        break;
      case "constraint_violation":
        violations++;
        break;
      case "invalid_tag":
        invalidTags++;
        break;
    }
  }
  const totalPromoted = promotedThreshold + promotedBypass;
  const totalSubmissionAttempts = submitted + invalidTags;
  const safe = (n: number, d: number) => (d > 0 ? n / d : 0);
  return {
    submitted,
    promotedViaThreshold: promotedThreshold,
    promotedViaBypass: promotedBypass,
    pending,
    duplicate,
    tooSoon,
    prunedStale,
    decayedPruned,
    constraintViolations: violations,
    invalidTagCount: invalidTags,
    promotionRate: safe(totalPromoted, submitted),
    bypassRate: safe(promotedBypass, totalPromoted),
    violationRate: safe(violations, submitted),
    invalidTagRate: safe(invalidTags, totalSubmissionAttempts),
    tagEntropy: tagEntropyBits(submittedTags),
    topTagShare: topTagShare(submittedTags),
  };
}
