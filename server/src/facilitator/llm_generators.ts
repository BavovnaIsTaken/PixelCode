/**
 * LLM-backed StyledOutputGenerator implementations.
 *
 * Each generator calls Claude (via Claude Agent SDK) to produce a
 * narrative-rich seed output matching the style's persona and lexicon.
 * On failure the error propagates — the WS handler surfaces
 * `facilitator_error` to the client rather than silently stubbing.
 *
 * Design: caller (callClaude) is injectable via constructor so unit
 * tests avoid real API calls.
 */

import {
  query,
  type SDKAssistantMessage,
  type SDKResultMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { tierForScore, totalScore } from "../quest/scope_scorer.js";
import type {
  GeneratorInput,
  GeneratorOutput,
  StyledOutputGenerator,
} from "./output_generator.js";
import type { FacilitatorStyle } from "./types.js";

// ─── Shared types & utilities ──────────────────────────────────────────────

export type CallerFn = (
  systemPrompt: string,
  userPrompt: string,
  model: "haiku" | "sonnet",
  projectPath: string,
) => Promise<string>;

/** Strips markdown fences; falls back to outermost { … } extraction. */
export function extractJson(text: string): string {
  const jsonFence = text.match(/```json\s*([\s\S]+?)\s*```/);
  if (jsonFence) return jsonFence[1].trim();
  const codeFence = text.match(/```\s*([\s\S]+?)\s*```/);
  if (codeFence) return codeFence[1].trim();
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start !== -1 && end > start) return text.slice(start, end + 1);
  return text.trim();
}

export function modelForTier(tier: string): "haiku" | "sonnet" {
  return tier === "medium" || tier === "large" ? "sonnet" : "haiku";
}

function lexiconLines(lexicon: Record<string, string>): string {
  const entries = Object.entries(lexicon);
  if (!entries.length) return "  (none)";
  return entries.map(([k, v]) => `  ${k} → "${v}"`).join("\n");
}

export async function callClaude(
  systemPrompt: string,
  userPrompt: string,
  model: "haiku" | "sonnet",
  projectPath: string,
): Promise<string> {
  let output = "";

  const iter = query({
    prompt: userPrompt,
    options: {
      systemPrompt,
      model,
      allowedTools: [],
      cwd: projectPath,
      includePartialMessages: false,
      permissionMode: "acceptEdits",
      maxTurns: 1,
      persistSession: false,
    },
  });

  for await (const msg of iter) {
    if (msg.type === "assistant") {
      const asst = msg as SDKAssistantMessage;
      if (!asst.parent_tool_use_id) {
        for (const block of asst.message.content) {
          if (block.type === "text") {
            output += (block as { type: "text"; text: string }).text;
          }
        }
      }
    }
    if (msg.type === "result") {
      const res = msg as SDKResultMessage;
      const resText =
        "result" in res
          ? (res as unknown as Record<string, string>).result ?? ""
          : "";
      if (resText && !output) output = resText;
    }
  }

  return output;
}

// ─── QuestLine generator ───────────────────────────────────────────────────

const QUEST_LINE_SCHEMA = `\
{
  "format": "quest_line",
  "id": "<outputId>",
  "projectPath": "<projectPath>",
  "appSummary": "<1-2 sentences describing the app>",
  "tier": "<micro|small|medium|large>",
  "scoreBreakdown": <scoreBreakdown object>,
  "acts": [
    {
      "id": "act-1",
      "name": "<act name in style voice>",
      "archetype": "<foundation|interface|logic|connection|polish|launch>",
      "quests": [
        {
          "id": "q1",
          "actId": "act-1",
          "title": "<quest title>",
          "subtitle": "<one sentence>",
          "description": "<what the developer must do, style voice, 1-3 sentences>",
          "payoffLine": "<optional reward/consequence line>",
          "devTask": {
            "category": "<data-model|ui-screen|ui-component|api-route|auth|integration|realtime|testing|deploy>",
            "description": "<technical coding task>",
            "acceptanceCriteria": ["<specific testable criterion>"],
            "files": []
          },
          "status": "available",
          "type": "main",
          "dependsOn": [],
          "unlocks": ["q2"],
          "xp": 150,
          "estimatedMinutes": 30
        }
      ]
    }
  ],
  "transformativeChanges": 0,
  "createdAt": "<ISO8601>"
}`;

function questLineSystemPrompt(style: FacilitatorStyle): string {
  return `\
You are a facilitator for a software development game. Your persona:
${style.personaPrompt}

Generate a quest line (narrative project plan) for a software project. Return ONLY valid JSON — no prose, no markdown fences, no explanation before or after.

Tone (scale 0.0–1.0):
- aggression=${style.toneModifiers.aggression}  (0=calm, 1=intense)
- formality=${style.toneModifiers.formality}  (0=casual, 1=formal)
- verbosity=${style.toneModifiers.verbosity}  (0=terse, 1=elaborate)

Lexicon overrides:
${lexiconLines(style.lexicon)}

Rules:
- First quest of each act: status "available"; all others: status "locked"
- dependsOn/unlocks form a sequential chain within each act (q1 unlocks q2, q2 unlocks q3, …)
- xp: integer 50–500; estimatedMinutes: integer 15–180
- acceptanceCriteria: 2–4 specific, testable items
- devTask.category must be exactly one of: data-model, ui-screen, ui-component, api-route, auth, integration, realtime, testing, deploy
- appSummary: 1–2 plain-language sentences about what the app does

Schema (fill every placeholder, keep "format": "quest_line" verbatim):
${QUEST_LINE_SCHEMA}`;
}

const QUEST_CFG: Record<string, { quests: number; acts: number }> = {
  micro: { quests: 3, acts: 1 },
  small: { quests: 5, acts: 2 },
  medium: { quests: 8, acts: 3 },
  large: { quests: 14, acts: 3 },
};

export class ClaudeQuestLineGenerator implements StyledOutputGenerator {
  constructor(
    private readonly projectPath: string,
    private readonly caller: CallerFn = callClaude,
  ) {}

  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    const tier = tierForScore(totalScore(input.finalScore)).tier;
    const { quests, acts } = QUEST_CFG[tier] ?? { quests: 3, acts: 1 };
    const model = modelForTier(tier);

    const userPrompt = `\
Project description: ${input.projectDescription}

Generate a quest line for this project.
- tier: ${tier}
- total quests: ${quests}, distributed across ${acts} act(s)
- outputId: ${input.outputId}
- projectPath: ${input.projectPath}
- scoreBreakdown: ${JSON.stringify(input.finalScore)}
- createdAt: ${input.now.toISOString()}

Return ONLY the JSON object.`;

    try {
      const raw = await this.caller(
        questLineSystemPrompt(input.style),
        userPrompt,
        model,
        this.projectPath,
      );
      const json = extractJson(raw);
      JSON.parse(json); // validate before returning
      return { outputJson: json, format: "quest_line" };
    } catch (err) {
      throw new Error(`ClaudeQuestLineGenerator failed: ${err}`);
    }
  }
}

// ─── MissionBriefing generator ─────────────────────────────────────────────

const MISSION_BRIEFING_SCHEMA = `\
{
  "format": "mission_briefing",
  "id": "<outputId>",
  "projectPath": "<projectPath>",
  "objective": "<1-2 sentence mission statement, style voice>",
  "missions": [
    {
      "id": "m1",
      "briefing": "<terse in-character briefing>",
      "target": "<specific measurable target>",
      "category": "<data-model|ui-screen|ui-component|api-route|auth|integration|realtime|testing|deploy>",
      "status": "standby",
      "xp": 200,
      "estimatedMinutes": 45
    }
  ],
  "scoreBreakdown": <scoreBreakdown object>,
  "createdAt": "<ISO8601>"
}`;

function missionBriefingSystemPrompt(style: FacilitatorStyle): string {
  return `\
You are a facilitator for a software development game. Your persona:
${style.personaPrompt}

Generate a mission briefing (project plan) for a software project. Return ONLY valid JSON — no prose, no markdown, no explanation.

Tone (scale 0.0–1.0):
- aggression=${style.toneModifiers.aggression}
- formality=${style.toneModifiers.formality}
- verbosity=${style.toneModifiers.verbosity}

Lexicon overrides:
${lexiconLines(style.lexicon)}

Rules:
- All missions have status "standby"
- briefing: punchy, in-character (match aggression + verbosity tone)
- target: specific and measurable ("Implement JWT auth with refresh tokens", not "do auth")
- category must be exactly one of: data-model, ui-screen, ui-component, api-route, auth, integration, realtime, testing, deploy
- xp: integer 100–500; estimatedMinutes: integer 30–240

Schema (fill every placeholder, keep "format": "mission_briefing" verbatim):
${MISSION_BRIEFING_SCHEMA}`;
}

const MISSION_CFG: Record<string, number> = {
  micro: 1,
  small: 2,
  medium: 3,
  large: 3,
};

export class ClaudeMissionBriefingGenerator implements StyledOutputGenerator {
  constructor(
    private readonly projectPath: string,
    private readonly caller: CallerFn = callClaude,
  ) {}

  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    const tier = tierForScore(totalScore(input.finalScore)).tier;
    const missionCount = MISSION_CFG[tier] ?? 3;
    const model = modelForTier(tier);

    const userPrompt = `\
Project description: ${input.projectDescription}

Generate a mission briefing for this project.
- tier: ${tier}
- missions: ${missionCount}
- outputId: ${input.outputId}
- projectPath: ${input.projectPath}
- scoreBreakdown: ${JSON.stringify(input.finalScore)}
- createdAt: ${input.now.toISOString()}

Return ONLY the JSON object.`;

    try {
      const raw = await this.caller(
        missionBriefingSystemPrompt(input.style),
        userPrompt,
        model,
        this.projectPath,
      );
      const json = extractJson(raw);
      JSON.parse(json);
      return { outputJson: json, format: "mission_briefing" };
    } catch (err) {
      throw new Error(`ClaudeMissionBriefingGenerator failed: ${err}`);
    }
  }
}

// ─── MilestoneTree generator ───────────────────────────────────────────────

const MILESTONE_TREE_SCHEMA = `\
{
  "format": "milestone_tree",
  "id": "<outputId>",
  "projectPath": "<projectPath>",
  "objective": "<high-level project goal>",
  "milestones": [
    {
      "id": "M1",
      "name": "<milestone name>",
      "dueDate": "<optional YYYY-MM-DD>",
      "dependsOn": [],
      "status": "not_started",
      "tasks": [
        {
          "id": "t1-1",
          "milestoneId": "M1",
          "title": "<task title>",
          "description": "<what to build>",
          "category": "<data-model|ui-screen|ui-component|api-route|auth|integration|realtime|testing|deploy>",
          "status": "pending",
          "xp": 50,
          "estimatedMinutes": 25
        }
      ]
    }
  ],
  "scoreBreakdown": <scoreBreakdown object>,
  "createdAt": "<ISO8601>"
}`;

function milestoneTreeSystemPrompt(style: FacilitatorStyle): string {
  return `\
You are a facilitator for a software development game. Your persona:
${style.personaPrompt}

Generate a milestone tree (project plan) for a software project. Return ONLY valid JSON — no prose, no markdown, no explanation.

Tone (scale 0.0–1.0):
- aggression=${style.toneModifiers.aggression}
- formality=${style.toneModifiers.formality}
- verbosity=${style.toneModifiers.verbosity}

Lexicon overrides:
${lexiconLines(style.lexicon)}

Rules:
- All milestones status "not_started"; all tasks status "pending"
- Milestones form a sequential chain: M2.dependsOn=["M1"], M3.dependsOn=["M2"], etc.; M1.dependsOn=[]
- dueDate optional — include only if the project scope warrants a date (YYYY-MM-DD)
- category must be exactly one of: data-model, ui-screen, ui-component, api-route, auth, integration, realtime, testing, deploy
- task xp: integer 30–200; milestone names: clear, achievement-focused

Schema (fill every placeholder, keep "format": "milestone_tree" verbatim):
${MILESTONE_TREE_SCHEMA}`;
}

const MILESTONE_CFG: Record<string, { milestones: number; tasksEach: number }> =
  {
    micro: { milestones: 2, tasksEach: 2 },
    small: { milestones: 3, tasksEach: 2 },
    medium: { milestones: 4, tasksEach: 3 },
    large: { milestones: 5, tasksEach: 4 },
  };

export class ClaudeMilestoneTreeGenerator implements StyledOutputGenerator {
  constructor(
    private readonly projectPath: string,
    private readonly caller: CallerFn = callClaude,
  ) {}

  async generate(input: GeneratorInput): Promise<GeneratorOutput> {
    const tier = tierForScore(totalScore(input.finalScore)).tier;
    const { milestones, tasksEach } =
      MILESTONE_CFG[tier] ?? { milestones: 3, tasksEach: 2 };
    const model = modelForTier(tier);

    const userPrompt = `\
Project description: ${input.projectDescription}

Generate a milestone tree for this project.
- tier: ${tier}
- milestones: ${milestones}, tasks per milestone: ${tasksEach}
- outputId: ${input.outputId}
- projectPath: ${input.projectPath}
- scoreBreakdown: ${JSON.stringify(input.finalScore)}
- createdAt: ${input.now.toISOString()}

Return ONLY the JSON object.`;

    try {
      const raw = await this.caller(
        milestoneTreeSystemPrompt(input.style),
        userPrompt,
        model,
        this.projectPath,
      );
      const json = extractJson(raw);
      JSON.parse(json);
      return { outputJson: json, format: "milestone_tree" };
    } catch (err) {
      throw new Error(`ClaudeMilestoneTreeGenerator failed: ${err}`);
    }
  }
}
