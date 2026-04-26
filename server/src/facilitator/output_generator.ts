/**
 * StyledOutputGenerator — produces the seed `FacilitatorOutput` for a
 * given style, project description, and final ScopeScore.
 *
 * The interface is generator-agnostic: stub implementations (used in
 * tests and as fallbacks) produce minimal-but-valid outputs without an
 * LLM; the real implementations wrapping Claude/Anthropic SDK plug in
 * via the same interface.
 *
 * Design: docs/FACILITATOR_SYSTEM.md §4 + §6 (hierarchical safety —
 * narrative content goes through the style; technical decisions don't).
 */

import {
  tierForScore,
  totalScore,
  type ScopeScore,
} from "../quest/scope_scorer.js";
import type {
  FacilitatorStyle,
  OutputFormatKey,
} from "./types.js";

// ─── Generator input/output ────────────────────────────────────────────────

export interface GeneratorInput {
  /** Stable id for the output (UUID at the call site). */
  outputId: string;
  /** Project filesystem path. */
  projectPath: string;
  /** Free-form project description from the user. */
  projectDescription: string;
  /** Final ScopeScore after intake processing. */
  finalScore: ScopeScore;
  /** Style we're generating for. */
  style: FacilitatorStyle;
  /** Wall-clock now (passed in for test determinism). */
  now: Date;
}

/**
 * The generator returns a serialized JSON payload (which already
 * includes the `format` discriminator from the output's `serialize()`)
 * and the format key so the runner can persist + relay both pieces
 * efficiently.
 */
export interface GeneratorOutput {
  outputJson: string;
  format: OutputFormatKey;
}

export interface StyledOutputGenerator {
  generate(input: GeneratorInput): Promise<GeneratorOutput>;
}

// ─── Stub generators ───────────────────────────────────────────────────────
//
// Stubs produce minimal-but-valid outputs that pass the corresponding
// Dart `fromJson` decoder. They:
//   - Honor the style's outputMapper (returning the right shape)
//   - Calibrate output size by tier (micro → small → medium → large)
//   - Don't make narrative claims they can't back up — that's the LLM
//     generator's job, not the stub's.
//
// Use these in tests and as the runner's fallback when no real LLM
// generator is configured.

const QUEST_COUNT_BY_TIER: Record<string, number> = {
  micro: 3,
  small: 5,
  medium: 8,
  large: 14,
};

function questCountFor(score: ScopeScore): number {
  const tier = tierForScore(totalScore(score)).tier;
  return QUEST_COUNT_BY_TIER[tier] ?? 3;
}

export class StubQuestLineGenerator implements StyledOutputGenerator {
  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    const count = questCountFor(input.finalScore);
    const acts = [
      {
        id: "act-1",
        name: "Foundation",
        archetype: "foundation",
        quests: Array.from({ length: count }, (_, i) => ({
          id: `q${i + 1}`,
          actId: "act-1",
          title: `Quest ${i + 1}`,
          subtitle: "Stub-generated quest — narrative pending",
          description: "",
          devTask: {
            category: "data-model",
            description: "",
            acceptanceCriteria: [],
            files: [],
          },
          status: i === 0 ? "available" : "locked",
          type: "main",
          dependsOn: i === 0 ? [] : [`q${i}`],
          unlocks: i === count - 1 ? [] : [`q${i + 2}`],
          xp: 100,
          estimatedMinutes: 25,
        })),
      },
    ];

    const payload = {
      format: "quest_line",
      id: input.outputId,
      projectPath: input.projectPath,
      appSummary: input.projectDescription.slice(0, 200),
      tier: tierForScore(totalScore(input.finalScore)).tier,
      scoreBreakdown: input.finalScore,
      acts,
      transformativeChanges: 0,
      createdAt: input.now.toISOString(),
    };

    return {
      outputJson: JSON.stringify(payload),
      format: "quest_line",
    };
  }
}

export class StubMissionBriefingGenerator implements StyledOutputGenerator {
  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    // Drill caps at 3 missions regardless of tier.
    const tier = tierForScore(totalScore(input.finalScore)).tier;
    const missionCount = tier === "micro" ? 1 : tier === "small" ? 2 : 3;

    const missions = Array.from({ length: missionCount }, (_, i) => ({
      id: `m${i + 1}`,
      briefing: `Mission ${i + 1}.`,
      target: "",
      category: "data-model",
      status: "standby",
      xp: 100,
      estimatedMinutes: 25,
    }));

    const payload = {
      format: "mission_briefing",
      id: input.outputId,
      projectPath: input.projectPath,
      objective: input.projectDescription.slice(0, 200),
      missions,
      scoreBreakdown: input.finalScore,
      createdAt: input.now.toISOString(),
    };

    return {
      outputJson: JSON.stringify(payload),
      format: "mission_briefing",
    };
  }
}

export class StubMilestoneTreeGenerator implements StyledOutputGenerator {
  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    const tier = tierForScore(totalScore(input.finalScore)).tier;
    const milestoneCount = tier === "micro" ? 2 : tier === "small" ? 3 : 5;
    const tasksPerMilestone = tier === "large" ? 4 : 2;

    const milestones = Array.from({ length: milestoneCount }, (_, i) => ({
      id: `M${i + 1}`,
      name: `Milestone ${i + 1}`,
      dependsOn: i === 0 ? [] : [`M${i}`],
      status: "not_started",
      tasks: Array.from({ length: tasksPerMilestone }, (_, j) => ({
        id: `t${i + 1}-${j + 1}`,
        milestoneId: `M${i + 1}`,
        title: `Task ${j + 1}`,
        description: "",
        category: "data-model",
        status: "pending",
        xp: 50,
        estimatedMinutes: 25,
      })),
    }));

    const payload = {
      format: "milestone_tree",
      id: input.outputId,
      projectPath: input.projectPath,
      objective: input.projectDescription.slice(0, 200),
      milestones,
      scoreBreakdown: input.finalScore,
      createdAt: input.now.toISOString(),
    };

    return {
      outputJson: JSON.stringify(payload),
      format: "milestone_tree",
    };
  }
}

// ─── Registry ──────────────────────────────────────────────────────────────

/**
 * Picks the right generator for a style's `outputMapper`. Defaults to
 * stub generators; real LLM-backed generators replace these via
 * `setGenerator` at server boot.
 */
export class GeneratorRegistry {
  private generators = new Map<OutputFormatKey, StyledOutputGenerator>();

  constructor() {
    this.generators.set("quest_line", new StubQuestLineGenerator());
    this.generators.set("mission_briefing", new StubMissionBriefingGenerator());
    this.generators.set("milestone_tree", new StubMilestoneTreeGenerator());
  }

  setGenerator(format: OutputFormatKey, generator: StyledOutputGenerator) {
    this.generators.set(format, generator);
  }

  /**
   * Resolves the generator for the style's declared output mapper.
   * Throws if no generator is registered (caller should pre-register
   * stubs at boot to avoid this in production paths).
   */
  forStyle(style: FacilitatorStyle): StyledOutputGenerator {
    const g = this.generators.get(style.outputMapper);
    if (!g) {
      throw new Error(
        `No generator registered for output format "${style.outputMapper}" `
          + `(style id=${style.id})`,
      );
    }
    return g;
  }
}
