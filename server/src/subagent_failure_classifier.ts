/**
 * Pure classifier — turns an opaque sub-agent error string into a stable
 * `{ reason, message }` pair the UI can branch on.
 *
 * Why this exists: the prior code emitted only a generic `error` toast,
 * so the client UI could not tell "timed out (system fault, retry)" apart
 * from "breaker tripped (cost budget exhausted, do NOT retry)" apart
 * from "real error (look at message)". Surfacing the discriminator lets
 * the client clear stale tool-progress state, suggest retry vs. budget
 * adjustment, and avoid surprising the user with a bare red toast.
 *
 * Kept in its own file so the regex is unit-testable without booting any
 * WebSocket / SDK plumbing.
 */

export type SubAgentFailureReason = "timeout" | "breaker" | "error";

export interface SubAgentFailureClassification {
  reason: SubAgentFailureReason;
  /** Verbatim message passed in — surfaced to the user. */
  message: string;
}

/**
 * Patterns calibrated to the messages emitted by `agent_runner.ts` catch
 * block. If those error strings change, this classifier degrades silently
 * to "error" — which is the safe fallback (generic toast, no retry hint).
 */
const TIMEOUT_PATTERN = /hard timeout|timed out after|did not yield/i;
const BREAKER_PATTERN = /circuit breaker|breaker tripped/i;

export function classifySubAgentFailure(message: string): SubAgentFailureClassification {
  if (TIMEOUT_PATTERN.test(message)) {
    return { reason: "timeout", message };
  }
  if (BREAKER_PATTERN.test(message)) {
    return { reason: "breaker", message };
  }
  return { reason: "error", message };
}
