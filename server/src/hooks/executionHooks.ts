/**
 * Hook system for agent execution lifecycle events.
 *
 * Allows registering callbacks for key execution phases:
 * - beforeDispatch: before task is sent to agent
 * - afterExecution: after task completes
 * - onError: when execution fails
 * - onLearning: when lessons are extracted
 */

export type HookName =
  | "beforeDispatch"
  | "afterExecution"
  | "onError"
  | "onLearning";

/**
 * Payload passed to all hook callbacks.
 * Core fields are required; additional context can be added via [key: string]: any
 */
export interface HookPayload {
  timestamp: number; // Unix timestamp in ms
  agentId: string;
  sessionId: string;
  [key: string]: any; // Flexible additional fields
}

type HookCallback = (payload: HookPayload) => Promise<void> | void;

/**
 * ExecutionHooks — manages registration and execution of lifecycle hooks.
 * Catches and logs errors in callbacks to prevent hook failures from crashing execution.
 */
export class ExecutionHooks {
  private readonly _hooks: Map<HookName, HookCallback[]> = new Map();

  constructor() {
    // Initialize hook arrays for each hook type
    (["beforeDispatch", "afterExecution", "onError", "onLearning"] as const).forEach(
      (name) => {
        this._hooks.set(name, []);
      }
    );

    // Register built-in afterExecution hook for logging lessons
    this.register("afterExecution", this._logLessons.bind(this));
  }

  /**
   * Register a callback for a specific hook.
   * Multiple callbacks can be registered for the same hook.
   */
  register(hookName: HookName, callback: HookCallback): void {
    const hooks = this._hooks.get(hookName);
    if (hooks) {
      hooks.push(callback);
    }
  }

  /**
   * Fire all callbacks registered for a hook.
   * Runs all callbacks asynchronously, catching errors to prevent cascading failures.
   */
  async fire(hookName: HookName, payload: HookPayload): Promise<void> {
    const hooks = this._hooks.get(hookName);
    if (!hooks || hooks.length === 0) {
      return;
    }

    const promises = hooks.map((callback) =>
      Promise.resolve()
        .then(() => callback(payload))
        .catch((error) => {
          // Log error but don't throw — allow other hooks to run
          console.error(
            `[ExecutionHooks] Error in ${hookName} callback for agent ${payload.agentId}:`,
            error instanceof Error ? error.message : String(error)
          );
        })
    );

    await Promise.all(promises);
  }

  /**
   * Built-in hook: logs lessons/insights extracted during execution.
   * This demonstrates the hook pattern for learning and analytics.
   */
  private async _logLessons(payload: HookPayload): Promise<void> {
    // Check if lessons are included in the payload
    if (payload.lessons && Array.isArray(payload.lessons) && payload.lessons.length > 0) {
      console.log(
        `[Lessons] Agent ${payload.agentId} learned: ${payload.lessons.join(", ")}`
      );
    }
  }
}

/**
 * Singleton instance of ExecutionHooks.
 * Used throughout the application for hook management.
 */
export const executionHooks = new ExecutionHooks();
