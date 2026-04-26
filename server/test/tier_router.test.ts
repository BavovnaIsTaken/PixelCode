import { test } from "node:test";
import assert from "node:assert/strict";
import type { AgentBackend, BackendResult } from "../src/agent_backend.js";

// ─── Mock backends ─────────────────────────────────────────────────────────

class MockLocalFastBackend implements AgentBackend {
  private cost = 0;

  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: `local-fast: ${prompt}`,
      durationMs: 5,
      costUsd: 0,
    };
  }

  async getCost(): Promise<number> {
    return this.cost;
  }
}

class MockLocalQualityBackend implements AgentBackend {
  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: `local-quality: ${prompt}`,
      durationMs: 15,
      costUsd: 0,
    };
  }
}

class MockCloudBackend implements AgentBackend {
  private cost = 0;

  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: `cloud: ${prompt}`,
      durationMs: 3,
      costUsd: 0.01,
    };
  }

  async addCost(usd: number): Promise<void> {
    this.cost += usd;
  }

  async getCost(): Promise<number> {
    return this.cost;
  }
}

// ─── TierRouter implementation for testing ──────────────────────────────────

class TierRouter {
  private localFastBackend: AgentBackend;
  private localQualityBackend: AgentBackend;
  private cloudBackend: AgentBackend;
  private costTracking = new Map<string, number>();

  constructor(
    localFast: AgentBackend,
    localQuality: AgentBackend,
    cloud: AgentBackend
  ) {
    this.localFastBackend = localFast;
    this.localQualityBackend = localQuality;
    this.cloudBackend = cloud;
  }

  routeForHardware(hwTier: number): "local-fast" | "local-quality" | "cloud" {
    if (hwTier <= 1) return "local-fast";
    if (hwTier <= 3) return "local-quality";
    return "cloud";
  }

  async routeForDifficulty(
    difficulty: 1 | 2 | 3,
    hwTier: number
  ): Promise<AgentBackend> {
    // difficulty 3 always escalates to cloud
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

    // Track cost per agent
    const key = `${agentId}-${model}`;
    const currentCost = this.costTracking.get(key) ?? 0;
    this.costTracking.set(key, currentCost + result.costUsd);

    return result;
  }

  getCumulativeCost(agentId: string): number {
    let total = 0;
    for (const [key, cost] of this.costTracking.entries()) {
      if (key.startsWith(agentId)) {
        total += cost;
      }
    }
    return total;
  }

  async fallbackToCloud(
    agentId: string,
    prompt: string,
    systemPrompt: string,
    model: string
  ): Promise<BackendResult> {
    return this.cloudBackend.execute(prompt, systemPrompt, model);
  }
}

// ─── Routing tests ─────────────────────────────────────────────────────────

test("TierRouter routes hwTier 0-1 to local-fast", () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  assert.equal(router.routeForHardware(0), "local-fast");
  assert.equal(router.routeForHardware(1), "local-fast");
});

test("TierRouter routes hwTier 2-3 to local-quality", () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  assert.equal(router.routeForHardware(2), "local-quality");
  assert.equal(router.routeForHardware(3), "local-quality");
});

test("TierRouter routes hwTier 4+ to cloud", () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  assert.equal(router.routeForHardware(4), "cloud");
  assert.equal(router.routeForHardware(5), "cloud");
});

test("TierRouter routes difficulty 3 always to cloud", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const backend0 = await router.routeForDifficulty(3, 0);
  const backend4 = await router.routeForDifficulty(3, 4);

  // Both should return cloud backend (verify by executing and checking output)
  const result0 = await backend0.execute("test", "sys", "haiku");
  const result4 = await backend4.execute("test", "sys", "haiku");

  assert.ok(result0.text.includes("cloud"));
  assert.ok(result4.text.includes("cloud"));
});

test("TierRouter difficulty 1-2 respects hardware tier", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const backend = await router.routeForDifficulty(1, 0);
  const result = await backend.execute("test", "sys", "haiku");

  assert.ok(result.text.includes("local-fast"));
});

// ─── Cost tracking tests ────────────────────────────────────────────────────

test("TierRouter tracks cost per agent", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Execute on cloud (cost 0.01)
  await router.executeWithCostTracking(
    "agent#1",
    "test",
    "sys",
    "opus",
    3, // difficulty 3 → cloud
    0
  );

  const cost = router.getCumulativeCost("agent#1");
  assert.equal(cost, 0.01);
});

test("TierRouter accumulates cost across multiple dispatches", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Two cloud executions
  await router.executeWithCostTracking(
    "agent#1",
    "test1",
    "sys",
    "haiku",
    3,
    0
  );
  await router.executeWithCostTracking(
    "agent#1",
    "test2",
    "sys",
    "opus",
    3,
    0
  );

  const cost = router.getCumulativeCost("agent#1");
  assert.equal(cost, 0.02); // 0.01 + 0.01
});

test("TierRouter zero cost for local backends", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Local execution (difficulty 1, hw tier 0)
  await router.executeWithCostTracking(
    "agent#1",
    "test",
    "sys",
    "haiku",
    1, // difficulty 1 → respects hardware
    0  // hardware tier 0 → local-fast
  );

  const cost = router.getCumulativeCost("agent#1");
  assert.equal(cost, 0);
});

// ─── Fallback tests ────────────────────────────────────────────────────────

test("TierRouter fallback to cloud", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const result = await router.fallbackToCloud(
    "agent#1",
    "test",
    "sys",
    "opus"
  );

  assert.ok(result.text.includes("cloud"));
});

// ─── Backend selection verification ────────────────────────────────────────

test("TierRouter returns correct backend for low hardware", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const backend = await router.routeForDifficulty(1, 0);
  const result = await backend.execute("test", "sys", "haiku");

  assert.ok(result.text.includes("local-fast"));
});

test("TierRouter returns correct backend for mid hardware", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const backend = await router.routeForDifficulty(2, 2);
  const result = await backend.execute("test", "sys", "haiku");

  assert.ok(result.text.includes("local-quality"));
});

test("TierRouter returns correct backend for high hardware", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  const backend = await router.routeForDifficulty(1, 4);
  const result = await backend.execute("test", "sys", "haiku");

  assert.ok(result.text.includes("cloud"));
});
