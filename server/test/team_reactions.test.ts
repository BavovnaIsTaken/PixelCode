import { test, describe } from "node:test";
import assert from "node:assert/strict";

import {
  parseReactions,
  generateTeamReactions,
} from "../src/facilitator/team_reactions.js";
import type { CallerFn } from "../src/facilitator/llm_generators.js";

const ROLES = [
  "manager",
  "tech-lead",
  "coder",
  "reviewer",
  "tester",
] as const;

describe("parseReactions", () => {
  test("extracts well-formed reactions from raw JSON", () => {
    const raw = JSON.stringify({
      reactions: [
        { role: "manager", text: "Беру brief, розкладемо на 4 кроки." },
        { role: "tech-lead", text: "Авторизація — найбільший ризик тут." },
      ],
    });
    const out = parseReactions(raw, ROLES, 3);
    assert.deepEqual(out, [
      { role: "manager", text: "Беру brief, розкладемо на 4 кроки." },
      { role: "tech-lead", text: "Авторизація — найбільший ризик тут." },
    ]);
  });

  test("handles ```json fenced LLM output", () => {
    const raw = '```json\n{"reactions":[{"role":"coder","text":"ок, починаю"}]}\n```';
    const out = parseReactions(raw, ROLES, 3);
    assert.deepEqual(out, [{ role: "coder", text: "ок, починаю" }]);
  });

  test("returns null on malformed JSON", () => {
    assert.equal(parseReactions("not json at all", ROLES, 3), null);
    assert.equal(parseReactions("{ broken", ROLES, 3), null);
  });

  test("returns null when reactions field is missing or non-array", () => {
    assert.equal(parseReactions(JSON.stringify({}), ROLES, 3), null);
    assert.equal(
      parseReactions(JSON.stringify({ reactions: "nope" }), ROLES, 3),
      null,
    );
  });

  test("filters out reactions with unknown role ids", () => {
    const raw = JSON.stringify({
      reactions: [
        { role: "manager", text: "ok" },
        { role: "ceo", text: "should be dropped" },
        { role: "tech-lead", text: "good" },
      ],
    });
    const out = parseReactions(raw, ROLES, 3);
    assert.deepEqual(out, [
      { role: "manager", text: "ok" },
      { role: "tech-lead", text: "good" },
    ]);
  });

  test("drops items with empty text or wrong types, caps at maxReactions", () => {
    const raw = JSON.stringify({
      reactions: [
        { role: "manager", text: "" },
        { role: "tech-lead", text: "   " },
        { role: "coder", text: 123 },
        { role: "tester", text: "valid 1" },
        { role: "reviewer", text: "valid 2" },
        { role: "manager", text: "valid 3" },
        { role: "manager", text: "over the cap" },
      ],
    });
    const out = parseReactions(raw, ROLES, 3);
    assert.equal(out?.length, 3);
    assert.deepEqual(out, [
      { role: "tester", text: "valid 1" },
      { role: "reviewer", text: "valid 2" },
      { role: "manager", text: "valid 3" },
    ]);
  });
});

describe("generateTeamReactions (graceful failure contract)", () => {
  test("returns reactions on happy path", async () => {
    const caller: CallerFn = async () =>
      JSON.stringify({
        reactions: [
          { role: "manager", text: "ok" },
          { role: "tech-lead", text: "watch the auth path" },
        ],
      });
    const out = await generateTeamReactions(
      {
        projectDescription: "build a thing",
        validRoles: ROLES,
        projectPath: "/tmp",
      },
      { caller },
    );
    assert.equal(out.length, 2);
    assert.equal(out[0].role, "manager");
  });

  test("returns [] when caller throws (does not propagate)", async () => {
    const caller: CallerFn = async () => {
      throw new Error("boom");
    };
    const out = await generateTeamReactions(
      {
        projectDescription: "build a thing",
        validRoles: ROLES,
        projectPath: "/tmp",
      },
      { caller, runOptions: { retries: 0, timeoutMs: 50 } },
    );
    assert.deepEqual(out, []);
  });

  test("returns [] on malformed LLM JSON", async () => {
    const caller: CallerFn = async () => "this is not json";
    const out = await generateTeamReactions(
      {
        projectDescription: "build a thing",
        validRoles: ROLES,
        projectPath: "/tmp",
      },
      { caller, runOptions: { retries: 0 } },
    );
    assert.deepEqual(out, []);
  });

  test("returns [] when validRoles is empty (skips LLM)", async () => {
    let called = false;
    const caller: CallerFn = async () => {
      called = true;
      return "{}";
    };
    const out = await generateTeamReactions(
      {
        projectDescription: "build a thing",
        validRoles: [],
        projectPath: "/tmp",
      },
      { caller },
    );
    assert.deepEqual(out, []);
    assert.equal(called, false, "must not call LLM when no roles allowed");
  });
});
