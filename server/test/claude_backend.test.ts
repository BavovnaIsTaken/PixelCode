import { test } from "node:test";
import assert from "node:assert/strict";
import {
  CLAUDE_RATES,
  CLAUDE_DEFAULT_INPUT_TOKENS,
  CLAUDE_TOKENS_PER_CHAR,
  claudeCostUsd,
} from "../src/claude_pricing.js";

// ─── Rate table shape ────────────────────────────────────────────────────

test("CLAUDE_RATES contains haiku, sonnet, opus keys", () => {
  assert.ok(Object.prototype.hasOwnProperty.call(CLAUDE_RATES, "haiku"));
  assert.ok(Object.prototype.hasOwnProperty.call(CLAUDE_RATES, "sonnet"));
  assert.ok(Object.prototype.hasOwnProperty.call(CLAUDE_RATES, "opus"));
});

test("CLAUDE_RATES entries have input and output per-token rates", () => {
  for (const model of ["haiku", "sonnet", "opus"]) {
    const rate = CLAUDE_RATES[model];
    assert.ok(typeof rate.input === "number" && rate.input > 0);
    assert.ok(typeof rate.output === "number" && rate.output > 0);
  }
});

// ─── Pricing constant values ────────────────────────────────────────────

test("Haiku input price is ~$0.80/M tokens", () => {
  const haikuInput = CLAUDE_RATES.haiku.input;
  assert.ok(
    Math.abs(haikuInput * 1_000_000 - 0.8) < 1e-9,
    `haiku input rate ${haikuInput} does not yield ~$0.80/M`
  );
});

test("Haiku output price is ~$4.00/M tokens", () => {
  const haikuOutput = CLAUDE_RATES.haiku.output;
  assert.ok(
    Math.abs(haikuOutput * 1_000_000 - 4) < 1e-9,
    `haiku output rate ${haikuOutput} does not yield ~$4/M`
  );
});

test("Sonnet input price is ~$3.00/M tokens", () => {
  const sonnetInput = CLAUDE_RATES.sonnet.input;
  assert.ok(
    Math.abs(sonnetInput * 1_000_000 - 3) < 1e-9,
    `sonnet input rate ${sonnetInput} does not yield ~$3/M`
  );
});

test("Sonnet output price is ~$15.00/M tokens", () => {
  const sonnetOutput = CLAUDE_RATES.sonnet.output;
  assert.ok(
    Math.abs(sonnetOutput * 1_000_000 - 15) < 1e-9,
    `sonnet output rate ${sonnetOutput} does not yield ~$15/M`
  );
});

test("Opus input price is ~$15.00/M tokens", () => {
  const opusInput = CLAUDE_RATES.opus.input;
  assert.ok(
    Math.abs(opusInput * 1_000_000 - 15) < 1e-9,
    `opus input rate ${opusInput} does not yield ~$15/M`
  );
});

test("Opus output price is ~$75.00/M tokens", () => {
  const opusOutput = CLAUDE_RATES.opus.output;
  assert.ok(
    Math.abs(opusOutput * 1_000_000 - 75) < 1e-9,
    `opus output rate ${opusOutput} does not yield ~$75/M`
  );
});

// ─── Constants ──────────────────────────────────────────────────────────

test("CLAUDE_TOKENS_PER_CHAR is 1/4", () => {
  assert.equal(CLAUDE_TOKENS_PER_CHAR, 0.25);
});

test("CLAUDE_DEFAULT_INPUT_TOKENS is a positive integer", () => {
  assert.ok(Number.isInteger(CLAUDE_DEFAULT_INPUT_TOKENS));
  assert.ok(CLAUDE_DEFAULT_INPUT_TOKENS > 0);
  assert.equal(CLAUDE_DEFAULT_INPUT_TOKENS, 500);
});

// ─── claudeCostUsd ─────────────────────────────────────────────────────

test("claudeCostUsd returns 0 for empty usage", () => {
  assert.equal(claudeCostUsd("sonnet", 0, 0), 0);
});

test("claudeCostUsd computes haiku cost correctly", () => {
  // 1M input + 1M output → ($0.80) + ($4.00) = $4.80
  const cost = claudeCostUsd("haiku", 1_000_000, 1_000_000);
  assert.ok(
    Math.abs(cost - 4.8) < 1e-9,
    `haiku 1M+1M expected ~$4.80, got $${cost}`
  );
});

test("claudeCostUsd computes sonnet cost correctly", () => {
  // 1M input + 1M output → ($3.00) + ($15.00) = $18.00
  const cost = claudeCostUsd("sonnet", 1_000_000, 1_000_000);
  assert.ok(
    Math.abs(cost - 18) < 1e-9,
    `sonnet 1M+1M expected ~$18.00, got $${cost}`
  );
});

test("claudeCostUsd computes opus cost correctly", () => {
  // 1M input + 1M output → ($15.00) + ($75.00) = $90.00
  const cost = claudeCostUsd("opus", 1_000_000, 1_000_000);
  assert.ok(
    Math.abs(cost - 90) < 1e-9,
    `opus 1M+1M expected ~$90.00, got $${cost}`
  );
});

test("claudeCostUsd falls back to sonnet for unknown model", () => {
  const unknown = claudeCostUsd("gpt-5", 1_000_000, 1_000_000);
  const sonnet = claudeCostUsd("sonnet", 1_000_000, 1_000_000);
  assert.equal(
    unknown,
    sonnet,
    "unknown model should fall back to sonnet rate"
  );
});

test("claudeCostUsd is monotonic in input tokens", () => {
  const base = claudeCostUsd("sonnet", 1000, 1000);
  const more = claudeCostUsd("sonnet", 2000, 1000);
  assert.ok(more > base);
});

test("claudeCostUsd is monotonic in output tokens", () => {
  const base = claudeCostUsd("sonnet", 1000, 1000);
  const more = claudeCostUsd("sonnet", 1000, 2000);
  assert.ok(more > base);
});

test("claudeCostUsd: opus > sonnet > haiku for same token count", () => {
  const input = 500_000;
  const output = 200_000;
  const haikuCost = claudeCostUsd("haiku", input, output);
  const sonnetCost = claudeCostUsd("sonnet", input, output);
  const opusCost = claudeCostUsd("opus", input, output);

  assert.ok(
    haikuCost < sonnetCost,
    `haiku (${haikuCost}) should be cheaper than sonnet (${sonnetCost})`
  );
  assert.ok(
    sonnetCost < opusCost,
    `sonnet (${sonnetCost}) should be cheaper than opus (${opusCost})`
  );
});
