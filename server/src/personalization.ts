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
import type { ProfileCacheService } from "./profile_cache.js";
import type { LessonExtractor, Lesson } from "./lesson_extractor.js";

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

// ─── LLM-extracted lessons → AgentProfile batch apply ──────────────────────

/**
 * Shape of a single lesson as produced by the LLM reflection in reflectOnQuery
 * (see server.ts). Loose `type` because we accept untrusted JSON and validate.
 */
export interface LlmLesson {
  agentId: string;
  type: string;
  tag: string;
  lesson: string;
}

export interface ApplyLlmLessonsDeps {
  cache: ProfileCacheService;
  extractor: LessonExtractor;
  /** Currently a clientId proxy — see TODO(auth). */
  userId: string;
  onError?: (err: unknown) => void;
}

/** Initial confidence for LLM-extracted lessons. Aligns with extractLessons' "error recovery" baseline. */
const INITIAL_LESSON_CONFIDENCE = 0.7;

/**
 * Convert validated LLM lessons into the AgentProfile schema and apply them
 * via the lifecycle-aware extractor. Groups lessons by agent so each agent's
 * profile is loaded/saved exactly once per call.
 *
 * Always safe:
 * - empty input → fast return, no I/O
 * - non-strength/weakness types ignored
 * - missing fields ignored
 * - any thrown error funneled through onError, never re-thrown
 */
export async function applyLlmLessons(
  llmLessons: readonly LlmLesson[],
  deps: ApplyLlmLessonsDeps
): Promise<void> {
  if (llmLessons.length === 0) return;

  const byAgent = new Map<string, Lesson[]>();
  for (const l of llmLessons) {
    if (l.type !== "strength" && l.type !== "weakness") continue;
    if (!l.agentId || !l.tag || !l.lesson) continue;

    let bucket = byAgent.get(l.agentId);
    if (!bucket) {
      bucket = [];
      byAgent.set(l.agentId, bucket);
    }
    bucket.push({
      category: l.type,
      title: l.tag,
      context: l.lesson,
      confidence: INITIAL_LESSON_CONFIDENCE,
    });
  }

  if (byAgent.size === 0) return;

  try {
    const userProfile = await deps.cache.loadUserProfile(deps.userId);
    for (const [agentId, lessons] of byAgent) {
      await deps.extractor.applyLessons(agentId, lessons, userProfile);
    }
  } catch (err) {
    deps.onError?.(err);
  }
}
