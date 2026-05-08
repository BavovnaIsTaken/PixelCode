/**
 * Generate a short "team reaction" scene for a facilitator brief.
 *
 * Why: the facilitator pipeline currently returns a quest plan in one
 * silent JSON blob. The user submits a task and waits — there is no
 * sense that "the team discussed it". This module fires a fast Haiku
 * call that returns 2–3 in-character reactions (one per role) which
 * the WS layer streams into chat as bubbles BEFORE the seeded board
 * fills, so the user feels the team is alive.
 *
 * Design constraints:
 *   - Pure module, caller (LLM client) is injected → unit-testable
 *     without real API calls.
 *   - Failure NEVER blocks the seed. Any error → empty array, the
 *     facilitator pipeline continues unchanged.
 *   - Role IDs come from a whitelist passed by the caller; reactions
 *     referencing unknown roles are silently dropped.
 */

import {
  LLMGenerationError,
  runWithTimeoutAndRetry,
  type RunOptions,
} from "./llm_runner.js";
import type { CallerFn } from "./llm_generators.js";
import { extractJson } from "./llm_generators.js";

export interface TeamReaction {
  /** Agent/role id, e.g. "manager", "tech-lead". */
  role: string;
  /** 1–2 sentence in-character line. */
  text: string;
}

export interface TeamReactionsInput {
  projectDescription: string;
  /** Whitelist of valid role ids — reactions with other roles are dropped. */
  validRoles: readonly string[];
  /** Project working directory passed through to the LLM caller. */
  projectPath: string;
  /** Min reactions to ask the LLM for. The model usually returns 2–3. */
  minReactions?: number;
  /** Hard cap on reactions returned to caller. */
  maxReactions?: number;
}

export interface TeamReactionsDeps {
  caller: CallerFn;
  runOptions?: RunOptions;
}

const SCHEMA = `\
{
  "reactions": [
    { "role": "<one of the valid role ids>", "text": "<1-2 sentence reaction in Ukrainian or English, in character>" }
  ]
}`;

function systemPrompt(validRoles: readonly string[]): string {
  return `\
You are simulating a short team-reaction scene in a software-development game. The user just handed in a project brief; the team is reading it.

Return ONLY valid JSON — no prose, no fences, no explanation.

Produce 2 to 3 reactions. Each reaction is one team member responding to the brief in character. Reactions should feel like a Slack channel right after a brief drops: short, specific, sometimes skeptical, sometimes eager. Not a chorus of "sounds good".

Allowed role ids (use EXACTLY these strings): ${validRoles.join(", ")}.

Pick different roles for each reaction. The manager usually leads; tech-lead usually flags an architectural concern; the third reaction is from any other role that has a stake in the brief (coder if it is feature-heavy, security if auth/data, designer if UI-heavy, tester if quality-heavy, etc.).

Each \`text\` is 1–2 sentences. Match the language the user used in their brief. Keep it grounded — no theatrics, no exclamation spam.

Schema (fill every placeholder):
${SCHEMA}`;
}

/**
 * Parse + validate a raw LLM JSON string. Exported for tests.
 *
 * Returns the reactions array on success, `null` on any malformedness.
 * Drops items whose role is not in `validRoles` or whose text is empty.
 */
export function parseReactions(
  raw: string,
  validRoles: readonly string[],
  maxReactions: number,
): TeamReaction[] | null {
  const json = extractJson(raw);
  if (json === null) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object") return null;
  const arr = (parsed as { reactions?: unknown }).reactions;
  if (!Array.isArray(arr)) return null;
  const allowed = new Set(validRoles);
  const out: TeamReaction[] = [];
  for (const item of arr) {
    if (!item || typeof item !== "object") continue;
    const r = item as { role?: unknown; text?: unknown };
    if (typeof r.role !== "string" || typeof r.text !== "string") continue;
    if (!allowed.has(r.role)) continue;
    const text = r.text.trim();
    if (!text) continue;
    out.push({ role: r.role, text });
    if (out.length >= maxReactions) break;
  }
  return out;
}

/**
 * Fire one Haiku call to generate team reactions for a brief.
 *
 * Never throws. On any failure (parse, timeout, auth, …) returns an
 * empty array so the caller can continue the seed pipeline.
 */
export async function generateTeamReactions(
  input: TeamReactionsInput,
  deps: TeamReactionsDeps,
): Promise<TeamReaction[]> {
  const max = input.maxReactions ?? 3;
  if (input.validRoles.length === 0) return [];
  const userPrompt = `Project brief:\n${input.projectDescription}\n\nReturn ONLY the JSON object.`;
  try {
    const raw = await runWithTimeoutAndRetry(
      () =>
        deps.caller(systemPrompt(input.validRoles), userPrompt, "haiku", input.projectPath),
      deps.runOptions ?? {},
    );
    const reactions = parseReactions(raw, input.validRoles, max);
    return reactions ?? [];
  } catch (err) {
    // Swallow — reactions are decorative. The seed must not fail because
    // the scene LLM had a bad day.
    if (err instanceof LLMGenerationError) return [];
    return [];
  }
}
