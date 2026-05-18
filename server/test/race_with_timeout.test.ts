/**
 * Tests for the C.2.5 Promise.race hard-timeout primitive.
 *
 * What we pin here:
 *   - A never-resolving work() rejects within hardTimeoutMs + grace
 *     (regression test for the 14m23s stall — the real-world failure
 *     mode the primitive is designed against).
 *   - A fast work() resolves normally and the timer is cleared.
 *   - onTimeout fires synchronously on the timeout path; not at all on
 *     the success path.
 *   - Exceptions inside onTimeout don't replace the timeout error.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { runWithHardTimeout } from "../src/race_with_timeout.js";

test("never-resolving work rejects within hardTimeoutMs + grace", async () => {
  const HARD_MS = 50;
  const t0 = Date.now();
  await assert.rejects(
    runWithHardTimeout<void>(() => new Promise(() => {}), HARD_MS),
    /hard timeout/,
  );
  const elapsed = Date.now() - t0;
  // Grace ceiling generous on purpose — slow CI shouldn't break this.
  assert.ok(elapsed >= HARD_MS, `elapsed ${elapsed}ms < HARD_MS ${HARD_MS}ms`);
  assert.ok(elapsed < HARD_MS + 200, `elapsed ${elapsed}ms way over budget`);
});

test("work that resolves before timeout returns normally", async () => {
  const HARD_MS = 1000;
  const t0 = Date.now();
  const result = await runWithHardTimeout(
    async () => {
      await new Promise((r) => setTimeout(r, 20));
      return 42;
    },
    HARD_MS,
  );
  const elapsed = Date.now() - t0;
  assert.equal(result, 42);
  assert.ok(elapsed < 100, `elapsed ${elapsed}ms suggests timer not cleared`);
});

test("onTimeout fires on the timeout path", async () => {
  let onTimeoutCalled = false;
  await assert.rejects(
    runWithHardTimeout(() => new Promise(() => {}), 30, {
      onTimeout: () => {
        onTimeoutCalled = true;
      },
    }),
    /hard timeout/,
  );
  assert.equal(onTimeoutCalled, true);
});

test("onTimeout does NOT fire on the success path", async () => {
  let onTimeoutCalled = false;
  const result = await runWithHardTimeout(
    async () => "done",
    1000,
    {
      onTimeout: () => {
        onTimeoutCalled = true;
      },
    },
  );
  assert.equal(result, "done");
  // Give the timeout a chance to fire if it was going to (sanity).
  await new Promise((r) => setTimeout(r, 50));
  assert.equal(onTimeoutCalled, false, "onTimeout fired despite work completing first");
});

test("exception inside onTimeout does not replace the hard-timeout error", async () => {
  // If onTimeout throws while flipping caller-side flags, the user-facing
  // error should still say "hard timeout" — not the secondary exception.
  await assert.rejects(
    runWithHardTimeout(() => new Promise(() => {}), 30, {
      onTimeout: () => {
        throw new Error("flag flip exploded");
      },
    }),
    /hard timeout/,
  );
});

test("custom message is preserved", async () => {
  await assert.rejects(
    runWithHardTimeout(() => new Promise(() => {}), 20, {
      message: "Sub-agent X timed out",
    }),
    /Sub-agent X timed out/,
  );
});

test("regression scenario: SDK-stuck-on-multimodal shape resolves within budget", async () => {
  // Simulate the 2026-05-18 incident: imagine the SDK is mid-fetch on
  // a vision API call that never returns. for-await never yields, the
  // body of the wrapped async IIFE is awaiting forever. Before this
  // primitive, runAgent's Promise hung indefinitely and the
  // MAX_CONCURRENT slot leaked. With runWithHardTimeout, we resolve in
  // ~timeout + grace, allowing the dispatch().promise.finally() to
  // free the slot.
  const HARD_MS = 80;
  let slotFreed = false;
  const dispatchPromise = runWithHardTimeout(
    async () => {
      for await (const _ of (async function* hangForever() {
        await new Promise(() => {}); // never yields
      })()) {
        // Unreachable.
      }
    },
    HARD_MS,
    { onTimeout: () => { /* simulate abortController.abort() best-effort */ } },
  );
  dispatchPromise.catch(() => {}).finally(() => { slotFreed = true; });

  await assert.rejects(dispatchPromise, /hard timeout/);
  // Wait one microtask for the .finally() in the chain above to run.
  await new Promise((r) => setImmediate(r));
  assert.equal(slotFreed, true, "the .finally() that frees MAX_CONCURRENT must run");
});
