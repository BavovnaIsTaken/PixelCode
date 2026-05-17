/**
 * CircuitBreaker — safety-net abort for SDK queries.
 *
 * Tests pin the trip thresholds + accumulation math + idempotent trip
 * (only one trip object returned even if observe() is called more times).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { CircuitBreaker } from "../src/circuit_breaker.js";

test("fresh breaker has no trip and zero counters", () => {
  const b = new CircuitBreaker("sonnet");
  assert.equal(b.isTripped, false);
  assert.equal(b.toolCalls, 0);
  assert.equal(b.currentCostUsd(), 0);
  assert.equal(b.maxCostUsd, 5);
  assert.equal(b.maxToolCalls, 30);
});

test("accumulates input + output across multiple observations", () => {
  const b = new CircuitBreaker("sonnet");
  b.observeAssistantMessage({ input_tokens: 1_000, output_tokens: 200 }, []);
  b.observeAssistantMessage({ input_tokens: 500, output_tokens: 100 }, []);
  // sonnet: $3/M input, $15/M output
  // total: 1500 * 3e-6 + 300 * 15e-6 = 0.0045 + 0.0045 = 0.009
  assert.ok(Math.abs(b.currentCostUsd() - 0.009) < 1e-9);
});

test("counts tool_use blocks across messages", () => {
  const b = new CircuitBreaker("sonnet");
  b.observeAssistantMessage(null, [
    { type: "text" },
    { type: "tool_use" },
    { type: "tool_use" },
  ]);
  b.observeAssistantMessage(null, [{ type: "tool_use" }]);
  assert.equal(b.toolCalls, 3);
});

test("trips on tool_use cap of 30", () => {
  const b = new CircuitBreaker("sonnet");
  let trip = null;
  for (let i = 0; i < 29; i++) {
    trip = b.observeAssistantMessage(null, [{ type: "tool_use" }]);
    assert.equal(trip, null, `should not trip on call ${i + 1}`);
  }
  trip = b.observeAssistantMessage(null, [{ type: "tool_use" }]);
  assert.equal(b.isTripped, true);
  assert.equal(trip?.reason, "tool_cap");
  assert.equal(trip?.toolCalls, 30);
  assert.match(trip?.message ?? "", /tool-call cap/);
});

test("trips on cost cap of $5 default", () => {
  const b = new CircuitBreaker("sonnet");
  // sonnet output rate: $15 / 1M tokens → need 333_334 output tokens for $5+
  const trip = b.observeAssistantMessage(
    { input_tokens: 0, output_tokens: 333_334 },
    []
  );
  assert.equal(trip?.reason, "cost_cap");
  assert.ok(trip!.costUsd >= 5);
});

test("trip object is returned exactly once, then null", () => {
  const b = new CircuitBreaker("sonnet", { maxToolCalls: 1 });
  const first = b.observeAssistantMessage(null, [{ type: "tool_use" }]);
  assert.notEqual(first, null);

  const second = b.observeAssistantMessage(null, [{ type: "tool_use" }]);
  assert.equal(second, null, "subsequent calls return null after trip");

  // But isTripped stays true and counters stop incrementing.
  assert.equal(b.isTripped, true);
  assert.equal(b.toolCalls, 1, "counters frozen after trip");
});

test("custom caps override defaults", () => {
  const b = new CircuitBreaker("haiku", { maxCostUsd: 0.001, maxToolCalls: 100 });
  assert.equal(b.maxCostUsd, 0.001);
  assert.equal(b.maxToolCalls, 100);

  // haiku output rate: $4/M; 250 tokens = $0.001 — should trip on cost
  const trip = b.observeAssistantMessage(
    { input_tokens: 0, output_tokens: 250 },
    []
  );
  assert.equal(trip?.reason, "cost_cap");
});

test("unknown model falls back to sonnet pricing via claudeCostUsd", () => {
  const b = new CircuitBreaker("unknown-model");
  b.observeAssistantMessage({ input_tokens: 1_000_000, output_tokens: 0 }, []);
  // sonnet input rate: $3/M → $3
  assert.ok(Math.abs(b.currentCostUsd() - 3) < 1e-6);
});

test("cache tokens contribute to cost (conservative)", () => {
  const b = new CircuitBreaker("sonnet");
  b.observeAssistantMessage(
    {
      input_tokens: 0,
      output_tokens: 0,
      cache_creation_input_tokens: 1_000_000,
      cache_read_input_tokens: 1_000_000,
    },
    []
  );
  // 2M tokens treated as input @ $3/M = $6 — trips immediately
  assert.equal(b.isTripped, true);
});

test("snapshot exposes full accumulated state", () => {
  const b = new CircuitBreaker("sonnet");
  b.observeAssistantMessage(
    { input_tokens: 100, output_tokens: 50 },
    [{ type: "tool_use" }, { type: "tool_use" }]
  );
  const snap = b.snapshot();
  assert.equal(snap.inputTokens, 100);
  assert.equal(snap.outputTokens, 50);
  assert.equal(snap.toolCalls, 2);
  assert.equal(snap.tripped, null);
  assert.ok(snap.costUsd > 0);
});

test("handles null/undefined usage and content gracefully", () => {
  const b = new CircuitBreaker("sonnet");
  assert.doesNotThrow(() => {
    b.observeAssistantMessage(null, null);
    b.observeAssistantMessage(undefined, undefined);
  });
  assert.equal(b.currentCostUsd(), 0);
  assert.equal(b.toolCalls, 0);
});
