import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEEPSEEK_API_URL,
  DEEPSEEK_DEFAULT_MODEL,
  DEEPSEEK_MODEL_MAP,
  DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN,
  DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN,
  deepseekCostUsd,
  resolveDeepSeekModel,
} from "../src/deepseek_pricing.js";

// ─── Endpoint / model identity ─────────────────────────────────────────────

test("DEEPSEEK_API_URL points at official endpoint", () => {
  assert.equal(DEEPSEEK_API_URL, "https://api.deepseek.com/v1/chat/completions");
});

test("DEEPSEEK_DEFAULT_MODEL is deepseek-chat", () => {
  assert.equal(DEEPSEEK_DEFAULT_MODEL, "deepseek-chat");
});

test("MODEL_MAP routes haiku/sonnet/opus all to the default", () => {
  assert.equal(DEEPSEEK_MODEL_MAP.haiku, DEEPSEEK_DEFAULT_MODEL);
  assert.equal(DEEPSEEK_MODEL_MAP.sonnet, DEEPSEEK_DEFAULT_MODEL);
  assert.equal(DEEPSEEK_MODEL_MAP.opus, DEEPSEEK_DEFAULT_MODEL);
});

// ─── resolveDeepSeekModel ────────────────────────────────────────────────

test("resolveDeepSeekModel returns mapped id for known logical models", () => {
  assert.equal(resolveDeepSeekModel("haiku"), DEEPSEEK_DEFAULT_MODEL);
  assert.equal(resolveDeepSeekModel("sonnet"), DEEPSEEK_DEFAULT_MODEL);
  assert.equal(resolveDeepSeekModel("opus"), DEEPSEEK_DEFAULT_MODEL);
});

test("resolveDeepSeekModel falls back to default for unknown logical model", () => {
  assert.equal(resolveDeepSeekModel("gpt-5"), DEEPSEEK_DEFAULT_MODEL);
  assert.equal(resolveDeepSeekModel(""), DEEPSEEK_DEFAULT_MODEL);
  assert.equal(resolveDeepSeekModel("anything-else"), DEEPSEEK_DEFAULT_MODEL);
});

// ─── Pricing constants ────────────────────────────────────────────────────

test("Input price is $0.27/M tokens", () => {
  // 1_000_000 input tokens should cost $0.27 (allow FP tolerance).
  assert.ok(
    Math.abs(DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN * 1_000_000 - 0.27) < 1e-9
  );
});

test("Output price is $1.10/M tokens", () => {
  // 1_000_000 output tokens should cost $1.10 (allow FP tolerance).
  assert.ok(
    Math.abs(DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN * 1_000_000 - 1.1) < 1e-9
  );
});

// ─── deepseekCostUsd ──────────────────────────────────────────────────────

test("deepseekCostUsd returns 0 for empty usage", () => {
  assert.equal(deepseekCostUsd(0, 0), 0);
});

test("deepseekCostUsd computes input-only cost", () => {
  // 1M input tokens, 0 output → $0.27
  assert.ok(Math.abs(deepseekCostUsd(1_000_000, 0) - 0.27) < 1e-9);
});

test("deepseekCostUsd computes output-only cost", () => {
  // 0 input, 1M output tokens → $1.10
  assert.ok(Math.abs(deepseekCostUsd(0, 1_000_000) - 1.1) < 1e-9);
});

test("deepseekCostUsd combines input + output costs additively", () => {
  // 500k input ($0.135) + 200k output ($0.22) = $0.355
  const expected = 0.135 + 0.22;
  const actual = deepseekCostUsd(500_000, 200_000);
  // Allow for floating-point noise.
  assert.ok(
    Math.abs(actual - expected) < 1e-9,
    `expected ~$${expected}, got $${actual}`
  );
});

test("deepseekCostUsd is monotonic in both axes", () => {
  const base = deepseekCostUsd(1000, 1000);
  assert.ok(deepseekCostUsd(2000, 1000) > base);
  assert.ok(deepseekCostUsd(1000, 2000) > base);
});

test("deepseekCostUsd weights output ~4.07x input (per-token ratio)", () => {
  // Sanity-check the relative pricing — output should be more expensive than input.
  const ratio =
    DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN / DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN;
  assert.ok(ratio > 3.9 && ratio < 4.2, `unexpected ratio: ${ratio}`);
});
