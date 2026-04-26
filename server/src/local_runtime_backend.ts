/**
 * Local runtime backend using Gemini CLI.
 *
 * Wraps LocalGeminiRunner to implement the AgentBackend interface.
 * Provides health checks, timeout handling, and error recovery.
 */

import { LocalGeminiRunner } from "./local_gemini_runner.js";
import type { AgentBackend, BackendResult } from "./agent_backend.js";

export class LocalRuntimeBackend implements AgentBackend {
  private runner = new LocalGeminiRunner();
  private timeoutMs = 30000; // 30 seconds default

  async isAvailable(): Promise<boolean> {
    try {
      // Quick health check: try a minimal query
      await this.execute("ping", "Respond with 'pong'.", "haiku");
      return true;
    } catch {
      return false;
    }
  }

  async execute(
    prompt: string,
    systemPrompt: string,
    model: string
  ): Promise<BackendResult> {
    const startTime = Date.now();

    try {
      const result = await Promise.race([
        this.runner.query({
          agentId: "backend-agent",
          systemPrompt,
          userMessage: prompt,
          onText: () => {
            // Optionally log streamed text here
          },
        }),
        this.createTimeout(this.timeoutMs),
      ]);

      const durationMs = Date.now() - startTime;

      return {
        text: result.result,
        durationMs,
        costUsd: result.total_cost_usd, // Always 0 for local
      };
    } catch (error) {
      const durationMs = Date.now() - startTime;

      // Re-throw with context
      if (error instanceof Error) {
        throw new Error(`Local backend error (${durationMs}ms): ${error.message}`);
      }

      throw error;
    }
  }

  private createTimeout(ms: number): Promise<never> {
    return new Promise((_, reject) => {
      setTimeout(() => {
        reject(new Error(`Local execution timeout (${ms}ms)`));
      }, ms);
    });
  }

  setTimeoutMs(ms: number): void {
    this.timeoutMs = ms;
  }
}
