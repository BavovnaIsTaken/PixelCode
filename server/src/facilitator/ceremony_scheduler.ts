/**
 * Ceremony Scheduler — pure, deterministic logic that decides which
 * ceremonies are due to fire given a style's `ceremonySchedule` and a
 * fire log of past firings.
 *
 * No LLM calls. No clock side effects (caller passes `now`). Suitable
 * for unit testing without time travel.
 *
 * Design: docs/FACILITATOR_SYSTEM.md §2 (ceremonyRhythm) + §3
 * (FacilitatorRunner contract).
 */

import type {
  CeremonyCadence,
  CeremonyFireLog,
  CeremonySpec,
  CeremonyTrigger,
  FacilitatorEvent,
  FacilitatorStyle,
} from "./types.js";

// ─── Fire-log key derivation ────────────────────────────────────────────────

/**
 * Key used in the `CeremonyFireLog` to track when a ceremony last fired.
 * Distinct ceremonies of the same kind can coexist (e.g. two `briefing`
 * specs with different `triggerEvent`s); the key includes all three
 * fields to keep them separate.
 */
export function ceremonyKey(spec: CeremonySpec): string {
  return `${spec.kind}:${spec.cadence}:${spec.triggerEvent ?? ""}`;
}

// ─── Cadence intervals ──────────────────────────────────────────────────────

/**
 * Minimum elapsed time before a cadence-based ceremony fires again.
 * `on_event` and `never` return `null` — they don't fire on the clock.
 */
export function cadenceIntervalMs(cadence: CeremonyCadence): number | null {
  switch (cadence) {
    case "daily":
      return 24 * 60 * 60 * 1000;
    case "weekly":
      return 7 * 24 * 60 * 60 * 1000;
    case "biweekly":
      return 14 * 24 * 60 * 60 * 1000;
    case "monthly":
      return 30 * 24 * 60 * 60 * 1000;
    case "on_event":
    case "never":
      return null;
  }
}

// ─── Due-check logic ────────────────────────────────────────────────────────

/**
 * Decide whether a single ceremony is due now.
 *
 * Rules:
 *   - `never` cadence → never due (returns `false`).
 *   - `on_event` cadence → never due via this check (it fires from
 *     `tick(event)`, not from the wall clock).
 *   - Cadence-based → due if (a) we have no record of it firing yet,
 *     OR (b) the elapsed time since last fire ≥ the cadence interval.
 */
export function isCeremonyDue(
  spec: CeremonySpec,
  fireLog: CeremonyFireLog,
  now: Date,
): boolean {
  const interval = cadenceIntervalMs(spec.cadence);
  if (interval === null) return false;

  const lastIso = fireLog[ceremonyKey(spec)];
  if (lastIso === undefined) return true;

  const elapsed = now.getTime() - new Date(lastIso).getTime();
  return elapsed >= interval;
}

/**
 * Return all ceremonies in the style's schedule that are due to fire
 * now. Order matches the style's `ceremonySchedule` order.
 *
 * `on_event` ceremonies are NOT returned here (use `dueOnEvent`).
 */
export function dueNow(
  style: FacilitatorStyle,
  fireLog: CeremonyFireLog,
  now: Date,
): CeremonySpec[] {
  return style.ceremonySchedule.filter((spec) =>
    isCeremonyDue(spec, fireLog, now),
  );
}

/**
 * Return ceremonies fired by a runtime event. Matches `triggerEvent`
 * against the event's `kind`.
 */
export function dueOnEvent(
  style: FacilitatorStyle,
  event: FacilitatorEvent,
): CeremonySpec[] {
  return style.ceremonySchedule.filter(
    (spec) => spec.cadence === "on_event" && spec.triggerEvent === event.kind,
  );
}

// ─── Fire-log mutation ──────────────────────────────────────────────────────

/**
 * Record that a ceremony fired at `at`. Returns a NEW fire log — the
 * input is treated as immutable for predictable state mgmt.
 */
export function recordFire(
  fireLog: CeremonyFireLog,
  spec: CeremonySpec,
  at: Date,
): CeremonyFireLog {
  return {
    ...fireLog,
    [ceremonyKey(spec)]: at.toISOString(),
  };
}

/**
 * Convenience: convert a list of due specs into `CeremonyTrigger[]`,
 * recording every fire in a single pass and returning the updated log.
 */
export function fireAll(
  fireLog: CeremonyFireLog,
  specs: CeremonySpec[],
  at: Date,
): { triggers: CeremonyTrigger[]; updatedLog: CeremonyFireLog } {
  let log = fireLog;
  const triggers: CeremonyTrigger[] = [];
  for (const spec of specs) {
    log = recordFire(log, spec, at);
    triggers.push({ spec, firedAt: at });
  }
  return { triggers, updatedLog: log };
}
