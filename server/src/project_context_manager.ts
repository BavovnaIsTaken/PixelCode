/**
 * Project Context Manager — handles cross-project transitions for AgentProfiles.
 *
 * Design: docs/IMPLEMENTATION_GUIDE.md §5 + AGENT_PERSONALIZATION_SYSTEM.md §2.5.
 *
 * Universal context (strengths, weaknesses, contextPatterns.universal) follows
 * the agent everywhere. Project-specific context is intentionally scoped to its
 * project and dropped on switch.
 */

import { profileCache, ProfileCacheService } from "./profile_cache";

export class ProjectContextManager {
  constructor(private readonly cache: ProfileCacheService = profileCache) {}

  /**
   * Switch an agent's active project context.
   *
   * - **Kept:** strengths, weaknesses, contextPatterns.universal
   * - **Dropped:** contextPatterns.projectSpecific[oldProject]
   * - **Initialized (if absent):** contextPatterns.projectSpecific[newProject] = {}
   * - **Invalidated:** promptCacheV1 (regenerated on next prompt build)
   *
   * **Destructive trade-off:** removing projectSpecific[oldProject] means
   * returning to the old project starts from empty project-specific context.
   * This matches the spec's "agent forgets project-old specifics" intent.
   * If we later want non-destructive switching, keep projectSpecific[old]
   * and only invalidate promptCacheV1.
   */
  async migrateProfileToNewProject(
    agentId: string,
    oldProject: string,
    newProject: string
  ): Promise<void> {
    const profile = await this.cache.loadAgentProfile(agentId);

    delete profile.contextPatterns.projectSpecific[oldProject];

    if (!profile.contextPatterns.projectSpecific[newProject]) {
      profile.contextPatterns.projectSpecific[newProject] = {};
    }

    profile.promptCacheV1 = "";

    await this.cache.saveAgentProfile(profile);
  }

  /**
   * Pure equality check. Lives on the manager so callers can swap the
   * meaning later (e.g. detect by repo root vs. raw CWD path) without
   * touching call sites.
   */
  detectProjectChange(currentProject: string, previousProject: string): boolean {
    return currentProject !== previousProject;
  }
}

export const projectContextManager = new ProjectContextManager();
