/**
 * Run an async unit of work with a guaranteed wall-clock deadline.
 *
 * The 2026-05-18 incident root cause: when the Claude SDK is blocked on
 * a pending multimodal HTTP fetch, calling `abortController.abort()`
 * does NOT yield the for-await loop — `await` never throws, never
 * resolves. AbortController-only timeouts therefore can't enforce a
 * deadline against an unresponsive SDK.
 *
 * `runWithHardTimeout` wraps the work in `Promise.race` against a timer
 * promise we own. When the timer wins, the resulting Promise rejects
 * regardless of the underlying SDK state — the caller's outer `.finally`
 * fires, the MAX_CONCURRENT slot is released, and the catch path runs.
 *
 * The `onTimeout` callback is fired synchronously when the timer wins
 * the race, so the caller can set flags (`_timedOut = true`) and signal
 * the SDK best-effort (`abortController.abort()`) before the throw
 * propagates. This is intentional: a stuck SDK that eventually wakes up
 * should know its context is no longer wanted.
 */

export interface RunWithHardTimeoutOptions {
  /**
   * Called when the timeout wins the race. Fired BEFORE the returned
   * Promise rejects. Use this to flip caller-owned flags (e.g.
   * `_timedOut = true`) and best-effort abort underlying resources.
   * Exceptions from this callback are swallowed so they don't replace
   * the timeout error.
   */
  onTimeout?: () => void;
  /**
   * Message of the Error thrown when the timeout wins. Default
   * `"hard timeout after Xms"`. Pin to a stable string when callers
   * branch on `err.message`.
   */
  message?: string;
}

export async function runWithHardTimeout<T>(
  work: () => Promise<T>,
  hardTimeoutMs: number,
  opts: RunWithHardTimeoutOptions = {},
): Promise<T> {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  let timeoutFired = false;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      timeoutFired = true;
      try {
        opts.onTimeout?.();
      } catch {
        // Caller-side flag flipping must not replace the timeout error.
      }
      reject(new Error(opts.message ?? `hard timeout after ${hardTimeoutMs}ms`));
    }, hardTimeoutMs);
  });
  // If work wins the race, the timeout promise rejects later — swallow
  // so Node doesn't emit an unhandled-rejection warning.
  timeoutPromise.catch(() => {});

  try {
    return await Promise.race([work(), timeoutPromise]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
    // `timeoutFired` is used only for telemetry by callers that want
    // it; we expose nothing back here. The decision was: keep the API
    // shape of `Promise<T>` so call sites read like a normal `await`.
    void timeoutFired;
  }
}
