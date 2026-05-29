/**
 * Agent Trait Memory — persistent learning system.
 *
 * Agents learn from mistakes and successes. The more frequently
 * a lesson is observed, the stronger it becomes in the agent's behavior.
 *
 * Frequency scale (effective frequency after decay):
 *  1-2  → Note (mild influence)
 *  3-4  → Important (moderate influence)
 *  5+   → Critical (strong directive)
 *
 * Decay: every DECAY_PERIOD_MS of inactivity since lastSeen subtracts 1 from
 * the effective frequency. Persisted `frequency` is untouched; readers compute
 * `effectiveFrequency` at read time. Lessons whose effective value drops to 0
 * are pruned on the next save.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";

// ─── Types ─────────────────────────────────────────────────────────────────

export type LessonType = "strength" | "weakness";

export type LessonCategory =
  | "code_quality"
  | "architecture"
  | "testing"
  | "security"
  | "communication"
  | "delegation"
  | "problem_solving"
  | "tools_usage";

/**
 * Provenance of a lesson observation. Used to namespace tag-collisions between
 * the rigid hook-based learners ("task-rework", "clean-execution" — structural
 * signals from emit code paths) and LLM-judged reflection lessons, which may
 * accidentally reuse the same kebab-tag.
 *
 *   hook    — structural signal (lib/services autoLearnLesson). Bypasses
 *             candidate gate; observation directly reinforces real trait.
 *   llm     — extracted by post-session Haiku reflection. Must clear the
 *             candidate gate (multi-session, time-spaced) to land in real
 *             TraitStore.
 *   unknown — legacy records from before this field existed. Treated as
 *             "neither" — never matched by either path's existing-lesson
 *             lookup; decay through the natural lifecycle.
 */
export type LessonSource = "hook" | "llm" | "unknown";

export interface AgentLesson {
  id: string;
  agentId: string;
  type: LessonType;
  category: LessonCategory;
  tag: string;            // kebab-case key for dedup / matching
  lesson: string;         // one-sentence description
  frequency: number;      // 1–10, higher = stronger memory
  source: LessonSource;
  firstSeen: string;      // ISO 8601
  lastSeen: string;       // ISO 8601
}

export interface TraitStore {
  version: number;
  agents: Record<string, AgentLesson[]>;
  consent?: Record<string, boolean>;
}

/**
 * Candidate lesson awaiting confirmation across multiple sessions before
 * it is promoted into the real TraitStore. Used as a confabulation gate for
 * LLM-extracted reflection lessons — single-session observations stay here
 * and either accumulate into a real trait or expire after CANDIDATE_TTL_MS.
 */
export interface TraitCandidate {
  id: string;
  agentId: string;
  type: LessonType;
  category: LessonCategory;
  tag: string;
  lesson: string;
  /** Always "llm" in current usage — kept explicit for future hook-candidates. */
  source: LessonSource;
  sessionCount: number;     // distinct sessions that observed this
  lastSessionId: string;    // dedup within-session re-extractions
  firstSeen: string;        // ISO 8601
  lastSeen: string;         // ISO 8601
}

export interface CandidateStore {
  version: number;
  candidates: Record<string, TraitCandidate[]>;
}

// ─── Storage paths ─────────────────────────────────────────────────────────

function traitsDir(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key);
}

function traitsFile(projectPath: string): string {
  return join(traitsDir(projectPath), "traits.json");
}

function candidatesFile(projectPath: string): string {
  return join(traitsDir(projectPath), "trait_candidates.json");
}

// ─── Decay parameters ─────────────────────────────────────────────────────

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Per-category inactivity period after which effective frequency loses 1.
 *
 * Differentiated because lesson half-lives vary by domain:
 *  - tools_usage: short — tool allowlists/configurations churn every release
 *  - communication/delegation/problem_solving: medium — social patterns
 *  - architecture/code_quality/testing/security: long — principles stable
 */
export const CATEGORY_DECAY_PERIOD_MS: Record<LessonCategory, number> = {
  tools_usage: 14 * DAY_MS,
  communication: 30 * DAY_MS,
  delegation: 30 * DAY_MS,
  problem_solving: 30 * DAY_MS,
  architecture: 60 * DAY_MS,
  code_quality: 60 * DAY_MS,
  testing: 60 * DAY_MS,
  security: 60 * DAY_MS,
};

/** Default decay period when category is unknown or malformed. */
export const DEFAULT_DECAY_PERIOD_MS = 30 * DAY_MS;

/**
 * Legacy alias — many callers still reference `DECAY_PERIOD_MS`. Equals the
 * default decay period (which is what the previous global-constant meant
 * before per-category granularity landed).
 */
export const DECAY_PERIOD_MS = DEFAULT_DECAY_PERIOD_MS;

export function decayPeriodFor(category: LessonCategory): number {
  return CATEGORY_DECAY_PERIOD_MS[category] ?? DEFAULT_DECAY_PERIOD_MS;
}

/**
 * Candidate promotion thresholds. Asymmetric by lesson type because the
 * blast-radius of false positives differs sharply:
 *  - weakness promoted incorrectly → agent's prompt warns it away from a real
 *    capability → primary UX breakage. Higher bar (3 sessions).
 *  - strength promoted incorrectly → agent gets a mild confidence note → low
 *    impact. Lower bar (2 sessions).
 */
export const STRENGTH_PROMOTION_THRESHOLD = 2;
export const WEAKNESS_PROMOTION_THRESHOLD = 3;

/** Back-compat alias for code/tests written against the symmetric constant. */
export const CANDIDATE_PROMOTION_THRESHOLD = STRENGTH_PROMOTION_THRESHOLD;

export function promotionThresholdFor(type: LessonType): number {
  return type === "weakness"
    ? WEAKNESS_PROMOTION_THRESHOLD
    : STRENGTH_PROMOTION_THRESHOLD;
}

/**
 * Minimum time gap between two same-tag observations for them to count as
 * distinct sessions. Defeats burst-confabulation: two task dispatches 5 min
 * apart that both confabulate the same wrong tag now collapse into a single
 * observation rather than instantly promoting.
 *
 * Drawn from spaced-repetition literature (Cepeda et al. 2006): repetition
 * only consolidates if separated. 2h is short enough that a long debugging
 * session over a day still produces independent observations.
 */
export const MIN_PROMOTION_GAP_MS = 2 * 60 * 60 * 1000;

/** Single-session candidates older than this are dropped as likely confabulations. */
export const CANDIDATE_TTL_MS = 14 * DAY_MS;

/**
 * Effective frequency after applying inactivity decay. Never negative.
 * Per-category decay period is applied — tools_usage decays faster than
 * architecture (see CATEGORY_DECAY_PERIOD_MS).
 */
export function effectiveFrequency(lesson: AgentLesson, now: Date = new Date()): number {
  const ageMs = now.getTime() - new Date(lesson.lastSeen).getTime();
  if (ageMs <= 0) return lesson.frequency;
  const period = decayPeriodFor(lesson.category);
  const periodsInactive = Math.floor(ageMs / period);
  return Math.max(0, lesson.frequency - periodsInactive);
}

/** Remove lessons whose effective frequency has decayed to 0. Pure on `store`. */
export function pruneDecayedLessons(store: TraitStore, now: Date = new Date()): number {
  let removed = 0;
  for (const agentId of Object.keys(store.agents)) {
    const before = store.agents[agentId].length;
    store.agents[agentId] = store.agents[agentId].filter(
      (l) => effectiveFrequency(l, now) > 0,
    );
    removed += before - store.agents[agentId].length;
  }
  return removed;
}

// ─── Load / Save ───────────────────────────────────────────────────────────

export function loadTraits(projectPath: string): TraitStore {
  const file = traitsFile(projectPath);
  if (!existsSync(file)) {
    return { version: 1, agents: {} };
  }
  try {
    const store = JSON.parse(readFileSync(file, "utf-8")) as TraitStore;
    // Legacy migration: lessons stored before the `source` field existed get
    // tagged "unknown" so existing-lesson lookups (which are source-scoped)
    // don't accidentally match them. They decay through the normal lifecycle.
    let migrated = false;
    for (const agentId of Object.keys(store.agents ?? {})) {
      for (const lesson of store.agents[agentId]) {
        if (!lesson.source) {
          lesson.source = "unknown";
          migrated = true;
        }
      }
    }
    // Sweep decayed lessons on load so disk converges to effective state.
    const prunedCount = pruneDecayedLessons(store);
    if (prunedCount > 0 || migrated) {
      try {
        writeFileSync(file, JSON.stringify(store, null, 2));
      } catch {
        // Read-only FS: keep the in-memory pruned copy regardless.
      }
    }
    return store;
  } catch {
    return { version: 1, agents: {} };
  }
}

export function saveTraits(projectPath: string, store: TraitStore): void {
  const dir = traitsDir(projectPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  pruneDecayedLessons(store);
  writeFileSync(traitsFile(projectPath), JSON.stringify(store, null, 2));
}

// ─── Lesson CRUD ───────────────────────────────────────────────────────────

const MAX_LESSONS_PER_AGENT = 20;

/**
 * Get all live lessons for an agent (effective frequency > 0), sorted by
 * effective frequency descending. Decayed lessons are omitted but not deleted
 * from the store — pruning happens on the next save.
 */
export function getLessonsForAgent(
  store: TraitStore,
  agentId: string,
  now: Date = new Date(),
): AgentLesson[] {
  const lessons = store.agents[agentId] ?? [];
  return [...lessons]
    .filter((l) => effectiveFrequency(l, now) > 0)
    .sort((a, b) => effectiveFrequency(b, now) - effectiveFrequency(a, now));
}

/**
 * Record a lesson. Existing-lesson lookup is scoped to (tag, source) — so a
 * `task-rework` weakness written by the hook learner does not collide with a
 * coincidentally-same tag emitted by LLM reflection.
 *
 * Default source is "unknown" — callers that route through hooks or the
 * candidate gate must pass an explicit source to opt into proper namespacing.
 */
export function recordLesson(
  projectPath: string,
  store: TraitStore,
  input: {
    agentId: string;
    type: LessonType;
    category: LessonCategory;
    tag: string;
    lesson: string;
    source?: LessonSource;
  },
): AgentLesson {
  const { agentId, type, category, tag, lesson } = input;
  const source: LessonSource = input.source ?? "unknown";
  const now = new Date().toISOString();

  if (!store.agents[agentId]) {
    store.agents[agentId] = [];
  }

  const lessons = store.agents[agentId];
  const existing = lessons.find(
    (l) => l.tag === tag && (l.source ?? "unknown") === source,
  );

  if (existing) {
    existing.frequency = Math.min(existing.frequency + 1, 10);
    existing.lastSeen = now;
    // Keep the longer (more descriptive) lesson text
    if (lesson.length > existing.lesson.length) {
      existing.lesson = lesson;
    }
    // Allow type migration if pattern changes (e.g. weakness becomes strength)
    existing.type = type;
    saveTraits(projectPath, store);
    return existing;
  }

  const newLesson: AgentLesson = {
    id: `${agentId}_${type}_${Date.now()}`,
    agentId,
    type,
    category,
    tag,
    lesson,
    source,
    frequency: 1,
    firstSeen: now,
    lastSeen: now,
  };
  lessons.push(newLesson);

  // Cap per-agent — drop those with the lowest *effective* frequency so a
  // stale freq=8 (effective=2 after decay) does not displace a fresh freq=1.
  if (lessons.length > MAX_LESSONS_PER_AGENT) {
    const evalNow = new Date();
    lessons.sort(
      (a, b) => effectiveFrequency(b, evalNow) - effectiveFrequency(a, evalNow),
    );
    lessons.length = MAX_LESSONS_PER_AGENT;
  }

  saveTraits(projectPath, store);
  return newLesson;
}

/** Remove a specific lesson by id. */
export function removeLesson(
  projectPath: string,
  store: TraitStore,
  lessonId: string,
): boolean {
  for (const agentId of Object.keys(store.agents)) {
    const lessons = store.agents[agentId];
    const idx = lessons.findIndex((l) => l.id === lessonId);
    if (idx >= 0) {
      lessons.splice(idx, 1);
      saveTraits(projectPath, store);
      return true;
    }
  }
  return false;
}

// ─── Prompt formatting ─────────────────────────────────────────────────────

/**
 * Build a prompt section describing the agent's learned traits.
 * Weaknesses get progressively stronger language as frequency grows.
 * Strengths get progressively more confident language.
 */
export function formatTraitsForPrompt(
  store: TraitStore,
  agentId: string,
  now: Date = new Date(),
): string {
  const lessons = getLessonsForAgent(store, agentId, now);
  if (lessons.length === 0) return "";

  const weaknesses = lessons.filter((l) => l.type === "weakness");
  const strengths = lessons.filter((l) => l.type === "strength");

  const lines: string[] = [];

  if (weaknesses.length > 0) {
    lines.push("### Known Weaknesses (learn from past mistakes)");
    for (const w of weaknesses) {
      const eff = effectiveFrequency(w, now);
      const emphasis =
        eff >= 5 ? "CRITICAL — repeatedly observed" :
        eff >= 3 ? "Important" :
        "Note";
      lines.push(`- **[${emphasis}]** ${w.lesson} _(observed ${eff}×)_`);
    }
    lines.push("");
  }

  if (strengths.length > 0) {
    lines.push("### Known Strengths (leverage these)");
    for (const s of strengths) {
      const eff = effectiveFrequency(s, now);
      const emphasis =
        eff >= 5 ? "Expert-level" :
        eff >= 3 ? "Strong" :
        "Capable";
      lines.push(`- **[${emphasis}]** ${s.lesson} _(confirmed ${eff}×)_`);
    }
  }

  return lines.join("\n");
}

/**
 * Flat array of all live lessons across all agents (for sending to client).
 * Decayed lessons are filtered out so UI never displays them.
 */
export function getAllTraits(store: TraitStore, now: Date = new Date()): AgentLesson[] {
  const all: AgentLesson[] = [];
  for (const lessons of Object.values(store.agents)) {
    for (const l of lessons) {
      if (effectiveFrequency(l, now) > 0) all.push(l);
    }
  }
  return all;
}

// ─── Consent ──────────────────────────────────────────────────────────────

export function isConsentEnabled(store: TraitStore, agentId: string): boolean {
  return store.consent?.[agentId] ?? true;
}

export function setConsent(
  projectPath: string,
  store: TraitStore,
  agentId: string,
  enabled: boolean,
): void {
  if (!store.consent) store.consent = {};
  store.consent[agentId] = enabled;
  saveTraits(projectPath, store);
}

export function getAllConsent(store: TraitStore): Record<string, boolean> {
  return store.consent ?? {};
}

// ─── Candidate pool (LLM reflection gate) ──────────────────────────────────

export function loadCandidates(projectPath: string): CandidateStore {
  const file = candidatesFile(projectPath);
  if (!existsSync(file)) {
    return { version: 1, candidates: {} };
  }
  try {
    const store = JSON.parse(readFileSync(file, "utf-8")) as CandidateStore;
    if (pruneStaleCandidates(store) > 0) {
      try {
        writeFileSync(file, JSON.stringify(store, null, 2));
      } catch {
        // ignore — in-memory copy is authoritative for the session
      }
    }
    return store;
  } catch {
    return { version: 1, candidates: {} };
  }
}

export function saveCandidates(projectPath: string, store: CandidateStore): void {
  const dir = traitsDir(projectPath);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  pruneStaleCandidates(store);
  writeFileSync(candidatesFile(projectPath), JSON.stringify(store, null, 2));
}

/**
 * Drop single-session candidates whose most recent observation is older than
 * the TTL. TTL is anchored to `lastSeen` (not `firstSeen`) so a slowly-
 * accumulating pattern — observed day 1 then again day 13 — is not punished
 * for its first observation timing.
 *
 * Candidates that have already cleared their type-specific promotion
 * threshold are kept regardless of age; they are awaiting the next call to
 * promote, not aging out.
 */
export function pruneStaleCandidates(
  store: CandidateStore,
  now: Date = new Date(),
): number {
  let removed = 0;
  for (const agentId of Object.keys(store.candidates)) {
    const before = store.candidates[agentId].length;
    store.candidates[agentId] = store.candidates[agentId].filter((c) => {
      if (c.sessionCount >= promotionThresholdFor(c.type)) return true;
      const ageMs = now.getTime() - new Date(c.lastSeen).getTime();
      return ageMs < CANDIDATE_TTL_MS;
    });
    removed += before - store.candidates[agentId].length;
    if (store.candidates[agentId].length === 0) delete store.candidates[agentId];
  }
  return removed;
}

/**
 * Result of submitting a candidate lesson observation.
 *
 *   pending          — stored as candidate, awaiting more observations
 *   duplicate        — same session OR within MIN_PROMOTION_GAP_MS; no inflation
 *   too-soon         — distinct session id, but observed too soon after last
 *                      observation to count as independent (burst-defense)
 *   promoted         — threshold reached or matching real trait reinforced
 */
export type CandidateOutcome =
  | { status: "pending"; candidate: TraitCandidate }
  | { status: "duplicate"; candidate: TraitCandidate }
  | { status: "too-soon"; candidate: TraitCandidate; gapMs: number }
  | { status: "promoted"; lesson: AgentLesson; via: "threshold" | "real-trait-bypass" };

/**
 * Submit an LLM-extracted lesson observation. Routes through the candidate
 * pool so single-session confabulations cannot pollute the real TraitStore.
 *
 * Gate semantics:
 *  - Existing real trait with the same `(agentId, tag, source="llm")` →
 *    direct reinforcement (the gate has already been cleared once).
 *  - Real traits written by hooks live under a different source namespace
 *    and are NOT reinforced by reflection observations sharing the same tag.
 *  - New candidate accumulates sessionCount across distinct sessions, but
 *    only if separated by at least MIN_PROMOTION_GAP_MS (spaced-repetition
 *    burst-defense).
 *  - Promotion threshold is type-dependent: weakness=3, strength=2.
 *
 * @param sessionId Identifier of the reflection session. Stability matters —
 *   if every call passes a unique id, the gate cannot accumulate.
 */
export function recordLessonCandidate(
  projectPath: string,
  store: TraitStore,
  candidates: CandidateStore,
  input: {
    agentId: string;
    type: LessonType;
    category: LessonCategory;
    tag: string;
    lesson: string;
  },
  sessionId: string,
  now: Date = new Date(),
): CandidateOutcome {
  const { agentId, type, category, tag, lesson } = input;
  const nowIso = now.toISOString();
  // LLM-sourced observation is always submitted with source="llm".
  const source: LessonSource = "llm";

  // Real-trait fast-path: an llm-sourced trait with the same tag was already
  // promoted in the past. The gate has been cleared once; further observations
  // simply reinforce it (with normal frequency decay applying separately).
  //
  // Hooks and "unknown"-legacy traits live under their own source and are
  // intentionally NOT matched here — this is the namespace separation that
  // defends against `task-rework` tag-collisions between hook and reflection.
  const realLessons = store.agents[agentId] ?? [];
  const existingReal = realLessons.find(
    (l) => l.tag === tag && (l.source ?? "unknown") === "llm",
  );
  if (existingReal) {
    const lessonRecord = recordLesson(projectPath, store, { ...input, source });
    return { status: "promoted", lesson: lessonRecord, via: "real-trait-bypass" };
  }

  if (!candidates.candidates[agentId]) {
    candidates.candidates[agentId] = [];
  }
  const bucket = candidates.candidates[agentId];
  const existing = bucket.find((c) => c.tag === tag);

  if (existing) {
    if (existing.lastSessionId === sessionId) {
      // Same session re-extracted the same pattern — do not inflate.
      existing.lastSeen = nowIso;
      if (lesson.length > existing.lesson.length) existing.lesson = lesson;
      saveCandidates(projectPath, candidates);
      return { status: "duplicate", candidate: existing };
    }

    // Burst defense: distinct session id but observed too soon to count as
    // independent. Refresh lastSeen so the TTL doesn't expire stable streams,
    // but do not advance sessionCount.
    const gapMs = now.getTime() - new Date(existing.lastSeen).getTime();
    if (gapMs < MIN_PROMOTION_GAP_MS) {
      existing.lastSeen = nowIso;
      if (lesson.length > existing.lesson.length) existing.lesson = lesson;
      saveCandidates(projectPath, candidates);
      return { status: "too-soon", candidate: existing, gapMs };
    }

    existing.sessionCount++;
    existing.lastSessionId = sessionId;
    existing.lastSeen = nowIso;
    if (lesson.length > existing.lesson.length) existing.lesson = lesson;
    existing.type = type;
    existing.category = category;

    const threshold = promotionThresholdFor(type);
    if (existing.sessionCount >= threshold) {
      // Promote into the real trait store.
      const idx = bucket.indexOf(existing);
      bucket.splice(idx, 1);
      if (bucket.length === 0) delete candidates.candidates[agentId];
      saveCandidates(projectPath, candidates);
      const lessonRecord = recordLesson(projectPath, store, {
        agentId,
        type,
        category,
        tag,
        lesson: existing.lesson,
        source,
      });
      return { status: "promoted", lesson: lessonRecord, via: "threshold" };
    }
    saveCandidates(projectPath, candidates);
    return { status: "pending", candidate: existing };
  }

  const candidate: TraitCandidate = {
    id: `${agentId}_candidate_${Date.now()}`,
    agentId,
    type,
    category,
    tag,
    lesson,
    source,
    sessionCount: 1,
    lastSessionId: sessionId,
    firstSeen: nowIso,
    lastSeen: nowIso,
  };
  bucket.push(candidate);
  saveCandidates(projectPath, candidates);
  return { status: "pending", candidate };
}

/** Flat list of all live candidates (matches pruneStaleCandidates semantics). */
export function getAllCandidates(
  store: CandidateStore,
  now: Date = new Date(),
): TraitCandidate[] {
  const all: TraitCandidate[] = [];
  for (const list of Object.values(store.candidates)) {
    for (const c of list) {
      if (c.sessionCount >= promotionThresholdFor(c.type)) {
        all.push(c);
        continue;
      }
      const ageMs = now.getTime() - new Date(c.lastSeen).getTime();
      if (ageMs < CANDIDATE_TTL_MS) all.push(c);
    }
  }
  return all;
}
