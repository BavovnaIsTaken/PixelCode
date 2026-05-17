import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  extractJson,
  modelForTier,
  ClaudeQuestLineGenerator,
  ClaudeMissionBriefingGenerator,
  ClaudeMilestoneTreeGenerator,
  type CallerFn,
} from "../src/facilitator/llm_generators.js";
import { LLMGenerationError } from "../src/facilitator/llm_runner.js";
import type { GeneratorInput } from "../src/facilitator/output_generator.js";
import type { FacilitatorStyle } from "../src/facilitator/types.js";
import type { ScopeScore } from "../src/quest/scope_scorer.js";

// ─── Fixtures ──────────────────────────────────────────────────────────────

const T0 = new Date("2026-04-28T10:00:00Z");

const microScore: ScopeScore = {
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
}; // total=2 → micro

const largeScore: ScopeScore = {
  entityCount: 4,
  interactionSurface: 4,
  auth: 3,
  integrations: 4,
  realtime: 3,
}; // total=18 → large

const gameMasterStyle: FacilitatorStyle = {
  id: "game_master",
  displayName: "Game Master",
  tagline: "",
  laloux: "green",
  personaPrompt: "You are a mysterious game master guiding the hero.",
  lexicon: { task: "quest", feature: "power" },
  ceremonySchedule: [],
  intakeTemplate: [],
  outputMapper: "quest_line",
  toneModifiers: { aggression: 0.1, formality: 0.2, verbosity: 0.7 },
};

const drillStyle: FacilitatorStyle = {
  ...gameMasterStyle,
  id: "drill_sergeant",
  displayName: "Drill Sergeant",
  personaPrompt: "You are a relentless drill sergeant.",
  lexicon: { task: "mission", feature: "objective" },
  outputMapper: "mission_briefing",
  toneModifiers: { aggression: 0.95, formality: 0.45, verbosity: 0.15 },
};

const mariyaStyle: FacilitatorStyle = {
  ...gameMasterStyle,
  id: "Mariya",
  displayName: "Марія (Project Manager)",
  personaPrompt: "Ти Марія — PM для соло-розробника PixelCode.",
  lexicon: { task: "завдання", milestone: "мілстоун", blocker: "блокер" },
  outputMapper: "milestone_tree",
  toneModifiers: { aggression: 0.1, formality: 0.75, verbosity: 0.5 },
};

function makeInput(
  style: FacilitatorStyle,
  score: ScopeScore = microScore,
): GeneratorInput {
  return {
    outputId: "test-output-1",
    projectPath: "/tmp/test-project",
    projectDescription: "A task management app for remote teams.",
    finalScore: score,
    style,
    now: T0,
  };
}

// ─── extractJson ───────────────────────────────────────────────────────────

describe("extractJson", () => {
  test("returns bare JSON unchanged", () => {
    const json = '{"format":"quest_line","id":"x"}';
    assert.equal(extractJson(json), json);
  });

  test("strips ```json fences", () => {
    const wrapped = '```json\n{"format":"quest_line"}\n```';
    assert.equal(extractJson(wrapped), '{"format":"quest_line"}');
  });

  test("strips plain ``` fences", () => {
    const wrapped = '```\n{"a":1}\n```';
    assert.equal(extractJson(wrapped), '{"a":1}');
  });

  test("extracts outermost braces when prose wraps JSON", () => {
    const text = 'Here is the JSON:\n{"format":"mission_briefing"}\nDone.';
    assert.equal(extractJson(text), '{"format":"mission_briefing"}');
  });

  test("returns null when no JSON-shaped block is present", () => {
    // Previously this fell through to text.trim(), which produced
    // confusing JSON.parse errors downstream. Now the caller has to
    // detect missing JSON explicitly.
    assert.equal(extractJson("  no json here  "), null);
    assert.equal(extractJson(""), null);
    assert.equal(extractJson("just an opening { without close"), null);
  });
});

// ─── modelForTier ──────────────────────────────────────────────────────────

describe("modelForTier", () => {
  test("micro → haiku", () => assert.equal(modelForTier("micro"), "haiku"));
  test("small → haiku", () => assert.equal(modelForTier("small"), "haiku"));
  test("medium → sonnet", () => assert.equal(modelForTier("medium"), "sonnet"));
  test("large → sonnet", () => assert.equal(modelForTier("large"), "sonnet"));
});

// ─── ClaudeQuestLineGenerator ──────────────────────────────────────────────

describe("ClaudeQuestLineGenerator", () => {
  const validQuestLine = JSON.stringify({
    format: "quest_line",
    id: "test-output-1",
    projectPath: "/tmp/test-project",
    appSummary: "A task management app for remote teams.",
    tier: "micro",
    scoreBreakdown: microScore,
    acts: [
      {
        id: "act-1",
        name: "The Foundation",
        archetype: "foundation",
        quests: [
          {
            id: "q1",
            actId: "act-1",
            title: "Summon the Data Model",
            subtitle: "Lay the groundwork.",
            description: "Create the core data model.",
            devTask: {
              category: "data-model",
              description: "Define the Task entity.",
              acceptanceCriteria: ["Task has id, title, status"],
              files: [],
            },
            status: "available",
            type: "main",
            dependsOn: [],
            unlocks: [],
            xp: 100,
            estimatedMinutes: 30,
          },
        ],
      },
    ],
    transformativeChanges: 0,
    createdAt: T0.toISOString(),
  });

  test("returns quest_line format from valid Claude response", async () => {
    const mockCaller: CallerFn = async () => validQuestLine;
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(gameMasterStyle));

    assert.equal(result.format, "quest_line");
    const parsed = JSON.parse(result.outputJson) as { format: string };
    assert.equal(parsed.format, "quest_line");
  });

  test("unwraps ```json fences from Claude response", async () => {
    const mockCaller: CallerFn = async () =>
      "```json\n" + validQuestLine + "\n```";
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(gameMasterStyle));
    assert.equal(result.format, "quest_line");
  });

  test("uses haiku for micro tier", async () => {
    let capturedModel = "";
    const mockCaller: CallerFn = async (_sys, _usr, model) => {
      capturedModel = model;
      return validQuestLine;
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(gameMasterStyle, microScore));
    assert.equal(capturedModel, "haiku");
  });

  test("uses sonnet for large tier", async () => {
    let capturedModel = "";
    const largePaylod = JSON.stringify({ ...JSON.parse(validQuestLine), tier: "large" });
    const mockCaller: CallerFn = async (_sys, _usr, model) => {
      capturedModel = model;
      return largePaylod;
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(gameMasterStyle, largeScore));
    assert.equal(capturedModel, "sonnet");
  });

  test("throws on invalid JSON from caller", async () => {
    const mockCaller: CallerFn = async () => "not json at all";
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await assert.rejects(
      () => gen.generate(makeInput(gameMasterStyle)),
      LLMGenerationError,
    );
  });

  test("throws when caller throws", async () => {
    const mockCaller: CallerFn = async () => {
      throw new Error("API unavailable");
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await assert.rejects(
      () => gen.generate(makeInput(gameMasterStyle)),
      LLMGenerationError,
    );
  });

  test("passes persona prompt to system prompt", async () => {
    let capturedSystem = "";
    const mockCaller: CallerFn = async (sys) => {
      capturedSystem = sys;
      return validQuestLine;
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(gameMasterStyle));
    assert.ok(
      capturedSystem.includes(gameMasterStyle.personaPrompt),
      "system prompt should include persona",
    );
  });

  test("passes lexicon overrides to system prompt", async () => {
    let capturedSystem = "";
    const mockCaller: CallerFn = async (sys) => {
      capturedSystem = sys;
      return validQuestLine;
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(gameMasterStyle));
    assert.ok(capturedSystem.includes("quest"), "lexicon key should appear");
  });
});

// ─── ClaudeMissionBriefingGenerator ───────────────────────────────────────

describe("ClaudeMissionBriefingGenerator", () => {
  const validBriefing = JSON.stringify({
    format: "mission_briefing",
    id: "test-output-1",
    projectPath: "/tmp/test-project",
    objective: "Ship the MVP.",
    missions: [
      {
        id: "m1",
        briefing: "Get it done, soldier.",
        target: "Implement Task CRUD API.",
        category: "api-route",
        status: "standby",
        xp: 200,
        estimatedMinutes: 45,
      },
    ],
    scoreBreakdown: microScore,
    createdAt: T0.toISOString(),
  });

  test("returns mission_briefing format", async () => {
    const mockCaller: CallerFn = async () => validBriefing;
    const gen = new ClaudeMissionBriefingGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(drillStyle));
    assert.equal(result.format, "mission_briefing");
  });

  test("unwraps ```json fences", async () => {
    const mockCaller: CallerFn = async () =>
      "```json\n" + validBriefing + "\n```";
    const gen = new ClaudeMissionBriefingGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(drillStyle));
    assert.equal(result.format, "mission_briefing");
  });

  test("throws on invalid JSON", async () => {
    const mockCaller: CallerFn = async () => "not json";
    const gen = new ClaudeMissionBriefingGenerator("/tmp/proj", mockCaller);
    await assert.rejects(
      () => gen.generate(makeInput(drillStyle)),
      LLMGenerationError,
    );
  });

  test("includes micro=1 mission count in user prompt", async () => {
    let capturedUser = "";
    const mockCaller: CallerFn = async (_sys, usr) => {
      capturedUser = usr;
      return validBriefing;
    };
    const gen = new ClaudeMissionBriefingGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(drillStyle, microScore));
    assert.ok(capturedUser.includes("missions: 1"), "micro tier → 1 mission");
  });
});

// ─── ClaudeMilestoneTreeGenerator ─────────────────────────────────────────

describe("ClaudeMilestoneTreeGenerator", () => {
  const validTree = JSON.stringify({
    format: "milestone_tree",
    id: "test-output-1",
    projectPath: "/tmp/test-project",
    objective: "Build a remote-team task manager.",
    milestones: [
      {
        id: "M1",
        name: "Foundation",
        dependsOn: [],
        status: "not_started",
        tasks: [
          {
            id: "t1-1",
            milestoneId: "M1",
            title: "Define data model",
            description: "Create Task entity.",
            category: "data-model",
            status: "pending",
            xp: 50,
            estimatedMinutes: 25,
          },
        ],
      },
    ],
    scoreBreakdown: microScore,
    createdAt: T0.toISOString(),
  });

  test("returns milestone_tree format", async () => {
    const mockCaller: CallerFn = async () => validTree;
    const gen = new ClaudeMilestoneTreeGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(mariyaStyle));
    assert.equal(result.format, "milestone_tree");
  });

  test("unwraps ```json fences", async () => {
    const mockCaller: CallerFn = async () =>
      "```json\n" + validTree + "\n```";
    const gen = new ClaudeMilestoneTreeGenerator("/tmp/proj", mockCaller);
    const result = await gen.generate(makeInput(mariyaStyle));
    assert.equal(result.format, "milestone_tree");
  });

  test("throws on caller error", async () => {
    const mockCaller: CallerFn = async () => {
      throw new Error("timeout");
    };
    const gen = new ClaudeMilestoneTreeGenerator("/tmp/proj", mockCaller);
    await assert.rejects(
      () => gen.generate(makeInput(mariyaStyle)),
      LLMGenerationError,
    );
  });

  test("passes project path to caller", async () => {
    let capturedPath = "";
    const mockCaller: CallerFn = async (_sys, _usr, _model, path) => {
      capturedPath = path;
      return validTree;
    };
    const gen = new ClaudeMilestoneTreeGenerator("/actual/project", mockCaller);
    await gen.generate(makeInput(mariyaStyle));
    assert.equal(capturedPath, "/actual/project");
  });

  test("micro tier: 2 milestones, 2 tasks each in user prompt", async () => {
    let capturedUser = "";
    const mockCaller: CallerFn = async (_sys, usr) => {
      capturedUser = usr;
      return validTree;
    };
    const gen = new ClaudeMilestoneTreeGenerator("/tmp/proj", mockCaller);
    await gen.generate(makeInput(mariyaStyle, microScore));
    assert.ok(capturedUser.includes("milestones: 2"), "micro → 2 milestones");
    assert.ok(capturedUser.includes("tasks per milestone: 2"), "micro → 2 tasks");
  });
});
