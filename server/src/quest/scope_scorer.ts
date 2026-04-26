/**
 * Scope Scorer — converts a free-text app idea into a typed ScopeScore
 * across 5 dimensions (entityCount, interactionSurface, auth, integrations,
 * realtime). The total maps to a QuestTier and quest-count budget.
 *
 * This is the FIRST pass that runs before the intake interview. The interview
 * then refines/overrides individual dimensions where the score is uncertain.
 *
 * Design: docs/QUEST_SYSTEM.md §2.3.
 */

export interface ScopeScore {
  entityCount: number;       // 0–4
  interactionSurface: number;// 0–4
  auth: number;              // 0–3
  integrations: number;      // 0–4
  realtime: number;          // 0–3
}

export type QuestTier = "micro" | "small" | "medium" | "large";

export interface TierInfo {
  tier: QuestTier;
  questCountMin: number;
  questCountMax: number;
}

/** Cap each dimension at its design ceiling. */
export function clampScore(s: ScopeScore): ScopeScore {
  return {
    entityCount: clamp(s.entityCount, 0, 4),
    interactionSurface: clamp(s.interactionSurface, 0, 4),
    auth: clamp(s.auth, 0, 3),
    integrations: clamp(s.integrations, 0, 4),
    realtime: clamp(s.realtime, 0, 3),
  };
}

export function totalScore(s: ScopeScore): number {
  const c = clampScore(s);
  return (
    c.entityCount + c.interactionSurface + c.auth + c.integrations + c.realtime
  );
}

export function tierForScore(total: number): TierInfo {
  if (total <= 4) return { tier: "micro", questCountMin: 3, questCountMax: 4 };
  if (total <= 8) return { tier: "small", questCountMin: 5, questCountMax: 7 };
  if (total <= 12) return { tier: "medium", questCountMin: 8, questCountMax: 13 };
  return { tier: "large", questCountMin: 14, questCountMax: 20 };
}

// ─── Keyword rules ──────────────────────────────────────────────────────────

interface KeywordRule {
  /** Pattern matched against the lower-cased description. */
  pattern: RegExp;
  /** Per-dimension increments to add (capped after summation). */
  bumps: Partial<ScopeScore>;
  /** Short label, used by tests + UI for explainability. */
  label: string;
}

/**
 * The rule list. Each rule fires INDEPENDENTLY — multiple matches accumulate.
 * Patterns are compiled once at module load.
 *
 * Order does not matter for scoring (commutative addition), but kept roughly
 * by dimension for readability.
 */
export const KEYWORD_RULES: KeywordRule[] = [
  // Auth
  { pattern: /\b(users?|accounts?|login|sign[- ]?up|sign[- ]?in)\b/, bumps: { auth: 2 }, label: "user accounts" },
  { pattern: /\b(admin|roles?|permissions?|moderation|moderators?)\b/, bumps: { auth: 1 }, label: "admin/roles" },
  { pattern: /\b(oauth|google login|facebook login|sso|social login)\b/, bumps: { auth: 1, integrations: 1 }, label: "social login" },

  // Integrations
  { pattern: /\b(payments?|stripe|checkout|billing|subscription)\b/, bumps: { integrations: 2 }, label: "payments" },
  { pattern: /\b(map|maps|location|gps|geolocation|geofenc\w*)\b/, bumps: { integrations: 1 }, label: "maps/location" },
  { pattern: /\b(upload|photo|video|file|attach\w*|camera)\b/, bumps: { integrations: 1 }, label: "media" },
  { pattern: /\b(notifications?|push|remind\w*|alert\w*)\b/, bumps: { integrations: 1 }, label: "notifications" },
  { pattern: /\b(email|smtp|mailing|newsletter)\b/, bumps: { integrations: 1 }, label: "email" },
  { pattern: /\b(sms|twilio|phone verification)\b/, bumps: { integrations: 1 }, label: "sms" },
  { pattern: /\b(ai|llm|gpt|chatgpt|claude|openai|anthropic)\b/, bumps: { integrations: 1 }, label: "AI/LLM" },

  // Realtime
  { pattern: /\b(real[- ]?time|live|websocket|streaming)\b/, bumps: { realtime: 2 }, label: "realtime" },
  { pattern: /\b(chat|messaging|conversation)\b/, bumps: { realtime: 2, entityCount: 1 }, label: "chat" },
  { pattern: /\b(collab\w*|multiplayer|co[- ]?editing|shared cursor)\b/, bumps: { realtime: 3 }, label: "collaborative" },
  { pattern: /\b(sync|synchroniz\w*|offline[- ]?first)\b/, bumps: { realtime: 1 }, label: "sync" },

  // Interaction surface
  { pattern: /\b(dashboard|admin panel|analytics)\b/, bumps: { interactionSurface: 2 }, label: "dashboard" },
  { pattern: /\b(crud|create.+update|edit and delete|manage \w+)\b/, bumps: { interactionSurface: 2 }, label: "CRUD" },
  { pattern: /\b(feed|timeline|stream of)\b/, bumps: { interactionSurface: 1, entityCount: 1 }, label: "feed" },
  { pattern: /\b(search|filter\w*|sort\w*)\b/, bumps: { interactionSurface: 1 }, label: "search/filter" },

  // Entities (proxies — actual count adjusted by noun-density heuristic below)
  { pattern: /\b(comments?|reviews?|ratings?)\b/, bumps: { entityCount: 1 }, label: "comments" },
  { pattern: /\b(post|article|blog|story|stories)\b/, bumps: { entityCount: 1 }, label: "posts" },
  { pattern: /\b(product|item|listing|inventory)\b/, bumps: { entityCount: 1 }, label: "products" },
  { pattern: /\b(order|cart|checkout)\b/, bumps: { entityCount: 1 }, label: "orders" },
  { pattern: /\b(event|booking|appointment|reservation)\b/, bumps: { entityCount: 1 }, label: "events" },
  { pattern: /\b(group|team|workspace|tenant)\b/, bumps: { entityCount: 1, auth: 1 }, label: "groups" },
];

// ─── Scoring ────────────────────────────────────────────────────────────────

export interface ScoreBreakdown {
  score: ScopeScore;
  matchedRules: string[];
  total: number;
  tier: TierInfo;
}

/**
 * Score an idea by accumulating bumps from every matching rule.
 *
 * Returns the dimension-clamped score, the raw label list of matched rules
 * (for UI explainability and test assertions), the total, and the tier.
 */
export function scoreIdea(description: string): ScoreBreakdown {
  const text = description.toLowerCase();
  const acc: ScopeScore = {
    entityCount: 0,
    interactionSurface: 0,
    auth: 0,
    integrations: 0,
    realtime: 0,
  };
  const matched: string[] = [];

  for (const rule of KEYWORD_RULES) {
    if (rule.pattern.test(text)) {
      acc.entityCount += rule.bumps.entityCount ?? 0;
      acc.interactionSurface += rule.bumps.interactionSurface ?? 0;
      acc.auth += rule.bumps.auth ?? 0;
      acc.integrations += rule.bumps.integrations ?? 0;
      acc.realtime += rule.bumps.realtime ?? 0;
      matched.push(rule.label);
    }
  }

  // Baseline interaction surface — every app has at least one screen.
  if (acc.interactionSurface === 0) acc.interactionSurface = 1;

  // Baseline entity count — there's always SOMETHING the app stores.
  if (acc.entityCount === 0) acc.entityCount = 1;

  const score = clampScore(acc);
  const total = totalScore(score);
  const tier = tierForScore(total);
  return { score, matchedRules: matched, total, tier };
}

/**
 * Apply explicit overrides from intake-interview answers. Each provided
 * dimension REPLACES the heuristic value (it's a typed user signal,
 * not a bump).
 */
export function applyOverrides(
  base: ScopeScore,
  overrides: Partial<ScopeScore>,
): ScopeScore {
  return clampScore({
    entityCount: overrides.entityCount ?? base.entityCount,
    interactionSurface:
      overrides.interactionSurface ?? base.interactionSurface,
    auth: overrides.auth ?? base.auth,
    integrations: overrides.integrations ?? base.integrations,
    realtime: overrides.realtime ?? base.realtime,
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}
