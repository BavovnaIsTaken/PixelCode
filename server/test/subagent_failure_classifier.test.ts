/**
 * Tests for the C.2.5 sub-agent failure classifier — pins the message
 * patterns that agent_runner.ts emits in each terminal-error path.
 *
 * The contract is bidirectional: if agent_runner.ts changes its error
 * message string, these tests catch the drift before the UI silently
 * degrades to "error" for what's actually a timeout.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  classifySubAgentFailure,
} from "../src/subagent_failure_classifier.js";

test("hard-timeout message classified as timeout", () => {
  // Verbatim shape from agent_runner.ts runWithHardTimeout call.
  const msg = "Sub-agent character-artist#1 hard timeout (180s) — for-await did not yield";
  const r = classifySubAgentFailure(msg);
  assert.equal(r.reason, "timeout");
  assert.equal(r.message, msg);
});

test("legacy 'timed out after' message classified as timeout", () => {
  // Older code paths in agent_runner.ts catch block still use this form;
  // include it so a refactor that removes one but not the other doesn't
  // produce inconsistent UI behavior.
  const msg = "Sub-agent coder#1 timed out after 3 minutes";
  assert.equal(classifySubAgentFailure(msg).reason, "timeout");
});

test("breaker-trip message classified as breaker", () => {
  const msg = "Sub-agent reviewer#1 stopped: circuit breaker tripped — cost cap $5 exceeded";
  const r = classifySubAgentFailure(msg);
  assert.equal(r.reason, "breaker");
});

test("breaker variant phrasing also classified as breaker", () => {
  const msg = "Run halted: breaker tripped";
  assert.equal(classifySubAgentFailure(msg).reason, "breaker");
});

test("network / SDK error classified as generic error", () => {
  const msg = "ECONNRESET: connection reset by peer";
  const r = classifySubAgentFailure(msg);
  assert.equal(r.reason, "error");
  assert.equal(r.message, msg);
});

test("unknown shape falls back to error (safe default)", () => {
  // The safe default matters: the UI should not suggest "retry" for an
  // unrecognized shape — could be a budget-exhaustion failure mode we
  // don't yet recognize as breaker.
  const r = classifySubAgentFailure("something completely unexpected");
  assert.equal(r.reason, "error");
});

test("empty message → error (no false-positive classification)", () => {
  assert.equal(classifySubAgentFailure("").reason, "error");
});
