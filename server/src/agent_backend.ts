/**
 * Abstract agent execution backend.
 *
 * Allows swapping Claude SDK, local Gemini, Ollama, or other models
 * without changing dungeon/runner logic.
 */

export interface BackendResult {
  /** Model output text. */
  text: string;
  /** Execution time in milliseconds. */
  durationMs: number;
  /** Cost in USD (0 for local backends). */
  costUsd: number;
}

export interface AgentBackend {
  /**
   * Execute a prompt with the given system prompt and model.
   * Returns text output and metrics.
   */
  execute(prompt: string, systemPrompt: string, model: string): Promise<BackendResult>;
}
