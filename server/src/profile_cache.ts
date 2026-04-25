/**
 * Profile Cache Service — persistent learning system for user and agent profiles.
 *
 * Manages UserProfile (communication style, preferences) and AgentProfile (learned strengths/weaknesses).
 * Profiles persist to disk (~/.pixelcode/profiles/) and enable prompt caching for token efficiency.
 *
 * Gracefully handles missing files by returning default profiles.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import * as zlib from "zlib";
import {
  computeScore,
  memoryLifecycleConfig,
} from "./memory_lifecycle";

// ─── Types ─────────────────────────────────────────────────────────────────

export interface UserProfile {
  userId: string;
  version: string;
  communicationStyle: {
    language: "uk" | "en";
    verbosity: "concise" | "detailed";
    technicalLevel: "beginner" | "intermediate" | "advanced";
  };
  preferences: {
    parallelizeWork: boolean;
    preferDelegation: boolean;
    errorTolerance: "low" | "medium" | "high";
  };
  globalPatterns: {
    successfulApproaches: string[];
    avoidedMistakes: string[];
    topicAffinities: Record<string, number>; // 0–1 scale
  };
  updatedAt: string; // ISO 8601
}

export interface AgentProfile {
  agentId: string;
  version: string;
  strengths: Array<{
    skill: string;
    context: string;
    observedCount: number;
    appliedCount: number;
    confidence: number; // 0–1
    lastObservedAt: string; // ISO 8601
    lastAppliedAt: string; // ISO 8601
    createdAt: string; // ISO 8601
  }>;
  weaknesses: Array<{
    pitfall: string;
    impact: string;
    observedCount: number;
    avoidedCount: number;
    avoidanceScore: number; // 0–1
    lastObservedAt: string; // ISO 8601
    lastAvoidedAt: string; // ISO 8601
    createdAt: string; // ISO 8601
  }>;
  contextPatterns: {
    universal: Record<string, unknown>;
    projectSpecific: Record<string, Record<string, unknown>>;
  };
  promptCacheV1: string; // Compressed context (~4KB gzip+base64)
  updatedAt: string; // ISO 8601
}

// ─── Service ────────────────────────────────────────────────────────────────

export class ProfileCacheService {
  private readonly profileDir: string;

  constructor(profileDirOverride?: string) {
    this.profileDir =
      profileDirOverride ?? join(homedir(), ".pixelcode", "profiles");
    this.ensureProfileDirExists();
  }

  /**
   * Ensure ~/.pixelcode/profiles/ exists.
   */
  private ensureProfileDirExists(): void {
    try {
      mkdirSync(this.profileDir, { recursive: true });
    } catch {
      // Non-critical — will attempt on each operation
    }
  }

  /**
   * Load user profile by userId.
   * Returns default profile if file doesn't exist.
   */
  async loadUserProfile(userId: string): Promise<UserProfile> {
    const filePath = join(this.profileDir, `user-${userId}.json`);
    if (!existsSync(filePath)) {
      return this.createDefaultUserProfile(userId);
    }
    try {
      const data = readFileSync(filePath, "utf-8");
      return JSON.parse(data) as UserProfile;
    } catch {
      return this.createDefaultUserProfile(userId);
    }
  }

  /**
   * Save user profile to disk.
   */
  async saveUserProfile(profile: UserProfile): Promise<void> {
    const filePath = join(this.profileDir, `user-${profile.userId}.json`);
    try {
      this.ensureProfileDirExists();
      profile.updatedAt = new Date().toISOString();
      writeFileSync(filePath, JSON.stringify(profile, null, 2), "utf-8");
    } catch {
      // Non-critical — profile remains in memory
    }
  }

  /**
   * Load agent profile by agentId.
   * Returns default profile if file doesn't exist.
   */
  async loadAgentProfile(agentId: string): Promise<AgentProfile> {
    const filePath = join(this.profileDir, `agent-${agentId}.json`);
    if (!existsSync(filePath)) {
      return this.createDefaultAgentProfile(agentId);
    }
    try {
      const data = readFileSync(filePath, "utf-8");
      return JSON.parse(data) as AgentProfile;
    } catch {
      return this.createDefaultAgentProfile(agentId);
    }
  }

  /**
   * Save agent profile to disk.
   */
  async saveAgentProfile(profile: AgentProfile): Promise<void> {
    const filePath = join(this.profileDir, `agent-${profile.agentId}.json`);
    try {
      this.ensureProfileDirExists();
      profile.updatedAt = new Date().toISOString();
      writeFileSync(filePath, JSON.stringify(profile, null, 2), "utf-8");
    } catch {
      // Non-critical — profile remains in memory
    }
  }

  /**
   * Generate compressed prompt cache (gzip + base64) from profiles.
   * Includes top strengths/weaknesses and project-specific patterns.
   */
  async generatePromptCache(
    userProfile: UserProfile,
    agentProfile: AgentProfile,
    currentProject: string
  ): Promise<string> {
    const affinity = (key: string) =>
      userProfile.globalPatterns.topicAffinities[key] ??
      memoryLifecycleConfig.defaultTopicAffinity;

    // Spread before sort — never mutate the caller's arrays.
    const topStrengths = [...agentProfile.strengths]
      .sort(
        (a, b) =>
          computeScore(b, affinity(b.skill)) -
          computeScore(a, affinity(a.skill))
      )
      .slice(0, 3);

    const topWeaknesses = [...agentProfile.weaknesses]
      .sort(
        (a, b) =>
          computeScore(b, affinity(b.pitfall)) -
          computeScore(a, affinity(a.pitfall))
      )
      .slice(0, 3);

    const cacheData = {
      userStyle: userProfile.communicationStyle,
      userPrefs: userProfile.preferences,
      topStrengths,
      topWeaknesses,
      universalPatterns: agentProfile.contextPatterns.universal,
      projectPatterns:
        agentProfile.contextPatterns.projectSpecific[currentProject] || {},
      generated: new Date().toISOString(),
    };

    const json = JSON.stringify(cacheData);
    const compressed = zlib.gzipSync(json).toString("base64");
    return compressed;
  }

  /**
   * Periodic compaction — drops entries whose score has decayed below
   * memoryLifecycleConfig.hardPruneThreshold. Run every ~N sessions or when
   * the JSON file grows past a soft size threshold.
   */
  async compactProfile(
    agentId: string,
    userProfile: UserProfile
  ): Promise<void> {
    const profile = await this.loadAgentProfile(agentId);
    const affinity = (key: string) =>
      userProfile.globalPatterns.topicAffinities[key] ??
      memoryLifecycleConfig.defaultTopicAffinity;

    profile.strengths = profile.strengths.filter(
      (s) =>
        computeScore(s, affinity(s.skill)) >=
        memoryLifecycleConfig.hardPruneThreshold
    );
    profile.weaknesses = profile.weaknesses.filter(
      (w) =>
        computeScore(w, affinity(w.pitfall)) >=
        memoryLifecycleConfig.hardPruneThreshold
    );

    await this.saveAgentProfile(profile);
  }

  /**
   * Get profile directory path (for testing purposes).
   */
  getProfileDir(): string {
    return this.profileDir;
  }

  // ─── Defaults ──────────────────────────────────────────────────────────────

  private createDefaultUserProfile(userId: string): UserProfile {
    return {
      userId,
      version: "1.0",
      communicationStyle: {
        language: "uk",
        verbosity: "concise",
        technicalLevel: "advanced",
      },
      preferences: {
        parallelizeWork: true,
        preferDelegation: true,
        errorTolerance: "medium",
      },
      globalPatterns: {
        successfulApproaches: [],
        avoidedMistakes: [],
        topicAffinities: {},
      },
      updatedAt: new Date().toISOString(),
    };
  }

  private createDefaultAgentProfile(agentId: string): AgentProfile {
    return {
      agentId,
      version: "1.0",
      strengths: [],
      weaknesses: [],
      contextPatterns: {
        universal: {},
        projectSpecific: {},
      },
      promptCacheV1: "",
      updatedAt: new Date().toISOString(),
    };
  }
}

// ─── Singleton ──────────────────────────────────────────────────────────────

export const profileCache = new ProfileCacheService();
