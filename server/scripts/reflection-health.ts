#!/usr/bin/env tsx
/**
 * Reflection telemetry health check — single source of truth for
 * "is the personalization confabulation gate actually working?"
 *
 * Reads `~/.pixelcode/projects/<key>/telemetry/reflection.jsonl` for the
 * current project (or one passed via --project=<path>), summarizes via
 * `summarizeReflectionTelemetry`, and prints KPIs with traffic-light
 * verdicts against the thresholds documented in CLAUDE.md §5.
 *
 * Usage:
 *   tsx server/scripts/reflection-health.ts
 *   tsx server/scripts/reflection-health.ts --project=/path/to/project
 *   tsx server/scripts/reflection-health.ts --since=7d
 *
 * Run from the server/ directory or pass a full path to tsx.
 */

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import {
  summarizeReflectionTelemetry,
  type ReflectionEvent,
} from "../src/reflection_prompt.ts";

interface Args {
  projectPath: string;
  sinceMs: number | null;
}

function parseArgs(argv: string[]): Args {
  let projectPath = process.cwd();
  let sinceMs: number | null = null;
  for (const a of argv.slice(2)) {
    if (a.startsWith("--project=")) projectPath = a.slice("--project=".length);
    else if (a.startsWith("--since=")) {
      const v = a.slice("--since=".length);
      const m = /^(\d+)([dhm])$/.exec(v);
      if (!m) {
        console.error(`Invalid --since value: ${v} (expected e.g. 7d, 24h, 30m)`);
        process.exit(2);
      }
      const n = Number(m[1]);
      const unit = m[2];
      sinceMs = n * (unit === "d" ? 86_400_000 : unit === "h" ? 3_600_000 : 60_000);
    }
  }
  return { projectPath, sinceMs };
}

function telemetryFile(projectPath: string): string {
  const key = projectPath.replace(/\//g, "-").replace(/^-/, "");
  return join(homedir(), ".pixelcode", "projects", key, "telemetry", "reflection.jsonl");
}

function loadEvents(file: string, sinceMs: number | null): ReflectionEvent[] {
  if (!existsSync(file)) return [];
  const lines = readFileSync(file, "utf-8").split("\n").filter((l) => l.length > 0);
  const cutoff = sinceMs !== null ? Date.now() - sinceMs : 0;
  const events: ReflectionEvent[] = [];
  for (const l of lines) {
    try {
      const obj = JSON.parse(l) as ReflectionEvent & { ts?: string };
      if (cutoff > 0 && obj.ts && new Date(obj.ts).getTime() < cutoff) continue;
      events.push(obj as ReflectionEvent);
    } catch {
      // skip malformed line — telemetry is append-only, partial writes possible
    }
  }
  return events;
}

function light(ok: boolean): string {
  return ok ? "🟢" : "🔴";
}

function pct(n: number): string {
  return `${(n * 100).toFixed(1)}%`;
}

function main(): void {
  const args = parseArgs(process.argv);
  const file = telemetryFile(args.projectPath);

  console.log(`Project:  ${args.projectPath}`);
  console.log(`Log:      ${file}`);
  if (args.sinceMs) console.log(`Window:   last ${args.sinceMs / 86_400_000} day(s)`);
  console.log("");

  if (!existsSync(file)) {
    console.log("⚠ No telemetry log exists yet — run a few reflection passes first.");
    console.log("  Cold-project state. Re-check after ~10 chat sessions with the team.");
    process.exit(0);
  }

  const events = loadEvents(file, args.sinceMs);
  if (events.length === 0) {
    console.log("⚠ Log exists but no events in the requested window.");
    process.exit(0);
  }

  const kpi = summarizeReflectionTelemetry(events);

  console.log("=== Reflection KPIs ===\n");
  console.log(`Submitted candidates:       ${kpi.submitted}`);
  console.log(`  → pending:                ${kpi.pending}`);
  console.log(`  → duplicate (same-sess):  ${kpi.duplicate}`);
  console.log(`  → too-soon (burst-deny):  ${kpi.tooSoon}`);
  console.log(`  → promoted (threshold):   ${kpi.promotedViaThreshold}`);
  console.log(`  → promoted (real-bypass): ${kpi.promotedViaBypass}`);
  console.log("");
  console.log(`Traits decayed-pruned:      ${kpi.decayedPruned}`);
  console.log(`Candidates pruned (stale):  ${kpi.prunedStale}`);
  console.log(`Constraint violations:      ${kpi.constraintViolations}`);
  console.log("");
  console.log("=== Health (thresholds from CLAUDE.md §5) ===\n");

  const promotionOk = kpi.promotionRate >= 0.1 && kpi.promotionRate <= 0.7;
  const bypassOk = kpi.bypassRate <= 0.7;
  const violationOk = kpi.violationRate < 0.05;
  const tooSoonActive = kpi.tooSoon > 0 || kpi.submitted < 5;

  console.log(`${light(promotionOk)} promotionRate = ${pct(kpi.promotionRate)}`);
  console.log(`     ${promotionOk ? "in healthy 10–70% band" : kpi.promotionRate < 0.1 ? "TOO LOW — gate may be over-strict OR Haiku is noisy" : "TOO HIGH — gate may be over-permissive"}`);
  console.log("");
  console.log(`${light(bypassOk)} bypassRate    = ${pct(kpi.bypassRate)}`);
  console.log(`     ${bypassOk ? "ok — gate is doing real work" : "TOO HIGH — most promotions skip the gate via existing real traits; gate is redundant"}`);
  console.log("");
  console.log(`${light(violationOk)} violationRate = ${pct(kpi.violationRate)}`);
  console.log(`     ${violationOk ? "ok — Haiku respects hard-constraint" : "ALERT — Haiku is producing 'tool unavailable'-style claims despite ground-truth"}`);
  console.log("");
  console.log(`${light(tooSoonActive)} too-soon defense = ${kpi.tooSoon} events`);
  console.log(`     ${tooSoonActive ? "active or sample too small" : "ZERO too-soon hits over a non-trivial sample — sessionId fallback may be broken"}`);
  console.log("");

  // Roadmap decision pre-conditions (from ROADMAP.md "Reflection model upgrade")
  console.log("=== Q4 2026 Sonnet-upgrade decision ===\n");
  const skipUpgrade = kpi.promotionRate >= 0.3 && kpi.violationRate < 0.05;
  if (skipUpgrade) {
    console.log("🟢 KPI within target — Haiku reflection is healthy, NO model upgrade needed.");
  } else {
    console.log("🟡 KPI outside target — Sonnet upgrade may be worth it.");
    if (kpi.promotionRate < 0.3) console.log(`   promotionRate ${pct(kpi.promotionRate)} < 0.3 target`);
    if (kpi.violationRate >= 0.05) console.log(`   violationRate ${pct(kpi.violationRate)} ≥ 0.05 ceiling`);
  }
  console.log("");

  // Show top-N recent violations for manual inspection
  const violationEvents = events.filter((e) => e.kind === "constraint_violation").slice(-5);
  if (violationEvents.length > 0) {
    console.log("=== Last 5 constraint violations ===\n");
    for (const v of violationEvents) {
      if (v.kind !== "constraint_violation") continue;
      console.log(`  [${v.agentId}] tag=${v.tag} phrases=${JSON.stringify(v.phrases)}`);
      console.log(`     lesson: "${v.lesson.slice(0, 120)}${v.lesson.length > 120 ? "…" : ""}"`);
    }
    console.log("");
  }
}

main();
