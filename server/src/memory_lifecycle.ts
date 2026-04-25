/**
 * Memory Lifecycle — time-dependent score, find-by-title helpers,
 * transient batch indexes, and per-tier capacity caps.
 *
 * Design: docs/IMPLEMENTATION_GUIDE.md §6.
 *
 * Invariant: this module produces no on-disk state. Indexes built by
 * buildStrengthIndex / buildWeaknessIndex are transient — discard after use.
 */

import type { AgentProfile } from "./profile_cache";

// ─── Tunables ──────────────────────────────────────────────────────────────

export const memoryLifecycleConfig = {
  baseHalfLifeDays: 30,
  hardPruneThreshold: 0.05,
  confidenceObserveBoost: 0.05,
  confidenceApplyBoost: 0.1, // applied successfully > merely observed
  topicWeightFloor: 0.5,
  defaultTopicAffinity: 0.5,
  compactionEverySessions: 50,
};

// ─── Score (time-dependent — recomputed on demand, never cached) ───────────

interface ScorableEntry {
  confidence?: number;
  avoidanceScore?: number;
  lastAppliedAt?: string;
  lastAvoidedAt?: string;
  lastObservedAt: string;
}

export function computeScore(
  entry: ScorableEntry,
  topicAffinity: number = memoryLifecycleConfig.defaultTopicAffinity
): number {
  const lastUsedISO =
    entry.lastAppliedAt ?? entry.lastAvoidedAt ?? entry.lastObservedAt;
  const deltaDays =
    (Date.now() - new Date(lastUsedISO).getTime()) / 86_400_000;
  const tau = memoryLifecycleConfig.baseHalfLifeDays * (1 + topicAffinity);
  const decayFactor = Math.exp(-deltaDays / tau);
  const topicWeight = memoryLifecycleConfig.topicWeightFloor + topicAffinity;
  const strength = entry.confidence ?? entry.avoidanceScore ?? 0;
  return strength * decayFactor * topicWeight;
}

// ─── Find-by-title helpers (single swap point for future semantic dedup) ───

export function findStrength(
  profile: AgentProfile,
  title: string
): AgentProfile["strengths"][number] | undefined {
  // v1: exact-string match. v2: nearest-neighbor over embeddings, threshold-gated.
  return profile.strengths.find((s) => s.skill === title);
}

export function findWeakness(
  profile: AgentProfile,
  title: string
): AgentProfile["weaknesses"][number] | undefined {
  return profile.weaknesses.find((w) => w.pitfall === title);
}

// ─── Transient batch indexes (build inside hot loops, never persist) ───────

export function buildStrengthIndex(
  profile: AgentProfile
): Map<string, AgentProfile["strengths"][number]> {
  return new Map(profile.strengths.map((s) => [s.skill, s]));
}

export function buildWeaknessIndex(
  profile: AgentProfile
): Map<string, AgentProfile["weaknesses"][number]> {
  return new Map(profile.weaknesses.map((w) => [w.pitfall, w]));
}

// ─── Capacity tiers ────────────────────────────────────────────────────────

export interface CapacityTier {
  topK_strengths: number;
  topK_weaknesses: number;
  MAX_STRENGTHS: number;
  MAX_WEAKNESSES: number;
}

export const CAPACITY_TIERS = {
  opus: {
    topK_strengths: 5,
    topK_weaknesses: 5,
    MAX_STRENGTHS: 150,
    MAX_WEAKNESSES: 150,
  },
  sonnet: {
    topK_strengths: 3,
    topK_weaknesses: 3,
    MAX_STRENGTHS: 75,
    MAX_WEAKNESSES: 75,
  },
  haiku: {
    topK_strengths: 2,
    topK_weaknesses: 2,
    MAX_STRENGTHS: 30,
    MAX_WEAKNESSES: 30,
  },
} as const satisfies Record<string, CapacityTier>;

export function tierForAgent(_agentId: string): CapacityTier {
  // TODO: wire to actual agent→model registry once one exists in the project.
  // Until then, default everything to Sonnet tier.
  return CAPACITY_TIERS.sonnet;
}
