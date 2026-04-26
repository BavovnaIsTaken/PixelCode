import { test } from "node:test";
import assert from "node:assert/strict";

import {
  parseStartRequest,
  handleStartRequest,
} from "../src/facilitator/ws_handler.js";
import {
  FacilitatorRunner,
} from "../src/facilitator/runner.js";
import {
  GeneratorRegistry,
  type GeneratorInput,
  type GeneratorOutput,
  type StyledOutputGenerator,
} from "../src/facilitator/output_generator.js";
import type { FacilitatorStyle } from "../src/facilitator/types.js";

// ─── Fixtures ──────────────────────────────────────────────────────────────

const T0 = new Date("2026-04-26T10:00:00Z");

/** Minimal-but-valid Game Master payload — kept in a builder so individual
 *  tests can mutate single fields without restating the whole shape. */
function makeStyle(overrides: Partial<FacilitatorStyle> = {}): FacilitatorStyle {
  return {
    id: "game_master",
    displayName: "Game Master",
    tagline: "Quests, not tasks",
    laloux: "green",
    personaPrompt: "Speak as a DM.",
    lexicon: { task: "quest" },
    ceremonySchedule: [
      { kind: "briefing", cadence: "on_event", triggerEvent: "act_complete" },
    ],
    intakeTemplate: [
      {
        id: "party",
        prompt: "Solo or party?",
        inputKind: "choice",
        choices: ["Solo", "Party"],
        mapsTo: "auth",
      },
    ],
    outputMapper: "quest_line",
    toneModifiers: { aggression: 0.1, formality: 0.2, verbosity: 0.7 },
    ...overrides,
  };
}

function makeRequest(over: Partial<{
  style: unknown;
  projectDescription: unknown;
  answers: unknown;
}> = {}) {
  return {
    style: over.style ?? makeStyle(),
    projectDescription: over.projectDescription ?? "Build a todo app",
    answers: over.answers ?? { party: "Solo" },
  };
}

// ─── parseStartRequest: top-level shape ────────────────────────────────────

test("parseStartRequest — valid payload parses to typed value", () => {
  const r = parseStartRequest(makeRequest());
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.value.style.id, "game_master");
    assert.equal(r.value.projectDescription, "Build a todo app");
    assert.deepEqual(r.value.answers, { party: "Solo" });
  }
});

test("parseStartRequest — non-object root rejected", () => {
  for (const bad of [null, undefined, "x", 42, []]) {
    const r = parseStartRequest(bad);
    assert.equal(r.ok, false);
  }
});

test("parseStartRequest — missing projectDescription rejected", () => {
  const r = parseStartRequest({ ...makeRequest(), projectDescription: undefined });
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /projectDescription/);
});

test("parseStartRequest — empty/whitespace projectDescription rejected", () => {
  const r = parseStartRequest(makeRequest({ projectDescription: "   " }));
  assert.equal(r.ok, false);
});

test("parseStartRequest — non-object answers rejected", () => {
  const r = parseStartRequest(makeRequest({ answers: "huh" }));
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /answers/);
});

test("parseStartRequest — non-string answer values rejected", () => {
  const r = parseStartRequest(makeRequest({ answers: { party: 7 } }));
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /answers\["party"\]/);
});

test("parseStartRequest — empty answers map is allowed", () => {
  const r = parseStartRequest(makeRequest({ answers: {} }));
  assert.equal(r.ok, true);
});

// ─── parseStartRequest: style validation ───────────────────────────────────

test("parseStartRequest — bad laloux rejected", () => {
  const r = parseStartRequest(makeRequest({ style: makeStyle({ laloux: "purple" as never }) }));
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /style\.laloux/);
});

test("parseStartRequest — bad outputMapper rejected", () => {
  const r = parseStartRequest(
    makeRequest({ style: makeStyle({ outputMapper: "kanban" as never }) }),
  );
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /style\.outputMapper/);
});

test("parseStartRequest — on_event cadence requires triggerEvent", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        ceremonySchedule: [{ kind: "briefing", cadence: "on_event" }],
      }),
    }),
  );
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /ceremonySchedule\[0\]/);
});

test("parseStartRequest — non-on_event cadence is fine without triggerEvent", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        ceremonySchedule: [{ kind: "standup", cadence: "daily" }],
      }),
    }),
  );
  assert.equal(r.ok, true);
});

test("parseStartRequest — choice intake without choices is rejected", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        intakeTemplate: [
          { id: "x", prompt: "?", inputKind: "choice", mapsTo: "auth" },
        ],
      }),
    }),
  );
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /intakeTemplate\[0\]/);
});

test("parseStartRequest — text intake without choices is fine", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        intakeTemplate: [
          { id: "x", prompt: "Describe", inputKind: "text", mapsTo: "none" },
        ],
      }),
    }),
  );
  assert.equal(r.ok, true);
});

test("parseStartRequest — toneModifiers out of range rejected", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        toneModifiers: { aggression: 1.5, formality: 0, verbosity: 0 },
      }),
    }),
  );
  assert.equal(r.ok, false);
  if (!r.ok) assert.match(r.error, /toneModifiers/);
});

test("parseStartRequest — bad mapsTo rejected", () => {
  const r = parseStartRequest(
    makeRequest({
      style: makeStyle({
        intakeTemplate: [
          {
            id: "x",
            prompt: "?",
            inputKind: "text",
            mapsTo: "speed" as never,
          },
        ],
      }),
    }),
  );
  assert.equal(r.ok, false);
});

test("parseStartRequest — extra unknown fields on style are tolerated", () => {
  const styleWithExtra: unknown = { ...makeStyle(), futureField: "ignored" };
  const r = parseStartRequest(makeRequest({ style: styleWithExtra }));
  assert.equal(r.ok, true);
});

// ─── handleStartRequest ────────────────────────────────────────────────────

function makeRunner(deps: { generators?: GeneratorRegistry } = {}) {
  return new FacilitatorRunner({
    clock: () => T0,
    newId: () => "fixed-output-id",
    generators: deps.generators,
  });
}

test("handleStartRequest — happy path returns seeded state + parseable JSON", async () => {
  const runner = makeRunner();
  const parse = parseStartRequest(makeRequest());
  assert.equal(parse.ok, true);
  if (!parse.ok) return;

  const result = await handleStartRequest(runner, "/tmp/proj", parse.value);
  assert.equal(result.ok, true);
  if (!result.ok) return;

  assert.equal(result.state.projectPath, "/tmp/proj");
  assert.equal(result.state.style.id, "game_master");
  assert.equal(result.state.outputId, "fixed-output-id");
  assert.equal(result.seed.outputFormat, "quest_line");

  const decoded = JSON.parse(result.seed.outputJson);
  assert.equal(decoded.format, "quest_line");
  assert.equal(decoded.id, "fixed-output-id");
  assert.equal(decoded.projectPath, "/tmp/proj");
});

test("handleStartRequest — generator error surfaces as result.error", async () => {
  class ExplodingGen implements StyledOutputGenerator {
    async generate(_input: GeneratorInput): Promise<GeneratorOutput> {
      throw new Error("LLM down");
    }
  }
  const generators = new GeneratorRegistry();
  generators.setGenerator("quest_line", new ExplodingGen());
  const runner = makeRunner({ generators });

  const parse = parseStartRequest(makeRequest());
  assert.equal(parse.ok, true);
  if (!parse.ok) return;

  const result = await handleStartRequest(runner, "/tmp/proj", parse.value);
  assert.equal(result.ok, false);
  if (!result.ok) assert.match(result.error, /LLM down/);
});

test("handleStartRequest — missing generator for outputMapper surfaces typed error", async () => {
  const generators = new GeneratorRegistry(); // default has no sprint_backlog
  const runner = makeRunner({ generators });

  const sprintStyle = makeStyle({
    id: "scrum",
    outputMapper: "sprint_backlog",
  });
  const parse = parseStartRequest(makeRequest({ style: sprintStyle }));
  assert.equal(parse.ok, true);
  if (!parse.ok) return;

  const result = await handleStartRequest(runner, "/tmp/proj", parse.value);
  assert.equal(result.ok, false);
  if (!result.ok) assert.match(result.error, /sprint_backlog/);
});

test("handleStartRequest — finalScore reflects intake answers", async () => {
  // The Game Master "party" choice maps to `auth`; "Public" should bump
  // the auth dimension on the heuristic baseline.
  const runner = makeRunner();
  const stylePublic = makeStyle({
    intakeTemplate: [
      {
        id: "party",
        prompt: "?",
        inputKind: "choice",
        choices: ["Solo", "Party", "Public"],
        mapsTo: "auth",
      },
    ],
  });
  const parsePublic = parseStartRequest({
    style: stylePublic,
    projectDescription: "Build a todo app",
    answers: { party: "Public" },
  });
  assert.equal(parsePublic.ok, true);
  if (!parsePublic.ok) return;

  const parseSolo = parseStartRequest({
    style: stylePublic,
    projectDescription: "Build a todo app",
    answers: { party: "Solo" },
  });
  assert.equal(parseSolo.ok, true);
  if (!parseSolo.ok) return;

  const pub = await handleStartRequest(runner, "/tmp/proj", parsePublic.value);
  const solo = await handleStartRequest(runner, "/tmp/proj", parseSolo.value);
  assert.equal(pub.ok, true);
  assert.equal(solo.ok, true);
  if (!pub.ok || !solo.ok) return;

  assert.ok(
    pub.seed.finalScore.auth >= solo.seed.finalScore.auth,
    "Public party should not score lower on auth than Solo",
  );
});
