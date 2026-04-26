/**
 * Backend routing based on hardware tier and task difficulty.
 *
 * - hwTier 0-1: local-fast (minimal models)
 * - hwTier 2-3: local-quality (larger local models)
 * - hwTier 4+: cloud (Claude)
 * - difficulty 3: always escalate to cloud (complex tasks)
 *
 * Tracks cost per agent and model for billing.
 */

import type { AgentBackend, BackendResult } from "./agent_backend.js";

export type BackendTier = "local-fast" | "local-quality" | "cloud";

export class TierRouter {
  private costTracking = new Map<string, number>();

  constructor(
    private localFastBackend: AgentBackend,
    private localQualityBackend: AgentBackend,
    private cloudBackend: AgentBackend
  ) {}

  /**
   * Route a request to the appropriate backend based on hardware tier.
   *
   * - hwTier 0-1 → local-fast
   * - hwTier 2-3 → local-quality
   * - hwTier 4+ → cloud
   */
  routeForHardware(hwTier: number): BackendTier {
    if (hwTier <= 1) return "local-fast";
    if (hwTier <= 3) return "local-quality";
    return "cloud";
  }

  /**
   * Route a request to the appropriate backend based on task difficulty and hardware.
   *
   * Difficulty 3 (complex) always escalates to cloud, regardless of hardware.
   */
  async routeForDifficulty(
    difficulty: 1 | 2 | 3,
    hwTier: number
  ): Promise<AgentBackend> {
    if (difficulty === 3) return this.cloudBackend;

    const tier = this.routeForHardware(hwTier);
    switch (tier) {
      case "local-fast":
        return this.localFastBackend;
      case "local-quality":
        return this.localQualityBackend;
      case "cloud":
        return this.cloudBackend;
    }
  }

  /**
   * Execute a task with automatic cost tracking.
   */
  async executeWithCostTracking(
    agentId: string,
    prompt: string,
    systemPrompt: string,
    model: string,
    difficulty: 1 | 2 | 3,
    hwTier: number
  ): Promise<BackendResult> {
    const backend = await this.routeForDifficulty(difficulty, hwTier);
    const result = await backend.execute(prompt, systemPrompt, model);

    // Track cumulative cost per agent/model pair
    const key = `${agentId}-${model}`;
    const currentCost = this.costTracking.get(key) ?? 0;
    this.costTracking.set(key, currentCost + result.costUsd);

    return result;
  }

  /**
   * Get cumulative cost for an agent across all models.
   */
  getCumulativeCost(agentId: string): number {
    let total = 0;
    for (const [key, cost] of this.costTracking.entries()) {
      if (key.startsWith(`${agentId}-`)) {
        total += cost;
      }
    }
    return total;
  }

  /**
   * Fallback: execute on cloud backend if local is unavailable.
   */
  async fallbackToCloud(
    agentId: string,
    prompt: string,
    systemPrompt: string,
    model: string
  ): Promise<BackendResult> {
    const result = await this.cloudBackend.execute(prompt, systemPrompt, model);

    // Track cost
    const key = `${agentId}-${model}`;
    const currentCost = this.costTracking.get(key) ?? 0;
    this.costTracking.set(key, currentCost + result.costUsd);

    return result;
  }

  /**
   * Clear cost tracking (useful for testing).
   */
  resetCostTracking(): void {
    this.costTracking.clear();
  }
}
