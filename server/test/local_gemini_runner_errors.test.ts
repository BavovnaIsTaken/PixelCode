import { test } from "node:test";
import assert from "node:assert/strict";

import {
  LocalGeminiError,
  classifyGeminiError,
  tryParseGeminiJson,
} from "../src/gemini_errors.js";

test("classifyGeminiError detects quota exhaustion", () => {
  const err = classifyGeminiError(
    { message: "You have exhausted your capacity on this model.", code: 429 },
    "",
  );
  assert.equal(err.kind, "quota_exhausted");
  assert.ok(err instanceof LocalGeminiError);
});

test("classifyGeminiError extracts retryDelayMs from stderr", () => {
  const err = classifyGeminiError(
    { message: "quota exhausted" },
    "retryDelayMs: 26905031",
  );
  assert.equal(err.kind, "quota_exhausted");
  assert.equal(err.retryAfterMs, 26905031);
});

test("classifyGeminiError parses 'reset after Xh Ym Zs'", () => {
  const err = classifyGeminiError(
    { message: "exhausted, reset after 7h28m25s" },
    "",
  );
  assert.equal(err.kind, "quota_exhausted");
  assert.equal(err.retryAfterMs, ((7 * 3600) + (28 * 60) + 25) * 1000);
});

test("classifyGeminiError detects auth errors", () => {
  const err = classifyGeminiError(
    { message: "unauthenticated, please run gemini to login", code: 401 },
    "",
  );
  assert.equal(err.kind, "not_authenticated");
});

test("classifyGeminiError falls back to process_error", () => {
  const err = classifyGeminiError({ message: "something else broke" }, "");
  assert.equal(err.kind, "process_error");
});

test("tryParseGeminiJson skips warnings before JSON", () => {
  const text = `Warning: 256-color support not detected.\n{"session_id":"abc","response":"hi"}`;
  const parsed = tryParseGeminiJson(text);
  assert.deepEqual(parsed, { session_id: "abc", response: "hi" });
});

test("tryParseGeminiJson returns null on garbage", () => {
  assert.equal(tryParseGeminiJson("no json here"), null);
});

test("tryParseGeminiJson returns null on unbalanced JSON", () => {
  assert.equal(tryParseGeminiJson("{not really json"), null);
});
