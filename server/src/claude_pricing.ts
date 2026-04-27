/**
 * Pure pricing/model helpers for the Claude Agent SDK backend.
 * Kept separate from claude_backend.ts so they can be unit-tested without
 * pulling in the WebSocket server module's top-level side effects.
 */

// Claude pricing as of 2025:
// haiku: ~$0.80 / 1M input, ~$4 / 1M output
// sonnet: ~$3 / 1M input, ~$15 / 1M output
// opus: ~$15 / 1M input, ~$75 / 1M output
export const CLAUDE_RATES: Record<string, { input: number; output: number }> = {
  haiku: { input: 0.80 / 1e6, output: 4 / 1e6 },
  sonnet: { input: 3 / 1e6, output: 15 / 1e6 },
  opus: { input: 15 / 1e6, output: 75 / 1e6 },
};

// Rough approximation: 1 character ≈ 1/4 token
export const CLAUDE_TOKENS_PER_CHAR = 1 / 4;

// Rough estimate for dungeon prompts
export const CLAUDE_DEFAULT_INPUT_TOKENS = 500;

export function claudeCostUsd(
  model: string,
  inputTokens: number,
  outputTokens: number
): number {
  const rate = CLAUDE_RATES[model] ?? CLAUDE_RATES.sonnet;
  return inputTokens * rate.input + outputTokens * rate.output;
}
