/**
 * Integration: roster lifecycle through validation, persistence, and
 * fire-mid-task cleanup.
 *
 * Composes WP5 modules (validateGameState, firedInstanceIds,
 * classifyPersistedGameState) with the persistence envelope to verify
 * the full hire/fire daily flow.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  classifyPersistedGameState,
  firedInstanceIds,
  validateGameState,
} from "../../src/roster_validation.ts";
import type { GameStateData } from "../../src/agents.ts";

function inst(roleType: string, overrides: Record<string, unknown> = {}) {
  return {
    roleType,
    nickname: roleType,
    hardware: 2,
    skills: { precision: 5 },
    ...overrides,
  };
}

test("e2e: hire sequence — first manager + 2 coders accepted", () => {
  const state: GameStateData = {
    instances: {
      "manager#1": inst("manager"),
      "coder#1": inst("coder"),
      "coder#2": inst("coder"),
    },
  };
  const r = validateGameState(state, {
    hasDeepseekKey: false,
    hasKimiKey: false,
  });
  assert.equal(r.ok, true);
  assert.equal(firedInstanceIds(undefined, state).length, 0);
});

test("e2e: trying to hire a second manager is rejected (single error)", () => {
  const state: GameStateData = {
    instances: {
      "manager#1": inst("manager"),
      "manager#2": inst("manager"),
    },
  };
  const r = validateGameState(state, { hasDeepseekKey: false, hasKimiKey: false });
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.code === "manager_singleton"));
});

test(
  "e2e: hiring DeepSeek without a key fails fast; supplying the key recovers",
  () => {
    const state: GameStateData = {
      instances: { "coder#1": inst("coder", { provider: 3 }) },
    };
    const before = validateGameState(state, {
      hasDeepseekKey: false,
      hasKimiKey: false,
    });
    assert.equal(before.ok, false);
    assert.ok(before.errors.some((e) => e.code === "missing_api_key"));

    const after = validateGameState(state, {
      hasDeepseekKey: true,
      hasKimiKey: false,
    });
    assert.equal(after.ok, true);
  });

test(
  "e2e: fire-mid-task — diff produces the right cleanup set, manager singleton enforced after",
  () => {
    const before: GameStateData = {
      instances: {
        "manager#1": inst("manager"),
        "coder#1": inst("coder"),
        "coder#2": inst("coder"),
        "tester#1": inst("tester"),
      },
    };
    // Fire two coders + the tester. activeAgentTasks for the
    // server-side handler would clear these ids based on the diff.
    const after: GameStateData = {
      instances: { "manager#1": inst("manager") },
    };
    const fired = firedInstanceIds(before, after).sort();
    assert.deepEqual(fired, ["coder#1", "coder#2", "tester#1"]);

    // The post-fire roster is still valid (manager singleton ≤ 1).
    const r = validateGameState(after, { hasDeepseekKey: false, hasKimiKey: false });
    assert.equal(r.ok, true);
  });

test(
  "e2e: persisted state envelope — corrupted inner JSON is quarantined, not adopted",
  () => {
    // The classifier sees an outer envelope that parses fine, but the
    // inner fullState is broken. The server's loadPersistedGameState
    // would move the file aside and start fresh.
    const env = JSON.stringify({
      fullState: "{ malformed inside",
      updatedAt: 1700000000,
    });
    const r = classifyPersistedGameState(env);
    assert.equal(r.kind, "quarantine_inner");
  });

test(
  "e2e: persisted state envelope — wrong-shape file is ignored without quarantine",
  () => {
    // Old/partial files might miss `updatedAt`; we want to keep them on
    // disk for inspection rather than wiping silently.
    const env = JSON.stringify({ fullState: "{}" });
    const r = classifyPersistedGameState(env);
    assert.equal(r.kind, "shape_mismatch");
  });

test(
  "e2e: validation collects every problem in one pass (UI shows all at once)",
  () => {
    const state: GameStateData = {
      instances: {
        "manager#1": inst("manager"),
        "manager#2": inst("manager", { hardware: -2 }),
        "x#1": inst("wizard" /* unknown role */),
        "y#1": inst("coder", { provider: 3, skills: { p: 99 } }),
      },
    };
    const r = validateGameState(state, {
      hasDeepseekKey: false,
      hasKimiKey: false,
    });
    assert.equal(r.ok, false);
    const codes = new Set(r.errors.map((e) => e.code));
    assert.ok(codes.has("manager_singleton"));
    assert.ok(codes.has("hardware_out_of_range"));
    assert.ok(codes.has("unknown_role"));
    assert.ok(codes.has("missing_api_key"));
    assert.ok(codes.has("skill_out_of_range"));
  });
