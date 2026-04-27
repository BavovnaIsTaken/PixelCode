/**
 * Claude Agent SDK backend implementation.
 *
 * Wraps the existing `query()` API from @anthropic-ai/claude-agent-sdk
 * to implement the AgentBackend interface.
 */

import { query, type SDKAssistantMessage, type SDKResultMessage } from "@anthropic-ai/claude-agent-sdk";
import type { AgentBackend, BackendResult } from "./agent_backend.js";
import { claudeCostUsd, CLAUDE_DEFAULT_INPUT_TOKENS, CLAUDE_TOKENS_PER_CHAR } from "./claude_pricing.js";

export {
  CLAUDE_RATES,
  CLAUDE_DEFAULT_INPUT_TOKENS,
  CLAUDE_TOKENS_PER_CHAR,
  claudeCostUsd,
} from "./claude_pricing.js";

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

    const outputTokens = Math.ceil(output.length / CLAUDE_TOKENS_PER_CHAR);
    const costUsd = claudeCostUsd(model, CLAUDE_DEFAULT_INPUT_TOKENS, outputTokens);

    return {
      text: output,
      durationMs,
      costUsd,
    };
  }
}
