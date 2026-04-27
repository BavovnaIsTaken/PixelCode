import { test } from "node:test";
import assert from "node:assert/strict";
import type { AgentBackend, BackendResult } from "../src/agent_backend.js";
import { TierRouter } from "../src/tier_router.js";

// ─── Mock backends ─────────────────────────────────────────────────────────

class MockLocalFastBackend implements AgentBackend {
  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: `local-fast: ${prompt}`,
      durationMs: 5,
      costUsd: 0,
    };
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
  async execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult> {
    return {
      text: `cloud: ${prompt}`,
      durationMs: 3,
      costUsd: 0.01,
    };
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

// ─── Additional cost tracking and reset tests ──────────────────────────────

test("TierRouter getCumulativeCost sums across multiple models for same agent", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Execute with two different models on cloud (cost 0.01 each)
  await router.executeWithCostTracking(
    "agent#1",
    "test1",
    "sys",
    "haiku",
    3, // difficulty 3 → cloud
    0
  );
  await router.executeWithCostTracking(
    "agent#1",
    "test2",
    "sys",
    "sonnet",
    3, // difficulty 3 → cloud
    0
  );

  // getCumulativeCost should sum both models (0.01 + 0.01)
  const cost = router.getCumulativeCost("agent#1");
  assert.equal(cost, 0.02);
});

test("TierRouter fallbackToCloud tracks cost", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Call fallbackToCloud (should track cost)
  await router.fallbackToCloud("agent#1", "test", "sys", "opus");

  // Cost should be tracked (0.01)
  const cost = router.getCumulativeCost("agent#1");
  assert.equal(cost, 0.01);
});

test("TierRouter resetCostTracking clears all accumulated costs", async () => {
  const router = new TierRouter(
    new MockLocalFastBackend(),
    new MockLocalQualityBackend(),
    new MockCloudBackend()
  );

  // Execute multiple times to accumulate cost
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
    "sonnet",
    3,
    0
  );

  // Verify cost is accumulated
  assert.equal(router.getCumulativeCost("agent#1"), 0.02);

  // Reset and verify it's cleared
  router.resetCostTracking();
  assert.equal(router.getCumulativeCost("agent#1"), 0);
});
