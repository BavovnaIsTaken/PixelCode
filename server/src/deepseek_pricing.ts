/**
 * Pure pricing/model helpers for the DeepSeek backend.
 * Kept separate from deepseek_backend.ts so they can be unit-tested without
 * pulling in the WebSocket server module's top-level side effects.
 */

export const DEEPSEEK_API_URL = "https://api.deepseek.com/v1/chat/completions";

export const DEEPSEEK_DEFAULT_MODEL = "deepseek-chat";

// Maps logical model names to DeepSeek model IDs.
// deepseek-chat = DeepSeek-V3 (MoE 236B, activated 21B) — best for code.
export const DEEPSEEK_MODEL_MAP: Record<string, string> = {
  haiku: DEEPSEEK_DEFAULT_MODEL,
  sonnet: DEEPSEEK_DEFAULT_MODEL,
  opus: DEEPSEEK_DEFAULT_MODEL,
};

// Pricing: $0.27/M input, $1.10/M output (DeepSeek-V3, 2025).
export const DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN = 0.00000027;
export const DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN = 0.0000011;

export function resolveDeepSeekModel(logicalModel: string): string {
  return DEEPSEEK_MODEL_MAP[logicalModel] ?? DEEPSEEK_DEFAULT_MODEL;
}

export function deepseekCostUsd(inputTokens: number, outputTokens: number): number {
  return (
    inputTokens * DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN +
    outputTokens * DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN
  );
}
