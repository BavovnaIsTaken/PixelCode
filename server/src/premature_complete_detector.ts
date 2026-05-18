/**
 * Pure detector for the "manager claims Готово without observed result"
 * failure mode (C.2.5 invariant I1).
 *
 * Semantics: a *premature completion claim* is a manager turn where
 *   (a) the manager invoked `mcp__dispatch__dispatch` for at least one
 *       sub-agent, AND
 *   (b) the manager's own assistant text contains a completion-claim
 *       pattern ("Готово: X", "Done: X", "Completed: X", "✅ Готово", ...),
 *       AND
 *   (c) at least one dispatched sub-agent has NOT yet returned a paired
 *       `subagent_result` notification by the time the turn ends.
 *
 * Returning `fabricated: true` does NOT prove the manager lied — it could
 * be a legitimate completion claim about an unrelated task that finished
 * earlier. The signal is a *rate indicator* for the C.2.5 daily-control
 * surface; consumers gate "this is unusual" only when the cross-bucket
 * rate exceeds a threshold (TBD after baseline measurement).
 *
 * Kept in its own file (and pure) so the regex / cross-reference logic
 * is unit-testable without the WebSocket / SDK plumbing.
 */

/**
 * Completion-claim pattern. Calibrated against the 2026-05-18 incident
 * ("Готово: спрайти Мурчика оновлені..."). Conservative on purpose —
 * matches the "Готово:" colon form, not the loose "готово" (adjective).
 *
 * False-positive bias is acceptable for the daily-control surface
 * (it surfaces an audit candidate, not a block). False negatives are
 * worse — they hide the failure mode.
 */
export const COMPLETION_CLAIM_PATTERN =
  /(?:^|[^а-яёіїєА-ЯЁІЇЄa-zA-Z])(Готово|Done|Completed)\s*:[^\n]/u;

export interface PrematureCompleteInput {
  /** dispatch_ids that the manager invoked via the dispatch tool during this turn. */
  dispatchedIds: string[];
  /**
   * Manager's own assistant text emitted during the same turn (concatenated
   * across multiple assistant blocks if the turn produced more than one).
   */
  managerOutputText: string;
  /**
   * dispatch_ids whose paired `subagent_result` [System notification] has
   * already been observed (i.e. `handleSubAgentComplete` fired and the
   * notification was enqueued) at the moment this detection runs.
   *
   * Must be a subset of `dispatchedIds` to be meaningful.
   */
  resolvedDispatchIds: string[];
}

export interface PrematureCompleteResult {
  /** True iff the claim is unsupported by an observed result. */
  fabricated: boolean;
  /** Subset of `dispatchedIds` still missing a paired `subagent_result`. */
  unmatchedDispatchIds: string[];
  /** Substring of `managerOutputText` that triggered the claim, or null. */
  matchedClaim: string | null;
}

/**
 * Pure transform: replace "Готово: X." patterns with "Працюємо над X."
 * Used by the C.2.5 Stage 4 alert/strip layer.
 *
 * Stage 4 (current): the server runs this transform PURELY for logging
 * so we can measure how often the regex would have rewritten text. The
 * manager's actual output is NOT modified. This is the "alert mode"
 * promised in the C.2.5 plan — observe before block.
 *
 * Stage 4-block (future, gated on baseline data): if the measurement
 * shows the manager keeps fabricating "Готово:" despite the dispatch
 * tool's anchor-prompt, flip a flag to apply this transform before
 * sending the assistant text to the client.
 *
 * The transform is conservative: only the colon-form ("Готово: X.") is
 * rewritten. Bare "Готово." or progress-report phrasings are left alone.
 */
export function stripPrematureCompleteClaim(text: string): string {
  // Match the same shape as COMPLETION_CLAIM_PATTERN's keyword, but with
  // a colon-suffix and capture the following clause up to a sentence
  // terminator. Replace the whole "Готово: <clause>." with
  // "Працюємо над <clause>." — i.e. preserve the user-visible *task name*
  // (clause), just demote the completion claim to a status report.
  //
  // Why preserve the clause: the manager often includes the task name
  // after the colon ("Готово: спрайти Мурчика..."), which is exactly
  // what the user wants to see *as progress*. A pure delete leaves the
  // user with cryptic gaps in the message.
  return text.replace(
    /(^|[^а-яёіїєА-ЯЁІЇЄa-zA-Z])(Готово)\s*:\s*([^.\n]+?)([.!?\n]|$)/gu,
    (_match, lead, _word, clause, term) => {
      const cleanClause = String(clause).trim();
      return `${lead}Працюємо над ${cleanClause}${term ?? "."}`;
    },
  );
}

export function detectPrematureComplete(
  input: PrematureCompleteInput,
): PrematureCompleteResult {
  if (input.dispatchedIds.length === 0) {
    return { fabricated: false, unmatchedDispatchIds: [], matchedClaim: null };
  }

  const resolved = new Set(input.resolvedDispatchIds);
  const unmatched = input.dispatchedIds.filter((id) => !resolved.has(id));
  if (unmatched.length === 0) {
    return { fabricated: false, unmatchedDispatchIds: [], matchedClaim: null };
  }

  const match = input.managerOutputText.match(COMPLETION_CLAIM_PATTERN);
  if (!match) {
    return { fabricated: false, unmatchedDispatchIds: unmatched, matchedClaim: null };
  }

  return {
    fabricated: true,
    unmatchedDispatchIds: unmatched,
    matchedClaim: match[0],
  };
}
