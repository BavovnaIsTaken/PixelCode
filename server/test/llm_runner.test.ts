import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  LLMGenerationError,
  classifyError,
  isTransient,
  runWithTimeoutAndRetry,
} from "../src/facilitator/llm_runner.ts";

const noWait = { sleepFn: async (_ms: number) => {} };

describe("isTransient", () => {
  test("recognises HTTP 5xx and 429 in plain Errors", () => {
    assert.equal(isTransient(new Error("upstream returned 502 bad gateway")), true);
    assert.equal(isTransient(new Error("rate limit (429)")), true);
    assert.equal(isTransient(new Error("503")), true);
  });

  test("recognises common network error tokens", () => {
    assert.equal(isTransient(new Error("ECONNRESET")), true);
    assert.equal(isTransient(new Error("ETIMEDOUT")), true);
    assert.equal(isTransient(new Error("fetch failed")), true);
    assert.equal(isTransient(new Error("socket hang up")), true);
  });

  test("LLMGenerationError(timeout) is transient", () => {
    assert.equal(isTransient(new LLMGenerationError("timeout", "x")), true);
  });

  test("LLMGenerationError(rate_limit) is transient", () => {
    assert.equal(isTransient(new LLMGenerationError("rate_limit", "x")), true);
  });

  test("LLMGenerationError(parse) is NOT transient", () => {
    assert.equal(isTransient(new LLMGenerationError("parse", "x")), false);
  });

  test("LLMGenerationError(auth) is NOT transient", () => {
    assert.equal(isTransient(new LLMGenerationError("auth", "x")), false);
  });

  test("400/404 are not transient", () => {
    assert.equal(isTransient(new Error("400 bad request")), false);
    assert.equal(isTransient(new Error("404 not found")), false);
  });
});

describe("classifyError", () => {
  test("preserves an existing LLMGenerationError", () => {
    const e = new LLMGenerationError("parse", "boom");
    assert.equal(classifyError(e), e);
  });

  test("maps 401 / unauthorized → auth", () => {
    assert.equal(classifyError(new Error("401 unauthorized")).kind, "auth");
    assert.equal(classifyError(new Error("invalid api key")).kind, "auth");
  });

  test("maps 429 → rate_limit", () => {
    assert.equal(classifyError(new Error("429 too many")).kind, "rate_limit");
    assert.equal(classifyError(new Error("rate-limit hit")).kind, "rate_limit");
  });

  test("falls back to unknown for plain errors", () => {
    assert.equal(classifyError(new Error("something broke")).kind, "unknown");
    assert.equal(classifyError("string error").kind, "unknown");
  });
});

describe("runWithTimeoutAndRetry", () => {
  test("returns immediately when fn resolves on first call", async () => {
    let calls = 0;
    const result = await runWithTimeoutAndRetry(async () => {
      calls++;
      return 42;
    }, noWait);
    assert.equal(result, 42);
    assert.equal(calls, 1);
  });

  test("converts a hung call into LLMGenerationError(timeout)", async () => {
    // The fn never resolves; we rely on the injected timeout to fire.
    const fn = () => new Promise<number>(() => { /* never */ });
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { timeoutMs: 5, retries: 0, ...noWait }),
      (e) => e instanceof LLMGenerationError && e.kind === "timeout",
    );
  });

  test("retries once on a transient error then succeeds", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      if (calls === 1) throw new Error("502 bad gateway");
      return "ok";
    };
    const result = await runWithTimeoutAndRetry(fn, { retries: 1, ...noWait });
    assert.equal(result, "ok");
    assert.equal(calls, 2);
  });

  test("propagates the last error after retry exhaustion", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      throw new Error("503 still down");
    };
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { retries: 1, ...noWait }),
      (e) => e instanceof LLMGenerationError && e.kind === "unknown",
    );
    assert.equal(calls, 2, "fn called once + one retry");
  });

  test("does not retry parse errors", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      throw new LLMGenerationError("parse", "not json");
    };
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { retries: 3, ...noWait }),
      (e) => e instanceof LLMGenerationError && e.kind === "parse",
    );
    assert.equal(calls, 1);
  });

  test("does not retry auth errors", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      throw new LLMGenerationError("auth", "401 unauthorized");
    };
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { retries: 3, ...noWait }),
      (e) => e instanceof LLMGenerationError && e.kind === "auth",
    );
    assert.equal(calls, 1);
  });

  test("respects retries=0 — fail without retry on transient", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      throw new Error("502 transient");
    };
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { retries: 0, ...noWait }),
      LLMGenerationError,
    );
    assert.equal(calls, 1);
  });

  test("waits the configured backoff between attempts", async () => {
    let sleepObserved = -1;
    const sleepFn = async (ms: number) => {
      sleepObserved = ms;
    };
    let calls = 0;
    const fn = async () => {
      calls++;
      if (calls === 1) throw new Error("503");
      return "ok";
    };
    await runWithTimeoutAndRetry(fn, { retries: 1, retryDelayMs: 1234, sleepFn });
    assert.equal(sleepObserved, 1234);
    assert.equal(calls, 2);
  });

  test("does not retry plain non-transient errors", async () => {
    let calls = 0;
    const fn = async () => {
      calls++;
      throw new Error("400 malformed payload");
    };
    await assert.rejects(
      runWithTimeoutAndRetry(fn, { retries: 3, ...noWait }),
      LLMGenerationError,
    );
    assert.equal(calls, 1);
  });
});
