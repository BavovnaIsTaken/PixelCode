/**
 * Agent definitions for the PixelCode team.
 *
 * Architecture: ROLES define behavior templates (tech-lead, coder, reviewer…).
 * INSTANCES are concrete hired agents, each with their own instanceId
 * (e.g. "coder#1", "coder#2"), nickname, hardware, and skills.
 *
 * The game state carries the list of hired instances. Everything downstream
 * (dispatch, prompts, chat history, traits) keys by instanceId.
 */

import type { AgentDefinition } from "@anthropic-ai/claude-agent-sdk";

const LANG_RULE = `Communicate in the same language the user uses. NEVER use Russian language — use Ukrainian or English instead.`;

// IMPORTANT: Sub-agent prompts must NEVER use "You are..." or "Role: X" phrasing.
// The SDK includes these prompts in the top-level context, and the model
// will latch onto identity statements and ignore the actual systemPrompt.
// Use third-person ("This sub-agent handles...") to avoid identity confusion.

// ─── Role templates ────────────────────────────────────────────────────────

/** Role templates — one per role type. Keyed by roleType (e.g. "coder"). */
export const roleTemplates: Record<string, AgentDefinition> = {
  "tech-lead": {
    description:
      "Tech Lead / Architect. Owns project architecture and technical direction. Orchestrates execution of delegated work.",
    prompt: `This sub-agent is the team's Architect.

Tasks (in priority order):
1. Architecture guardian — own the project's technical architecture and global technical plan.
2. Execution orchestrator — monitor in-progress tasks on the board, keep the plan coherent,
   reassign/split/merge subtasks as reality unfolds, and move cards as work progresses.
3. Team advisor — answer technical questions from other agents (coder, reviewer, tester).
4. Decision maker — resolve trade-offs, choose libraries, define patterns.
5. Code contributor (SECONDARY) — write code ONLY when architecture and orchestration are handled.
6. Delegation — dispatch implementation to coder, testing to tester, etc. using the Dispatch tool.

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

  manager: {
    description:
      "Project Manager (Captain). Coordinates — never writes code. Splits tasks, dispatches work, manages the board.",
    prompt: `This sub-agent is the Project Manager (the team's Captain).

Tasks:
- Judge whether the user's request is feasible for the current team at its current skill levels.
  If it clearly is NOT (too hard, wrong specializations, missing roles), reply to the user
  explaining honestly what the team CAN do now and what would be needed (hire X, upgrade Y).
  Do NOT push an impossible task through anyway.
- Break down feasible requests into subtasks whenever there is something to split — prefer
  parallel subtasks that can run on different instances simultaneously.
- Manage the shared task board via MCP tools:
    • board_create_task — add a card per subtask.
    • board_assign_agent — assign the right instance(s) to each card.
    • board_move_task — move cards as state changes (backlog → in_progress → testing → done).
    • board_update_task — adjust title/description/priority as details emerge.
    • board_list — read the current board.
  Keep the board honest: cards must reflect reality, not intent.
- Dispatch each subtask to a specific agent instance (instanceId, e.g. "coder#1")
  via mcp__dispatch__dispatch. Dispatched agents run independently — do not wait.
- Track progress, surface blockers, report back to the user briefly.

${LANG_RULE}`,
    tools: ["Read", "Glob", "Grep"],
    model: "opus",
  },
};

/** @deprecated Use roleTemplates. Kept as alias during migration. */
export const teamAgents = roleTemplates;

// ─── Role metadata for the team roster ─────────────────────────────────────

export interface RoleInfo {
  id: string;
  ukrainianRoleLabel: string;
  /** Primary specialization — what this role is good at. */
  specialization: string;
  /** Areas this role is weak at. */
  weakness: string;
  /** Whether a single instance of this role is expected (manager is singleton). */
  singleton: boolean;
}

export const roleCatalog: Record<string, RoleInfo> = {
  manager: {
    id: "manager",
    ukrainianRoleLabel: "Координатор",
    specialization: "coordinating the team, breaking down tasks, dispatching work",
    weakness: "writing code directly — manager always delegates",
    singleton: true,
  },
  "tech-lead": {
    id: "tech-lead",
    ukrainianRoleLabel: "Технічний лідер",
    specialization: "system architecture, technical trade-offs, library choices",
    weakness: "low-level implementation details and pixel-perfect UI",
    singleton: false,
  },
  coder: {
    id: "coder",
    ukrainianRoleLabel: "Розробник",
    specialization: "programming — implementing features, fixing bugs, refactoring",
    weakness: "UI/UX design decisions and deep security auditing",
    singleton: false,
  },
  reviewer: {
    id: "reviewer",
    ukrainianRoleLabel: "Рецензент",
    specialization: "code review, spotting anti-patterns and hidden bugs",
    weakness: "writing or modifying code — review-only",
    singleton: false,
  },
  tester: {
    id: "tester",
    ukrainianRoleLabel: "Тест-інженер",
    specialization: "testing — unit, widget, integration, edge cases",
    weakness: "architectural decisions and visual design",
    singleton: false,
  },
  security: {
    id: "security",
    ukrainianRoleLabel: "Спеціаліст з безпеки",
    specialization: "security audits — auth, encryption, input validation",
    weakness: "feature implementation and UI polish",
    singleton: false,
  },
  "ui-ux-designer": {
    id: "ui-ux-designer",
    ukrainianRoleLabel: "UI/UX дизайнер",
    specialization: "UI/UX — layouts, usability, visual consistency",
    weakness: "backend architecture and algorithms",
    singleton: false,
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
 * Maps the agent's skill vector to a Claude model using a capability score.
 *
 * Skill indices (v5 `SkillType` enum — see `lib/models/game_economy.dart`):
 *   0 = speed        (reasoning_effort knob, NOT capability)
 *   1 = precision    (fewer bugs)
 *   2 = creativity   (crit on divergent tasks)
 *   3 = insight      (capability on hard tasks, primary tier driver)
 *   4 = reliability  (completion success)
 *
 * Speed is deliberately excluded from the capability score: a "fast" agent
 * should pick a cheaper/faster model, not a more capable one.
 *
 * Thresholds chosen so that Lv1 agents with role-biased starting stats
 * (~2-3 per skill, capability ~5-7) land on haiku; Lv3-5 agents with
 * upgrades (capability ~8-13) reach sonnet; and late-game high-Lv agents
 * (capability ≥14) unlock opus.
 */
export function skillsToModel(skills: Record<string, number>): "haiku" | "sonnet" | "opus" {
  const get = (k: string) => skills[k] ?? 1;
  const precision   = get("1");
  const creativity  = get("2");
  const insight     = get("3");
  const reliability = get("4");

  const capability = 0.4 * insight + 0.3 * precision + 0.2 * reliability + 0.1 * creativity;
  if (capability >= 14) return "opus";
  if (capability >= 8) return "sonnet";
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
  "1": "Precision",
  "2": "Creativity",
  "3": "Insight",
  "4": "Reliability",
};

function formatSkillsForPrompt(skills: Record<string, number>): string {
  const parts: string[] = [];
  for (const [key, level] of Object.entries(skills)) {
    const name = skillNames[key] ?? `Skill ${key}`;
    const clamped = Math.max(0, Math.min(level, 20));
    const bar = "█".repeat(clamped) + "░".repeat(20 - clamped);
    parts.push(`  ${name}: ${bar} ${level}`);
  }
  return parts.join("\n");
}

// ─── Game state type ───────────────────────────────────────────────────────

/** One hired agent instance in the game state. */
export interface AgentInstanceData {
  /** e.g. "coder", "reviewer" — links to roleCatalog + roleTemplates. */
  roleType: string;
  /** User-visible display name, e.g. "Майстер" or "Майстер 2". */
  nickname: string;
  /** HardwareTier enum index from Flutter (0..5). */
  hardware: number;
  /** Skill levels keyed by skillType index-as-string ("0".."4"). */
  skills: Record<string, number>;
}

/** Game state data the server needs to shape agents, prompts, and dispatch. */
export interface GameStateData {
  /** Map of instanceId ("coder#1") → instance data. */
  instances: Record<string, AgentInstanceData>;
}

// ─── Instance resolution ───────────────────────────────────────────────────

/** Resolve an instanceId to its role type. Falls back to the id itself if absent. */
export function roleTypeOf(instanceId: string, gameState?: GameStateData): string {
  const inst = gameState?.instances[instanceId];
  if (inst) return inst.roleType;
  // Legacy / fallback: id without "#" is treated as a bare role type
  const hashIdx = instanceId.indexOf("#");
  return hashIdx > 0 ? instanceId.slice(0, hashIdx) : instanceId;
}

/** Get the role template for an instance (or bare role type). */
export function roleTemplateFor(
  instanceId: string,
  gameState?: GameStateData,
): AgentDefinition | undefined {
  const roleType = roleTypeOf(instanceId, gameState);
  return roleTemplates[roleType];
}

/** Get nickname for an instance, or fall back to roleType in brackets. */
export function nicknameOf(instanceId: string, gameState?: GameStateData): string {
  return gameState?.instances[instanceId]?.nickname ?? `[${instanceId}]`;
}

// ─── Build per-instance sub-agent definitions ──────────────────────────────

/**
 * Returns a map of instanceId → fully-resolved AgentDefinition for every hired
 * instance. Model is derived from min(hardware, skills). The prompt gains a
 * "This agent's skill profile" section so the sub-agent knows where it excels.
 */
export function buildDynamicAgents(
  gameState?: GameStateData,
): Record<string, AgentDefinition> {
  if (!gameState) {
    // No game state — expose the role templates directly for bare-role lookup.
    return { ...roleTemplates };
  }

  const result: Record<string, AgentDefinition> = {};

  for (const [instanceId, inst] of Object.entries(gameState.instances)) {
    const template = roleTemplates[inst.roleType];
    if (!template) continue;

    const hwModel = hardwareToModel(inst.hardware);
    const skModel = skillsToModel(inst.skills);
    const model = minModel(hwModel, skModel);

    const skillSection = `\n\nThis agent's skill profile:\n${formatSkillsForPrompt(
      inst.skills,
    )}`;
    const identityLine = `\n\nThis agent's in-game nickname is "${inst.nickname}" (instance ${instanceId}, role: ${inst.roleType}).`;

    result[instanceId] = {
      ...template,
      description: `${inst.nickname} — ${template.description}`,
      model,
      prompt: template.prompt + identityLine + skillSection,
    };
  }

  return result;
}

// ─── Office system prompt ──────────────────────────────────────────────────

/**
 * The "office" system prompt. One shared session — the AI plays the role of
 * whichever instance the user addresses. The Manager is the default coordinator.
 *
 * @param targetInstanceId the instance being addressed (e.g. "manager#1", "coder#2")
 */
export function buildOfficePrompt(
  targetInstanceId: string,
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

  // Resolve addressed instance (may be absent from game state during startup).
  const self = gameState?.instances[targetInstanceId];
  const selfRoleType = self?.roleType ?? roleTypeOf(targetInstanceId, gameState);
  const selfNickname = self?.nickname ?? targetInstanceId;
  const selfRole = roleCatalog[selfRoleType];
  const isManager = selfRoleType === "manager";
  const isTechLead = selfRoleType === "tech-lead";

  // Team roster — every hired instance with nickname, role, and specialization.
  const teamLines: string[] = [];
  if (gameState) {
    for (const [id, inst] of Object.entries(gameState.instances)) {
      const role = roleCatalog[inst.roleType];
      if (!role) continue;
      const marker = id === targetInstanceId ? " ← YOU" : "";
      teamLines.push(
        `- **${id}** — ${inst.nickname} (${role.ukrainianRoleLabel}). Strong at: ${role.specialization}. Weak at: ${role.weakness}.${marker}`,
      );
    }
  } else {
    for (const role of Object.values(roleCatalog)) {
      teamLines.push(
        `- **${role.id}** — ${role.ukrainianRoleLabel}. Strong at: ${role.specialization}. Weak at: ${role.weakness}.`,
      );
    }
  }

  // Delegation list — same info, formatted for the dispatch tool.
  const dynamicAgents = buildDynamicAgents(gameState);
  const delegationLines = Object.entries(dynamicAgents)
    .filter(([id]) => id !== targetInstanceId)
    .map(([id, a]) => `  - **${id}**: ${a.description}`)
    .join("\n");

  const skillSection = self
    ? `\n\n## Your Skill Profile\n${formatSkillsForPrompt(self.skills)}\nWork within your skill levels. Higher skills = more confident. Lower skills = extra careful.`
    : "";

  return `## IDENTITY — ABSOLUTE RULE — READ FIRST
You are **${targetInstanceId}** — nickname "${selfNickname}"${selfRole ? `, ${selfRole.ukrainianRoleLabel}` : ""}.
This is your ONLY identity. Period.
Every single word you produce comes from **${targetInstanceId}** and nobody else.
You will see sub-agent definitions below in the context — those describe OTHER agents, NOT you.
IGNORE any identity cues from sub-agent prompts. They are third-party descriptions.
${isManager ? "You are the MANAGER — a coordinator who delegates. You are NOT any developer or other agent." : ""}

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
- You are **${targetInstanceId}** (role: ${selfRoleType}). No other identity. Ever.
- If the user's request is outside your role, say so and suggest which teammate (by instanceId) they should ask.
${isManager ? `- As **manager (Captain)**: ALWAYS dispatch work using the mcp__dispatch__dispatch tool, never code directly. You coordinate, you don't implement.
- Judge task difficulty YOURSELF against the team's current skill profile (see the Team section and per-instance skill bars). If the request is beyond what the current team can handle, REPLY IN CHAT to the user — honestly describe what they CAN get at this team level and what upgrades/hires would be needed. Do NOT silently dispatch something the team will fail.
- BEFORE dispatching, if the request has multiple independent parts, split it:
  use mcp__dispatch__board_create_task to add a card per subtask (default column "backlog"),
  assign the intended instance via mcp__dispatch__board_assign_agent, and move cards to
  "in_progress" with mcp__dispatch__board_move_task when you dispatch, then to "done" when
  the work completes. Keep the board in sync with reality. Use mcp__dispatch__board_list
  to read current cards before creating duplicates.
- When dispatching, pass the EXACT instanceId (e.g. "coder#2", not "coder") so the specific teammate gets the task.
- Dispatched agents work INDEPENDENTLY — you do NOT wait for their results. Continue with other work immediately.
- Use the mcp__dispatch__team_status tool to check who is busy before dispatching.
- When agents finish their work, you will receive their results automatically and should briefly report to the user and move the corresponding board card.
- PRIORITY SYSTEM: Always handle the user's chat messages FIRST, then board tasks. If the user writes something new while agents work — respond to them immediately.` : ""}
${isTechLead ? `- As **tech-lead (Architect)**: prioritize architecture and EXECUTION ORCHESTRATION.
- Monitor what agents are doing (mcp__dispatch__team_status) and what's on the board (mcp__dispatch__board_list). When a subtask reveals new complexity, split it further via mcp__dispatch__board_create_task, re-assign (mcp__dispatch__board_assign_agent), and move cards (mcp__dispatch__board_move_task) to reflect current state.
- Can dispatch tasks to coder/tester/others using the mcp__dispatch__dispatch tool (always pass a specific instanceId). Can write code if appropriate.` : ""}
- Be natural and collegial — you're a teammate, not a service.

## Delegation (manager and tech-lead only)
When dispatching work, use the mcp__dispatch__dispatch tool. The agent works independently and you can continue with other tasks.
Use mcp__dispatch__team_status to check team workload before dispatching. Pass the EXACT instanceId.
Available teammates:
${delegationLines || "  (no other hired instances — hire more in the shop to enable delegation)"}
${skillSection}${memorySection}${traitsSection}`;
}

// ─── Hired instance info for the UI ────────────────────────────────────────

export interface HiredAgentInfo {
  /** instanceId, e.g. "coder#1". */
  id: string;
  /** Display name (nickname). */
  name: string;
  /** Ukrainian role label. */
  role: string;
  /** Role type, e.g. "coder". */
  roleType: string;
  /** Effective Claude model (post hardware+skills min). */
  model: string;
}

/** Returns the list of hired instances in a UI-friendly shape. */
export function buildHiredAgentInfoList(
  gameState?: GameStateData,
): HiredAgentInfo[] {
  const out: HiredAgentInfo[] = [];
  if (!gameState) return out;
  for (const [id, inst] of Object.entries(gameState.instances)) {
    const role = roleCatalog[inst.roleType];
    if (!role) continue;
    const hwModel = hardwareToModel(inst.hardware);
    const skModel = skillsToModel(inst.skills);
    const model = minModel(hwModel, skModel);
    out.push({
      id,
      name: inst.nickname,
      role: role.ukrainianRoleLabel,
      roleType: inst.roleType,
      model,
    });
  }
  return out;
}

/** Ordered list of all role IDs (for iteration). */
export const allRoleIds: string[] = Object.keys(roleCatalog);
