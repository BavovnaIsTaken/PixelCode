import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ALLOWED_WEAKNESS_TAGS,
  ALLOWED_STRENGTH_TAGS,
  TAG_HINTS,
  isValidTag,
  formatTaxonomyForPrompt,
  tagEntropyBits,
  topTagShare,
} from "../src/reflection_taxonomy.ts";

// ─── Taxonomy shape / invariants ────────────────────────────────────────────

test("ALLOWED_WEAKNESS_TAGS and ALLOWED_STRENGTH_TAGS are disjoint", () => {
  const wset = new Set(ALLOWED_WEAKNESS_TAGS);
  for (const s of ALLOWED_STRENGTH_TAGS) {
    assert.ok(
      !wset.has(s as never),
      `tag "${s}" appears in BOTH weakness and strength sets`,
    );
  }
});

test("Taxonomy size matches design — 8 weakness + 6 strength tags (C.2.6 sweet spot)", () => {
  // Sizing comes from the llm-specialist review: at N>10 Haiku starts
  // binning into the most generic-sounding option. Changing this number
  // means revisiting CLAUDE.md §5 and adding entropy fixtures for the
  // new shape.
  assert.equal(ALLOWED_WEAKNESS_TAGS.length, 8, "weakness taxonomy must stay at 8");
  assert.equal(ALLOWED_STRENGTH_TAGS.length, 6, "strength taxonomy must stay at 6");
});

test("Every canonical tag has a one-line hint in TAG_HINTS", () => {
  for (const t of ALLOWED_WEAKNESS_TAGS) {
    assert.ok(TAG_HINTS[t], `missing hint for weakness tag "${t}"`);
    assert.ok(TAG_HINTS[t].length <= 90,
      `hint for "${t}" is too long (${TAG_HINTS[t].length}): ${TAG_HINTS[t]}`);
  }
  for (const t of ALLOWED_STRENGTH_TAGS) {
    assert.ok(TAG_HINTS[t], `missing hint for strength tag "${t}"`);
    assert.ok(TAG_HINTS[t].length <= 90,
      `hint for "${t}" is too long (${TAG_HINTS[t].length}): ${TAG_HINTS[t]}`);
  }
});

test("All canonical tags are kebab-case", () => {
  const kebab = /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/;
  for (const t of [...ALLOWED_WEAKNESS_TAGS, ...ALLOWED_STRENGTH_TAGS]) {
    assert.match(t, kebab, `tag "${t}" is not kebab-case`);
  }
});

// ─── isValidTag ─────────────────────────────────────────────────────────────

test("isValidTag: accepts canonical weakness tag for type=weakness", () => {
  assert.equal(isValidTag("insufficient-context-gathering", "weakness"), true);
  assert.equal(isValidTag("tool-misuse", "weakness"), true);
});

test("isValidTag: accepts canonical strength tag for type=strength", () => {
  assert.equal(isValidTag("proactive-investigation", "strength"), true);
  assert.equal(isValidTag("clean-decomposition", "strength"), true);
});

test("isValidTag: rejects mismatched type (weakness tag with type=strength)", () => {
  // Defense against Haiku producing the right vocabulary under the wrong
  // type — would dilute strength/weakness statistics if accepted.
  assert.equal(isValidTag("tool-misuse", "strength"), false);
  assert.equal(isValidTag("proactive-investigation", "weakness"), false);
});

test("isValidTag: rejects invented tags (the failure mode being fixed)", () => {
  // These are the actual tags found in trait_candidates.json on 2026-05-18
  // — pre-C.2.6 Haiku-invented vocabulary the gate could never accumulate.
  const invented = [
    "unclear-specification-loop",
    "premature-user-escalation",       // covered by "premature-user-escalation"? — no, that IS canonical
    "context-not-passed-to-agents",
    "unclear-initial-dispatch",
    "missing-context-investigation",
    "insufficient-context-gathering",  // this IS canonical
    "missing-context-proactive-search",
  ];
  // Filter out tags that happen to also be canonical (the test must not
  // collapse if the taxonomy already covers one of them by name).
  const wset = new Set<string>(ALLOWED_WEAKNESS_TAGS);
  const trulyInvented = invented.filter((t) => !wset.has(t));
  assert.ok(trulyInvented.length >= 4,
    "regression fixture must keep ≥4 invented tags");
  for (const t of trulyInvented) {
    assert.equal(isValidTag(t, "weakness"), false,
      `invented tag "${t}" must not validate as canonical`);
  }
});

test("isValidTag: rejects empty / nonsense strings", () => {
  assert.equal(isValidTag("", "weakness"), false);
  assert.equal(isValidTag("not-a-real-tag-anywhere", "weakness"), false);
  assert.equal(isValidTag("Tool-Misuse", "weakness"), false, "case-sensitive");
});

// ─── formatTaxonomyForPrompt ────────────────────────────────────────────────

test("formatTaxonomyForPrompt: lists every canonical tag with its hint", () => {
  const out = formatTaxonomyForPrompt();
  for (const t of ALLOWED_WEAKNESS_TAGS) {
    assert.ok(out.includes(t), `weakness tag "${t}" missing from prompt block`);
    assert.ok(out.includes(TAG_HINTS[t]),
      `hint for "${t}" missing from prompt block`);
  }
  for (const t of ALLOWED_STRENGTH_TAGS) {
    assert.ok(out.includes(t), `strength tag "${t}" missing from prompt block`);
  }
});

test("formatTaxonomyForPrompt: deterministic (no Date / random)", () => {
  const a = formatTaxonomyForPrompt();
  const b = formatTaxonomyForPrompt();
  assert.equal(a, b);
});

test("formatTaxonomyForPrompt: separates weakness and strength sections", () => {
  const out = formatTaxonomyForPrompt();
  const wIdx = out.indexOf("Weakness tags");
  const sIdx = out.indexOf("Strength tags");
  assert.ok(wIdx >= 0 && sIdx >= 0, "both section headers must appear");
  assert.ok(wIdx < sIdx, "weakness section comes first");
});

// ─── tagEntropyBits ─────────────────────────────────────────────────────────

test("tagEntropyBits: empty stream returns 0", () => {
  assert.equal(tagEntropyBits([]), 0);
});

test("tagEntropyBits: single-tag stream returns 0 (no uncertainty)", () => {
  assert.equal(tagEntropyBits(["a", "a", "a"]), 0);
});

test("tagEntropyBits: uniform 4-tag stream returns 2 bits (-log2(1/4))", () => {
  const h = tagEntropyBits(["a", "b", "c", "d"]);
  assert.ok(Math.abs(h - 2) < 1e-9, `expected exactly 2 bits, got ${h}`);
});

test("tagEntropyBits: uniform 8-tag stream returns 3 bits", () => {
  const tags = ["a","b","c","d","e","f","g","h"];
  const h = tagEntropyBits(tags);
  assert.ok(Math.abs(h - 3) < 1e-9, `expected exactly 3 bits, got ${h}`);
});

test("tagEntropyBits: skewed distribution drops below 1.5 bits (drift threshold)", () => {
  // 90% one tag, 10% spread — the catastrophic-binning failure mode.
  const tags: string[] = [];
  for (let i = 0; i < 90; i++) tags.push("top");
  for (let i = 0; i < 10; i++) tags.push(`other-${i}`);
  const h = tagEntropyBits(tags);
  assert.ok(h < 1.5,
    `90/10 split should fall below the 1.5-bit drift threshold; got ${h}`);
});

test("tagEntropyBits: balanced 14-tag taxonomy stays above 3.0 bits", () => {
  // Realistic healthy-system check: with 7 candidates per tag across all
  // 14 canonical tags, entropy is right at log2(14) ≈ 3.81 bits.
  const tags: string[] = [];
  const all = [...ALLOWED_WEAKNESS_TAGS, ...ALLOWED_STRENGTH_TAGS];
  for (const t of all) for (let i = 0; i < 7; i++) tags.push(t);
  const h = tagEntropyBits(tags);
  assert.ok(h > 3.0, `healthy uniform spread should exceed 3 bits; got ${h}`);
});

// ─── topTagShare ────────────────────────────────────────────────────────────

test("topTagShare: empty stream returns 0", () => {
  assert.equal(topTagShare([]), 0);
});

test("topTagShare: single-tag stream returns 1.0", () => {
  assert.equal(topTagShare(["x", "x", "x"]), 1);
});

test("topTagShare: 4-tag uniform returns 0.25", () => {
  assert.equal(topTagShare(["a", "b", "c", "d"]), 0.25);
});

test("topTagShare: 75/25 split returns 0.75 (above the 50% drift threshold)", () => {
  const tags = [...Array(75).fill("hot"), ...Array(25).fill("cold")];
  const share = topTagShare(tags);
  assert.ok(Math.abs(share - 0.75) < 1e-9);
  assert.ok(share > 0.5, "75% share must clear the drift threshold");
});

// ─── 15-candidate regression fixture (C.2.6 acceptance) ─────────────────────

/**
 * The actual pre-fix candidates pulled from
 * /Users/danylooliinyk/.pixelcode/projects/.../trait_candidates.json
 * on 2026-05-18. Each entry maps the historical free-form tag → the
 * canonical tag the new taxonomy should bin it into. If a future
 * taxonomy edit makes any of these mappings unreachable, this test
 * fails — signalling that the taxonomy is losing real-world coverage.
 *
 * The mapping is hand-derived (not automated) — that's the point:
 * the human auditor (this test author) certifies that the canonical
 * tag is a faithful generalisation of the observed lesson.
 */
const HISTORICAL_CANDIDATES: Array<{
  tag: string;
  type: "weakness" | "strength";
  canonical: string;
}> = [
  // manager#1 weaknesses
  { tag: "unclear-specification-loop",   type: "weakness", canonical: "unclear-dispatch-specification" },
  { tag: "premature-user-escalation",    type: "weakness", canonical: "premature-user-escalation" },
  { tag: "context-not-passed-to-agents", type: "weakness", canonical: "unclear-dispatch-specification" },
  { tag: "unclear-initial-dispatch",     type: "weakness", canonical: "unclear-dispatch-specification" },
  // manager#1 strengths
  { tag: "context-sufficient-delegation", type: "strength", canonical: "context-rich-delegation" },
  { tag: "efficient-course-correction",   type: "strength", canonical: "efficient-course-correction" },
  { tag: "escalation-and-context-clarity", type: "strength", canonical: "context-rich-delegation" },
  // character-artist#1 weaknesses
  { tag: "premature-escalation",            type: "weakness", canonical: "premature-user-escalation" },
  { tag: "missing-context-investigation",   type: "weakness", canonical: "insufficient-context-gathering" },
  { tag: "unclear-requirements-blocking",   type: "weakness", canonical: "insufficient-context-gathering" },
  { tag: "insufficient-context-gathering",  type: "weakness", canonical: "insufficient-context-gathering" },
  { tag: "missing-context-proactive-search", type: "weakness", canonical: "insufficient-context-gathering" },
  // character-artist#1 strengths
  { tag: "clarification-before-execution", type: "strength", canonical: "proactive-investigation" },
  { tag: "proactive-context-recovery",     type: "strength", canonical: "proactive-investigation" },
  { tag: "persistence-through-blockers",   type: "strength", canonical: "proactive-investigation" },
];

test("Regression: every 2026-05 historical candidate maps to a CURRENT canonical tag", () => {
  assert.equal(HISTORICAL_CANDIDATES.length, 15,
    "fixture should mirror the 15 candidates that motivated C.2.6");
  for (const c of HISTORICAL_CANDIDATES) {
    assert.equal(
      isValidTag(c.canonical, c.type),
      true,
      `historical tag "${c.tag}" maps to "${c.canonical}" but canonical no longer exists`,
    );
  }
});

test("Regression: taxonomy compression — 15 historical tags collapse into ≤6 canonical bins", () => {
  // The 0%-promotion failure mode came from 15 distinct tags. The fix is
  // meaningful only if the taxonomy compresses them into a small number
  // of buckets (so accumulation across "sessions" can actually happen).
  // Target: ≤6 canonical bins — would make weakness=3 / strength=2
  // promotion thresholds reachable within ~3-5 working sessions.
  const canonicals = new Set(HISTORICAL_CANDIDATES.map((c) => c.canonical));
  assert.ok(canonicals.size <= 6,
    `taxonomy should compress 15 → ≤6 bins, got ${canonicals.size}: ${[...canonicals]}`);
});
