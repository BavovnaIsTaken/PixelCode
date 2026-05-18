/**
 * Anchor-prompt invariants for the dispatch MCP tool.
 *
 * These tests pin the load-bearing phrases that prevent the
 * C.2.5 "manager fabricates Готово right after dispatch" failure mode.
 * If you edit dispatch_prompts.ts, keep these anchors verbatim or update
 * both the implementation and these expectations together.
 *
 * Why pin literals: the strings here are fresh-context anchors a Claude
 * manager-LLM sees immediately after calling dispatch. Rewording quietly
 * (e.g. dropping "Готово" or "fabrication") regresses the protection
 * without breaking compile.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DISPATCH_TOOL_DESCRIPTION,
  buildDispatchReturnString,
  extractDispatchIdFromToolResult,
} from "../src/dispatch_prompts.js";

test("DISPATCH_TOOL_DESCRIPTION carries entity-validation rule (C.2.5 I2)", () => {
  // Manager must be told to resolve named entities BEFORE dispatching,
  // not after. The Glob/Grep mention prevents adding a separate
  // find_entity MCP tool — the rule lives in the description instead.
  assert.match(DISPATCH_TOOL_DESCRIPTION, /resolve it via Glob\/Grep/);
  assert.match(DISPATCH_TOOL_DESCRIPTION, /never dispatch to 'update' an entity whose existence/);
  assert.match(DISPATCH_TOOL_DESCRIPTION, /ASK the user to clarify/);
});

test("DISPATCH_TOOL_DESCRIPTION preserves fire-and-forget contract", () => {
  // The fire-and-forget semantics is by-design (see agents.ts:282,742).
  // The new entity-validation rule must NOT remove the "don't wait"
  // language that drives the rest of the manager loop.
  assert.match(DISPATCH_TOOL_DESCRIPTION, /works independently/);
  assert.match(DISPATCH_TOOL_DESCRIPTION, /System notification.*confirm completion/);
});

test("buildDispatchReturnString includes dispatch_id and agentId", () => {
  const text = buildDispatchReturnString("character-artist#1", "dispatch_42_1700000000");
  assert.match(text, /character-artist#1/);
  assert.match(text, /dispatch_42_1700000000/);
});

test("buildDispatchReturnString forbids fabricating 'Готово' (C.2.5 I1)", () => {
  const text = buildDispatchReturnString("coder#1", "dispatch_1_2");
  // The Ukrainian "Готово" is the literal token the model would otherwise
  // emit — naming it directly in the anchor is what makes the rule stick.
  assert.match(text, /Готово/);
  assert.match(text, /DO NOT report this as "Готово"/);
  assert.match(text, /fabrication/);
});

test("buildDispatchReturnString offers concrete valid status options", () => {
  const text = buildDispatchReturnString("reviewer#1", "dispatch_x_y");
  // A negative-only rule ("don't say Готово") is weaker than negative+positive;
  // the model needs a redirect target for its next turn.
  assert.match(text, /Працюємо над/);
  assert.match(text, /reviewer#1 ще працює над/);
});

test("buildDispatchReturnString references the specific dispatch_id in the wait condition", () => {
  // Anchoring the wait condition to *this specific* dispatch_id (not
  // "any" notification) prevents cross-contamination when multiple
  // dispatches are in-flight: the manager must wait for the exact one.
  const text = buildDispatchReturnString("ui-ux-designer#1", "dispatch_99_abc");
  assert.match(text, /dispatch_id=dispatch_99_abc/);
});

test("extractDispatchIdFromToolResult is the inverse of buildDispatchReturnString", () => {
  // The roundtrip is what makes the C.2.5 detector work: server.ts scrapes
  // dispatch_ids from tool_result text by parsing exactly what dispatchTool
  // produced. If the produce/parse pair drifts, the detector silently
  // stops correlating claims to in-flight dispatches.
  const text = buildDispatchReturnString("coder#1", "dispatch_42_1700000000");
  const extracted = extractDispatchIdFromToolResult(text);
  assert.equal(extracted, "dispatch_42_1700000000");
});

test("extractDispatchIdFromToolResult returns null for non-dispatch text", () => {
  assert.equal(extractDispatchIdFromToolResult("Some random tool_result."), null);
  assert.equal(extractDispatchIdFromToolResult(""), null);
  assert.equal(extractDispatchIdFromToolResult("Task dispatched to X (ID: not-a-dispatch-id)"), null);
});

test("extractDispatchIdFromToolResult finds id even with surrounding whitespace", () => {
  // SDK can wrap tool_result content in arrays of text blocks that get
  // joined with extra newlines — make sure the regex is whitespace-tolerant.
  const text = "  Task dispatched to character-artist#1 (ID: dispatch_1_2). They are working...";
  assert.equal(extractDispatchIdFromToolResult(text), "dispatch_1_2");
});
