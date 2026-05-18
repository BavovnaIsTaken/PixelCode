/**
 * Prompts and return-strings for the in-process `dispatch` MCP tool.
 *
 * Extracted from server.ts so they can be unit-tested independently of the
 * WebSocket plumbing. The strings here are load-bearing prompt surface:
 * they are the *anchor* a manager-LLM sees in fresh context immediately
 * after calling `mcp__dispatch__dispatch`, and they enforce the C.2.5
 * Dispatch Lifecycle invariants:
 *
 *   I1. Manager MUST NOT report a dispatched task as "Готово" before the
 *       paired [System notification] arrives with the dispatch_id.
 *   I2. Manager MUST resolve named entities (character/sprite/file) to
 *       actual project artifacts BEFORE dispatching — never dispatch to
 *       "update" an entity whose existence was not verified.
 *
 * These invariants are reinforced (not enforced) by prompt-discipline;
 * the structural backups live in server.ts (regex-strip) and
 * agent_runner.ts (Promise.race hard-escape).
 */

export const DISPATCH_TOOL_DESCRIPTION =
  "Dispatch a task to a specific team agent INSTANCE. " +
  "BEFORE calling: if the user named a specific entity (character, sprite, file, feature) " +
  "you have not seen in this conversation, resolve it via Glob/Grep first — " +
  "never dispatch to 'update' an entity whose existence you have not verified. " +
  "If the named entity isn't found in the project, ASK the user to clarify " +
  "(e.g. 'I didn't find 'X' — did you mean Y?') instead of dispatching. " +
  "After dispatch: the agent works independently — you do NOT wait for the result. " +
  "Continue with other work. The [System notification] with the dispatch_id will " +
  "confirm completion later; only then can you report the task as done.";

/**
 * Builds the tool_result string the manager-LLM sees immediately after
 * calling dispatch. This is *anchor-prompt* territory — fresh context that
 * the model pays high attention to. Phrasing is deliberate:
 *
 *   - Explicit "DO NOT report Готово" with the literal Ukrainian word the
 *     model would otherwise emit.
 *   - Concrete valid status options to redirect the model's next text block.
 *   - References the exact dispatch_id so the model knows which paired
 *     notification to wait for.
 */
/**
 * Inverse of buildDispatchReturnString — extracts the dispatch_id from
 * the tool_result text the manager sees, so the C.2.5 incident detector
 * can correlate a "Готово:" claim back to a specific in-flight dispatch.
 *
 * Co-located with buildDispatchReturnString so both sides of the contract
 * change together: if the return-string ever drops the literal "ID: ..."
 * sentinel, this regex breaks at test time, not at incident-detection time.
 *
 * Returns null when the text is not a dispatch tool_result.
 */
export const DISPATCH_ID_PATTERN = /Task dispatched to .+? \(ID:\s*(dispatch_\d+_\d+)\)/;

export function extractDispatchIdFromToolResult(text: string): string | null {
  const m = DISPATCH_ID_PATTERN.exec(text);
  return m && m[1] ? m[1] : null;
}

export function buildDispatchReturnString(
  agentId: string,
  dispatchId: string,
): string {
  return [
    `Task dispatched to ${agentId} (ID: ${dispatchId}). They are working independently in the background.`,
    ``,
    `⚠️ DO NOT report this as "Готово" / "Done" / "Completed" yet. You have only DISPATCHED the task; the agent has not finished.`,
    `Until a [System notification] arrives with dispatch_id=${dispatchId} confirming completion, your only valid status lines are:`,
    `  - "Працюємо над {task}." (immediately after dispatch)`,
    `  - "${agentId} ще працює над {task}." (interim, if user asks for status)`,
    ``,
    `Saying "Готово: {X}." without a paired [System notification] for dispatch_id=${dispatchId} is a fabrication — wait for the actual result, then summarize what the agent produced.`,
    ``,
    `Continue with other work or report dispatch progress to the user (NOT completion).`,
  ].join("\n");
}
