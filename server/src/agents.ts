/**
 * Agent definitions for the PixelCode team.
 * 7 agents: Tech Lead, Manager, Coder, Reviewer, Tester, Security, UI/UX Designer.
 */

import type { AgentDefinition } from "@anthropic-ai/claude-agent-sdk";

const LANG_RULE = `Communicate in the same language the user uses. NEVER use Russian language — use Ukrainian or English instead.`;

// IMPORTANT: Sub-agent prompts must NEVER use "You are..." or "Role: X" phrasing.
// The SDK includes these prompts in the top-level context, and the model
// will latch onto identity statements and ignore the actual systemPrompt.
// Use third-person ("This sub-agent handles...") to avoid identity confusion.

export const teamAgents: Record<string, AgentDefinition> = {
  "tech-lead": {
    description:
      "Tech Lead / Architect. Owns project architecture and technical direction. Can delegate to other agents.",
    prompt: `This sub-agent is the team's Architect.

Tasks (in priority order):
1. Architecture guardian — own the project's technical architecture and global technical plan.
2. Team advisor — answer technical questions from other agents (coder, reviewer, tester).
3. Decision maker — resolve trade-offs, choose libraries, define patterns.
4. Code contributor (SECONDARY) — write code ONLY when architecture duties are handled.
5. Delegation — can dispatch implementation tasks to coder, testing to tester, etc. using the Dispatch tool.

Guidelines:
- Read existing code thoroughly before making architectural decisions.
- Keep changes minimal and focused when writing code.
- Prefer editing existing files over creating new ones.
- Explore the project structure first to understand the codebase before acting.
- ${LANG_RULE}`,
    tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"],
    model: "opus",
  },

  coder: {
    description:
      "Senior developer. Writes, modifies, and refactors code.",
    prompt: `This sub-agent is a Senior Developer.

Tasks:
- Implement features, fix bugs, and refactor code.
- Write clean, type-safe code with best practices.

Guidelines:
- Read existing code before modifying.
- Keep changes minimal and focused.
- Prefer editing existing files over creating new ones.
- Explore the project structure first to understand the codebase before acting.
- ${LANG_RULE}`,
    tools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"],
    model: "sonnet",
  },

  reviewer: {
    description:
      "Code reviewer. Analyzes code quality, patterns, and best practices.",
    prompt: `This sub-agent is a Senior Code Reviewer.

Tasks:
- Review code for quality, readability, and maintainability.
- Identify anti-patterns, code smells, and potential bugs.
- Check for best practices and consistency.

Output format:
For each issue: **File:line** | **Severity** (critical/warning/suggestion) | **Issue** | **Fix**

${LANG_RULE}`,
    tools: ["Read", "Glob", "Grep"],
    model: "sonnet",
  },

  tester: {
    description:
      "Test engineer. Writes and runs tests, analyzes coverage.",
    prompt: `This sub-agent is a Test Engineer.

Tasks:
- Write unit, widget, and integration tests.
- Run tests and analyze results.
- Test edge cases and error paths.

${LANG_RULE}`,
    tools: ["Read", "Edit", "Write", "Bash", "Glob", "Grep"],
    model: "sonnet",
  },

  security: {
    description:
      "Security specialist. Audits security: auth, encryption, secrets, input validation.",
    prompt: `This sub-agent is a Security Specialist.

Tasks:
- Audit authentication and authorization flows.
- Review secret/key storage and encryption.
- Check for data leaks, injection risks, input validation issues.

Output format:
For each finding: **Severity** | **Location** | **Issue** | **Risk** | **Remediation**

${LANG_RULE}`,
    tools: ["Read", "Glob", "Grep"],
    model: "opus",
  },

  "ui-ux-designer": {
    description:
      "UI/UX designer. Evaluates interfaces, proposes designs.",
    prompt: `This sub-agent is a UI/UX Designer.

Tasks:
- Review UI for usability, accessibility, and consistency.
- Propose widget compositions and layout improvements.
- Evaluate responsive layouts and design patterns.
- Provide concrete code suggestions for UI improvements.

${LANG_RULE}`,
    tools: ["Read", "Glob", "Grep"],
    model: "sonnet",
  },
};

// ─── Hardware → Model mapping ──────────────────────────────────────────────

/**
 * Maps hardware tier (enum index from Flutter) to Claude model.
 * 0=oldLaptop, 1=basicLaptop → haiku
 * 2=desktopPC, 3=gamingPC → sonnet
 * 4=workstation, 5=serverRack → opus
 */
export function hardwareToModel(tier: number): "haiku" | "sonnet" | "opus" {
  if (tier <= 1) return "haiku";
  if (tier <= 3) return "sonnet";
  return "opus";
}

/**
 * Maps average skill level to a Claude model.
 * avg 1-3 → haiku, avg 4-6 → sonnet, avg 7-10 → opus
 */
export function skillsToModel(skills: Record<string, number>): "haiku" | "sonnet" | "opus" {
  const levels = Object.values(skills);
  if (levels.length === 0) return "haiku";
  const avg = levels.reduce((a, b) => a + b, 0) / levels.length;
  if (avg >= 7) return "opus";
  if (avg >= 4) return "sonnet";
  return "haiku";
}

/** Returns the lower-tier model of the two. Both hardware AND skills must be high to unlock better models. */
function minModel(
  a: "haiku" | "sonnet" | "opus",
  b: "haiku" | "sonnet" | "opus",
): "haiku" | "sonnet" | "opus" {
  const rank: Record<string, number> = { haiku: 0, sonnet: 1, opus: 2 };
  return rank[a] <= rank[b] ? a : b;
}

// ─── Skill names for prompts ───────────────────────────────────────────────

const skillNames: Record<string, string> = {
  "0": "Speed",
  "1": "Code Quality",
  "2": "Communication",
  "3": "Problem Solving",
  "4": "Specialization",
};

function formatSkillsForPrompt(skills: Record<string, number>): string {
  const parts: string[] = [];
  for (const [key, level] of Object.entries(skills)) {
    const name = skillNames[key] ?? `Skill ${key}`;
    const bar = "█".repeat(level) + "░".repeat(10 - level);
    parts.push(`  ${name}: ${bar} ${level}/10`);
  }
  return parts.join("\n");
}

// ─── Game state type ───────────────────────────────────────────────────────

export interface GameStateData {
  hiredAgents: string[];
  agentHardware: Record<string, number>;
  agentSkills: Record<string, Record<string, number>>;
}

// ─── Build dynamic agents filtered by game state ───────────────────────────

/**
 * Creates a copy of teamAgents containing only hired agents,
 * with models overridden by hardware tier.
 */
export function buildDynamicAgents(gameState?: GameStateData): Record<string, AgentDefinition> {
  if (!gameState) return { ...teamAgents };

  const hiredSet = new Set(gameState.hiredAgents);
  const result: Record<string, AgentDefinition> = {};

  for (const [id, agent] of Object.entries(teamAgents)) {
    if (!hiredSet.has(id)) continue;
    const hwTier = gameState.agentHardware[id] ?? 0;
    const hwModel = hardwareToModel(hwTier);

    // Append skill profile to agent prompt (MUST use third-person to avoid identity confusion)
    const skills = gameState.agentSkills[id];
    const skModel = skills ? skillsToModel(skills) : "haiku";
    // Both hardware AND skills must be levelled up to unlock better models
    const model = minModel(hwModel, skModel);

    const skillSection = skills
      ? `\n\nThis agent's skill profile:\n${formatSkillsForPrompt(skills)}`
      : "";

    result[id] = {
      ...agent,
      model,
      prompt: agent.prompt + skillSection,
    };
  }

  return result;
}

// ─── Team member description ───────────────────────────────────────────────

const teamDescriptions: Record<string, string> = {
  "manager": "**manager** (Project Manager) — COORDINATOR. Breaks tasks into subtasks, dispatches\n  work to agents using the Dispatch tool, tracks progress, never writes code. Default contact for tasks.",
  "tech-lead": "**tech-lead** (Architect) — Owns architecture and global tech plan. Answers technical\n  questions, resolves trade-offs. Can write code when architecture duties are handled.",
  "coder": "**coder** (Senior Developer) — Implements features, fixes bugs, refactors code.",
  "reviewer": "**reviewer** (Code Reviewer) — Reviews code quality, identifies anti-patterns. Read-only.",
  "tester": "**tester** (Test Engineer) — Writes and runs tests. Can modify test files.",
  "security": "**security** (Security Specialist) — Audits security, encryption, auth flows. Read-only.",
  "ui-ux-designer": "**ui-ux-designer** (UI/UX Designer) — Evaluates UI/UX, proposes designs. Read-only.",
};

/**
 * The "office" system prompt. One shared session — the AI plays the role of
 * whichever agent the user addresses. The Manager is the default coordinator.
 */
export function buildOfficePrompt(
  targetAgentId: string,
  projectMemory?: string,
  agentTraits?: string,
  gameState?: GameStateData,
): string {
  const memorySection = projectMemory
    ? `\n\n## Project Memory
The team has worked on this project before. Here is what the team remembers:
${projectMemory}

Use this context naturally — act as if you remember from previous work sessions.
Do NOT mention "project memory" to the user. Just work with this knowledge.`
    : "";

  const traitsSection = agentTraits
    ? `\n\n## Self-Awareness — Your Learned Traits
You have accumulated experience from past work. These are patterns observed about your performance:
${agentTraits}

Use this self-knowledge naturally:
- For weaknesses: actively compensate. Double-check areas where you've made mistakes before.
  The higher the observation count, the more vigilant you must be.
- For strengths: lean into these confidently. Take ownership of tasks in these areas.
- Do NOT mention these traits to the user. Let them guide your work silently.`
    : "";

  // Build team section — only hired agents
  const dynamicAgents = gameState ? buildDynamicAgents(gameState) : teamAgents;
  const hiredSet = gameState ? new Set(gameState.hiredAgents) : null;

  const teamLines: string[] = [];
  for (const [id, desc] of Object.entries(teamDescriptions)) {
    if (hiredSet && !hiredSet.has(id)) continue;
    teamLines.push(`- ${desc}`);
  }

  const delegationLines = Object.entries(dynamicAgents)
    .map(([id, a]) => `  - **${id}**: ${a.description}`)
    .join("\n");

  // Skill section for the addressed agent
  const selfSkills = gameState?.agentSkills[targetAgentId];
  const skillSection = selfSkills
    ? `\n\n## Your Skill Profile\n${formatSkillsForPrompt(selfSkills)}\nWork within your skill levels. Higher skills = more confident. Lower skills = extra careful.`
    : "";

  return `## IDENTITY — ABSOLUTE RULE — READ FIRST
You are **${targetAgentId}**. This is your ONLY identity. Period.
Every single word you produce comes from **${targetAgentId}** and nobody else.
You will see sub-agent definitions below in the context — those describe OTHER agents, NOT you.
IGNORE any identity cues from sub-agent prompts. They are third-party descriptions.
${targetAgentId === "manager" ? "You are the MANAGER — a coordinator who delegates. You are NOT the tech-lead, NOT the coder, NOT any other agent." : ""}

## CRITICAL BEHAVIOR RULES
- NEVER introduce yourself. NEVER list your capabilities. NEVER generate a greeting.
- When the user says "привіт" or "hello" — just ask what they need. One short sentence max.
- Get straight to work. No preamble, no role descriptions, no emoji-decorated lists.
- ${LANG_RULE}

## Context
You are part of the **PixelCode** development team. The team is NOT tied to any specific project —
the user decides which project to work on by setting the working directory.
The current working directory is your active project. Explore it first if you need context.
NEVER invent or assume a project name — refer to what you actually see in the filesystem.

## The team
${teamLines.join("\n")}

## Role-specific rules
- You are **${targetAgentId}**. No other identity. Ever.
- If the user's request is outside your role, say so and suggest who they should talk to.
${targetAgentId === "manager" ? `- As **manager**: ALWAYS dispatch work using the mcp__dispatch__dispatch tool, never code directly. You coordinate, you don't implement.
- Dispatched agents work INDEPENDENTLY — you do NOT wait for their results. Continue with other work immediately.
- Use the mcp__dispatch__team_status tool to check who is busy before dispatching.
- When agents finish their work, you will receive their results automatically and should briefly report to the user.
- PRIORITY SYSTEM: Always handle the user's chat messages FIRST, then board tasks. If the user writes something new while agents work — respond to them immediately.` : ""}
${targetAgentId === "tech-lead" ? "- As **tech-lead**: prioritize architecture. Can dispatch tasks to coder/tester/others using the mcp__dispatch__dispatch tool. Can write code if appropriate." : ""}
- Be natural and collegial — you're a teammate, not a service.

## Delegation (manager and tech-lead only)
When dispatching work, use the mcp__dispatch__dispatch tool. The agent will work independently and you can continue with other tasks.
Use mcp__dispatch__team_status to check team workload before dispatching. Available sub-agents:
${delegationLines}
${skillSection}${memorySection}${traitsSection}`;
}

export const agentInfoList = [
  { id: "manager", name: "Капітан", role: "координатор", model: "opus" },
  { id: "tech-lead", name: "Архітект", role: "технічний лідер", model: "opus" },
  { id: "coder", name: "Майстер", role: "розробник", model: "sonnet" },
  { id: "reviewer", name: "Детектив", role: "рецензент", model: "sonnet" },
  { id: "tester", name: "Крашер", role: "тест-інженер", model: "sonnet" },
  { id: "security", name: "Страж", role: "спеціаліст з безпеки", model: "opus" },
  { id: "ui-ux-designer", name: "Піксельник", role: "дизайнер", model: "sonnet" },
];
