/**
 * Pure pricing/model helpers for the Kimi K2.6 backend.
 * Kept separate from kimi_backend.ts so they can be unit-tested without
 * pulling in the WebSocket server module's top-level side effects.
 */

export const KIMI_API_URL = "https://api.moonshot.ai/v1/chat/completions";

export const KIMI_DEFAULT_MODEL = "kimi-k2.6";

// Maps logical model names to Kimi model IDs.
// kimi-k2.6 = MoE ~1T params, 32B active, 256K context — best for code/agents.
export const KIMI_MODEL_MAP: Record<string, string> = {
  haiku: KIMI_DEFAULT_MODEL,
  sonnet: KIMI_DEFAULT_MODEL,
  opus: KIMI_DEFAULT_MODEL,
};

// Pricing: $0.80/M input, $3.50/M output (Kimi K2.6 via api.moonshot.ai, 2026).
export const KIMI_PRICE_INPUT_USD_PER_TOKEN = 0.0000008;
export const KIMI_PRICE_OUTPUT_USD_PER_TOKEN = 0.0000035;

export function resolveKimiModel(logicalModel: string): string {
  return KIMI_MODEL_MAP[logicalModel] ?? KIMI_DEFAULT_MODEL;
}

export function kimiCostUsd(inputTokens: number, outputTokens: number): number {
  return (
    inputTokens * KIMI_PRICE_INPUT_USD_PER_TOKEN +
    outputTokens * KIMI_PRICE_OUTPUT_USD_PER_TOKEN
  );
}
