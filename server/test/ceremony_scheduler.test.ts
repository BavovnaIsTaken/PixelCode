import { test } from "node:test";
import assert from "node:assert/strict";

import {
  cadenceIntervalMs,
  ceremonyKey,
  dueNow,
  dueOnEvent,
  fireAll,
  isCeremonyDue,
  recordFire,
} from "../src/facilitator/ceremony_scheduler.js";
import type {
  CeremonyFireLog,
  CeremonySpec,
  FacilitatorStyle,
} from "../src/facilitator/types.js";

const T0 = new Date("2026-04-26T10:00:00Z");
const t = (ms: number) => new Date(T0.getTime() + ms);
const day = 24 * 60 * 60 * 1000;

function styleWithSchedule(schedule: CeremonySpec[]): FacilitatorStyle {
  return {
    id: "test",
    displayName: "Test",
    tagline: "",
    laloux: "red",
    personaPrompt: "",
    lexicon: {},
    ceremonySchedule: schedule,
    intakeTemplate: [],
    outputMapper: "mission_briefing",
    toneModifiers: { aggression: 0.5, formality: 0.5, verbosity: 0.5 },
  };
}

// ─── ceremonyKey ───────────────────────────────────────────────────────────

test("ceremonyKey distinguishes by kind, cadence, and triggerEvent", () => {
  const a = ceremonyKey({ kind: "briefing", cadence: "on_event", triggerEvent: "act_start" });
  const b = ceremonyKey({ kind: "briefing", cadence: "on_event", triggerEvent: "act_complete" });
  const c = ceremonyKey({ kind: "briefing", cadence: "weekly" });
  assert.notEqual(a, b);
  assert.notEqual(a, c);
});

test("ceremonyKey is stable for the same spec", () => {
  const k1 = ceremonyKey({ kind: "standup", cadence: "daily" });
  const k2 = ceremonyKey({ kind: "standup", cadence: "daily" });
  assert.equal(k1, k2);
});

// ─── cadenceIntervalMs ────────────────────────────────────────────────────

test("cadenceIntervalMs returns expected windows", () => {
  assert.equal(cadenceIntervalMs("daily"), day);
  assert.equal(cadenceIntervalMs("weekly"), 7 * day);
  assert.equal(cadenceIntervalMs("biweekly"), 14 * day);
  assert.equal(cadenceIntervalMs("monthly"), 30 * day);
});

test("cadenceIntervalMs returns null for non-clock cadences", () => {
  assert.equal(cadenceIntervalMs("on_event"), null);
  assert.equal(cadenceIntervalMs("never"), null);
});

// ─── isCeremonyDue ────────────────────────────────────────────────────────

test("isCeremonyDue — daily ceremony due immediately if never fired", () => {
  const spec: CeremonySpec = { kind: "standup", cadence: "daily" };
  assert.equal(isCeremonyDue(spec, {}, T0), true);
});

test("isCeremonyDue — daily ceremony NOT due 12h after firing", () => {
  const spec: CeremonySpec = { kind: "standup", cadence: "daily" };
  const log: CeremonyFireLog = recordFire({}, spec, T0);
  assert.equal(isCeremonyDue(spec, log, t(12 * 60 * 60 * 1000)), false);
});

test("isCeremonyDue — daily ceremony due exactly 24h after firing", () => {
  const spec: CeremonySpec = { kind: "standup", cadence: "daily" };
  const log: CeremonyFireLog = recordFire({}, spec, T0);
  assert.equal(isCeremonyDue(spec, log, t(day)), true);
});

test("isCeremonyDue — never cadence → false even with no log", () => {
  const spec: CeremonySpec = { kind: "none", cadence: "never" };
  assert.equal(isCeremonyDue(spec, {}, T0), false);
});

test("isCeremonyDue — on_event cadence → false (not clock-driven)", () => {
  const spec: CeremonySpec = {
    kind: "briefing",
    cadence: "on_event",
    triggerEvent: "act_start",
  };
  assert.equal(isCeremonyDue(spec, {}, T0), false);
});

test("isCeremonyDue — weekly ceremony due 8 days after firing", () => {
  const spec: CeremonySpec = { kind: "review", cadence: "weekly" };
  const log = recordFire({}, spec, T0);
  assert.equal(isCeremonyDue(spec, log, t(8 * day)), true);
});

// ─── dueNow ───────────────────────────────────────────────────────────────

test("dueNow filters style.ceremonySchedule to due ceremonies "
  + "preserving order", () => {
  const standup: CeremonySpec = { kind: "standup", cadence: "daily" };
  const review: CeremonySpec = { kind: "review", cadence: "weekly" };
  const briefing: CeremonySpec = {
    kind: "briefing",
    cadence: "on_event",
    triggerEvent: "act_start",
  };
  const style = styleWithSchedule([standup, briefing, review]);

  // Fresh log: standup + review due (briefing is on_event, never via dueNow).
  const due = dueNow(style, {}, T0);
  assert.deepEqual(due, [standup, review]);
});

test("dueNow returns empty when nothing is due", () => {
  const standup: CeremonySpec = { kind: "standup", cadence: "daily" };
  const style = styleWithSchedule([standup]);
  const log = recordFire({}, standup, T0);
  // Only 1h elapsed.
  assert.deepEqual(dueNow(style, log, t(60 * 60 * 1000)), []);
});

// ─── dueOnEvent ───────────────────────────────────────────────────────────

test("dueOnEvent matches triggerEvent against event.kind", () => {
  const briefing: CeremonySpec = {
    kind: "briefing",
    cadence: "on_event",
    triggerEvent: "act_complete",
  };
  const standup: CeremonySpec = { kind: "standup", cadence: "daily" };
  const style = styleWithSchedule([briefing, standup]);

  const due = dueOnEvent(style, {
    kind: "act_complete",
    actId: "a1",
    at: T0,
  });
  assert.deepEqual(due, [briefing]);
});

test("dueOnEvent only returns on_event-cadenced specs", () => {
  // A clock-cadenced ceremony shouldn't appear here even if its kind
  // happens to share a string with an event.
  const review: CeremonySpec = { kind: "review", cadence: "weekly" };
  const style = styleWithSchedule([review]);
  const due = dueOnEvent(style, {
    kind: "task_completed",
    taskId: "t1",
    at: T0,
  });
  assert.deepEqual(due, []);
});

test("dueOnEvent returns empty when no spec matches the event kind", () => {
  const briefing: CeremonySpec = {
    kind: "briefing",
    cadence: "on_event",
    triggerEvent: "act_start",
  };
  const style = styleWithSchedule([briefing]);
  const due = dueOnEvent(style, {
    kind: "task_completed",
    taskId: "t1",
    at: T0,
  });
  assert.deepEqual(due, []);
});

// ─── recordFire / fireAll ─────────────────────────────────────────────────

test("recordFire returns a NEW log object (does not mutate input)", () => {
  const spec: CeremonySpec = { kind: "standup", cadence: "daily" };
  const original: CeremonyFireLog = {};
  const updated = recordFire(original, spec, T0);
  assert.notEqual(updated, original);
  assert.deepEqual(original, {}, "input should not be mutated");
  assert.equal(updated[ceremonyKey(spec)], T0.toISOString());
});

test("recordFire overwrites an existing entry for the same key", () => {
  const spec: CeremonySpec = { kind: "standup", cadence: "daily" };
  const log = recordFire({}, spec, T0);
  const updated = recordFire(log, spec, t(2 * day));
  assert.equal(updated[ceremonyKey(spec)], t(2 * day).toISOString());
});

test("fireAll records every ceremony in order, returns triggers + log", () => {
  const standup: CeremonySpec = { kind: "standup", cadence: "daily" };
  const review: CeremonySpec = { kind: "review", cadence: "weekly" };
  const result = fireAll({}, [standup, review], T0);

  assert.equal(result.triggers.length, 2);
  assert.deepEqual(result.triggers[0]!.spec, standup);
  assert.deepEqual(result.triggers[1]!.spec, review);
  assert.equal(result.triggers[0]!.firedAt, T0);
  assert.equal(
    result.updatedLog[ceremonyKey(standup)],
    T0.toISOString(),
  );
  assert.equal(
    result.updatedLog[ceremonyKey(review)],
    T0.toISOString(),
  );
});

test("fireAll on empty list returns empty triggers and unchanged log", () => {
  const original: CeremonyFireLog = {
    "x:y:": new Date(0).toISOString(),
  };
  const result = fireAll(original, [], T0);
  assert.deepEqual(result.triggers, []);
  assert.deepEqual(result.updatedLog, original);
});
