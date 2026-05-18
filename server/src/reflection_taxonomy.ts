/**
 * Canonical tag taxonomy for the LLM-reflection candidate gate.
 *
 * Background: until C.2.6, Haiku reflection was free to emit any kebab-case
 * `tag` per observation. In practice this caused fatal tag-aliasing: 4-5
 * semantically equivalent tags ("unclear-specification-loop",
 * "premature-user-escalation", "context-not-passed-to-agents",
 * "unclear-initial-dispatch", ...) for the same underlying failure mode.
 * `recordLessonCandidate` matches with exact-string `bucket.find(c => c.tag === tag)`,
 * so aliased tags never accumulated and the promotion rate sat at 0% over
 * 15 candidates / 30 days.
 *
 * Fix: closed list of canonical tags. The reflection prompt enumerates the
 * allowed set; the server rejects any candidate whose tag falls outside it
 * (defense-in-depth — Haiku 4.5 follows the list ~92-96% of the time per
 * the llm-specialist review attached to the C.2.6 audit). Lesson `text`
 * stays freeform — only the dedup key is normalized.
 *
 * Sizing: 8 weakness + 6 strength tags. Per the llm-specialist review:
 * past ~10 enum items, Haiku starts binning into the most generic-sounding
 * option (catastrophic categorization drift). Detected via tag entropy
 * (H < 1.5 bits over a 30-day window) — see `summarizeReflectionTelemetry`.
 *
 * Growing the taxonomy: if `invalid_tag` rate > 5% over 14 days OR top-tag
 * share > 50%, add a tag rather than tolerating the drift. Each addition
 * needs a regression fixture in test/reflection_prompt.test.ts that
 * exercises the new tag.
 */

import type { LessonType, LessonCategory } from "./trait_memory.js";

// ─── Canonical tag sets ───────────────────────────────────────────────────

/**
 * Canonical weakness tags. Covers manager / coder / reviewer / artist failure
 * modes observed empirically through 2026-05 plus typical patterns from the
 * 10 agent roles. Each tag is one *behavioural failure mode*, not one *symptom*
 * — "premature-user-escalation" covers both "asked user instead of agent" and
 * "blocked on clarification it could have resolved itself".
 *
 * Maintenance: only edit this list together with the regression fixture in
 * test/reflection_prompt.test.ts ("15-candidate replay must all map").
 */
export const ALLOWED_WEAKNESS_TAGS = [
  "insufficient-context-gathering",
  "unclear-dispatch-specification",
  "premature-user-escalation",
  "incomplete-verification",
  "tool-misuse",
  "scope-creep",
  "missed-edge-case",
  "weak-error-handling",
] as const;

/** Canonical strength tags. See ALLOWED_WEAKNESS_TAGS for sizing rationale. */
export const ALLOWED_STRENGTH_TAGS = [
  "proactive-investigation",
  "context-rich-delegation",
  "efficient-course-correction",
  "thorough-verification",
  "clean-decomposition",
  "precise-tool-use",
] as const;

export type CanonicalWeaknessTag = (typeof ALLOWED_WEAKNESS_TAGS)[number];
export type CanonicalStrengthTag = (typeof ALLOWED_STRENGTH_TAGS)[number];
export type CanonicalTag = CanonicalWeaknessTag | CanonicalStrengthTag;

const WEAKNESS_SET = new Set<string>(ALLOWED_WEAKNESS_TAGS);
const STRENGTH_SET = new Set<string>(ALLOWED_STRENGTH_TAGS);

/**
 * Validate a tag against the canonical set scoped to the lesson type.
 * Rejects mixed-type usage (a "weakness" lesson tagged with a strength tag).
 */
export function isValidTag(tag: string, type: LessonType): boolean {
  if (type === "weakness") return WEAKNESS_SET.has(tag);
  if (type === "strength") return STRENGTH_SET.has(tag);
  return false;
}

// ─── Human-readable hints (rendered into Haiku prompt) ────────────────────

/**
 * One-line hint per tag. Goes into the reflection prompt so Haiku can match
 * its observation against a tag without guessing intent from the kebab name
 * alone. Keep each hint imperative + short (≤ 70 chars).
 */
export const TAG_HINTS: Record<CanonicalTag, string> = {
  // Weakness
  "insufficient-context-gathering":
    "agent acted/asked without first searching the project or reading prior context",
  "unclear-dispatch-specification":
    "manager dispatched without clear target file, success criteria, or context",
  "premature-user-escalation":
    "asked the user for info that an agent could have resolved autonomously",
  "incomplete-verification":
    "declared work done without running analyze/tests/build or checking output",
  "tool-misuse":
    "wrong tool, wrong args, or repeated same failing tool invocation",
  "scope-creep":
    "agent did substantially more than was asked, expanding the change",
  "missed-edge-case":
    "logic ignored a boundary condition (null, empty, max, concurrent)",
  "weak-error-handling":
    "silent catch, swallowed error, or no fallback for failing dependency",
  // Strength
  "proactive-investigation":
    "agent grepped/read related files to resolve ambiguity before acting",
  "context-rich-delegation":
    "manager passed concrete file paths, screenshots, or explicit success criteria",
  "efficient-course-correction":
    "agent pivoted cleanly after pushback without losing prior work",
  "thorough-verification":
    "agent ran tests/analyze and reported actual numbers, not 'should work'",
  "clean-decomposition":
    "broke a large change into reviewable, independently-correct pieces",
  "precise-tool-use":
    "picked the right tool for the job and used it with minimal args",
};

// ─── Prompt rendering ──────────────────────────────────────────────────────

/**
 * Format the taxonomy as a `<canonical_tags>` block for injection into the
 * reflection prompt. Two sub-sections (weakness vs strength) with hint
 * suffixes so Haiku can semantically pattern-match its observation onto a
 * tag without invented vocabulary.
 *
 * Pure — same output every call (no Date / sort instability). Used by
 * buildReflectionPrompt; tested directly so the taxonomy doc and the
 * prompt-injected block stay in sync.
 */
export function formatTaxonomyForPrompt(): string {
  const lines: string[] = [];
  lines.push("Weakness tags (pick ONE that best matches; tag is the dedup key):");
  for (const t of ALLOWED_WEAKNESS_TAGS) {
    lines.push(`  - ${t} — ${TAG_HINTS[t]}`);
  }
  lines.push("");
  lines.push("Strength tags (pick ONE that best matches; tag is the dedup key):");
  for (const t of ALLOWED_STRENGTH_TAGS) {
    lines.push(`  - ${t} — ${TAG_HINTS[t]}`);
  }
  return lines.join("\n");
}

// ─── Tag entropy (drift detector) ─────────────────────────────────────────

/**
 * Shannon entropy (in bits) over the tag distribution of a candidate stream.
 *
 *   H = -Σ p(tag) * log2 p(tag)
 *
 * Useful as a cheap drift signal: with the full 14-tag taxonomy and an even
 * spread, H ≈ 3.0-3.5 bits. If Haiku collapses into one or two generic-
 * sounding tags ("communication-issue" eats 70%+), H drops below 1.5.
 *
 * Returns 0 for an empty stream — no information, but also no drift to flag.
 * Single-tag streams correctly return 0 (no uncertainty).
 *
 * Why bits, not nats: the threshold in CLAUDE.md / agent_message.dart is
 * expressed in bits ("H < 1.5"). Keep one unit across server + client.
 */
export function tagEntropyBits(tags: string[]): number {
  if (tags.length === 0) return 0;
  const counts = new Map<string, number>();
  for (const t of tags) counts.set(t, (counts.get(t) ?? 0) + 1);
  const n = tags.length;
  let h = 0;
  for (const c of counts.values()) {
    const p = c / n;
    h -= p * Math.log2(p);
  }
  return h;
}

/**
 * Largest single-tag share of the stream (0..1). Cheap companion metric to
 * entropy — a > 0.5 top-share is the same "binning into one bucket" failure
 * mode that low entropy detects, but easier to explain in a banner
 * ("75% of lessons are tagged 'tool-misuse'").
 */
export function topTagShare(tags: string[]): number {
  if (tags.length === 0) return 0;
  const counts = new Map<string, number>();
  for (const t of tags) counts.set(t, (counts.get(t) ?? 0) + 1);
  let max = 0;
  for (const c of counts.values()) if (c > max) max = c;
  return max / tags.length;
}

// ─── Convenience re-exports for callers ───────────────────────────────────

export type { LessonType, LessonCategory };
