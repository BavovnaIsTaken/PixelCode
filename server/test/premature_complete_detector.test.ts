/**
 * Tests for the C.2.5 premature-complete detector — the pure logic that
 * powers `manager_premature_complete_rate` in the daily-control surface.
 *
 * Coverage matrix:
 *   - No dispatches → never fabricated (baseline)
 *   - Dispatch + claim + unresolved → fabricated
 *   - Dispatch + claim + resolved → not fabricated (legit completion report)
 *   - Dispatch + no claim → not fabricated
 *   - Multiple dispatches, partial resolution → fabricated on unresolved
 *   - Pattern variants (Готово / Done / Completed, with/without colon, with leading punctuation)
 *   - Negative cases the regex must NOT match (готовий, прогрес, etc.)
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  COMPLETION_CLAIM_PATTERN,
  detectPrematureComplete,
  stripPrematureCompleteClaim,
} from "../src/premature_complete_detector.js";

test("no dispatches in turn → not fabricated", () => {
  const r = detectPrematureComplete({
    dispatchedIds: [],
    managerOutputText: "Готово: все зроблено.",
    resolvedDispatchIds: [],
  });
  assert.equal(r.fabricated, false);
  assert.deepEqual(r.unmatchedDispatchIds, []);
  assert.equal(r.matchedClaim, null);
});

test("incident shape: dispatch + 'Готово: ...' + unresolved → fabricated", () => {
  const r = detectPrematureComplete({
    dispatchedIds: ["dispatch_1_1700000000"],
    managerOutputText:
      "Готово: спрайти Мурчика оновлені з покращеною анімацією ходьби.",
    resolvedDispatchIds: [],
  });
  assert.equal(r.fabricated, true);
  assert.deepEqual(r.unmatchedDispatchIds, ["dispatch_1_1700000000"]);
  assert.ok(r.matchedClaim !== null);
  assert.match(r.matchedClaim!, /Готово/);
});

test("dispatch + claim + all resolved → not fabricated (legit completion)", () => {
  const r = detectPrematureComplete({
    dispatchedIds: ["dispatch_1_x"],
    managerOutputText: "Готово: задача виконана агентом.",
    resolvedDispatchIds: ["dispatch_1_x"],
  });
  assert.equal(r.fabricated, false);
  assert.deepEqual(r.unmatchedDispatchIds, []);
});

test("dispatch + no completion claim in text → not fabricated", () => {
  const r = detectPrematureComplete({
    dispatchedIds: ["dispatch_1_x"],
    managerOutputText: "Працюємо над оновленням спрайтів.",
    resolvedDispatchIds: [],
  });
  assert.equal(r.fabricated, false);
  assert.deepEqual(r.unmatchedDispatchIds, ["dispatch_1_x"]);
  assert.equal(r.matchedClaim, null);
});

test("multiple dispatches, partial resolution → fabricated on the unresolved", () => {
  const r = detectPrematureComplete({
    dispatchedIds: ["dispatch_a", "dispatch_b", "dispatch_c"],
    managerOutputText: "Готово: усе зробив.",
    resolvedDispatchIds: ["dispatch_a"],
  });
  assert.equal(r.fabricated, true);
  assert.deepEqual(r.unmatchedDispatchIds, ["dispatch_b", "dispatch_c"]);
});

test("pattern matches Done: and Completed: (English variants)", () => {
  const variants = [
    "Done: refactored auth.ts.",
    "Completed: shipped fix.",
    "Done : trailing space colon variant.",
  ];
  for (const text of variants) {
    const r = detectPrematureComplete({
      dispatchedIds: ["d1"],
      managerOutputText: text,
      resolvedDispatchIds: [],
    });
    assert.equal(r.fabricated, true, `expected fabricated for: ${text}`);
  }
});

test("pattern does NOT match Ukrainian adjective 'готовий' / partial-progress phrases", () => {
  // The detector must NOT fire on:
  //   - "готовий" (adjective form, not the verb-like "Готово:")
  //   - "не готово" (negation — same surface form but contextual)
  //   - "готовність" (different word)
  // For the daily-control rate to be useful, false positives on legit
  // progress reports would drown the real signal.
  const benign = [
    "Працюємо. Агент готовий взятися за задачу.",
    "Прогрес: пишемо тести.",
    "Готовність команди: 3/5 агентів."
  ];
  for (const text of benign) {
    assert.equal(
      COMPLETION_CLAIM_PATTERN.test(text),
      false,
      `regex should not match benign text: ${text}`,
    );
  }
});

test("pattern requires a colon (not just the word 'Готово')", () => {
  // "Готово" without a colon is too ambiguous (could be interjection,
  // could be plain status). The colon-form is what the manager LLM
  // emits in the failure-mode incident; that's our anchor.
  assert.equal(COMPLETION_CLAIM_PATTERN.test("Готово."), false);
  assert.equal(COMPLETION_CLAIM_PATTERN.test("Готово!"), false);
});

test("pattern handles leading punctuation / newline / bullet", () => {
  // The detector runs over concatenated manager output that may include
  // bullets / newlines from the SDK's multi-block assistant message.
  const variants = [
    "- Готово: оновили палітру.",
    "\nГотово: deploy.",
    "* Готово: написали тести.",
  ];
  for (const text of variants) {
    const r = detectPrematureComplete({
      dispatchedIds: ["d1"],
      managerOutputText: text,
      resolvedDispatchIds: [],
    });
    assert.equal(r.fabricated, true, `expected fabricated for: ${JSON.stringify(text)}`);
  }
});

// ─── stripPrematureCompleteClaim ─────────────────────────────────────────────
//
// These tests pin the rewrite the Stage 4-block layer WOULD perform if the
// alert-mode baseline shows the manager keeps fabricating "Готово:". For
// now, the transform is invoked only for logging — the manager's user-
// facing text is unchanged. Pinning the transform now means flipping the
// switch later is a one-line change with confidence.

test("strip rewrites 'Готово: X.' into 'Працюємо над X.' (preserves task name)", () => {
  const out = stripPrematureCompleteClaim("Готово: спрайти Мурчика оновлені.");
  assert.equal(out, "Працюємо над спрайти Мурчика оновлені.");
});

test("strip preserves the rest of a multi-sentence message", () => {
  const out = stripPrematureCompleteClaim(
    "Готово: оновили палітру. Перевір у Settings.",
  );
  assert.match(out, /^Працюємо над оновили палітру\./);
  assert.match(out, /Перевір у Settings\.$/);
});

test("strip handles English 'Done: ...' separately (does NOT rewrite, regex is Ukrainian-only)", () => {
  // Intentional asymmetry: the Stage 4 transform only handles the
  // Ukrainian pattern. English is rare in this codebase's manager
  // output and rewriting it would risk false positives on legit reports.
  const text = "Done: shipped fix.";
  assert.equal(stripPrematureCompleteClaim(text), text);
});

test("strip leaves benign 'готовий' / 'готовність' alone", () => {
  const benign = [
    "Агент готовий взятися за задачу.",
    "Готовність команди: 3/5 агентів.",
    "Працюємо. Готується деплой.",
  ];
  for (const text of benign) {
    assert.equal(stripPrematureCompleteClaim(text), text, `should not rewrite: ${text}`);
  }
});

test("strip is idempotent — applying twice does not double-rewrite", () => {
  const once = stripPrematureCompleteClaim("Готово: x.");
  const twice = stripPrematureCompleteClaim(once);
  assert.equal(once, twice);
});

test("strip handles leading bullet / newline / punctuation", () => {
  assert.match(
    stripPrematureCompleteClaim("- Готово: оновили."),
    /Працюємо над оновили/,
  );
  assert.match(
    stripPrematureCompleteClaim("\nГотово: написали тести."),
    /Працюємо над написали тести/,
  );
});

test("strip preserves '!' or '?' sentence terminator", () => {
  assert.match(stripPrematureCompleteClaim("Готово: усе!"), /Працюємо над усе!/);
  assert.match(stripPrematureCompleteClaim("Готово: усе?"), /Працюємо над усе\?/);
});

test("regression: the 2026-05-18 Мурчик incident triggers fabricated=true", () => {
  // Verbatim replay of the production incident text — pins behavior
  // so a future regex tweak can't quietly drop coverage of this case.
  const r = detectPrematureComplete({
    dispatchedIds: ["dispatch_42_1700000000"],
    managerOutputText:
      "Готово: спрайти Мурчика оновлені з покращеною анімацією ходьби горизонтально, палітра збережена, готові до інтеграції.",
    resolvedDispatchIds: [],
  });
  assert.equal(r.fabricated, true);
  assert.deepEqual(r.unmatchedDispatchIds, ["dispatch_42_1700000000"]);
  assert.match(r.matchedClaim!, /Готово\s*:/);
});
