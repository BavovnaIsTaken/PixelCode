/**
 * Validation for `set_game_state` payloads.
 *
 * Until now the server accepted whatever shape arrived: invalid roleTypes,
 * out-of-range hardware/skills, two managers (the role catalog says manager
 * is singleton), and non-Claude providers without an API key. The cost of
 * each was paid lazily — at dispatch time, with confusing error messages
 * far from the action.
 *
 * This module pre-validates the payload so the user sees a clear error at
 * hire time, and the server never persists a corrupt roster.
 *
 * The module is pure — no IO, no globals — so tests can drive it directly.
 */

import { roleCatalog } from "./agents.js";
import type { GameStateData } from "./agents.js";

/** Hardware tier enum indices from Flutter. */
export const MIN_HARDWARE_TIER = 0;
export const MAX_HARDWARE_TIER = 5;

/** Skill levels are bounded so a buggy client cannot inject opus-tier
 *  capability via skills=99. Real values are 1-10; 20 leaves headroom for
 *  future bonuses without being a free pass. */
export const MIN_SKILL_LEVEL = 0;
export const MAX_SKILL_LEVEL = 20;

/**
 * Provider enum from `lib/models/agent_provider.dart`.
 *   0 = cloud (Claude Agent SDK; auth via env ANTHROPIC_API_KEY)
 *   1 = local (Gemini CLI; no API key needed)
 *   3 = deepseek (needs `deepseekApiKey` in session)
 *   4 = kimi     (needs `kimiApiKey` in session)
 */
export const PROVIDER_CLOUD = 0;
export const PROVIDER_LOCAL = 1;
export const PROVIDER_DEEPSEEK = 3;
export const PROVIDER_KIMI = 4;

const KNOWN_PROVIDERS: ReadonlySet<number> = new Set([
  PROVIDER_CLOUD,
  PROVIDER_LOCAL,
  PROVIDER_DEEPSEEK,
  PROVIDER_KIMI,
]);

export type RosterErrorCode =
  | "unknown_role"
  | "manager_singleton"
  | "hardware_out_of_range"
  | "skill_out_of_range"
  | "unknown_provider"
  | "missing_api_key";

export interface RosterError {
  /** instanceId the error refers to ("*" for collection-level errors). */
  instanceId: string;
  code: RosterErrorCode;
  message: string;
}

export interface ValidationContext {
  /** Whether deepseekApiKey is currently present on the session. */
  hasDeepseekKey: boolean;
  /** Whether kimiApiKey is currently present on the session. */
  hasKimiKey: boolean;
}

export interface ValidationResult {
  ok: boolean;
  errors: RosterError[];
}

/**
 * Validate a GameStateData against role-catalog constraints, numeric
 * bounds, and required provider auth. Collects every problem rather
 * than failing fast so the client can surface them all at once.
 */
export function validateGameState(
  state: GameStateData,
  ctx: ValidationContext,
): ValidationResult {
  const errors: RosterError[] = [];

  let managerCount = 0;

  for (const [instanceId, inst] of Object.entries(state.instances ?? {})) {
    // 1. Role must be in the catalog. An unknown role would crash dispatch
    //    when the server tries to read its template/prompt.
    if (!inst || typeof inst !== "object") {
      errors.push({
        instanceId,
        code: "unknown_role",
        message: `Instance ${instanceId} is not a valid object`,
      });
      continue;
    }
    if (!roleCatalog[inst.roleType]) {
      errors.push({
        instanceId,
        code: "unknown_role",
        message: `Unknown role "${inst.roleType}" for instance ${instanceId}`,
      });
      continue;
    }

    if (inst.roleType === "manager") managerCount++;

    // 2. Hardware tier in range.
    if (
      typeof inst.hardware !== "number" ||
      !Number.isFinite(inst.hardware) ||
      inst.hardware < MIN_HARDWARE_TIER ||
      inst.hardware > MAX_HARDWARE_TIER
    ) {
      errors.push({
        instanceId,
        code: "hardware_out_of_range",
        message: `Hardware tier ${inst.hardware} for ${instanceId} is outside [${MIN_HARDWARE_TIER}, ${MAX_HARDWARE_TIER}]`,
      });
    }

    // 3. Skill levels in range. Each entry of the skills map must be a
    //    finite number within [MIN_SKILL_LEVEL, MAX_SKILL_LEVEL].
    const skills = inst.skills ?? {};
    for (const [skillKey, level] of Object.entries(skills)) {
      if (
        typeof level !== "number" ||
        !Number.isFinite(level) ||
        level < MIN_SKILL_LEVEL ||
        level > MAX_SKILL_LEVEL
      ) {
        errors.push({
          instanceId,
          code: "skill_out_of_range",
          message: `Skill ${skillKey}=${level} for ${instanceId} is outside [${MIN_SKILL_LEVEL}, ${MAX_SKILL_LEVEL}]`,
        });
      }
    }

    // 4. Provider must be known. Default (undefined) maps to cloud and
    //    requires no session key.
    if (inst.provider !== undefined) {
      if (!KNOWN_PROVIDERS.has(inst.provider)) {
        errors.push({
          instanceId,
          code: "unknown_provider",
          message: `Unknown provider index ${inst.provider} for ${instanceId}`,
        });
        continue;
      }
      // 5. Non-Claude/non-local providers need their API key on the session.
      //    Failing here gives the user a clear "link account" prompt instead
      //    of a vague "key not set" error during the first dispatch.
      if (inst.provider === PROVIDER_DEEPSEEK && !ctx.hasDeepseekKey) {
        errors.push({
          instanceId,
          code: "missing_api_key",
          message: `Instance ${instanceId} uses DeepSeek but no API key is linked. Open Settings → API keys to link your DeepSeek account.`,
        });
      }
      if (inst.provider === PROVIDER_KIMI && !ctx.hasKimiKey) {
        errors.push({
          instanceId,
          code: "missing_api_key",
          message: `Instance ${instanceId} uses Kimi but no API key is linked. Open Settings → API keys to link your Kimi account.`,
        });
      }
    }
  }

  // 6. Manager singleton — the catalog flags it but nothing was enforcing
  //    it. Two managers would race when delegating off the kanban board.
  if (managerCount > 1) {
    errors.push({
      instanceId: "*",
      code: "manager_singleton",
      message: `Roster contains ${managerCount} manager instances; only one is allowed`,
    });
  }

  return { ok: errors.length === 0, errors };
}

/**
 * Compute the set of instanceIds that disappeared between the previous
 * roster and the new one. Used by the server to clean up `activeAgentTasks`
 * and emit `agent_fired` events.
 */
export function firedInstanceIds(
  prev: GameStateData | undefined,
  next: GameStateData,
): string[] {
  if (!prev) return [];
  const fired: string[] = [];
  const nextIds = new Set(Object.keys(next.instances ?? {}));
  for (const id of Object.keys(prev.instances ?? {})) {
    if (!nextIds.has(id)) fired.push(id);
  }
  return fired;
}

// ─── Persisted game-state envelope ────────────────────────────────────

/** Shape on disk for ~/.pixelcode/projects/{key}/game_state.json. */
export interface PersistedGameStateEnvelope {
  /** JSON-encoded full GameState. We keep it as a string because the
   *  client-side GameState schema evolves on its own cadence and the
   *  server treats it as opaque payload for cross-device sync. */
  fullState: string;
  /** Epoch ms — feeds the last-write-wins guard on cross-device sync. */
  updatedAt: number;
}

export type GameStateLoadResult =
  | { kind: "fresh" }
  | { kind: "loaded"; envelope: PersistedGameStateEnvelope }
  | { kind: "quarantine_outer"; reason: string }
  | { kind: "quarantine_inner"; reason: string }
  | { kind: "shape_mismatch"; reason: string };

/**
 * Decide what to do with the raw text of a persisted game-state file.
 *
 * - `fresh`: file does not exist (caller handles by skipping load).
 * - `loaded`: shape and inner JSON valid; safe to use.
 * - `quarantine_outer`: the file itself is not parseable JSON; the
 *   caller should move the file aside and start fresh.
 * - `quarantine_inner`: the envelope parsed but the embedded `fullState`
 *   is not valid JSON; corrupt — quarantine and start fresh.
 * - `shape_mismatch`: parsed but missing required fields; ignore but
 *   don't quarantine (might be a legacy/partial file we want to keep
 *   around for inspection).
 */
export function classifyPersistedGameState(rawText: string | null): GameStateLoadResult {
  if (rawText === null) return { kind: "fresh" };

  let outer: { fullState?: unknown; updatedAt?: unknown };
  try {
    outer = JSON.parse(rawText);
  } catch (e) {
    return { kind: "quarantine_outer", reason: String(e) };
  }

  if (typeof outer.fullState !== "string" || typeof outer.updatedAt !== "number") {
    return {
      kind: "shape_mismatch",
      reason: `Expected {fullState: string, updatedAt: number}, got fullState=${typeof outer.fullState}, updatedAt=${typeof outer.updatedAt}`,
    };
  }

  try {
    JSON.parse(outer.fullState);
  } catch (e) {
    return { kind: "quarantine_inner", reason: String(e) };
  }

  return {
    kind: "loaded",
    envelope: { fullState: outer.fullState, updatedAt: outer.updatedAt },
  };
}
