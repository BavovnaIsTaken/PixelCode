/**
 * Safety-net circuit breaker for SDK queries.
 *
 * NOT the primary cost control — per ROADMAP C.2, empirical per-role
 * baselines do the actual budgeting. This is the *emergency-only*
 * abort: if a runaway tool_use loop spends past $5 or fires more than
 * 30 tool calls, trip and let the caller `.abort()` the AbortController.
 *
 * Caller pattern (server.ts / agent_runner.ts):
 *   const breaker = new CircuitBreaker(modelKey);
 *   for await (const msg of query(...)) {
 *     if (msg.type === "assistant") {
 *       const trip = breaker.observeAssistantMessage(msg.message.usage, msg.message.content);
 *       if (trip) { queryAbort.abort(); break; }
 *     }
 *   }
 */

import { claudeCostUsd } from "./claude_pricing.js";

export interface CircuitBreakerOptions {
  /** Hard cost cap in USD. Default $5. */
  maxCostUsd?: number;
  /** Hard tool-call count cap. Default 30. */
  maxToolCalls?: number;
}

export interface CircuitBreakerTrip {
  reason: "cost_cap" | "tool_cap";
  message: string;
  costUsd: number;
  toolCalls: number;
}

interface UsageBlock {
  input_tokens?: number;
  output_tokens?: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
}

interface ContentBlockShape {
  type: string;
}

export class CircuitBreaker {
  private cumulativeInput = 0;
  private cumulativeOutput = 0;
  private cumulativeCacheCreate = 0;
  private cumulativeCacheRead = 0;
  private toolUseCount = 0;
  private tripped: CircuitBreakerTrip | null = null;

  readonly maxCostUsd: number;
  readonly maxToolCalls: number;

  constructor(
    private readonly model: string,
    opts: CircuitBreakerOptions = {}
  ) {
    this.maxCostUsd = opts.maxCostUsd ?? 5;
    this.maxToolCalls = opts.maxToolCalls ?? 30;
  }

  /**
   * Observe one SDK `assistant` message. Returns the trip object on the
   * very call that crossed a cap, then `null` on every subsequent call.
   *
   * `content` is the SDK assistant message's content blocks — used to count
   * `tool_use` occurrences (one per tool invocation).
   */
  observeAssistantMessage(
    usage: UsageBlock | null | undefined,
    content: ReadonlyArray<ContentBlockShape> | null | undefined
  ): CircuitBreakerTrip | null {
    if (this.tripped) return null;

    if (usage) {
      this.cumulativeInput += usage.input_tokens ?? 0;
      this.cumulativeOutput += usage.output_tokens ?? 0;
      this.cumulativeCacheCreate += usage.cache_creation_input_tokens ?? 0;
      this.cumulativeCacheRead += usage.cache_read_input_tokens ?? 0;
    }
    if (content) {
      for (const block of content) {
        if (block.type === "tool_use") this.toolUseCount++;
      }
    }

    const cost = this.currentCostUsd();
    if (cost >= this.maxCostUsd) {
      this.tripped = {
        reason: "cost_cap",
        message: `cost cap reached: $${cost.toFixed(2)} >= $${this.maxCostUsd}`,
        costUsd: cost,
        toolCalls: this.toolUseCount,
      };
      return this.tripped;
    }
    if (this.toolUseCount >= this.maxToolCalls) {
      this.tripped = {
        reason: "tool_cap",
        message: `tool-call cap reached: ${this.toolUseCount} >= ${this.maxToolCalls}`,
        costUsd: cost,
        toolCalls: this.toolUseCount,
      };
      return this.tripped;
    }
    return null;
  }

  /**
   * Cumulative cost estimate. Cache-creation tokens are billed at ~1.25x
   * the input rate (we approximate as 1.0x for simplicity — slight under-
   * estimate is acceptable for a safety net; bigger concern is over-trip).
   * Cache reads are ~0.1x input — included at full rate, again conservative
   * toward NOT tripping too eagerly.
   */
  currentCostUsd(): number {
    const inputLike =
      this.cumulativeInput +
      this.cumulativeCacheCreate +
      this.cumulativeCacheRead;
    return claudeCostUsd(this.model, inputLike, this.cumulativeOutput);
  }

  get toolCalls(): number {
    return this.toolUseCount;
  }

  get isTripped(): boolean {
    return this.tripped !== null;
  }

  /** Snapshot, useful for logging / persisting to AgentRun entity later. */
  snapshot(): {
    costUsd: number;
    toolCalls: number;
    inputTokens: number;
    outputTokens: number;
    cacheCreateTokens: number;
    cacheReadTokens: number;
    tripped: CircuitBreakerTrip | null;
  } {
    return {
      costUsd: this.currentCostUsd(),
      toolCalls: this.toolUseCount,
      inputTokens: this.cumulativeInput,
      outputTokens: this.cumulativeOutput,
      cacheCreateTokens: this.cumulativeCacheCreate,
      cacheReadTokens: this.cumulativeCacheRead,
      tripped: this.tripped,
    };
  }
}
