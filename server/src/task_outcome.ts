/**
 * Pure functions that roll a task's final outcome based on agent skills.
 *
 * Server-side mirror of `lib/services/task_outcome.dart`. Kept 1-to-1 with
 * the Dart implementation (same formulas, same clamps, same constants) so
 * the testing → ? roll can move from the client simulator to the server
 * (C.2 "Board transitions — server as single writer") without changing
 * the empirically-tuned outcome distribution.
 *
 * If you touch any constant or formula here, update the Dart file in the
 * same commit and re-run both test suites — drift between the two will
 * cause silent gameplay regressions.
 */

export type TaskOutcome = "clean" | "crit" | "bug" | "incomplete";

/** RNG that yields [0, 1). Injected so tests can pin a seeded sequence. */
export type Rng = () => number;

// ─── Skill-driven chance helpers ─────────────────────────────────────────────

/** `0.4 - 0.03 * precisionSkill`, clamped to `[0, 0.4]`. */
export function bugChance(precisionSkill: number): number {
  return clamp(0.4 - 0.03 * precisionSkill, 0.0, 0.4);
}

/** `0.02 * creativitySkill`, clamped to `[0, 1]`. Divergent tasks only. */
export function critChance(creativitySkill: number): number {
  return clamp(0.02 * creativitySkill, 0.0, 1.0);
}

/** `0.85 + 0.01 * reliabilitySkill`, clamped to `[0, 1]`. */
export function completionSuccessChance(reliabilitySkill: number): number {
  return clamp(0.85 + 0.01 * reliabilitySkill, 0.0, 1.0);
}

// ─── Task-type sets ──────────────────────────────────────────────────────────

export const divergentTaskTypes: ReadonlySet<string> = new Set([
  "architecture",
  "product-spec",
  "ui-design",
]);

export const workstationTaskTypes: ReadonlySet<string> = new Set([
  "coding",
  "testing",
  "debugging",
]);

// ─── Bonus caps (mirror game_economy.dart) ───────────────────────────────────

export const kUnassignedIncompletePenalty = 0.25;
export const kMaxSpecializationCritBonusInRoll = 0.30;
export const kMaxLessonSuccessBonusInRoll = 0.10;
export const kMaxProjectMemoryBonusInRoll = 0.15;

/** `0.005 * lessonCount`, clamped to `[0, kMaxLessonSuccessBonusInRoll]`. */
export function lessonSuccessBonus(lessonCount: number): number {
  return clamp(0.005 * lessonCount, 0.0, kMaxLessonSuccessBonusInRoll);
}

/** `0.01 * (totalTasksCompleted / 5)`, clamped. Architecture tasks only. */
export function projectMemoryDepthBonus(totalTasksCompleted: number): number {
  return clamp(0.01 * (totalTasksCompleted / 5), 0.0, kMaxProjectMemoryBonusInRoll);
}

// ─── Roll ────────────────────────────────────────────────────────────────────

export interface RollInput {
  rng: Rng;
  precisionSkill: number;
  creativitySkill: number;
  reliabilitySkill: number;
  isDivergentTask?: boolean;
  isUnassigned?: boolean;
  taskType?: string;
  specializationCritBonus?: number;
  lessonBonus?: number;
  projectMemoryBonus?: number;
}

/**
 * Order of checks (mirror Dart):
 *   1. Reliability gate (incomplete if we roll above the success threshold).
 *      Agents without a workstation on workstation tasks suffer a −0.25 penalty.
 *      `lessonBonus` adds to success, partially offsetting incomplete rate.
 *   2. Bug check (precision).
 *   3. Crit check (creativity + specialization, divergent tasks only).
 *      `projectMemoryBonus` is added for architecture tasks specifically.
 *   4. Otherwise `clean`.
 */
export function rollOutcome(input: RollInput): TaskOutcome {
  const {
    rng,
    precisionSkill,
    creativitySkill,
    reliabilitySkill,
    isDivergentTask = false,
    isUnassigned = false,
    taskType = "",
    specializationCritBonus = 0.0,
    lessonBonus = 0.0,
    projectMemoryBonus = 0.0,
  } = input;

  const baseSuccess = completionSuccessChance(reliabilitySkill);
  const needsDesk = isUnassigned && workstationTaskTypes.has(taskType);
  const clampedLesson = clamp(lessonBonus, 0.0, kMaxLessonSuccessBonusInRoll);
  const adjustedSuccess = needsDesk
    ? clamp(baseSuccess + clampedLesson - kUnassignedIncompletePenalty, 0.0, 1.0)
    : clamp(baseSuccess + clampedLesson, 0.0, 1.0);

  if (rng() > adjustedSuccess) {
    return "incomplete";
  }
  if (rng() < bugChance(precisionSkill)) {
    return "bug";
  }
  if (isDivergentTask) {
    const base = critChance(creativitySkill);
    const specBonus = clamp(
      specializationCritBonus,
      0.0,
      kMaxSpecializationCritBonusInRoll,
    );
    const memoryBonus = taskType === "architecture"
      ? clamp(projectMemoryBonus, 0.0, kMaxProjectMemoryBonusInRoll)
      : 0.0;
    if (rng() < clamp(base + specBonus + memoryBonus, 0.0, 1.0)) {
      return "crit";
    }
  }
  return "clean";
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function clamp(v: number, lo: number, hi: number): number {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

// ─── Seedable RNG for tests ──────────────────────────────────────────────────

/**
 * Mulberry32 — small, fast, well-distributed PRNG. Used in tests to pin a
 * deterministic outcome sequence; in production the runner injects
 * `Math.random` directly.
 *
 * Bit-identical between Node and any other JS runtime: only uses uint32 ops.
 */
export function mulberry32(seed: number): Rng {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
