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
import type { TechLeadDigest, DigestEntry } from "./tech_lead_digest.js";
import type { TeamReaction } from "./facilitator/team_reactions.js";

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
 */
export function recordTaskCompletion(
  digest: TechLeadDigest,
  task: TaskCardData,
): DigestEntry {
  const agentId = task.assignedAgents[0] ?? "unassigned";
  const role = agentId.includes("#") ? agentId.split("#")[0] : agentId;
  return digest.recordCompletion({
    taskId: task.id,
    title: task.title,
    agentId,
    role,
  });
}
