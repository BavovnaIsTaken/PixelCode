import { test } from "node:test";
import assert from "node:assert/strict";
import {
  KIMI_API_URL,
  KIMI_DEFAULT_MODEL,
  KIMI_MODEL_MAP,
  KIMI_PRICE_INPUT_USD_PER_TOKEN,
  KIMI_PRICE_OUTPUT_USD_PER_TOKEN,
  kimiCostUsd,
  resolveKimiModel,
} from "../src/kimi_pricing.js";

// ─── Endpoint / model identity ─────────────────────────────────────────────

test("KIMI_API_URL points at official Moonshot endpoint", () => {
  assert.equal(KIMI_API_URL, "https://api.moonshot.ai/v1/chat/completions");
});

test("KIMI_DEFAULT_MODEL is kimi-k2.6", () => {
  assert.equal(KIMI_DEFAULT_MODEL, "kimi-k2.6");
});

test("MODEL_MAP routes haiku/sonnet/opus all to the K2.6 default", () => {
  assert.equal(KIMI_MODEL_MAP.haiku, KIMI_DEFAULT_MODEL);
  assert.equal(KIMI_MODEL_MAP.sonnet, KIMI_DEFAULT_MODEL);
  assert.equal(KIMI_MODEL_MAP.opus, KIMI_DEFAULT_MODEL);
});

// ─── resolveKimiModel ──────────────────────────────────────────────────────

test("resolveKimiModel returns mapped id for known logical models", () => {
  assert.equal(resolveKimiModel("haiku"), KIMI_DEFAULT_MODEL);
  assert.equal(resolveKimiModel("sonnet"), KIMI_DEFAULT_MODEL);
  assert.equal(resolveKimiModel("opus"), KIMI_DEFAULT_MODEL);
});

test("resolveKimiModel falls back to default for unknown logical model", () => {
  assert.equal(resolveKimiModel("gpt-5"), KIMI_DEFAULT_MODEL);
  assert.equal(resolveKimiModel(""), KIMI_DEFAULT_MODEL);
  assert.equal(resolveKimiModel("anything-else"), KIMI_DEFAULT_MODEL);
});

// ─── Pricing constants ────────────────────────────────────────────────────

test("Input price is $0.80/M tokens", () => {
  // 1_000_000 input tokens should cost $0.80 (allow FP tolerance).
  assert.ok(
    Math.abs(KIMI_PRICE_INPUT_USD_PER_TOKEN * 1_000_000 - 0.8) < 1e-9
  );
});

test("Output price is $3.50/M tokens", () => {
  // 1_000_000 output tokens should cost $3.50 (allow FP tolerance).
  assert.ok(
    Math.abs(KIMI_PRICE_OUTPUT_USD_PER_TOKEN * 1_000_000 - 3.5) < 1e-9
  );
});

// ─── kimiCostUsd ──────────────────────────────────────────────────────────

test("kimiCostUsd returns 0 for empty usage", () => {
  assert.equal(kimiCostUsd(0, 0), 0);
});

test("kimiCostUsd computes input-only cost", () => {
  // 1M input tokens, 0 output → $0.80
  assert.ok(Math.abs(kimiCostUsd(1_000_000, 0) - 0.8) < 1e-9);
});

test("kimiCostUsd computes output-only cost", () => {
  // 0 input, 1M output tokens → $3.50
  assert.ok(Math.abs(kimiCostUsd(0, 1_000_000) - 3.5) < 1e-9);
});

test("kimiCostUsd combines input + output costs additively", () => {
  // 500k input ($0.40) + 200k output ($0.70) = $1.10
  const expected = 0.4 + 0.7;
  const actual = kimiCostUsd(500_000, 200_000);
  // Allow for floating-point noise.
  assert.ok(
    Math.abs(actual - expected) < 1e-9,
    `expected ~$${expected}, got $${actual}`
  );
});

test("kimiCostUsd is monotonic in both axes", () => {
  const base = kimiCostUsd(1000, 1000);
  assert.ok(kimiCostUsd(2000, 1000) > base);
  assert.ok(kimiCostUsd(1000, 2000) > base);
});

test("kimiCostUsd weights output ~4.375x input (per-token ratio)", () => {
  // Sanity-check the relative pricing — output should be more expensive than input.
  const ratio =
    KIMI_PRICE_OUTPUT_USD_PER_TOKEN / KIMI_PRICE_INPUT_USD_PER_TOKEN;
  assert.ok(ratio > 4 && ratio < 5, `unexpected ratio: ${ratio}`);
});
