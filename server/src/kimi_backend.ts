/**
 * Kimi K2.6 backend implementing AgentBackend.
 * Uses raw fetch to api.moonshot.ai/v1/chat/completions (OpenAI-compatible).
 */

import { dbg } from "./server.js";
import type { AgentBackend, BackendResult } from "./agent_backend.js";
import {
  KIMI_API_URL,
  kimiCostUsd,
  resolveKimiModel,
} from "./kimi_pricing.js";

export {
  KIMI_API_URL,
  KIMI_DEFAULT_MODEL,
  KIMI_MODEL_MAP,
  KIMI_PRICE_INPUT_USD_PER_TOKEN,
  KIMI_PRICE_OUTPUT_USD_PER_TOKEN,
  kimiCostUsd,
  resolveKimiModel,
} from "./kimi_pricing.js";

export class KimiBackend implements AgentBackend {
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
    const kimiModel = resolveKimiModel(model);

    dbg("info", "kimi", `Executing with model=${kimiModel}`);

    const response = await fetch(KIMI_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: kimiModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: prompt },
        ],
        stream: false,
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`Kimi API error ${response.status}: ${body}`);
    }

    const json = (await response.json()) as {
      choices: Array<{ message: { content: string } }>;
      usage?: { prompt_tokens: number; completion_tokens: number };
    };

    const text = json.choices[0]?.message?.content ?? "";
    const durationMs = Date.now() - start;

    const inputTokens = json.usage?.prompt_tokens ?? 0;
    const outputTokens = json.usage?.completion_tokens ?? 0;
    const costUsd = kimiCostUsd(inputTokens, outputTokens);

    dbg("info", "kimi", `Done in ${durationMs}ms, cost=$${costUsd.toFixed(6)}`);

    return { text, durationMs, costUsd };
  }
}
