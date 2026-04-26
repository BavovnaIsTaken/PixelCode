/**
 * Personalization injection — small, testable wrapper that decides whether
 * to extend a base system prompt with the AgentContextPreparer's
 * learned-context fragment.
 *
 * Pulled out of server.ts so the call site there is a single line and the
 * fallback / kill-switch / error-isolation policy is unit-testable without
 * standing up a full WebSocket server.
 */

import type { AgentContextPreparer } from "./agent_context.js";

export interface InjectLearnedContextDeps {
  preparer: AgentContextPreparer;
  /** Master kill-switch (e.g. backed by env var). false → return base unchanged. */
  enabled: boolean;
  /** Optional sink for unexpected errors from preparer.prepare(). */
  onError?: (err: unknown) => void;
}

export interface InjectLearnedContextArgs {
  agentId: string;
  userId: string;
  sessionId: string;
  currentProject: string;
}

/**
 * Append the personalization fragment to a base system prompt. Always safe:
 * - disabled flag → return base unchanged
 * - empty fragment → return base unchanged
 * - preparer throws → return base unchanged, invoke onError
 *
 * Never throws.
 */
export async function injectLearnedContext(
  baseSystemPrompt: string,
  deps: InjectLearnedContextDeps,
  args: InjectLearnedContextArgs
): Promise<string> {
  if (!deps.enabled) return baseSystemPrompt;

  try {
    const ctx = await deps.preparer.prepare(
      args.agentId,
      args.userId,
      args.sessionId,
      args.currentProject
    );
    if (!ctx.learnedContextFragment) return baseSystemPrompt;
    return `${baseSystemPrompt}\n\n${ctx.learnedContextFragment}`;
  } catch (err) {
    deps.onError?.(err);
    return baseSystemPrompt;
  }
}
