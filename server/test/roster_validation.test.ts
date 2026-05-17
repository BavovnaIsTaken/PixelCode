import { test } from "node:test";
import assert from "node:assert/strict";
import {
  PROVIDER_CLOUD,
  PROVIDER_DEEPSEEK,
  PROVIDER_KIMI,
  PROVIDER_LOCAL,
  classifyPersistedGameState,
  firedInstanceIds,
  validateGameState,
} from "../src/roster_validation.ts";
import type { GameStateData } from "../src/agents.ts";

function instance(overrides: Partial<GameStateData["instances"][string]> = {}) {
  return {
    roleType: "coder",
    nickname: "Bohdan",
    hardware: 2,
    skills: {},
    ...overrides,
  };
}

const NO_KEYS = { hasDeepseekKey: false, hasKimiKey: false };
const BOTH_KEYS = { hasDeepseekKey: true, hasKimiKey: true };

test("validateGameState accepts a clean roster", () => {
  const r = validateGameState(
    {
      instances: {
        "manager#1": instance({ roleType: "manager" }),
        "coder#1": instance(),
        "coder#2": instance({ hardware: 4, skills: { precision: 5, speed: 8 } }),
      },
    },
    NO_KEYS,
  );
  assert.equal(r.ok, true);
  assert.deepEqual(r.errors, []);
});

test("validateGameState empty roster is valid", () => {
  const r = validateGameState({ instances: {} }, NO_KEYS);
  assert.equal(r.ok, true);
});

test("validateGameState rejects unknown role", () => {
  const r = validateGameState(
    { instances: { "x#1": instance({ roleType: "wizard" }) } },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  assert.equal(r.errors.length, 1);
  assert.equal(r.errors[0].code, "unknown_role");
  assert.equal(r.errors[0].instanceId, "x#1");
});

test("validateGameState rejects two managers", () => {
  const r = validateGameState(
    {
      instances: {
        "manager#1": instance({ roleType: "manager" }),
        "manager#2": instance({ roleType: "manager" }),
      },
    },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  const codes = r.errors.map((e) => e.code);
  assert.ok(codes.includes("manager_singleton"));
});

test("validateGameState single manager is allowed", () => {
  const r = validateGameState(
    { instances: { "manager#1": instance({ roleType: "manager" }) } },
    NO_KEYS,
  );
  assert.equal(r.ok, true);
});

test("validateGameState rejects out-of-range hardware tiers", () => {
  for (const bad of [-1, 99, NaN, Infinity]) {
    const r = validateGameState(
      { instances: { "coder#1": instance({ hardware: bad as number }) } },
      NO_KEYS,
    );
    assert.equal(r.ok, false, `expected reject hardware=${bad}`);
    assert.ok(r.errors.some((e) => e.code === "hardware_out_of_range"));
  }
});

test("validateGameState rejects out-of-range skill levels", () => {
  const r = validateGameState(
    { instances: { "coder#1": instance({ skills: { precision: 99 } }) } },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.code === "skill_out_of_range"));
});

test("validateGameState reports every bad skill, not just the first", () => {
  const r = validateGameState(
    {
      instances: {
        "coder#1": instance({ skills: { precision: 99, speed: -1, insight: 5 } }),
      },
    },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  const skillErrs = r.errors.filter((e) => e.code === "skill_out_of_range");
  assert.equal(skillErrs.length, 2);
});

test("validateGameState rejects DeepSeek hire without an API key", () => {
  const r = validateGameState(
    {
      instances: {
        "coder#1": instance({ provider: PROVIDER_DEEPSEEK }),
      },
    },
    { hasDeepseekKey: false, hasKimiKey: false },
  );
  assert.equal(r.ok, false);
  const err = r.errors.find((e) => e.code === "missing_api_key");
  assert.ok(err);
  assert.match(err!.message, /DeepSeek/);
});

test("validateGameState accepts DeepSeek hire when key is linked", () => {
  const r = validateGameState(
    { instances: { "coder#1": instance({ provider: PROVIDER_DEEPSEEK }) } },
    { hasDeepseekKey: true, hasKimiKey: false },
  );
  assert.equal(r.ok, true);
});

test("validateGameState rejects Kimi hire without an API key", () => {
  const r = validateGameState(
    { instances: { "coder#1": instance({ provider: PROVIDER_KIMI }) } },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.code === "missing_api_key"));
});

test("validateGameState accepts cloud and local providers without session keys", () => {
  const r = validateGameState(
    {
      instances: {
        "a#1": instance({ provider: PROVIDER_CLOUD }),
        "b#1": instance({ provider: PROVIDER_LOCAL }),
      },
    },
    NO_KEYS,
  );
  assert.equal(r.ok, true);
});

test("validateGameState rejects unknown provider index", () => {
  const r = validateGameState(
    { instances: { "x#1": instance({ provider: 99 }) } },
    BOTH_KEYS,
  );
  assert.equal(r.ok, false);
  assert.ok(r.errors.some((e) => e.code === "unknown_provider"));
});

test("validateGameState collects multiple errors across instances", () => {
  const r = validateGameState(
    {
      instances: {
        "manager#1": instance({ roleType: "manager" }),
        "manager#2": instance({ roleType: "manager", hardware: -5 }),
        "x#1": instance({ roleType: "wizard" }),
        "y#1": instance({ provider: PROVIDER_DEEPSEEK, skills: { p: 99 } }),
      },
    },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  const codes = r.errors.map((e) => e.code).sort();
  assert.ok(codes.includes("manager_singleton"));
  assert.ok(codes.includes("hardware_out_of_range"));
  assert.ok(codes.includes("unknown_role"));
  assert.ok(codes.includes("missing_api_key"));
  assert.ok(codes.includes("skill_out_of_range"));
});

test("validateGameState defends against null-ish instance entries", () => {
  const r = validateGameState(
    { instances: { "a#1": null as unknown as GameStateData["instances"][string] } },
    NO_KEYS,
  );
  assert.equal(r.ok, false);
  assert.equal(r.errors[0].code, "unknown_role");
});

// ─── firedInstanceIds ──────────────────────────────────────────────────

test("firedInstanceIds returns ids removed in the new roster", () => {
  const prev: GameStateData = {
    instances: { "coder#1": instance(), "coder#2": instance(), "manager#1": instance({ roleType: "manager" }) },
  };
  const next: GameStateData = {
    instances: { "coder#1": instance(), "manager#1": instance({ roleType: "manager" }) },
  };
  assert.deepEqual(firedInstanceIds(prev, next), ["coder#2"]);
});

test("firedInstanceIds returns nothing when roster unchanged", () => {
  const state: GameStateData = { instances: { "coder#1": instance() } };
  assert.deepEqual(firedInstanceIds(state, state), []);
});

test("firedInstanceIds returns nothing on first roster (no prev)", () => {
  const next: GameStateData = { instances: { "coder#1": instance() } };
  assert.deepEqual(firedInstanceIds(undefined, next), []);
});

test("firedInstanceIds detects total wipe", () => {
  const prev: GameStateData = { instances: { a: instance(), b: instance() } };
  const next: GameStateData = { instances: {} };
  assert.deepEqual(firedInstanceIds(prev, next).sort(), ["a", "b"]);
});

// ─── classifyPersistedGameState ───────────────────────────────────────

test("classifyPersistedGameState returns 'fresh' for null input", () => {
  assert.equal(classifyPersistedGameState(null).kind, "fresh");
});

test("classifyPersistedGameState accepts a well-formed envelope with valid inner JSON", () => {
  const inner = JSON.stringify({ grim: 100, instances: {} });
  const env = JSON.stringify({ fullState: inner, updatedAt: 1700000000 });
  const r = classifyPersistedGameState(env);
  assert.equal(r.kind, "loaded");
  if (r.kind === "loaded") {
    assert.equal(r.envelope.fullState, inner);
    assert.equal(r.envelope.updatedAt, 1700000000);
  }
});

test("classifyPersistedGameState quarantines unparseable outer JSON", () => {
  const r = classifyPersistedGameState("{ this is not json");
  assert.equal(r.kind, "quarantine_outer");
});

test("classifyPersistedGameState quarantines parseable envelope with invalid inner JSON", () => {
  const env = JSON.stringify({ fullState: "{ broken inner", updatedAt: 1 });
  const r = classifyPersistedGameState(env);
  assert.equal(r.kind, "quarantine_inner");
});

test("classifyPersistedGameState rejects (without quarantine) wrong-shape envelopes", () => {
  // Missing updatedAt → unsafe to use, but legacy partial files may look
  // like this; preserve the file so a curious user can inspect it.
  for (const wrong of [
    JSON.stringify({}),
    JSON.stringify({ fullState: "{}" }),
    JSON.stringify({ updatedAt: 1 }),
    JSON.stringify({ fullState: 42, updatedAt: 1 }),
    JSON.stringify({ fullState: "{}", updatedAt: "not-a-number" }),
  ]) {
    const r = classifyPersistedGameState(wrong);
    assert.equal(r.kind, "shape_mismatch", `expected shape_mismatch for ${wrong}`);
  }
});
