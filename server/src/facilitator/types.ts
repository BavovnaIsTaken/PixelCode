/**
 * Server-side TS types for the Facilitator System.
 *
 * These mirror the Dart shapes defined in `lib/models/facilitator_*.dart`.
 * Keep them in sync — the JSON they emit/consume crosses the WS boundary.
 *
 * Design: docs/FACILITATOR_SYSTEM.md
 */

import type { ScopeScore } from "../quest/scope_scorer.js";

// ─── Style ──────────────────────────────────────────────────────────────────

export type Laloux = "red" | "amber" | "orange" | "green" | "teal";

export type CeremonyKind =
  | "standup"
  | "retro"
  | "review"
  | "briefing"
  | "journal"
  | "on_demand"
  | "none";

export type CeremonyCadence =
  | "daily"
  | "weekly"
  | "biweekly"
  | "monthly"
  | "on_event"
  | "never";

export interface CeremonySpec {
  kind: CeremonyKind;
  cadence: CeremonyCadence;
  triggerEvent?: string;
}

export type ScopeDimensionKey =
  | "entity_count"
  | "interaction_surface"
  | "auth"
  | "integrations"
  | "realtime"
  | "none";

export type IntakeInputKind = "text" | "choice";

export interface IntakeQuestion {
  id: string;
  prompt: string;
  inputKind: IntakeInputKind;
  choices?: string[];
  mapsTo: ScopeDimensionKey;
}

export interface ToneModifiers {
  aggression: number; // 0..1
  formality: number;
  verbosity: number;
}

export type OutputFormatKey =
  | "quest_line"
  | "mission_briefing"
  | "milestone_tree"
  | "sprint_backlog"
  | "koan_entry";

export interface FacilitatorStyle {
  id: string;
  displayName: string;
  tagline: string;
  laloux: Laloux;
  personaPrompt: string;
  lexicon: Record<string, string>;
  ceremonySchedule: CeremonySpec[];
  intakeTemplate: IntakeQuestion[];
  outputMapper: OutputFormatKey;
  toneModifiers: ToneModifiers;
}

// ─── Intake answers ─────────────────────────────────────────────────────────

/**
 * One answer per question, keyed by question id. For `text` questions,
 * this is the raw user reply. For `choice` questions, this is the chosen
 * option label (must match one of the `choices` entries).
 */
export type IntakeAnswers = Record<string, string>;

// ─── Runtime events ─────────────────────────────────────────────────────────

/**
 * Events the runner reacts to. Drives ceremony triggers and output
 * mutation. Concrete shapes for each event keep `runner.tick` typed.
 */
export type FacilitatorEvent =
  | { kind: "task_completed"; taskId: string; at: Date }
  | { kind: "task_started"; taskId: string; at: Date }
  | { kind: "act_complete"; actId: string; at: Date }
  | { kind: "sprint_end"; sprintNumber: number; at: Date }
  | { kind: "mission_assigned"; missionId: string; at: Date }
  | { kind: "user_idle"; sinceMinutes: number; at: Date };

// ─── Ceremony fire log ──────────────────────────────────────────────────────

/**
 * Tracks when each ceremony fired last, so the scheduler can decide
 * what's due now. Keyed by `${kind}:${cadence}:${triggerEvent ?? ""}`.
 */
export type CeremonyFireLog = Record<string, string>; // key → ISO timestamp

// ─── Runner result types ────────────────────────────────────────────────────

export interface SeedResult {
  /** Final ScopeScore after applying intake overrides on the heuristic. */
  finalScore: ScopeScore;

  /** Serialized `FacilitatorOutput` JSON (the discriminated payload). */
  outputJson: string;

  /** Format key the output is in. */
  outputFormat: OutputFormatKey;
}

export interface CeremonyTrigger {
  /** Which ceremony spec fired. */
  spec: CeremonySpec;

  /**
   * Wall-clock time the runner observed the fire. Recorded in the
   * fire log so the next due-check is offset correctly.
   */
  firedAt: Date;
}

export interface SwitchResult {
  /** Style id we switched away from. */
  fromStyleId: string;
  /** Style id we switched to. */
  toStyleId: string;
  /**
   * Whether the switch produced a fresh output seed (true if shapes
   * differ; false if the new style happens to use the same shape and
   * we kept the existing output).
   */
  reseedRequired: boolean;
}
