/**
 * FacilitatorRunner — orchestrator that wires intake processing,
 * scope scoring, output generation, ceremony scheduling, and style
 * switching into a coherent state machine.
 *
 * The runner is **state-bearing** (holds the chosen style + fire log
 * for a project) but **pure** about side effects: it returns plans /
 * results to the caller, who handles persistence and chat dispatch.
 *
 * Design: docs/FACILITATOR_SYSTEM.md §3.
 */

import { processIntake } from "./intake_processor.js";
import {
  dueNow,
  dueOnEvent,
  fireAll,
} from "./ceremony_scheduler.js";
import {
  GeneratorRegistry,
  type StyledOutputGenerator,
} from "./output_generator.js";
import type {
  CeremonyFireLog,
  CeremonyTrigger,
  FacilitatorEvent,
  FacilitatorStyle,
  IntakeAnswers,
  SeedResult,
  SwitchResult,
} from "./types.js";

// ─── Runner state ──────────────────────────────────────────────────────────

export interface RunnerState {
  projectPath: string;
  style: FacilitatorStyle;
  fireLog: CeremonyFireLog;
  /** Seeded output's id, present after `start()` succeeds. */
  outputId?: string;
}

/**
 * Construct an initial state for a project + style. No I/O.
 */
export function initState(
  projectPath: string,
  style: FacilitatorStyle,
): RunnerState {
  return { projectPath, style, fireLog: {} };
}

// ─── Runner ────────────────────────────────────────────────────────────────

export interface RunnerDeps {
  /** Generator registry — pluggable so tests / production can swap. */
  generators?: GeneratorRegistry;
  /**
   * Wall clock — defaults to `() => new Date()`. Tests inject for
   * determinism.
   */
  clock?: () => Date;
  /**
   * UUID/id generator — defaults to a timestamp + counter scheme. Tests
   * inject for stable ids.
   */
  newId?: () => string;
}

let _idCounter = 0;
function _defaultNewId(): string {
  _idCounter += 1;
  return `output-${Date.now()}-${_idCounter}`;
}

export class FacilitatorRunner {
  private readonly generators: GeneratorRegistry;
  private readonly clock: () => Date;
  private readonly newId: () => string;

  constructor(deps: RunnerDeps = {}) {
    this.generators = deps.generators ?? new GeneratorRegistry();
    this.clock = deps.clock ?? (() => new Date());
    this.newId = deps.newId ?? _defaultNewId;
  }

  /**
   * Start: intake + score + generate seed output.
   * Mutates the passed `state` to record the output id (caller then
   * persists the JSON). Returns the seed result for the caller to
   * relay/save.
   */
  async start(
    state: RunnerState,
    projectDescription: string,
    answers: IntakeAnswers,
  ): Promise<SeedResult> {
    const intake = processIntake(projectDescription, state.style, answers);

    const generator: StyledOutputGenerator = this.generators.forStyle(
      state.style,
    );
    const outputId = this.newId();
    const now = this.clock();
    const result = await generator.generate({
      outputId,
      projectPath: state.projectPath,
      projectDescription,
      finalScore: intake.finalScore,
      style: state.style,
      now,
    });

    state.outputId = outputId;

    return {
      finalScore: intake.finalScore,
      outputJson: result.outputJson,
      outputFormat: result.format,
    };
  }

  /**
   * tick: react to a runtime event. Currently — fire any on_event
   * ceremonies whose triggerEvent matches. Future: apply event-driven
   * mutations to the output (e.g. "task_completed" → mark mission done).
   */
  tick(state: RunnerState, event: FacilitatorEvent): CeremonyTrigger[] {
    const due = dueOnEvent(state.style, event);
    const { triggers, updatedLog } = fireAll(state.fireLog, due, event.at);
    state.fireLog = updatedLog;
    return triggers;
  }

  /**
   * Check clock-based ceremonies. Returns triggers for ceremonies due
   * AT OR BEFORE `now`, and updates the fire log to record the firings.
   */
  checkClockCeremonies(
    state: RunnerState,
    now: Date = this.clock(),
  ): CeremonyTrigger[] {
    const due = dueNow(state.style, state.fireLog, now);
    const { triggers, updatedLog } = fireAll(state.fireLog, due, now);
    state.fireLog = updatedLog;
    return triggers;
  }

  /**
   * Switch style. Reseeding is required when output shapes differ —
   * caller decides whether to call `start()` again with the new style
   * (preserving the project description) or keep the old output.
   *
   * Lesson namespacing (preserve task-level, drop facilitator-level)
   * lives in the personalization layer, NOT here. The runner just
   * tracks which style is active.
   */
  switchStyle(
    state: RunnerState,
    toStyle: FacilitatorStyle,
  ): SwitchResult {
    const fromId = state.style.id;
    const reseedRequired = state.style.outputMapper !== toStyle.outputMapper;
    state.style = toStyle;
    // Fire log is style-scoped — drop it on switch.
    state.fireLog = {};
    return {
      fromStyleId: fromId,
      toStyleId: toStyle.id,
      reseedRequired,
    };
  }
}
