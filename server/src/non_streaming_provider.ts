/**
 * Dispatch helper for non-streaming AgentBackends (DeepSeek, Kimi, …).
 *
 * Wraps a single-shot `AgentBackend.execute()` call into the same async-iterable
 * shape that the Claude SDK's `query()` produces, so the message loop in
 * `server.ts` can iterate over any provider uniformly.
 *
 * This is interim DRY for the giant if/else dispatch chain; the full F-section
 * abstraction (streaming-capable `AgentBackend`, per-event yield) lives in the
 * roadmap and is gated on a non-Anthropic provider that needs tool-use.
 */

import type { WebSocket } from "ws";
import type {
  SDKAssistantMessage,
  SDKMessage,
} from "@anthropic-ai/claude-agent-sdk";
import type { AgentBackend } from "./agent_backend.js";
import type { ServerMessage } from "./protocol.js";

/** Per-provider configuration for the non-streaming dispatcher. */
export interface NonStreamingProviderConfig {
  /** Resolve the per-client API key. Returns `undefined` if not linked. */
  getKey(ws: WebSocket): string | undefined;
  /** Build the backend instance for this request. */
  createBackend(apiKey: string): AgentBackend;
  /** Session-id label written into the synthetic SDK assistant message. */
  sessionId: string;
  /** Error message thrown when `getKey` returns nothing. */
  missingKeyError: string;
}

/** Inputs to a single dispatch call. */
export interface NonStreamingDispatchInput {
  config: NonStreamingProviderConfig;
  ws: WebSocket;
  prompt: string;
  systemPrompt: string;
  model: string;
  agentId: string;
  send: (ws: WebSocket, msg: ServerMessage) => void;
}

/**
 * Run a non-streaming backend and yield SDK-shaped messages so the consumer
 * can pretend it's Claude SDK output.
 *
 * Sequence: send `assistant_text` over WS → yield `assistant` → yield `result`.
 * This mirrors what the inlined DeepSeek/Kimi branches did before the refactor.
 */
export async function* runNonStreamingBackend(
  input: NonStreamingDispatchInput,
): AsyncGenerator<SDKMessage> {
  const { config, ws, prompt, systemPrompt, model, agentId, send } = input;

  const apiKey = config.getKey(ws);
  if (!apiKey) throw new Error(config.missingKeyError);

  const backend = config.createBackend(apiKey);
  const res = await backend.execute(prompt, systemPrompt, model);

  send(ws, {
    type: "assistant_text",
    text: res.text,
    isPartial: false,
    agentId,
  });

  yield {
    type: "assistant",
    subtype: "message",
    message: {
      role: "assistant",
      content: [{ type: "text", text: res.text }],
    },
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      total_cost_usd: res.costUsd,
    },
    duration_ms: res.durationMs,
    session_id: config.sessionId,
    parent_tool_use_id: null,
  } as unknown as SDKAssistantMessage;

  yield {
    type: "result",
    result: res.text,
    duration_ms: res.durationMs,
    total_cost_usd: res.costUsd,
  } as unknown as SDKMessage;
}
