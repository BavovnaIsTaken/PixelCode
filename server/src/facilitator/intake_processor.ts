/**
 * Intake Processor — pure, deterministic logic that turns intake answers
 * into ScopeScore overrides. No LLM calls.
 *
 * The interview is style-flavored on the front-end (Drill asks
 * differently than Marina asks differently than Game Master), but the
 * underlying signal collected — which scope dimension does each answer
 * inform — is style-agnostic. That's why every preset's
 * `intakeTemplate` carries `mapsTo` alongside its prompt.
 *
 * Design: docs/FACILITATOR_SYSTEM.md §3, §4 (cross-style scorer reuse).
 */

import type { ScopeScore } from "../quest/scope_scorer.js";
import {
  applyOverrides,
  scoreIdea,
  type ScoreBreakdown,
} from "../quest/scope_scorer.js";
import type {
  FacilitatorStyle,
  IntakeAnswers,
  IntakeQuestion,
  ScopeDimensionKey,
} from "./types.js";

// ─── Per-dimension answer interpretation ────────────────────────────────────

/**
 * Maps a user-supplied answer to a dimension delta. Returns `null` when
 * the answer doesn't carry enough signal to override (e.g. blank text,
 * unrecognized choice). The base heuristic score stays in those cases.
 *
 * We deliberately keep this simple — the goal is to nudge dimensions in
 * the right direction, not to be a full NLP layer.
 */
export function interpretAnswer(
  question: IntakeQuestion,
  answer: string,
): number | null {
  if (!answer || !answer.trim()) return null;
  const trimmed = answer.trim();

  // Choice answers — match by exact label, then by case-insensitive
  // contains-token heuristics.
  if (question.inputKind === "choice") {
    const idx = (question.choices ?? []).findIndex((c) => c === trimmed);
    if (idx < 0) {
      // Try fuzzy contains.
      const lower = trimmed.toLowerCase();
      const fuzzy = (question.choices ?? []).findIndex((c) =>
        lower.includes(c.toLowerCase()) || c.toLowerCase().includes(lower),
      );
      if (fuzzy < 0) return null;
      return choiceIndexToDelta(question.mapsTo, fuzzy);
    }
    return choiceIndexToDelta(question.mapsTo, idx);
  }

  // Text answers — keyword scan against the user's free-form text. Reuse
  // the same patterns the main scorer uses, scoped to the question's
  // mapped dimension.
  return textAnswerToDelta(question.mapsTo, trimmed);
}

/**
 * For `choice` questions, the choices are listed in order of *increasing
 * scope*. e.g. ["Solo", "Squad", "Public"] for `auth` ⇒ idx 0 = no
 * accounts, idx 1 = small group, idx 2 = full public. The delta is a
 * monotonic function of position, capped at the dimension ceiling.
 */
function choiceIndexToDelta(
  dimension: ScopeDimensionKey,
  idx: number,
): number | null {
  if (dimension === "none") return null;

  switch (dimension) {
    case "auth":
      // 0 → 0 (none), 1 → 2 (accounts), 2+ → 3 (roles/permissions)
      return idx === 0 ? 0 : idx === 1 ? 2 : 3;
    case "realtime":
      // 0 → 0 (static), 1 → 1 (sync), 2 → 2 (websocket), 3+ → 3 (live multi)
      return Math.min(idx, 3);
    case "integrations":
    case "interaction_surface":
    case "entity_count":
      // Generic 0..4 ramp.
      return Math.min(idx, 4);
  }
}

/**
 * Free-text answer → delta. Looks for explicit signals that should set a
 * dimension. Conservative: if no signal found, return `null` (don't
 * override the heuristic).
 */
function textAnswerToDelta(
  dimension: ScopeDimensionKey,
  text: string,
): number | null {
  if (dimension === "none") return null;
  const lower = text.toLowerCase();

  switch (dimension) {
    case "auth": {
      if (/\b(no|none|just me|solo|personal)\b/.test(lower)) return 0;
      if (/\b(admin|roles?|permissions?|moderation)\b/.test(lower)) return 3;
      if (/\b(users?|accounts?|login|signup)\b/.test(lower)) return 2;
      return null;
    }
    case "realtime": {
      // Check highest-signal patterns first; "collaborative editing" must
      // resolve to 3, not 2 (the "live"/"editing" overlap would otherwise
      // short-circuit it).
      // `\bcollab` (no trailing word-boundary) so it also matches
      // "collaborative", "collaboration" etc.
      if (/\bcollab|\bmultiplayer\b|\bshared cursor\b|\bco[- ]edit/.test(lower))
        return 3;
      if (/\b(real[- ]?time|live|websocket|streaming|chat)\b/.test(lower))
        return 2;
      if (/\b(sync|offline[- ]?first)\b/.test(lower)) return 1;
      if (/\b(no|never|static|once)\b/.test(lower)) return 0;
      return null;
    }
    case "integrations": {
      // Count distinct integration mentions, cap at 4.
      const hits = new Set<string>();
      const patterns: Array<[RegExp, string]> = [
        [/\b(payment|stripe|checkout|billing)\b/, "payments"],
        [/\b(maps?|location|gps)\b/, "maps"],
        [/\b(upload|photo|video|file|camera)\b/, "media"],
        [/\b(notification|push|remind|alert)\b/, "push"],
        [/\b(email|smtp|mailing)\b/, "email"],
        [/\b(sms|twilio)\b/, "sms"],
        [/\b(ai|llm|gpt|chatgpt|claude|openai|anthropic)\b/, "ai"],
      ];
      for (const [pattern, label] of patterns) {
        if (pattern.test(lower)) hits.add(label);
      }
      if (hits.size === 0 && /\b(no|none)\b/.test(lower)) return 0;
      return hits.size > 0 ? Math.min(hits.size, 4) : null;
    }
    case "entity_count": {
      // Count distinct domain nouns mentioned.
      const nouns = lower.match(
        /\b(user|account|post|comment|review|order|product|event|booking|message|photo|video|file|tag|group|team|workspace)s?\b/g,
      );
      if (!nouns || nouns.length === 0) return null;
      const distinct = new Set(nouns.map((n) => n.replace(/s$/, "")));
      return Math.min(distinct.size, 4);
    }
    case "interaction_surface": {
      if (/\b(dashboard|admin panel|analytics)\b/.test(lower)) return 3;
      if (/\b(crud|edit and delete|manage)\b/.test(lower)) return 2;
      if (/\b(read.only|view only|just display)\b/.test(lower)) return 1;
      return null;
    }
  }
}

// ─── Top-level entrypoint ──────────────────────────────────────────────────

export interface IntakeResult {
  /** Final score after the heuristic + answer overrides are merged. */
  finalScore: ScopeScore;
  /** Heuristic baseline (before overrides applied). */
  heuristicBreakdown: ScoreBreakdown;
  /** Per-dimension overrides actually applied. Empty if answers had no signal. */
  appliedOverrides: Partial<ScopeScore>;
  /** Question ids whose answers couldn't be interpreted. */
  unparsedQuestionIds: string[];
}

/**
 * Combine: keyword heuristic on the project description + answers from
 * the style's intake template → final ScopeScore.
 *
 * Algorithm:
 *   1. Run `scoreIdea(description)` for the baseline.
 *   2. For each question with `mapsTo !== "none"`, run `interpretAnswer`
 *      on its provided answer.
 *   3. Multiple answers mapping to the same dimension MAX-merge (the
 *      higher signal wins — better to over-scope than miss).
 *   4. Apply the merged overrides on top of the heuristic.
 */
export function processIntake(
  projectDescription: string,
  style: FacilitatorStyle,
  answers: IntakeAnswers,
): IntakeResult {
  const heuristicBreakdown = scoreIdea(projectDescription);

  const overrides: Partial<ScopeScore> = {};
  const unparsed: string[] = [];

  for (const q of style.intakeTemplate) {
    if (q.mapsTo === "none") continue;
    const answer = answers[q.id];
    if (answer === undefined) continue;
    const delta = interpretAnswer(q, answer);
    if (delta === null) {
      unparsed.push(q.id);
      continue;
    }
    const dimKey = mapsToDimensionField(q.mapsTo);
    if (dimKey === null) continue;

    // MAX-merge — see step 3 above.
    const existing = overrides[dimKey];
    overrides[dimKey] = existing === undefined ? delta : Math.max(existing, delta);
  }

  const finalScore = applyOverrides(heuristicBreakdown.score, overrides);

  return {
    finalScore,
    heuristicBreakdown,
    appliedOverrides: overrides,
    unparsedQuestionIds: unparsed,
  };
}

function mapsToDimensionField(
  mapsTo: ScopeDimensionKey,
): keyof ScopeScore | null {
  switch (mapsTo) {
    case "entity_count":
      return "entityCount";
    case "interaction_surface":
      return "interactionSurface";
    case "auth":
      return "auth";
    case "integrations":
      return "integrations";
    case "realtime":
      return "realtime";
    case "none":
      return null;
  }
}
