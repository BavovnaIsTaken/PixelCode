/**
 * Claude Agent SDK backend implementation.
 *
 * Wraps the existing `query()` API from @anthropic-ai/claude-agent-sdk
 * to implement the AgentBackend interface.
 */

import { query, type SDKAssistantMessage, type SDKResultMessage } from "@anthropic-ai/claude-agent-sdk";
import type { AgentBackend, BackendResult } from "./agent_backend.js";

export class ClaudeAgentSdkBackend implements AgentBackend {
  constructor(private projectCwd: string = process.cwd()) {}

  async execute(
    prompt: string,
    systemPrompt: string,
    model: string
  ): Promise<BackendResult> {
    const startTime = Date.now();
    let output = "";

    const queryIterator = query({
      prompt,
      options: {
        systemPrompt,
        model: model as "haiku" | "sonnet" | "opus",
        allowedTools: [],
        cwd: this.projectCwd,
        includePartialMessages: false,
        permissionMode: "acceptEdits",
        maxTurns: 3,
        persistSession: false,
      },
    });

    for await (const msg of queryIterator) {
      if (msg.type === "assistant") {
        const asst = msg as SDKAssistantMessage;
        if (!asst.parent_tool_use_id) {
          for (const block of asst.message.content) {
            if (block.type === "text") {
              output += (block as { type: "text"; text: string }).text;
            }
          }
        }
      }
      if (msg.type === "result") {
        const res = msg as SDKResultMessage;
        const resText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";
        if (resText && !output) output = resText;
      }
    }

    const durationMs = Date.now() - startTime;

    return {
      text: output,
      durationMs,
      costUsd: this.calculateCost(model, output),
    };
  }

  private calculateCost(model: string, output: string): number {
    // Rough estimation: Claude API pricing
    // haiku: ~$0.80 / 1M input, ~$4 / 1M output
    // sonnet: ~$3 / 1M input, ~$15 / 1M output
    // opus: ~$15 / 1M input, ~$75 / 1M output

    const outputTokens = Math.ceil(output.length / 4); // Rough approximation
    const inputTokens = 500; // Rough estimate for dungeon prompts

    const rates: Record<string, { input: number; output: number }> = {
      haiku: { input: 0.80 / 1e6, output: 4 / 1e6 },
      sonnet: { input: 3 / 1e6, output: 15 / 1e6 },
      opus: { input: 15 / 1e6, output: 75 / 1e6 },
    };

    const rate = rates[model] ?? rates.sonnet;
    return inputTokens * rate.input + outputTokens * rate.output;
  }
}
