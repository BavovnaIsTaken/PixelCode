/**
 * Glue helpers for the conversational core loop.
 *
 * Both the WS handler (`server.ts`) and the integration tests have to
 * (a) materialise team-reaction LLM output into chat-history rows, and
 * (b) record a board-task `done` transition into the tech-lead digest.
 *
 * Inlining either of those in `server.ts` made them untestable end-to-
 * end without spinning up a real WebSocket. Extracting them here means
 * the test calls the exact same code path the handler does — drift
 * between "what server.ts does" and "what the test verifies" becomes
 * impossible.
 *
 * Pure module: no side effects beyond mutating its arguments.
 * `chatHistory.save` and broadcast remain in `server.ts`, where the
 * file-system path and `wss.clients` are.
 */

import type { ChatHistory } from "./chat_history.js";
import type { TaskCardData } from "./protocol.js";
import type {
  TechLeadDigest,
  DigestEntry,
  DigestLesson,
} from "./tech_lead_digest.js";
import type { TeamReaction } from "./facilitator/team_reactions.js";

/**
 * Resolves the most-relevant lesson for an agent at the moment a task
 * completes. The server passes a closure over `traitStore`; tests can
 * pass a fixture or omit entirely. Returning `undefined` is the common
 * case for a fresh agent — the digest entry is then written without a
 * lesson hint, which is fine.
 */
export type LessonResolver = (agentId: string) => DigestLesson | undefined;

/**
 * Distill a one-paragraph project memory hint from a successful
 * facilitator seed. The text is what gets injected into every agent's
 * system prompt as "Project Memory" so the team can answer follow-up
 * questions ("what project are we in?") without the user re-typing
 * the brief.
 *
 * Why this lives in the loop module: the `facilitator_start` WS handler
 * has to (a) save it to `team_memory.txt` for cross-session persistence
 * and (b) set it on the per-client `clientProjectContext` map for the
 * current session. Both call sites need the same string. Centralising
 * it here also lets tests assert the exact memory shape.
 *
 * Format intentionally minimal — agents shouldn't lift the brief
 * verbatim into chat. One sentence + a date is enough for grounding.
 */
export function deriveProjectMemoryFromBrief(
  brief: string,
  now: Date = new Date(),
): string {
  const trimmed = brief.trim().replace(/\s+/g, " ");
  // Cap so a 5-page brief doesn't blow up every agent prompt.
  const summary = trimmed.length > 280 ? `${trimmed.slice(0, 277)}…` : trimmed;
  const dateStr = now.toISOString().slice(0, 10);
  return [
    `Current project brief (seeded ${dateStr}):`,
    summary,
    "If asked which project you're working on, ground answers in this brief — do not say you don't know.",
  ].join("\n");
}

/**
 * Append each reaction as an assistant chat message keyed by role id.
 * Caller is responsible for `chatHistory.save(...)` and broadcasting
 * the snapshot — those depend on environment (file path / ws clients).
 */
export function applyReactionsToChat(
  chatHistory: ChatHistory,
  reactions: readonly TeamReaction[],
  timestamp: string,
): void {
  for (const r of reactions) {
    chatHistory.add({
      role: "assistant",
      text: r.text,
      agentId: r.role,
      timestamp,
    });
  }
}

/**
 * Translate a board task that just transitioned into `done` into a
 * tech-lead digest entry. Derives the role from a `coder#1`-style
 * instance id; an unassigned task records both id and role as
 * `"unassigned"` so it still anchors the completion in time.
 *
 * If a `lessonResolver` is supplied, the agent's top accumulated lesson
 * (by frequency) is snapshotted into the entry — captures "what they
 * have learned by the time of this completion" so the tech-lead's
 * prompt can reference concrete growth, not just task titles. The
 * resolver is optional: tests with no fixture and fresh agents with no
 * lessons both fall through to a plain entry.
 */
export function recordTaskCompletion(
  digest: TechLeadDigest,
  task: TaskCardData,
  lessonResolver?: LessonResolver,
): DigestEntry {
  const agentId = task.assignedAgents[0] ?? "unassigned";
  const role = agentId.includes("#") ? agentId.split("#")[0] : agentId;
  const topLesson = lessonResolver ? lessonResolver(agentId) : undefined;
  return digest.recordCompletion({
    taskId: task.id,
    title: task.title,
    agentId,
    role,
    ...(topLesson ? { topLesson } : {}),
  });
}
