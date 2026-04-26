import { test } from "node:test";
import assert from "node:assert/strict";

import {
  FacilitatorRunner,
  initState,
} from "../src/facilitator/runner.js";
import {
  GeneratorRegistry,
  type GeneratorInput,
  type GeneratorOutput,
  type StyledOutputGenerator,
} from "../src/facilitator/output_generator.js";
import type {
  FacilitatorStyle,
} from "../src/facilitator/types.js";

// ─── Test fixtures ─────────────────────────────────────────────────────────

const T0 = new Date("2026-04-26T10:00:00Z");
const day = 24 * 60 * 60 * 1000;

const gameMaster: FacilitatorStyle = {
  id: "game_master",
  displayName: "Game Master",
  tagline: "",
  laloux: "green",
  personaPrompt: "",
  lexicon: { task: "quest" },
  ceremonySchedule: [
    {
      kind: "briefing",
      cadence: "on_event",
      triggerEvent: "act_complete",
    },
  ],
  intakeTemplate: [
    {
      id: "party",
      prompt: "",
      inputKind: "choice",
      choices: ["Solo", "Party", "Public"],
      mapsTo: "auth",
    },
  ],
  outputMapper: "quest_line",
  toneModifiers: { aggression: 0.1, formality: 0.2, verbosity: 0.7 },
};

const marina: FacilitatorStyle = {
  ...gameMaster,
  id: "marina",
  displayName: "Marina",
  laloux: "amber",
  outputMapper: "milestone_tree",
  ceremonySchedule: [
    { kind: "review", cadence: "weekly" },
  ],
};

const drill: FacilitatorStyle = {
  ...gameMaster,
  id: "drill_sergeant",
  displayName: "Drill",
  laloux: "red",
  outputMapper: "mission_briefing",
  ceremonySchedule: [
    { kind: "standup", cadence: "daily" },
    {
      kind: "briefing",
      cadence: "on_event",
      triggerEvent: "mission_assigned",
    },
  ],
};

function makeRunner() {
  return new FacilitatorRunner({
    clock: () => T0,
    newId: () => "fixed-id",
  });
}

// ─── start() — per-style happy path ────────────────────────────────────────

test("start — Game Master produces quest_line output", async () => {
  const runner = makeRunner();
  const state = initState("/tmp/proj", gameMaster);
  const seed = await runner.start(state, "todo app with reminders", {
    party: "Solo",
  });
  assert.equal(seed.outputFormat, "quest_line");
  const parsed = JSON.parse(seed.outputJson);
  assert.equal(parsed.format, "quest_line");
  assert.equal(parsed.id, "fixed-id");
  assert.ok(Array.isArray(parsed.acts));
  assert.equal(state.outputId, "fixed-id");
});

test("start — Marina produces milestone_tree output", async () => {
  const runner = makeRunner();
  const state = initState("/tmp/proj", marina);
  const seed = await runner.start(state, "internal CRUD dashboard", {
    party: "Public",
  });
  assert.equal(seed.outputFormat, "milestone_tree");
  const parsed = JSON.parse(seed.outputJson);
  assert.equal(parsed.format, "milestone_tree");
  assert.ok(Array.isArray(parsed.milestones));
});

test("start — Drill Sergeant produces mission_briefing output", async () => {
  const runner = makeRunner();
  const state = initState("/tmp/proj", drill);
  const seed = await runner.start(state, "tiny landing page", {
    party: "Solo",
  });
  assert.equal(seed.outputFormat, "mission_briefing");
  const parsed = JSON.parse(seed.outputJson);
  assert.equal(parsed.format, "mission_briefing");
  assert.ok(Array.isArray(parsed.missions));
});

// ─── start() — intake-driven sizing ─────────────────────────────────────────

test("start — answers boost score → larger output", async () => {
  const runner = makeRunner();

  // Solo answer → small; Public answer → bumps auth to 3
  // Drill caps missions at 1 for micro, 2 for small, 3 for medium+.
  const stateSmall = initState("/tmp/p1", drill);
  const seedSmall = await runner.start(stateSmall, "tiny page", {
    party: "Solo",
  });
  const small = JSON.parse(seedSmall.outputJson);

  const stateLarge = initState("/tmp/p2", drill);
  const seedLarge = await runner.start(
    stateLarge,
    "stripe payments + push notifications + maps + accounts",
    { party: "Public" },
  );
  const large = JSON.parse(seedLarge.outputJson);

  assert.ok(
    large.missions.length >= small.missions.length,
    `large=${large.missions.length} should be ≥ small=${small.missions.length}`,
  );
});

test("start — finalScore in SeedResult reflects intake overrides", async () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", gameMaster);
  // Heuristic baseline for "tiny page" → auth=0.
  // "Public" answer → auth override 3.
  const seed = await runner.start(state, "tiny page", { party: "Public" });
  assert.equal(seed.finalScore.auth, 3);
});

// ─── tick() — event-driven ceremonies ──────────────────────────────────────

test("tick — fires on_event ceremony matching triggerEvent", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", drill);
  const triggers = runner.tick(state, {
    kind: "mission_assigned",
    missionId: "m1",
    at: T0,
  });
  assert.equal(triggers.length, 1);
  assert.equal(triggers[0]!.spec.kind, "briefing");
  assert.equal(triggers[0]!.spec.triggerEvent, "mission_assigned");
});

test("tick — no on_event match → empty triggers", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", drill);
  const triggers = runner.tick(state, {
    kind: "user_idle",
    sinceMinutes: 30,
    at: T0,
  });
  assert.deepEqual(triggers, []);
});

test("tick — records fire in state.fireLog (mutating)", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", drill);
  assert.deepEqual(state.fireLog, {});
  runner.tick(state, {
    kind: "mission_assigned",
    missionId: "m1",
    at: T0,
  });
  assert.notDeepEqual(state.fireLog, {});
});

// ─── checkClockCeremonies ──────────────────────────────────────────────────

test("checkClockCeremonies — daily standup due immediately on fresh state",
  () => {
    const runner = makeRunner();
    const state = initState("/tmp/p", drill);
    const triggers = runner.checkClockCeremonies(state);
    assert.equal(triggers.length, 1);
    assert.equal(triggers[0]!.spec.kind, "standup");
  });

test("checkClockCeremonies — daily NOT due 12h after firing", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", drill);
  runner.checkClockCeremonies(state, T0);
  const second = runner.checkClockCeremonies(
    state,
    new Date(T0.getTime() + 12 * 60 * 60 * 1000),
  );
  assert.deepEqual(second, []);
});

test("checkClockCeremonies — daily due again after 24h", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", drill);
  runner.checkClockCeremonies(state, T0);
  const second = runner.checkClockCeremonies(
    state,
    new Date(T0.getTime() + day),
  );
  assert.equal(second.length, 1);
});

// ─── switchStyle ──────────────────────────────────────────────────────────

test("switchStyle — different output mapper → reseedRequired=true", () => {
  const runner = makeRunner();
  const state = initState("/tmp/p", gameMaster);
  state.fireLog = { "x:y:": "2026-01-01T00:00:00Z" };
  const result = runner.switchStyle(state, drill);
  assert.equal(result.reseedRequired, true);
  assert.equal(result.fromStyleId, "game_master");
  assert.equal(result.toStyleId, "drill_sergeant");
  assert.deepEqual(state.fireLog, {}, "fire log dropped on switch");
  assert.equal(state.style.id, "drill_sergeant");
});

test("switchStyle — same output mapper → reseedRequired=false", () => {
  const same: FacilitatorStyle = {
    ...gameMaster,
    id: "game_master_v2",
  };
  const runner = makeRunner();
  const state = initState("/tmp/p", gameMaster);
  const result = runner.switchStyle(state, same);
  assert.equal(result.reseedRequired, false);
});

// ─── Generator pluggability ────────────────────────────────────────────────

test("Custom generator can replace the stub for a format", async () => {
  const calls: GeneratorInput[] = [];
  const fakeGen: StyledOutputGenerator = {
    async generate(input): Promise<GeneratorOutput> {
      calls.push(input);
      return {
        outputJson: JSON.stringify({
          format: "quest_line",
          id: input.outputId,
          custom: true,
        }),
        format: "quest_line",
      };
    },
  };
  const registry = new GeneratorRegistry();
  registry.setGenerator("quest_line", fakeGen);

  const runner = new FacilitatorRunner({
    generators: registry,
    clock: () => T0,
    newId: () => "x",
  });
  const state = initState("/tmp/p", gameMaster);
  const seed = await runner.start(state, "anything", {});

  assert.equal(calls.length, 1);
  const parsed = JSON.parse(seed.outputJson);
  assert.equal(parsed.custom, true);
});

test("GeneratorRegistry throws when no generator is registered", () => {
  const registry = new GeneratorRegistry();
  // Force-clear the quest_line entry to simulate a missing one.
  // (setGenerator with no value isn't supported, so we use the
  // underlying Map by reflection.)
  const internal = (registry as unknown as { generators: Map<string, unknown> })
    .generators;
  internal.delete("quest_line");

  assert.throws(() => registry.forStyle(gameMaster), /No generator registered/);
});
