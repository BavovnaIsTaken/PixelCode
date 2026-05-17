/**
 * Manager auto-dispatch (MVP, no LLM).
 *
 * After the facilitator pipeline drops a batch of fresh tasks into the
 * backlog, the user previously had to drag every card onto an agent
 * by hand. The MVP picks an assignee deterministically by:
 *   1. role match (task.allowedRoles ∩ instance.roleType)
 *   2. load — agents below the load cap take priority
 *   3. lowest current load wins
 *   4. highest total skill is the tiebreaker
 *   5. instanceId is the final stable tiebreaker so two identical
 *      candidates always pick the same one (good for tests + deterministic
 *      replays).
 *
 * The function is pure — no IO, no globals, no time. Caller (server.ts)
 * holds the live `activeAgentTasks` map and game state.
 *
 * Concurrency note: JavaScript's event loop runs the WS handler
 * synchronously, so two `board_create_task` arrivals are processed back
 * to back — there is no real race between picks. The caller must
 * remember to bump the load *before* the next pick to keep the chain
 * deterministic.
 */

import type { GameStateData } from "./agents.js";
import type { TaskCardData } from "./protocol.js";

/** Maximum concurrent in-flight tasks per agent before they are skipped
 *  for auto-dispatch. Manual drag-and-drop is unaffected. */
export const MAX_AGENT_LOAD = 2;

export interface DispatchContext {
  /** Live roster keyed by instanceId. */
  instances: GameStateData["instances"];
  /** instanceId → in-flight task count. Missing key = 0. */
  load: ReadonlyMap<string, number>;
  /** Master switch — flip to false to short-circuit every pick. */
  enabled: boolean;
}

/**
 * Sum the agent's skill levels. We don't pull a "fit" score per task
 * yet — that requires a category→skill mapping not yet in the codebase
 * and is over-fit for MVP. Total skill is a useful tie-breaker because
 * it correlates with the model the agent runs (better agent finishes
 * faster) without locking us into a specific scoring scheme.
 */
function totalSkill(skills: Record<string, number> | undefined): number {
  if (!skills) return 0;
  let sum = 0;
  for (const v of Object.values(skills)) {
    if (typeof v === "number" && Number.isFinite(v)) sum += v;
  }
  return sum;
}

/**
 * Pick an agent for the task or return null if no eligible candidate
 * exists right now. Caller decides what to do with null — typically
 * leave the task in backlog so the user can drag it manually.
 */
export function pickAssignee(
  task: TaskCardData,
  ctx: DispatchContext,
): string | null {
  if (!ctx.enabled) return null;
  if (task.assignedAgents.length > 0) return null; // already manually assigned
  const allowed =
    task.allowedRoles && task.allowedRoles.length > 0
      ? new Set(task.allowedRoles)
      : null;

  const candidates: Array<{ id: string; load: number; skill: number }> = [];
  for (const [id, inst] of Object.entries(ctx.instances)) {
    if (!inst) continue;
    if (allowed && !allowed.has(inst.roleType)) continue;
    const load = ctx.load.get(id) ?? 0;
    if (load >= MAX_AGENT_LOAD) continue;
    candidates.push({ id, load, skill: totalSkill(inst.skills) });
  }
  if (candidates.length === 0) return null;
  candidates.sort(
    (a, b) =>
      a.load - b.load ||
      b.skill - a.skill ||
      a.id.localeCompare(b.id),
  );
  return candidates[0].id;
}

/**
 * Decide whether a freshly-committed task is a candidate for
 * auto-dispatch. Currently: facilitator-seeded tasks (taskType ===
 * "facilitator") that landed in `backlog` with no manual assignment.
 * Manual `board_create_task` flows are NOT touched — the user expects
 * those to sit where they put them.
 */
export function shouldAutoDispatch(task: TaskCardData): boolean {
  return (
    task.column === "backlog" &&
    task.assignedAgents.length === 0 &&
    task.taskType === "facilitator"
  );
}
