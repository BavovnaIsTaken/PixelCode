/**
 * Integration: LLM call → typed error → ws_handler typed code → client UX.
 *
 * Walks WP4's whole error-typing chain end-to-end:
 *   runWithTimeoutAndRetry → generator → handleStartRequest → result.code
 *
 * The point is to catch a regression where one layer stops carrying the
 * typed kind. A unit test on any single module would still pass even if
 * the wire-up forgot to pass the kind through.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ClaudeQuestLineGenerator,
  type CallerFn,
} from "../../src/facilitator/llm_generators.ts";
import {
  LLMGenerationError,
  runWithTimeoutAndRetry,
} from "../../src/facilitator/llm_runner.ts";
import {
  GeneratorRegistry,
  type StyledOutputGenerator,
} from "../../src/facilitator/output_generator.ts";
import { FacilitatorRunner } from "../../src/facilitator/runner.ts";
import {
  handleStartRequest,
  parseStartRequest,
} from "../../src/facilitator/ws_handler.ts";
import type { ScopeScore } from "../../src/quest/scope_scorer.ts";

const noWait = { sleepFn: async (_ms: number) => {} };

const microScore: ScopeScore = {
  entityCount: 1,
  interactionSurface: 1,
  auth: 0,
  integrations: 0,
  realtime: 0,
};

function makeStartRequest() {
  return {
    type: "facilitator_start" as const,
    style: {
      id: "game_master",
      displayName: "GM",
      tagline: "",
      laloux: "green" as const,
      personaPrompt: "",
      lexicon: {},
      ceremonySchedule: [],
      intakeTemplate: [],
      outputMapper: "quest_line" as const,
      toneModifiers: { aggression: 0, formality: 0, verbosity: 0 },
    },
    projectDescription: "A todo app",
    answers: {},
  };
}

function makeRunner(generator: StyledOutputGenerator) {
  const generators = new GeneratorRegistry();
  generators.setGenerator("quest_line", generator);
  return new FacilitatorRunner({ generators });
}

test("e2e: LLM hangs forever → handleStartRequest returns code='timeout'",
  async () => {
    // Caller never resolves; runWithTimeoutAndRetry's timeout fires.
    const hungCaller: CallerFn = () => new Promise<string>(() => {});
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", hungCaller, {
      timeoutMs: 5,
      retries: 0,
      ...noWait,
    });
    const runner = makeRunner(gen);
    const parsed = parseStartRequest(makeStartRequest());
    assert.equal(parsed.ok, true);
    if (!parsed.ok) return;
    const result = await handleStartRequest(runner, "/tmp/proj", parsed.value);
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.equal(result.code, "timeout");
      assert.match(result.error, /5ms/);
    }
  });

test("e2e: LLM returns garbage → handleStartRequest returns code='parse'",
  async () => {
    const garbageCaller: CallerFn = async () => "I am not JSON at all";
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", garbageCaller);
    const runner = makeRunner(gen);
    const parsed = parseStartRequest(makeStartRequest());
    if (!parsed.ok) return;
    const result = await handleStartRequest(runner, "/tmp/proj", parsed.value);
    assert.equal(result.ok, false);
    if (!result.ok) assert.equal(result.code, "parse");
  });

test(
  "e2e: transient 502 then success — handleStartRequest returns ok and the call retried exactly once",
  async () => {
    let calls = 0;
    const flakyCaller: CallerFn = async () => {
      calls++;
      if (calls === 1) throw new Error("upstream returned 502 bad gateway");
      return JSON.stringify({
        format: "quest_line",
        id: "x",
        projectPath: "/tmp/proj",
        appSummary: "x",
        tier: "micro",
        scoreBreakdown: microScore,
        acts: [],
        transformativeChanges: 0,
        createdAt: "2026-05-02T00:00:00Z",
      });
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", flakyCaller, {
      retries: 1,
      ...noWait,
    });
    const runner = makeRunner(gen);
    const parsed = parseStartRequest(makeStartRequest());
    if (!parsed.ok) return;
    const result = await handleStartRequest(runner, "/tmp/proj", parsed.value);
    assert.equal(result.ok, true);
    assert.equal(calls, 2, "exactly one retry");
  });

test(
  "e2e: 401 auth → handleStartRequest returns code='auth' without retrying",
  async () => {
    let calls = 0;
    const authBlowCaller: CallerFn = async () => {
      calls++;
      throw new Error("401 unauthorized: invalid api key");
    };
    const gen = new ClaudeQuestLineGenerator("/tmp/proj", authBlowCaller, {
      retries: 3,
      ...noWait,
    });
    const runner = makeRunner(gen);
    const parsed = parseStartRequest(makeStartRequest());
    if (!parsed.ok) return;
    const result = await handleStartRequest(runner, "/tmp/proj", parsed.value);
    assert.equal(result.ok, false);
    if (!result.ok) assert.equal(result.code, "auth");
    // Auth errors are typed inside classifyError → not retried.
    assert.equal(calls, 1);
  });

test("runWithTimeoutAndRetry × LLMGenerationError — kind preserved through the chain",
  async () => {
    const e = new LLMGenerationError("rate_limit", "429 too many");
    let calls = 0;
    await assert.rejects(
      runWithTimeoutAndRetry(
        async () => {
          calls++;
          throw e;
        },
        { retries: 1, ...noWait },
      ),
      (caught) =>
        caught instanceof LLMGenerationError && caught.kind === "rate_limit",
    );
    // rate_limit is transient → retried once before bubbling out.
    assert.equal(calls, 2);
  });
