/**
 * Prompt Cache Manager — assembles the system prompt for an agent and applies
 * the spaced-repetition boost to entries that get injected.
 *
 * Design: docs/IMPLEMENTATION_GUIDE.md §3.2 (system prompt structure)
 *         + §6.7 (sort by score, apply-boost on selected entries).
 *
 * Side effect: buildSystemPrompt mutates and persists agentProfile (apply-boost).
 * Each rebuild bumps confidence/avoidanceScore and touches lastAppliedAt /
 * lastAvoidedAt. The cacheKey reflects the loaded-state timestamp, so it is
 * stable for as long as the profile on disk is.
 */

import {
  profileCache,
  ProfileCacheService,
  type AgentProfile,
  type UserProfile,
} from "./profile_cache";
import {
  computeScore,
  tierForAgent,
  memoryLifecycleConfig,
  type CapacityTier,
} from "./memory_lifecycle";

export interface BuiltPrompt {
  systemPrompt: string;
  cacheKey: string;
}

export class PromptCacheManager {
  constructor(
    private readonly cache: ProfileCacheService = profileCache,
    private readonly resolveTier: (agentId: string) => CapacityTier = tierForAgent
  ) {}

  async buildSystemPrompt(
    agentId: string,
    userId: string,
    currentProject: string
  ): Promise<BuiltPrompt> {
    const userProfile = await this.cache.loadUserProfile(userId);
    const agentProfile = await this.cache.loadAgentProfile(agentId);

    // CacheKey snapshots the on-disk state. Apply-boost below will dirty the
    // profile and bump updatedAt on next save, invalidating the cache for the
    // next build — desired per spec.
    const cacheKey = `${agentId}-${currentProject}-${agentProfile.updatedAt}`;

    const basePrompt = this.buildBasePrompt(agentId, userProfile);
    const cachedContext = this.buildLearnedContext(
      agentId,
      userProfile,
      agentProfile,
      currentProject
    );

    await this.cache.saveAgentProfile(agentProfile);

    return {
      systemPrompt: `${basePrompt}\n\n${cachedContext}`,
      cacheKey,
    };
  }

  private buildBasePrompt(agentId: string, userProfile: UserProfile): string {
    const cs = userProfile.communicationStyle;
    const p = userProfile.preferences;
    return [
      `You are agent: ${agentId}`,
      `Communication style: ${cs.language}/${cs.verbosity}`,
      `Technical level: ${cs.technicalLevel}`,
      `Prefer delegation: ${p.preferDelegation}`,
      `Parallelize when possible: ${p.parallelizeWork}`,
    ].join("\n");
  }

  /**
   * Build the learned-context fragment AND apply the spaced-repetition boost to
   * the entries we're injecting. Mutates entries in agentProfile.{strengths,weaknesses}
   * via shared references.
   *
   * **Mutation contract:** caller is responsible for persisting agentProfile
   * after this returns (the boost is in-memory only). buildSystemPrompt does
   * this; standalone callers (e.g. AgentContextPreparer) must save explicitly.
   *
   * Used standalone when the consumer already has an outer prompt builder
   * (e.g. buildOfficePrompt) and just wants the personalization fragment to
   * append.
   */
  buildLearnedContext(
    agentId: string,
    userProfile: UserProfile,
    agentProfile: AgentProfile,
    currentProject: string
  ): string {
    const tier = this.resolveTier(agentId);
    const affinity = (key: string) =>
      userProfile.globalPatterns.topicAffinities[key] ??
      memoryLifecycleConfig.defaultTopicAffinity;
    const now = new Date().toISOString();

    // Spread copies array slots only — element references still point at the
    // originals, so mutations below propagate into agentProfile.
    const topStrengths = [...agentProfile.strengths]
      .sort(
        (a, b) =>
          computeScore(b, affinity(b.skill)) -
          computeScore(a, affinity(a.skill))
      )
      .slice(0, tier.topK_strengths);

    const topWeaknesses = [...agentProfile.weaknesses]
      .sort(
        (a, b) =>
          computeScore(b, affinity(b.pitfall)) -
          computeScore(a, affinity(a.pitfall))
      )
      .slice(0, tier.topK_weaknesses);

    // Spaced-repetition apply-boost: anything we expose to the model "counts"
    // as having been applied. confidenceApplyBoost > confidenceObserveBoost.
    for (const s of topStrengths) {
      s.appliedCount++;
      s.confidence = Math.min(
        1,
        s.confidence + memoryLifecycleConfig.confidenceApplyBoost
      );
      s.lastAppliedAt = now;
    }
    for (const w of topWeaknesses) {
      w.avoidedCount++;
      w.avoidanceScore = Math.min(
        1,
        w.avoidanceScore + memoryLifecycleConfig.confidenceApplyBoost
      );
      w.lastAvoidedAt = now;
    }

    const strengthsBlock =
      topStrengths.length === 0
        ? "None yet"
        : topStrengths
            .map(
              (s) =>
                `- ${s.skill} (confidence: ${(s.confidence * 100).toFixed(0)}%)`
            )
            .join("\n");

    const weaknessesBlock =
      topWeaknesses.length === 0
        ? "None yet"
        : topWeaknesses
            .map(
              (w) =>
                `- Avoid: ${w.pitfall} (score: ${(w.avoidanceScore * 100).toFixed(0)}%)`
            )
            .join("\n");

    const universalBlock = JSON.stringify(
      agentProfile.contextPatterns.universal,
      null,
      2
    );

    const projectSpecific =
      agentProfile.contextPatterns.projectSpecific[currentProject];
    const projectBlock = projectSpecific
      ? `\n\n## Project-Specific Patterns (${currentProject})\n${JSON.stringify(projectSpecific, null, 2)}`
      : "";

    return [
      `## Your Learned Strengths`,
      strengthsBlock,
      ``,
      `## Your Known Weaknesses`,
      weaknessesBlock,
      ``,
      `## Universal Patterns`,
      universalBlock,
    ].join("\n") + projectBlock;
  }
}

export const promptCacheManager = new PromptCacheManager();
