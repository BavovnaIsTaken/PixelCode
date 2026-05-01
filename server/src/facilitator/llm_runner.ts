/**
 * Run an LLM call with a hard timeout, one retry on transient failures,
 * and typed error reporting.
 *
 * The original facilitator pipeline collapsed every failure into
 * `failed: ${err}` — timeouts, parse errors, rate limits, and auth
 * problems all looked the same to the user. This module distinguishes
 * them so the WS layer can ship structured codes the client can act on
 * (retry button vs. settings prompt vs. "your style is broken").
 *
 * Pure module: timer/sleep are injectable so tests can drive the loop
 * without real wall-clock waits.
 */

export type LLMErrorKind =
  | "timeout"
  | "parse"
  | "rate_limit"
  | "auth"
  | "unknown";

/** Distinguishable error so the WS layer can emit a `code` field. */
export class LLMGenerationError extends Error {
  constructor(
    readonly kind: LLMErrorKind,
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = "LLMGenerationError";
  }
}

export interface RunOptions {
  /** Hard ceiling per attempt. Defaults to 60s. */
  timeoutMs?: number;
  /** Extra attempts on transient failure (default 1 — i.e. up to 2 calls). */
  retries?: number;
  /** Backoff before each retry. Default 3000ms. */
  retryDelayMs?: number;
  // Injection points for deterministic tests.
  setTimeoutFn?: (cb: () => void, ms: number) => unknown;
  clearTimeoutFn?: (handle: unknown) => void;
  sleepFn?: (ms: number) => Promise<void>;
}

/**
 * Heuristic for "transient" errors that justify a retry. Matches:
 *   - timeouts (`LLMGenerationError` of kind `timeout`)
 *   - HTTP 5xx and 429 in the message (the SDK throws Errors with the
 *     status code in the message; we don't have a typed surface yet)
 *   - common network errors (ECONNRESET, ETIMEDOUT, fetch failed)
 *
 * Parse errors and auth errors are deliberately NOT retried — repeating
 * the call won't fix them.
 */
export function isTransient(err: unknown): boolean {
  if (err instanceof LLMGenerationError) {
    return err.kind === "timeout" || err.kind === "rate_limit";
  }
  const msg = err instanceof Error ? err.message : String(err);
  return (
    /\b(5\d\d|429)\b/.test(msg) ||
    /ECONNRESET|ETIMEDOUT|ENETUNREACH|fetch failed|socket hang up/i.test(msg)
  );
}

/**
 * Map an arbitrary error onto an `LLMGenerationError`. Already-typed
 * errors pass through; everything else becomes `unknown`.
 */
export function classifyError(err: unknown): LLMGenerationError {
  if (err instanceof LLMGenerationError) return err;
  const msg = err instanceof Error ? err.message : String(err);
  if (/\b401\b|invalid.*api.*key|unauthorized/i.test(msg)) {
    return new LLMGenerationError("auth", msg, err);
  }
  if (/\b429\b|rate.?limit/i.test(msg)) {
    return new LLMGenerationError("rate_limit", msg, err);
  }
  return new LLMGenerationError("unknown", msg, err);
}

const defaultSleep = (ms: number) =>
  new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * Run `fn` with a per-attempt timeout. On transient failure, sleep and
 * retry up to `retries` extra times. Parse and auth errors throw
 * immediately (no point retrying).
 */
export async function runWithTimeoutAndRetry<T>(
  fn: () => Promise<T>,
  opts: RunOptions = {},
): Promise<T> {
  const timeoutMs = opts.timeoutMs ?? 60_000;
  const retries = opts.retries ?? 1;
  const retryDelayMs = opts.retryDelayMs ?? 3000;
  const setTimeoutFn =
    opts.setTimeoutFn ?? ((cb: () => void, ms: number) => setTimeout(cb, ms));
  const clearTimeoutFn =
    opts.clearTimeoutFn ??
    ((h: unknown) => clearTimeout(h as ReturnType<typeof setTimeout>));
  const sleep = opts.sleepFn ?? defaultSleep;

  let lastErr: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    let timer: unknown = null;
    try {
      const timeoutPromise = new Promise<never>((_resolve, reject) => {
        timer = setTimeoutFn(
          () =>
            reject(
              new LLMGenerationError(
                "timeout",
                `LLM call exceeded ${timeoutMs}ms`,
              ),
            ),
          timeoutMs,
        );
      });
      try {
        return await Promise.race([fn(), timeoutPromise]);
      } finally {
        if (timer !== null) clearTimeoutFn(timer);
      }
    } catch (e) {
      lastErr = e;
      // Parse and auth errors are terminal — never retry.
      if (e instanceof LLMGenerationError && (e.kind === "parse" || e.kind === "auth")) {
        throw e;
      }
      if (attempt < retries && isTransient(e)) {
        await sleep(retryDelayMs);
        continue;
      }
      throw classifyError(e);
    }
  }
  // Defensive: loop should always return or throw.
  throw classifyError(lastErr);
}
