/**
 * WS-layer glue for the FacilitatorRunner.
 *
 * Kept separate from `server.ts` so the validation + orchestration logic is
 * unit-testable without spinning up a WebSocket. The transport layer
 * (`server.ts`) only deals with `ws.send(...)` and per-client state maps.
 *
 * Design: docs/FACILITATOR_SYSTEM.md §3 (runner state machine).
 */

import {
  FacilitatorRunner,
  initState,
  type RunnerState,
} from "./runner.js";
import type {
  CeremonyCadence,
  CeremonyKind,
  CeremonySpec,
  FacilitatorStyle,
  IntakeAnswers,
  IntakeInputKind,
  IntakeQuestion,
  Laloux,
  OutputFormatKey,
  ScopeDimensionKey,
  SeedResult,
  ToneModifiers,
} from "./types.js";

// ─── Parse result (Result<T, string>) ──────────────────────────────────────

export interface ParsedStartRequest {
  style: FacilitatorStyle;
  projectDescription: string;
  answers: IntakeAnswers;
}

export type StartRequestParse =
  | { ok: true; value: ParsedStartRequest }
  | { ok: false; error: string };

// ─── Pure validator ────────────────────────────────────────────────────────

/**
 * Validates the shape of a `facilitator_start` payload. Strict on top-level
 * fields and on the style discriminators that drive runner behavior (output
 * mapper, intake template, ceremony schedule). Tolerant of unknown extras
 * so newer clients can ship richer styles to older servers.
 */
export function parseStartRequest(raw: unknown): StartRequestParse {
  if (!isObject(raw)) return fail("payload must be an object");

  const projectDescription = raw["projectDescription"];
  if (typeof projectDescription !== "string") {
    return fail("projectDescription must be a string");
  }
  if (projectDescription.trim().length === 0) {
    return fail("projectDescription must not be empty");
  }

  const answers = raw["answers"];
  if (!isObject(answers)) return fail("answers must be an object");
  for (const [k, v] of Object.entries(answers)) {
    if (typeof v !== "string") {
      return fail(`answers["${k}"] must be a string`);
    }
  }

  const styleRaw = raw["style"];
  if (!isObject(styleRaw)) return fail("style must be an object");
  const styleParse = parseStyle(styleRaw);
  if (!styleParse.ok) return styleParse;

  return {
    ok: true,
    value: {
      style: styleParse.value,
      projectDescription,
      answers: answers as IntakeAnswers,
    },
  };
}

// ─── Handler (impure, but only via the injected runner) ────────────────────

import { LLMGenerationError, type LLMErrorKind } from "./llm_runner.js";

export type StartHandlerResult =
  | { ok: true; state: RunnerState; seed: SeedResult }
  | {
      ok: false;
      error: string;
      /** Typed code so the WS layer can ship a structured `facilitator_error.code`. */
      code: LLMErrorKind;
    };

/**
 * Builds a fresh `RunnerState` for the project + style and seeds it via
 * `runner.start`. Catches generator errors so the caller can translate
 * them into a `facilitator_error` ServerMessage instead of crashing the
 * WS connection.
 */
export async function handleStartRequest(
  runner: FacilitatorRunner,
  projectPath: string,
  parsed: ParsedStartRequest,
): Promise<StartHandlerResult> {
  const state = initState(projectPath, parsed.style);
  try {
    const seed = await runner.start(
      state,
      parsed.projectDescription,
      parsed.answers,
    );
    return { ok: true, state, seed };
  } catch (err) {
    const code: LLMErrorKind =
      err instanceof LLMGenerationError ? err.kind : "unknown";
    return {
      ok: false,
      error: err instanceof Error ? err.message : String(err),
      code,
    };
  }
}

// ─── Style validation ──────────────────────────────────────────────────────

type StyleParse =
  | { ok: true; value: FacilitatorStyle }
  | { ok: false; error: string };

const LALOUX: readonly Laloux[] = ["red", "amber", "orange", "green", "teal"];
const CEREMONY_KIND: readonly CeremonyKind[] = [
  "standup", "retro", "review", "briefing", "journal", "on_demand", "none",
];
const CEREMONY_CADENCE: readonly CeremonyCadence[] = [
  "daily", "weekly", "biweekly", "monthly", "on_event", "never",
];
const SCOPE_DIM: readonly ScopeDimensionKey[] = [
  "entity_count", "interaction_surface", "auth", "integrations", "realtime", "none",
];
const INTAKE_KIND: readonly IntakeInputKind[] = ["text", "choice"];
const OUTPUT_MAPPER: readonly OutputFormatKey[] = [
  "quest_line", "mission_briefing", "milestone_tree", "sprint_backlog", "koan_entry",
];

function parseStyle(raw: Record<string, unknown>): StyleParse {
  const id = strField(raw, "id");
  if (!id) return styleErr("id");
  const displayName = strField(raw, "displayName");
  if (!displayName) return styleErr("displayName");

  const laloux = raw["laloux"];
  if (!isOneOf(laloux, LALOUX)) {
    return styleErr(`laloux (got ${JSON.stringify(laloux)})`);
  }

  const outputMapper = raw["outputMapper"];
  if (!isOneOf(outputMapper, OUTPUT_MAPPER)) {
    return styleErr(`outputMapper (got ${JSON.stringify(outputMapper)})`);
  }

  const intakeTemplateRaw = raw["intakeTemplate"];
  if (!Array.isArray(intakeTemplateRaw)) {
    return styleErr("intakeTemplate (must be array)");
  }
  const intakeTemplate: IntakeQuestion[] = [];
  for (let i = 0; i < intakeTemplateRaw.length; i++) {
    const q = parseIntakeQuestion(intakeTemplateRaw[i]);
    if (!q.ok) return styleErr(`intakeTemplate[${i}]: ${q.error}`);
    intakeTemplate.push(q.value);
  }

  const ceremonyRaw = raw["ceremonySchedule"];
  if (!Array.isArray(ceremonyRaw)) {
    return styleErr("ceremonySchedule (must be array)");
  }
  const ceremonySchedule: CeremonySpec[] = [];
  for (let i = 0; i < ceremonyRaw.length; i++) {
    const c = parseCeremonySpec(ceremonyRaw[i]);
    if (!c.ok) return styleErr(`ceremonySchedule[${i}]: ${c.error}`);
    ceremonySchedule.push(c.value);
  }

  const tone = parseTone(raw["toneModifiers"]);
  if (!tone.ok) return styleErr(`toneModifiers: ${tone.error}`);

  const lexiconRaw = raw["lexicon"];
  const lexicon: Record<string, string> = {};
  if (lexiconRaw !== undefined) {
    if (!isObject(lexiconRaw)) return styleErr("lexicon (must be object)");
    for (const [k, v] of Object.entries(lexiconRaw)) {
      if (typeof v !== "string") return styleErr(`lexicon["${k}"]`);
      lexicon[k] = v;
    }
  }

  return {
    ok: true,
    value: {
      id,
      displayName,
      tagline: strField(raw, "tagline") ?? "",
      laloux,
      personaPrompt: strField(raw, "personaPrompt") ?? "",
      lexicon,
      ceremonySchedule,
      intakeTemplate,
      outputMapper,
      toneModifiers: tone.value,
    },
  };
}

function parseIntakeQuestion(raw: unknown):
  | { ok: true; value: IntakeQuestion }
  | { ok: false; error: string }
{
  if (!isObject(raw)) return { ok: false, error: "must be object" };
  const id = strField(raw, "id");
  if (!id) return { ok: false, error: "missing id" };
  const prompt = strField(raw, "prompt");
  if (prompt === undefined) return { ok: false, error: "missing prompt" };

  const inputKind = raw["inputKind"];
  if (!isOneOf(inputKind, INTAKE_KIND)) {
    return { ok: false, error: `bad inputKind ${JSON.stringify(inputKind)}` };
  }

  const mapsTo = raw["mapsTo"];
  if (!isOneOf(mapsTo, SCOPE_DIM)) {
    return { ok: false, error: `bad mapsTo ${JSON.stringify(mapsTo)}` };
  }

  let choices: string[] | undefined;
  const choicesRaw = raw["choices"];
  if (choicesRaw !== undefined) {
    if (!Array.isArray(choicesRaw) || !choicesRaw.every((c) => typeof c === "string")) {
      return { ok: false, error: "choices must be string[]" };
    }
    choices = choicesRaw as string[];
  }
  if (inputKind === "choice" && (!choices || choices.length === 0)) {
    return { ok: false, error: "choice question requires non-empty choices" };
  }

  return { ok: true, value: { id, prompt, inputKind, mapsTo, choices } };
}

function parseCeremonySpec(raw: unknown):
  | { ok: true; value: CeremonySpec }
  | { ok: false; error: string }
{
  if (!isObject(raw)) return { ok: false, error: "must be object" };
  const kind = raw["kind"];
  if (!isOneOf(kind, CEREMONY_KIND)) {
    return { ok: false, error: `bad kind ${JSON.stringify(kind)}` };
  }
  const cadence = raw["cadence"];
  if (!isOneOf(cadence, CEREMONY_CADENCE)) {
    return { ok: false, error: `bad cadence ${JSON.stringify(cadence)}` };
  }
  const triggerEventRaw = raw["triggerEvent"];
  let triggerEvent: string | undefined;
  if (triggerEventRaw !== undefined) {
    if (typeof triggerEventRaw !== "string") {
      return { ok: false, error: "triggerEvent must be string" };
    }
    triggerEvent = triggerEventRaw;
  }
  if (cadence === "on_event" && !triggerEvent) {
    return { ok: false, error: "on_event cadence requires triggerEvent" };
  }
  return { ok: true, value: { kind, cadence, triggerEvent } };
}

function parseTone(raw: unknown):
  | { ok: true; value: ToneModifiers }
  | { ok: false; error: string }
{
  if (!isObject(raw)) return { ok: false, error: "must be object" };
  const aggression = raw["aggression"];
  const formality = raw["formality"];
  const verbosity = raw["verbosity"];
  for (const [name, v] of [
    ["aggression", aggression],
    ["formality", formality],
    ["verbosity", verbosity],
  ] as const) {
    if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 1) {
      return { ok: false, error: `${name} must be a number in [0,1]` };
    }
  }
  return {
    ok: true,
    value: {
      aggression: aggression as number,
      formality: formality as number,
      verbosity: verbosity as number,
    },
  };
}

// ─── Helpers ───────────────────────────────────────────────────────────────

function isObject(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function strField(raw: Record<string, unknown>, key: string): string | undefined {
  const v = raw[key];
  return typeof v === "string" ? v : undefined;
}

function isOneOf<T extends string>(v: unknown, allowed: readonly T[]): v is T {
  return typeof v === "string" && (allowed as readonly string[]).includes(v);
}

function fail(error: string): { ok: false; error: string } {
  return { ok: false, error };
}

function styleErr(detail: string): { ok: false; error: string } {
  return { ok: false, error: `style.${detail}` };
}
