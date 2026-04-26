import { test } from "node:test";
import assert from "node:assert/strict";

import {
  interpretAnswer,
  processIntake,
} from "../src/facilitator/intake_processor.js";
import type {
  FacilitatorStyle,
  IntakeQuestion,
} from "../src/facilitator/types.js";

function makeStyle(intakeTemplate: IntakeQuestion[]): FacilitatorStyle {
  return {
    id: "test",
    displayName: "Test",
    tagline: "",
    laloux: "red",
    personaPrompt: "",
    lexicon: {},
    ceremonySchedule: [],
    intakeTemplate,
    outputMapper: "mission_briefing",
    toneModifiers: { aggression: 0.5, formality: 0.5, verbosity: 0.5 },
  };
}

// ─── interpretAnswer ───────────────────────────────────────────────────────

test("interpretAnswer — blank text returns null", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, ""), null);
  assert.equal(interpretAnswer(q, "   "), null);
});

test("interpretAnswer — choice exact match returns delta", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "choice",
    choices: ["Solo", "Squad", "Public"],
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, "Solo"), 0);
  assert.equal(interpretAnswer(q, "Squad"), 2);
  assert.equal(interpretAnswer(q, "Public"), 3);
});

test("interpretAnswer — choice fuzzy contains match", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "choice",
    choices: ["Solo (тільки я)", "Кілька друзів", "Відкритий світ"],
    mapsTo: "auth",
  };
  // User selected "solo" lowercase — fuzzy match should find idx 0.
  assert.equal(interpretAnswer(q, "solo"), 0);
});

test("interpretAnswer — choice unknown returns null", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "choice",
    choices: ["A", "B"],
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, "Z"), null);
});

test("interpretAnswer — text 'no accounts' → 0", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, "no accounts, just personal use"), 0);
  assert.equal(interpretAnswer(q, "Just me"), 0);
});

test("interpretAnswer — text 'login signup' → 2", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, "users with login and signup"), 2);
});

test("interpretAnswer — text 'admin/roles' → 3", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "auth",
  };
  assert.equal(interpretAnswer(q, "admin panel with roles"), 3);
});

test("interpretAnswer — realtime 'live chat' → 2", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "realtime",
  };
  assert.equal(interpretAnswer(q, "live chat between users"), 2);
});

test("interpretAnswer — realtime 'collaborative' → 3", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "realtime",
  };
  assert.equal(
    interpretAnswer(q, "real-time collaborative editing"),
    3,
    "max wins (collab match takes 3 over realtime match)",
  );
});

test("interpretAnswer — integrations counts distinct mentions", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "integrations",
  };
  assert.equal(interpretAnswer(q, "stripe payments and push notifications"), 2);
  assert.equal(
    interpretAnswer(q, "stripe payments, maps, push notifications, email"),
    4,
  );
  assert.equal(interpretAnswer(q, "stripe and stripe and stripe"), 1);
});

test("interpretAnswer — integrations 'no' returns 0", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "integrations",
  };
  assert.equal(interpretAnswer(q, "no"), 0);
});

test("interpretAnswer — entity_count counts distinct domain nouns", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "entity_count",
  };
  assert.equal(
    interpretAnswer(q, "users post photos and write comments"),
    4,
    "user, post, photo, comment = 4 distinct entities",
  );
  // Singular vs plural collapse to one entity.
  assert.equal(interpretAnswer(q, "users and user accounts"), 2);
});

test("interpretAnswer — mapsTo='none' is short-circuit null", () => {
  const q: IntakeQuestion = {
    id: "q",
    prompt: "",
    inputKind: "text",
    mapsTo: "none",
  };
  assert.equal(interpretAnswer(q, "anything goes here"), null);
});

// ─── processIntake ─────────────────────────────────────────────────────────

test("processIntake — heuristic alone when no answers map to dimensions", () => {
  const style = makeStyle([
    {
      id: "vision",
      prompt: "What's the idea?",
      inputKind: "text",
      mapsTo: "none",
    },
  ]);
  const r = processIntake("a small todo app with reminders", style, {
    vision: "I want to track my tasks",
  });
  // No overrides applied — final score equals heuristic score.
  assert.deepEqual(r.appliedOverrides, {});
  assert.deepEqual(r.finalScore, r.heuristicBreakdown.score);
});

test("processIntake — overrides MAX-merge when multiple questions map "
  + "to the same dimension", () => {
  const style = makeStyle([
    {
      id: "q1",
      prompt: "",
      inputKind: "choice",
      choices: ["Solo", "Squad", "Public"],
      mapsTo: "auth",
    },
    {
      id: "q2",
      prompt: "",
      inputKind: "text",
      mapsTo: "auth",
    },
  ]);
  // Q1 picks Squad (delta 2), Q2 mentions admin/roles (delta 3) → final 3.
  const r = processIntake("project description", style, {
    q1: "Squad",
    q2: "admin panel with roles",
  });
  assert.equal(r.appliedOverrides.auth, 3);
  assert.equal(r.finalScore.auth, 3);
});

test("processIntake — answer with no signal → unparsedQuestionIds", () => {
  const style = makeStyle([
    {
      id: "q",
      prompt: "",
      inputKind: "text",
      mapsTo: "realtime",
    },
  ]);
  const r = processIntake("project description", style, {
    q: "I'm not sure honestly",
  });
  assert.deepEqual(r.unparsedQuestionIds, ["q"]);
  assert.equal(r.appliedOverrides.realtime, undefined);
});

test("processIntake — missing answer for question is silently skipped "
  + "(neither override nor unparsed)", () => {
  const style = makeStyle([
    {
      id: "q",
      prompt: "",
      inputKind: "text",
      mapsTo: "realtime",
    },
  ]);
  const r = processIntake("project description", style, {});
  assert.deepEqual(r.unparsedQuestionIds, []);
  assert.deepEqual(r.appliedOverrides, {});
});

test("processIntake — applied overrides modify final score", () => {
  const style = makeStyle([
    {
      id: "auth",
      prompt: "",
      inputKind: "choice",
      choices: ["Solo", "Squad", "Public"],
      mapsTo: "auth",
    },
    {
      id: "rt",
      prompt: "",
      inputKind: "text",
      mapsTo: "realtime",
    },
  ]);
  const r = processIntake("simple page", style, {
    auth: "Public",
    rt: "live multiplayer",
  });
  assert.equal(r.finalScore.auth, 3);
  assert.equal(r.finalScore.realtime, 3);
});
