/**
 * Agent Context Preparer — gathers everything a query() call needs from the
 * Personalization System into one bundle.
 *
 * Returns a fragment to append to whatever the existing prompt builder
 * (e.g. buildOfficePrompt in agents.ts) produces, plus a cache key and the
 * recent chat messages within a token budget.
 *
 * Phase 3 of docs/IMPLEMENTATION_GUIDE.md, adapted for the actual
 * @anthropic-ai/claude-agent-sdk shape (function-oriented query(), not
 * class-oriented Agent).
 *
 * Wiring into server.ts is intentionally NOT done here — this module is
 * additive. Phase 4 (or 1.4) will splice the fragment into runQuery's
 * systemPrompt and recentMessages into the message stream.
 */

import {
  profileCache,
  ProfileCacheService,
} from "./profile_cache";
import {
  promptCacheManager,
  PromptCacheManager,
} from "./prompt_cache_manager";
import { ChatHistory, type EnrichedChatMessage } from "./chat_history";

export interface AgentContext {
  /** Personalization fragment — append to whatever the outer prompt builder produces. */
  learnedContextFragment: string;
  /** Stable while on-disk profile state is unchanged; flips on every save. */
  cacheKey: string;
  /** Recent chat messages within token budget, oldest-first. */
  recentMessages: EnrichedChatMessage[];
}

const DEFAULT_CONTEXT_TOKEN_BUDGET = 2000;

export class AgentContextPreparer {
  constructor(
    private readonly chatHistory: ChatHistory,
    private readonly cache: ProfileCacheService = profileCache,
    private readonly promptManager: PromptCacheManager = promptCacheManager
  ) {}

  /**
   * @param userId - currently a `clientId` proxy until per-user auth exists.
   *                 ProfileCache keys profiles by this string; switching to
   *                 real user IDs later is a no-op at this interface.
   */
  async prepare(
    agentId: string,
    userId: string,
    sessionId: string,
    currentProject: string,
    contextTokenBudget: number = DEFAULT_CONTEXT_TOKEN_BUDGET
  ): Promise<AgentContext> {
    const userProfile = await this.cache.loadUserProfile(userId);
    const agentProfile = await this.cache.loadAgentProfile(agentId);

    // Snapshot before apply-boost (which would dirty updatedAt on save).
    const cacheKey = `${agentId}-${currentProject}-${agentProfile.updatedAt}`;

    const learnedContextFragment = this.promptManager.buildLearnedContext(
      agentId,
      userProfile,
      agentProfile,
      currentProject
    );

    // buildLearnedContext mutated entries (apply-boost). Persist now per its contract.
    await this.cache.saveAgentProfile(agentProfile);

    const recentMessages = this.chatHistory.getContextMessages(
      sessionId,
      contextTokenBudget
    );

    return { learnedContextFragment, cacheKey, recentMessages };
  }
}
