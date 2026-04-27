/**
 * DeepSeek API backend implementing AgentBackend.
 * Uses raw fetch to api.deepseek.com/v1/chat/completions (OpenAI-compatible).
 */

import { dbg } from "./server.js";
import type { AgentBackend, BackendResult } from "./agent_backend.js";
import {
  DEEPSEEK_API_URL,
  DEEPSEEK_MODEL_MAP,
  deepseekCostUsd,
  resolveDeepSeekModel,
} from "./deepseek_pricing.js";

export {
  DEEPSEEK_API_URL,
  DEEPSEEK_DEFAULT_MODEL,
  DEEPSEEK_MODEL_MAP,
  DEEPSEEK_PRICE_INPUT_USD_PER_TOKEN,
  DEEPSEEK_PRICE_OUTPUT_USD_PER_TOKEN,
  deepseekCostUsd,
  resolveDeepSeekModel,
} from "./deepseek_pricing.js";

export class DeepSeekBackend implements AgentBackend {
  private apiKey: string;

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  async execute(
    prompt: string,
    systemPrompt: string,
    model: string
  ): Promise<BackendResult> {
    const start = Date.now();
    const dsModel = resolveDeepSeekModel(model);

    dbg("info", "deepseek", `Executing with model=${dsModel}`);

    const response = await fetch(DEEPSEEK_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: dsModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: prompt },
        ],
        stream: false,
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`DeepSeek API error ${response.status}: ${body}`);
    }

    const json = (await response.json()) as {
      choices: Array<{ message: { content: string } }>;
      usage?: { prompt_tokens: number; completion_tokens: number };
    };

    const text = json.choices[0]?.message?.content ?? "";
    const durationMs = Date.now() - start;

    const inputTokens = json.usage?.prompt_tokens ?? 0;
    const outputTokens = json.usage?.completion_tokens ?? 0;
    const costUsd = deepseekCostUsd(inputTokens, outputTokens);

    dbg("info", "deepseek", `Done in ${durationMs}ms, cost=$${costUsd.toFixed(6)}`);

    return { text, durationMs, costUsd };
  }
}
