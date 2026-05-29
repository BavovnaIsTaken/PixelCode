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
import { CircuitBreaker } from "./circuit_breaker.js";
import { UsageLogger, newRunId } from "./usage_log.js";
import { IncidentLogger, newIncidentId, isNoOpRun } from "./incident_log.js";
import { runWithHardTimeout } from "./race_with_timeout.js";
import type { AgentRunStore } from "./agent_run.js";

// ─── Types ──────────────────────────────────────────────────────────────────

export interface SubAgentResult {
  dispatchId: string;
  agentId: string;
  text: string;
  costUsd: number;
  durationMs: number;
  /**
   * Identifier of the board card this dispatch served, when manager-LLM
   * supplied one via the `dispatch` MCP tool. Server uses this to advance
   * the card on terminal-success (C.2 — server as single writer for board
   * transitions). Absent for ad-hoc / non-board dispatches.
   */
  boardTaskId?: string;
}

export interface RunningAgent {
  dispatchId: string;
  agentId: string;
  task: string;
  abortController: AbortController;
  startedAt: number;
  promise: Promise<void>;
  /** Owning WebSocket — kept so disconnect can cancel only the dropped
   *  client's agents, not every peer's. */
  ws: WebSocket;
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
  /**
   * Optional usage logger — records the completed run's cost / tokens /
   * tool-call count to JSONL. Kept on the params struct (not a singleton)
   * so unit tests can omit it without ceremony, and so a future per-user
   * UsageLogger split doesn't need a runner refactor.
   */
  usageLogger?: UsageLogger;
  /**
   * Optional incident logger (C.2.5) — records dispatch-lifecycle
   * anomalies (no_op_run on this path). Same DI rationale as usageLogger.
   * Absent in older tests; the runner no-ops the incident path when null.
   */
  incidentLogger?: IncidentLogger;
  /**
   * Hard timeout in ms for the for-await loop (C.2.5 Promise.race
   * mechanism). Default 3 minutes — same wall-clock as the previous
   * AbortController-only timeout. Tests override to validate the
   * timeout-propagates-even-when-SDK-stalls invariant.
   */
  hardTimeoutMs?: number;
  /**
   * Optional persistent run store — records the dispatch lifecycle
   * (running → completed / failed / interrupted / cancelled) so the UI
   * can recover state on reconnect / server restart. Same DI rationale
   * as `usageLogger`: passed via params, not pulled from a singleton.
   */
  agentRunStore?: AgentRunStore;
  /**
   * Role type for the dispatched agent (e.g. "coder", "reviewer"). Used
   * by `usageLogger` so the JSONL has a `{role, taskType}` key suitable
   * for empirical baseline analysis. Pure passthrough — derive at the
   * call site so this module stays decoupled from agents.ts.
   */
  role?: string;
  /**
   * Identifier of the board card this dispatch is serving. Threaded through
   * `SubAgentResult.boardTaskId` so the server-side board-transition hook
   * (C.2) can advance the right card on dispatch finish. Absent for ad-hoc
   * dispatches.
   */
  boardTaskId?: string;
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
      ws: params.ws,
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

  /**
   * Cancel running agents. With `ws`, cancels only that ws's agents
   * (used on disconnect — must NOT take down peer agents). Without `ws`,
   * cancels everything (used on project switch / shutdown). Returns the
   * number of agents cancelled.
   */
  cancelAll(ws?: WebSocket): number {
    let n = 0;
    for (const [id, entry] of this.running) {
      if (ws && entry.ws !== ws) continue;
      entry.abortController.abort();
      this.running.delete(id);
      n++;
    }
    return n;
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
    const { agentId, task, projectCwd, gameState, projectMemory, traitStore, bypassPermissions, techLeadDigest, usageLogger, incidentLogger, agentRunStore, role } = params;

    let _timedOut = false;
    let _breakerTripped = false;
    let _breakerSnapshot: ReturnType<CircuitBreaker["snapshot"]> | null = null;
    const runId = newRunId("dispatch");
    const startedAt = new Date().toISOString();
    let _numTurns = 0;
    // Hoisted so the catch block can snapshot usage for interrupted runs
    // (timeouts, breaker trips, network errors all still cost money).
    let _breaker: CircuitBreaker | null = null;
    // C.2 — open the persistent run record. Status flips to its terminal
    // form in the success / catch paths.
    agentRunStore?.start({
      runId,
      agentId,
      taskType: "dispatch",
      userMessageSnippet: task.slice(0, 200),
      startedAt,
    });
    let _runPartial = "";
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

      // C.2.5 — hard timeout via Promise.race. The previous AbortController-only
      // timeout did NOT propagate when the SDK was blocked on a pending
      // multimodal HTTP fetch (e.g. `Read` on a PNG triggering a vision API
      // call that hangs). Without a Promise that *we own* resolving, the
      // for-await loop sat forever, the inner `finally` never fired, the
      // outer `.finally()` in `dispatch()` never freed the MAX_CONCURRENT
      // slot, and the system silently degraded to MAX_CONCURRENT-1 capacity
      // until restart. runWithHardTimeout guarantees runAgent resolves
      // within HARD_TIMEOUT_MS regardless of SDK state.
      const HARD_TIMEOUT_MS = params.hardTimeoutMs ?? 3 * 60_000;

      // C.2.4 circuit breaker — same safety policy as the main manager
      // query: cap cost ($5) + tool calls (30) per sub-agent run.
      const breaker = new CircuitBreaker(model);
      _breaker = breaker;

      const _forAwaitWork = async () => {
        for await (const message of q) {
          // Forward all messages for real-time UI updates
          params.onMessage(message, agentId, dispatchId);

          // Collect result
          if (message.type === "assistant") {
            const asst = message as SDKAssistantMessage;
            // Only collect text from top-level messages (no parent)
            if (!asst.parent_tool_use_id) {
              let _msgText = "";
              for (const block of asst.message.content) {
                if (block.type === "text") {
                  _msgText += (block as { type: "text"; text: string }).text;
                }
                // C.2 — surface tool_use into the persistent run record.
                if (block.type === "tool_use" && agentRunStore) {
                  agentRunStore.appendToolCall(runId, {
                    name: block.name,
                    id: block.id,
                    at: new Date().toISOString(),
                  });
                }
              }
              if (_msgText) {
                resultText += _msgText;
                _runPartial += _msgText;
                agentRunStore?.update(runId, { partialOutput: _runPartial });
              }
            }
            // Breaker observation — same logic as runQuery in server.ts.
            const trip = breaker.observeAssistantMessage(
              asst.message.usage as unknown as
                | { input_tokens?: number; output_tokens?: number; cache_creation_input_tokens?: number; cache_read_input_tokens?: number }
                | null
                | undefined,
              asst.message.content,
            );
            if (trip) {
              _breakerTripped = true;
              _breakerSnapshot = breaker.snapshot();
              abortController.abort();
            }
          }

          if (message.type === "result") {
            const res = message as SDKResultMessage;
            costUsd = res.total_cost_usd ?? 0;
            durationMs = res.duration_ms ?? 0;
            _numTurns = res.num_turns ?? 0;
            const resText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";
            if (resText && !resultText) {
              resultText = resText;
            }
          }
        }
      };

      try {
      await runWithHardTimeout(_forAwaitWork, HARD_TIMEOUT_MS, {
        onTimeout: () => {
          _timedOut = true;
          try {
            abortController.abort();
          } catch {
            // SDK abort() can throw on some paths; we'll surface via
            // the catch block's _timedOut branch regardless.
          }
        },
        message: `Sub-agent ${agentId} hard timeout (${HARD_TIMEOUT_MS / 1000}s) — for-await did not yield`,
      });

      if (usageLogger) {
        const snap = breaker.snapshot();
        usageLogger.record({
          runId,
          role: role ?? agentId,
          taskType: "dispatch",
          agentId,
          inputTokens: snap.inputTokens,
          outputTokens: snap.outputTokens,
          cacheCreationTokens: snap.cacheCreateTokens,
          cacheReadTokens: snap.cacheReadTokens,
          costUsd,
          durationMs,
          numTurns: _numTurns,
          numToolCalls: snap.toolCalls,
          startedAt,
          completedAt: new Date().toISOString(),
        });
      }
      // C.2.5 — no-op detection. A sub-agent that finishes a "real" task
      // (i.e. not interrupted, not breaker-tripped) with zero tool calls
      // produced no concrete artifact. Either the dispatched task was
      // trivially text-only (legit) or the agent silently hallucinated
      // doing work (the cascading-hallucination risk). Either way, the
      // rate over time is informative — record and move on.
      if (incidentLogger) {
        const snap = breaker.snapshot();
        if (isNoOpRun(snap.toolCalls)) {
          incidentLogger.record({
            incidentId: newIncidentId("no_op_run"),
            kind: "no_op_run",
            runId,
            role: role ?? agentId,
            taskType: "dispatch",
            agentId,
            occurredAt: new Date().toISOString(),
            details: {
              resultTextLength: resultText.length,
              durationMs,
              numTurns: _numTurns,
            },
          });
        }
      }
      if (agentRunStore) {
        const snap = breaker.snapshot();
        agentRunStore.update(runId, {
          status: "completed",
          finalOutput: resultText,
          usage: {
            inputTokens: snap.inputTokens,
            outputTokens: snap.outputTokens,
            cacheCreationTokens: snap.cacheCreateTokens,
            cacheReadTokens: snap.cacheReadTokens,
            costUsd,
            numTurns: _numTurns,
            numToolCalls: snap.toolCalls,
          },
        });
      }

      params.onComplete({
        dispatchId,
        agentId,
        text: resultText,
        costUsd,
        durationMs,
        boardTaskId: params.boardTaskId,
      });
      } finally {
        // runWithHardTimeout owns its own timer cleanup; nothing to do here.
        // Kept as `finally` for the structural symmetry around the inner
        // try — if more cleanup lands later, this is its home.
      }
    } catch (err) {
      // Abort with neither timeout nor breaker = explicit user cancel.
      const explicitCancel =
        abortController.signal.aborted && !_timedOut && !_breakerTripped;
      if (explicitCancel) {
        agentRunStore?.update(runId, {
          status: "cancelled",
          partialOutput: _runPartial || undefined,
        });
        return;
      }
      // _breakerSnapshot is assigned inside the for-await IIFE; TS'
      // control-flow analysis can't trace that assignment through the
      // async closure boundary and ends up narrowing the type to `never`
      // here. Re-snapshot from `_breaker` (assigned in the outer scope) —
      // CircuitBreaker holds the trip state internally so the snapshot
      // is identical, and the type stays `CircuitBreaker | null`.
      const _trippedMsg =
        _breaker?.snapshot().tripped?.message ?? "circuit breaker tripped";
      const errMsg = _breakerTripped
        ? `Sub-agent ${agentId} stopped: ${_trippedMsg}`
        : _timedOut
          ? `Sub-agent ${agentId} timed out after 3 minutes`
          : err instanceof Error ? err.message : String(err);
      // C.2 — flip persistent run to terminal status. Interrupted covers
      // breaker / timeout; everything else is a failure.
      if (agentRunStore) {
        const snap = _breaker?.snapshot();
        agentRunStore.update(runId, {
          status: _breakerTripped || _timedOut ? "interrupted" : "failed",
          reason: errMsg,
          partialOutput: _runPartial || undefined,
          usage: snap
            ? {
                inputTokens: snap.inputTokens,
                outputTokens: snap.outputTokens,
                cacheCreationTokens: snap.cacheCreateTokens,
                cacheReadTokens: snap.cacheReadTokens,
                costUsd: snap.costUsd,
                numTurns: _numTurns,
                numToolCalls: snap.toolCalls,
              }
            : undefined,
        });
      }
      // Record partial usage even on interruption — breaker / timeout runs
      // still cost money and belong in the baseline distribution.
      if (usageLogger && _breaker) {
        const snap = _breaker.snapshot();
        usageLogger.record({
          runId,
          role: role ?? agentId,
          taskType: "dispatch",
          agentId,
          inputTokens: snap.inputTokens,
          outputTokens: snap.outputTokens,
          cacheCreationTokens: snap.cacheCreateTokens,
          cacheReadTokens: snap.cacheReadTokens,
          costUsd: snap.costUsd,
          durationMs: Date.now() - new Date(startedAt).getTime(),
          numTurns: _numTurns,
          numToolCalls: snap.toolCalls,
          startedAt,
          completedAt: new Date().toISOString(),
        });
      }
      params.onError(agentId, dispatchId, errMsg);
    }
  }
}
