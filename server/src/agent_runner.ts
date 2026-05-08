/**
 * Independent sub-agent executor.
 *
 * Runs sub-agent queries as separate `query()` calls that don't block
 * the manager. Each sub-agent gets its own session and runs concurrently.
 */

import { WebSocket } from "ws";
import {
  query,
  type SDKMessage,
  type SDKAssistantMessage,
  type SDKResultMessage,
  type SDKSystemMessage,
  type SDKPartialAssistantMessage,
  type SDKToolProgressMessage,
} from "@anthropic-ai/claude-agent-sdk";
import {
  roleTemplateFor,
  buildOfficePrompt,
  hardwareToModel,
  type GameStateData,
} from "./agents.js";
import { formatTraitsForPrompt, type TraitStore } from "./trait_memory.js";

// ─── Types ──────────────────────────────────────────────────────────────────

export interface SubAgentResult {
  dispatchId: string;
  agentId: string;
  text: string;
  costUsd: number;
  durationMs: number;
}

export interface RunningAgent {
  dispatchId: string;
  agentId: string;
  task: string;
  abortController: AbortController;
  startedAt: number;
  promise: Promise<void>;
}

export interface DispatchParams {
  agentId: string;
  task: string;
  ws: WebSocket;
  projectCwd: string;
  gameState?: GameStateData;
  projectMemory?: string;
  traitStore: TraitStore;
  bypassPermissions?: boolean;
  /**
   * Pre-rendered tech-lead digest block. Only used when the dispatched
   * sub-agent's role is `tech-lead`; ignored otherwise. Kept on this
   * struct (not pulled from a global) so agent_runner stays pure and
   * unit-testable without a digest singleton.
   */
  techLeadDigest?: string;
  /** Called for every SDK message from the sub-agent (for real-time UI). */
  onMessage: (msg: SDKMessage, agentId: string, dispatchId: string) => void;
  /** Called when the sub-agent completes (success or error). */
  onComplete: (result: SubAgentResult) => void;
  /** Called on error. */
  onError: (agentId: string, dispatchId: string, error: string) => void;
}

// ─── AgentRunner ────────────────────────────────────────────────────────────

/** Maximum concurrent sub-agent queries. */
const MAX_CONCURRENT = 3;

let dispatchCounter = 0;

export class AgentRunner {
  private running = new Map<string, RunningAgent>();

  /**
   * Dispatch a task to a sub-agent. Returns immediately with a dispatch ID.
   * The sub-agent runs in the background and calls onComplete when done.
   */
  dispatch(params: DispatchParams): string {
    const dispatchId = `dispatch_${++dispatchCounter}_${Date.now()}`;

    if (this.running.size >= MAX_CONCURRENT) {
      params.onError(params.agentId, dispatchId, `Too many concurrent agents (${MAX_CONCURRENT} max). Wait for one to finish.`);
      return dispatchId;
    }

    const abortController = new AbortController();

    const entry: RunningAgent = {
      dispatchId,
      agentId: params.agentId,
      task: params.task,
      abortController,
      startedAt: Date.now(),
      promise: this.runAgent(dispatchId, params, abortController),
    };

    this.running.set(dispatchId, entry);

    // Auto-cleanup when done
    entry.promise.finally(() => {
      this.running.delete(dispatchId);
    });

    return dispatchId;
  }

  /** Cancel a running sub-agent. */
  cancel(dispatchId: string): boolean {
    const entry = this.running.get(dispatchId);
    if (!entry) return false;
    entry.abortController.abort();
    this.running.delete(dispatchId);
    return true;
  }

  /** Cancel all running agents for a given WebSocket (e.g. on disconnect). */
  cancelAll(ws?: WebSocket): void {
    for (const [id, entry] of this.running) {
      entry.abortController.abort();
      this.running.delete(id);
    }
  }

  /** Get list of currently running agents. */
  getRunning(): RunningAgent[] {
    return Array.from(this.running.values());
  }

  /** Check if a specific agent type is currently busy. */
  isAgentBusy(agentId: string): boolean {
    for (const entry of this.running.values()) {
      if (entry.agentId === agentId) return true;
    }
    return false;
  }

  /** Get status summary for all running agents. */
  getStatus(): Array<{ dispatchId: string; agentId: string; task: string; elapsedMs: number }> {
    const now = Date.now();
    return Array.from(this.running.values()).map((r) => ({
      dispatchId: r.dispatchId,
      agentId: r.agentId,
      task: r.task,
      elapsedMs: now - r.startedAt,
    }));
  }

  // ─── Private ────────────────────────────────────────────────────────────

  private async runAgent(
    dispatchId: string,
    params: DispatchParams,
    abortController: AbortController,
  ): Promise<void> {
    const { agentId, task, projectCwd, gameState, projectMemory, traitStore, bypassPermissions, techLeadDigest } = params;

    try {
      // Build the sub-agent's system prompt
      const agentTraits = formatTraitsForPrompt(traitStore, agentId);
      const systemPrompt = buildOfficePrompt(
        agentId,
        projectMemory,
        agentTraits,
        gameState,
        techLeadDigest,
      );

      // Determine model from hardware (hardware is tracked per instance now)
      const instance = gameState?.instances[agentId];
      const hwTier = instance?.hardware ?? 0;
      const model = hardwareToModel(hwTier);

      // Determine tools — sub-agents cannot delegate.
      // Look up the role template via the instance's roleType.
      const agentDef = roleTemplateFor(agentId, gameState);
      const agentTools = agentDef?.tools?.filter((t) => t !== "Agent") ?? ["Read", "Glob", "Grep", "Bash"];

      const promptText = `[Manager dispatched task] ${task}`;

      const q = query({
        prompt: promptText,
        options: {
          systemPrompt,
          model,
          allowedTools: agentTools,
          cwd: projectCwd,
          includePartialMessages: true,
          permissionMode: "bypassPermissions",
          maxTurns: 30,
          persistSession: false,
          abortController,
        },
      });

      let resultText = "";
      let costUsd = 0;
      let durationMs = 0;

      for await (const message of q) {
        // Forward all messages for real-time UI updates
        params.onMessage(message, agentId, dispatchId);

        // Collect result
        if (message.type === "assistant") {
          const asst = message as SDKAssistantMessage;
          // Only collect text from top-level messages (no parent)
          if (!asst.parent_tool_use_id) {
            for (const block of asst.message.content) {
              if (block.type === "text") {
                resultText += (block as { type: "text"; text: string }).text;
              }
            }
          }
        }

        if (message.type === "result") {
          const res = message as SDKResultMessage;
          costUsd = res.total_cost_usd ?? 0;
          durationMs = res.duration_ms ?? 0;
          const resText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";
          if (resText && !resultText) {
            resultText = resText;
          }
        }
      }

      params.onComplete({
        dispatchId,
        agentId,
        text: resultText,
        costUsd,
        durationMs,
      });
    } catch (err) {
      if (abortController.signal.aborted) return; // cancelled, not an error
      const errMsg = err instanceof Error ? err.message : String(err);
      params.onError(agentId, dispatchId, errMsg);
    }
  }
}
