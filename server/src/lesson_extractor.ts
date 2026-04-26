/**
 * Lesson Extractor — turns execution-hook payloads into typed Lessons,
 * then applies them to an AgentProfile (with consolidation + eviction).
 *
 * Design: docs/AGENT_PERSONALIZATION_IMPLEMENTATION.md §3.1 (extraction) + §6.7 (apply with eviction).
 */

import {
  profileCache,
  ProfileCacheService,
  type UserProfile,
} from "./profile_cache";
import {
  computeScore,
  tierForAgent,
  memoryLifecycleConfig,
  findSimilarStrength,
  findSimilarWeakness,
  type CapacityTier,
} from "./memory_lifecycle";

export interface Lesson {
  category: "strength" | "weakness";
  title: string;
  context: string;
  confidence: number; // 0–1, initial value if entry is new
}

/**
 * Loose payload shape produced by execution hooks. Fields are all optional
 * because different patterns inspect different subsets.
 */
export interface ExtractionPayload {
  action?: string; // e.g. "dispatch"
  result?: string; // e.g. "success"
  taskCount?: number;
  avoided?: string; // e.g. "tool-check"
  error?: string;
  recovery?: string;
  [key: string]: unknown;
}

export class LessonExtractor {
  constructor(
    private readonly cache: ProfileCacheService = profileCache,
    private readonly resolveTier: (agentId: string) => CapacityTier = tierForAgent
  ) {}

  /**
   * Recognize known patterns in a hook payload. Each pattern is independent —
   * a single payload may produce multiple lessons or none at all.
   */
  extractLessons(payload: ExtractionPayload): Lesson[] {
    const lessons: Lesson[] = [];

    // Pattern 1: Successful async dispatch
    if (payload.action === "dispatch" && payload.result === "success") {
      const count = payload.taskCount ?? 0;
      lessons.push({
        category: "strength",
        title: "Async dispatch effectiveness",
        context:
          count > 0
            ? `Dispatched ${count} task${count === 1 ? "" : "s"} in parallel`
            : "Successful dispatch",
        confidence: 0.85,
      });
    }

    // Pattern 2: Avoided a known pitfall (e.g. checked tool availability)
    if (payload.avoided === "tool-check") {
      lessons.push({
        category: "strength",
        title: "Tool availability verification",
        context: "Checked tool availability upfront — no fallback needed",
        confidence: 0.9,
      });
    }

    // Pattern 3: Error recovery (records the error as a weakness)
    if (payload.error && payload.recovery) {
      lessons.push({
        category: "weakness",
        title: payload.error,
        context: `Recovered via: ${payload.recovery}`,
        confidence: 0.7,
      });
    }

    return lessons;
  }

  /**
   * Persist lessons into the AgentProfile.
   * Existing entries are reinforced (observedCount++, confidence boost, lastObservedAt touched).
   * New entries are appended; if total exceeds MAX_*, the lowest-scored entry is evicted.
   */
  async applyLessons(
    agentId: string,
    lessons: Lesson[],
    userProfile: UserProfile
  ): Promise<void> {
    if (lessons.length === 0) return;

    const profile = await this.cache.loadAgentProfile(agentId);
    const tier = this.resolveTier(agentId);
    const now = new Date().toISOString();
    const affinity = (key: string) =>
      userProfile.globalPatterns.topicAffinities[key] ??
      memoryLifecycleConfig.defaultTopicAffinity;

    for (const lesson of lessons) {
      if (lesson.category === "strength") {
        // findSimilarStrength: exact-match-first, then token-Jaccard fallback.
        // Folds Haiku's synonym variations ("unclear-delegation-scope" vs
        // "vague-delegation-scope") into one entry instead of accumulating dupes.
        const existing = findSimilarStrength(profile, lesson.title);
        if (existing) {
          existing.observedCount++;
          existing.confidence = Math.min(
            1,
            existing.confidence +
              memoryLifecycleConfig.confidenceObserveBoost
          );
          existing.lastObservedAt = now;
        } else {
          profile.strengths.push({
            skill: lesson.title,
            context: lesson.context,
            observedCount: 1,
            appliedCount: 0,
            confidence: lesson.confidence,
            lastObservedAt: now,
            lastAppliedAt: now,
            createdAt: now,
          });

          if (profile.strengths.length > tier.MAX_STRENGTHS) {
            profile.strengths.sort(
              (a, b) =>
                computeScore(b, affinity(b.skill)) -
                computeScore(a, affinity(a.skill))
            );
            profile.strengths.length = tier.MAX_STRENGTHS;
          }
        }
      } else {
        const existing = findSimilarWeakness(profile, lesson.title);
        if (existing) {
          existing.observedCount++;
          existing.avoidanceScore = Math.min(
            1,
            existing.avoidanceScore +
              memoryLifecycleConfig.confidenceObserveBoost
          );
          existing.lastObservedAt = now;
        } else {
          profile.weaknesses.push({
            pitfall: lesson.title,
            impact: lesson.context,
            observedCount: 1,
            avoidedCount: 0,
            avoidanceScore: lesson.confidence,
            lastObservedAt: now,
            lastAvoidedAt: now,
            createdAt: now,
          });

          if (profile.weaknesses.length > tier.MAX_WEAKNESSES) {
            profile.weaknesses.sort(
              (a, b) =>
                computeScore(b, affinity(b.pitfall)) -
                computeScore(a, affinity(a.pitfall))
            );
            profile.weaknesses.length = tier.MAX_WEAKNESSES;
          }
        }
      }
    }

    await this.cache.saveAgentProfile(profile);
  }
}

export const lessonExtractor = new LessonExtractor();
