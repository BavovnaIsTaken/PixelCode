/**
 * Pure board-transition logic. Decides what should happen to a card on
 * sub-agent dispatch finish, and which orphaned cards need to bounce back
 * to backlog. Kept dependency-free (no WS, no agent runtime, no disk) so
 * the rules are unit-testable in isolation — same scoping doctrine as
 * `task_outcome.ts`.
 *
 * Owns the runtime invariant of C.2 "server as single writer for board
 * transitions": every column flip on the dispatched path goes through one
 * of the helpers below.
 */

import { rollOutcome, type Rng, type TaskOutcome } from "./task_outcome.js";
import type { AgentInstanceData } from "./agents.js";
import type { TaskCardData, TaskColumnKey } from "./protocol.js";

// ─── Skill access helpers ────────────────────────────────────────────────────

/**
 * Index of each `SkillType` as stored in the wire payload (mirrors the
 * `SkillType` enum in `lib/models/game_economy.dart`):
 *
 *   speed=0, precision=1, creativity=2, insight=3, reliability=4
 *
 * Kept explicit so a future skill insertion that shifts indices on the
 * client throws a server-side test rather than silently misreading skills.
 */
const SKILL_INDEX = {
  speed: "0",
  precision: "1",
  creativity: "2",
  insight: "3",
  reliability: "4",
} as const;

function skillLevel(skills: Record<string, number> | undefined, key: keyof typeof SKILL_INDEX): number {
  if (!skills) return 1;
  const idx = SKILL_INDEX[key];
  const v = skills[idx];
  return typeof v === "number" && Number.isFinite(v) ? v : 1;
}

// ─── Specialization crit bonus (mirror lib/models/game_economy.dart) ─────────

/**
 * Crit bonus per matching specialization. MUST mirror
 * `kSpecializationCritBonus` in `lib/models/game_economy.dart`. The Dart
 * side caps the aggregated bonus at `kMaxSpecializationCritBonus`; we re-clamp
 * inside `rollOutcome` defensively, so the server can multiply blindly without
 * re-implementing the cap here.
 */
export const kSpecializationCritBonus = 0.10;

function specializationCritBonusFor(
  agent: AgentInstanceData | undefined,
  taskType: string | undefined,
): number {
  if (!agent || !taskType) return 0.0;
  const specs = agent.specializations ?? [];
  return specs.includes(taskType) ? kSpecializationCritBonus : 0.0;
}

function totalTasksCompleted(agent: AgentInstanceData | undefined): number {
  if (!agent) return 0;
  const counters = agent.taskCompletionsByType ?? {};
  let sum = 0;
  for (const v of Object.values(counters)) {
    if (typeof v === "number" && Number.isFinite(v)) sum += v;
  }
  return sum;
}

// ─── Advance decision ────────────────────────────────────────────────────────

export interface AdvanceInput {
  task: TaskCardData;
  agent: AgentInstanceData | undefined;
  /** `lessonCount` for this agent — caller reads it from the trait store. */
  lessonCount: number;
  rng: Rng;
}

export interface AdvanceDecision {
  /** New column the card should land in. Equal to `task.column` if no advance. */
  nextColumn: TaskColumnKey;
  /**
   * Set only for transitions that ran a roll (i.e. coming out of `testing`).
   * `in_progress → testing` advances without rolling; outcome stays unset.
   */
  outcome?: TaskOutcome;
  /**
   * True when the decision DID change the column — caller writes the new
   * column to the card and broadcasts. False for "nothing to do".
   */
  changed: boolean;
}

/**
 * Decide where a card should land when its dispatched sub-agent finishes
 * SUCCESSFULLY. Breaker trip / timeout / cancel paths must NOT call this —
 * those terminal states leave the card alone (the user / manager has to
 * re-act); rolling on interrupted state would award XP for work that didn't
 * happen.
 *
 * Idempotent guard: only fires when the card is in `in_progress` or
 * `testing`. A card the manager-LLM already pushed to `done` (via its own
 * `board_move_task` tool call) stays in `done`; we never roll on top of an
 * already-finished card.
 */
export function advanceOnDispatchSuccess(input: AdvanceInput): AdvanceDecision {
  const { task, agent, lessonCount, rng } = input;

  if (task.column === "in_progress") {
    return { nextColumn: "testing", changed: true };
  }
  if (task.column !== "testing") {
    return { nextColumn: task.column, changed: false };
  }

  const taskType = task.taskType ?? "coding";
  const outcome = rollOutcome({
    rng,
    precisionSkill: skillLevel(agent?.skills, "precision"),
    creativitySkill: skillLevel(agent?.skills, "creativity"),
    reliabilitySkill: skillLevel(agent?.skills, "reliability"),
    isDivergentTask: ["architecture", "product-spec", "ui-design"].includes(taskType),
    isUnassigned: false, // server-driven dispatch implies workstation assigned
    taskType,
    specializationCritBonus: specializationCritBonusFor(agent, taskType),
    lessonBonus: 0.005 * lessonCount, // clamp happens inside rollOutcome
    projectMemoryBonus: 0.01 * (totalTasksCompleted(agent) / 5),
  });

  const nextColumn: TaskColumnKey = outcome === "clean" || outcome === "crit"
    ? "done"
    : outcome === "bug"
      ? "in_progress"
      : "backlog";

  // `testing → ?` always lands on a different column (the four possible
  // outcomes route to `done` / `in_progress` / `backlog`, never back to
  // `testing`), so `changed` is constant true once we've rolled.
  return { nextColumn, outcome, changed: true };
}

// ─── Orphan-active reset (Q1 variant A) ──────────────────────────────────────

/**
 * Cards stuck in `in_progress` / `testing` with no `assignedAgents` cannot
 * progress under the new "server as single writer" rule — no dispatch will
 * fire to advance them. Reset them back to `backlog` so the user (or manager
 * on the next intake) re-assigns and re-dispatches.
 *
 * Returns the list of card IDs that were reset; caller mutates `task.column`
 * and broadcasts. Pure: does not touch the card map itself.
 */
export function findOrphanActiveCards(tasks: Iterable<TaskCardData>): string[] {
  const orphans: string[] = [];
  for (const t of tasks) {
    if ((t.column === "in_progress" || t.column === "testing") && t.assignedAgents.length === 0) {
      orphans.push(t.id);
    }
  }
  return orphans;
}
