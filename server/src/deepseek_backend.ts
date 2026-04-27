/**
 * DeepSeek API backend implementing AgentBackend.
 * Uses raw fetch to api.deepseek.com/v1/chat/completions (OpenAI-compatible).
 */

import { dbg } from "./server.js";
import type { AgentBackend, BackendResult } from "./agent_backend.js";

const DEEPSEEK_API_URL = "https://api.deepseek.com/v1/chat/completions";

// Maps logical model names to DeepSeek model IDs.
// deepseek-chat = DeepSeek-V3 (MoE 236B, activated 21B) — best for code
const MODEL_MAP: Record<string, string> = {
  haiku: "deepseek-chat",
  sonnet: "deepseek-chat",
  opus: "deepseek-chat",
};

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
    const dsModel = MODEL_MAP[model] ?? "deepseek-chat";

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

    // Pricing: $0.27/M input, $1.10/M output (DeepSeek-V3, 2025)
    const inputTokens = json.usage?.prompt_tokens ?? 0;
    const outputTokens = json.usage?.completion_tokens ?? 0;
    const costUsd = inputTokens * 0.00000027 + outputTokens * 0.0000011;

    dbg("info", "deepseek", `Done in ${durationMs}ms, cost=$${costUsd.toFixed(6)}`);

    return { text, durationMs, costUsd };
  }
}
