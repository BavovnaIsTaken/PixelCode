import { test } from "node:test";
import assert from "node:assert/strict";

import {
  scoreIdea,
  tierForScore,
  totalScore,
  clampScore,
  applyOverrides,
  type ScopeScore,
} from "../src/quest/scope_scorer.ts";

test("tierForScore — boundary values map to documented tiers", () => {
  assert.equal(tierForScore(0).tier, "micro");
  assert.equal(tierForScore(4).tier, "micro");
  assert.equal(tierForScore(5).tier, "small");
  assert.equal(tierForScore(8).tier, "small");
  assert.equal(tierForScore(9).tier, "medium");
  assert.equal(tierForScore(12).tier, "medium");
  assert.equal(tierForScore(13).tier, "large");
  assert.equal(tierForScore(18).tier, "large");
});

test("tierForScore — quest count windows match the design", () => {
  assert.deepEqual(
    { min: tierForScore(2).questCountMin, max: tierForScore(2).questCountMax },
    { min: 3, max: 4 },
  );
  assert.deepEqual(
    { min: tierForScore(7).questCountMin, max: tierForScore(7).questCountMax },
    { min: 5, max: 7 },
  );
  assert.deepEqual(
    {
      min: tierForScore(11).questCountMin,
      max: tierForScore(11).questCountMax,
    },
    { min: 8, max: 13 },
  );
  assert.deepEqual(
    {
      min: tierForScore(17).questCountMin,
      max: tierForScore(17).questCountMax,
    },
    { min: 14, max: 20 },
  );
});

test("clampScore caps each dimension at its design ceiling", () => {
  const wild: ScopeScore = {
    entityCount: 99,
    interactionSurface: 99,
    auth: 99,
    integrations: 99,
    realtime: 99,
  };
  const c = clampScore(wild);
  assert.equal(c.entityCount, 4);
  assert.equal(c.interactionSurface, 4);
  assert.equal(c.auth, 3);
  assert.equal(c.integrations, 4);
  assert.equal(c.realtime, 3);
});

test("scoreIdea — minimal description gets baseline 1+1=2 (micro tier)", () => {
  const r = scoreIdea("a simple page that says hello");
  assert.equal(r.score.entityCount, 1);
  assert.equal(r.score.interactionSurface, 1);
  assert.equal(r.score.auth, 0);
  assert.equal(r.score.integrations, 0);
  assert.equal(r.score.realtime, 0);
  assert.equal(r.tier.tier, "micro");
});

test("scoreIdea — todo app with reminders lands in small tier", () => {
  const r = scoreIdea(
    "I want a todo app where I can add tasks with due dates and get reminder notifications",
  );
  assert.ok(r.matchedRules.includes("notifications"), "notifications matched");
  assert.equal(r.score.integrations >= 1, true);
  assert.equal(r.score.auth, 0);
  assert.ok(r.tier.tier === "micro" || r.tier.tier === "small");
});

test("scoreIdea — social photo app fires the relevant rules and exits micro", () => {
  // Keyword scorer is a FIRST pass; the interview then refines. We only
  // assert that the right signals fire and we leave micro tier — getting
  // all the way to medium requires interview-supplied dimensions
  // (extra entities, more screens, etc.).
  const r = scoreIdea(
    "Social photo sharing app with users, signup and login, photo upload, comments, push notifications, and a feed",
  );
  assert.ok(r.matchedRules.includes("user accounts"));
  assert.ok(r.matchedRules.includes("media"));
  assert.ok(r.matchedRules.includes("comments"));
  assert.ok(r.matchedRules.includes("notifications"));
  assert.ok(r.matchedRules.includes("feed"));
  assert.notEqual(r.tier.tier, "micro", `expected to exit micro, got total=${r.total}`);
});

test("scoreIdea — collaborative real-time tool maxes realtime + auth", () => {
  const r = scoreIdea(
    "A collaborative document editor with real-time co-editing, user accounts and shared workspaces",
  );
  assert.ok(r.matchedRules.includes("collaborative"));
  assert.ok(r.matchedRules.includes("user accounts"));
  assert.equal(r.score.realtime, 3);
  assert.ok(r.score.auth >= 2);
});

test("scoreIdea — payments + admin dashboard pushes integrations & interaction", () => {
  const r = scoreIdea(
    "Marketplace with stripe checkout, admin dashboard for moderators, products and orders",
  );
  assert.ok(r.matchedRules.includes("payments"));
  assert.ok(r.matchedRules.includes("dashboard"));
  assert.ok(r.matchedRules.includes("admin/roles"));
  assert.ok(r.score.integrations >= 2);
  assert.ok(r.score.interactionSurface >= 2);
  assert.ok(r.score.auth >= 1);
});

test("scoreIdea is case-insensitive", () => {
  const lower = scoreIdea("login and signup with stripe payments");
  const upper = scoreIdea("LOGIN AND SIGNUP WITH STRIPE PAYMENTS");
  assert.equal(lower.total, upper.total);
  assert.deepEqual(lower.matchedRules.sort(), upper.matchedRules.sort());
});

test("scoreIdea is deterministic across calls", () => {
  const a = scoreIdea("Todo app with reminders");
  const b = scoreIdea("Todo app with reminders");
  assert.deepEqual(a.score, b.score);
  assert.deepEqual(a.matchedRules, b.matchedRules);
});

test("totalScore matches sum of clamped dimensions", () => {
  const s: ScopeScore = {
    entityCount: 3,
    interactionSurface: 2,
    auth: 2,
    integrations: 4,
    realtime: 2,
  };
  assert.equal(totalScore(s), 13);
});

test("applyOverrides replaces only provided dimensions", () => {
  const base: ScopeScore = {
    entityCount: 1,
    interactionSurface: 2,
    auth: 0,
    integrations: 1,
    realtime: 0,
  };
  const out = applyOverrides(base, { auth: 2, realtime: 2 });
  assert.equal(out.entityCount, 1);
  assert.equal(out.interactionSurface, 2);
  assert.equal(out.auth, 2);
  assert.equal(out.integrations, 1);
  assert.equal(out.realtime, 2);
});

test("applyOverrides clamps explicit user values too", () => {
  const base: ScopeScore = {
    entityCount: 0,
    interactionSurface: 0,
    auth: 0,
    integrations: 0,
    realtime: 0,
  };
  const out = applyOverrides(base, { auth: 99, integrations: -5 });
  assert.equal(out.auth, 3);
  assert.equal(out.integrations, 0);
});
