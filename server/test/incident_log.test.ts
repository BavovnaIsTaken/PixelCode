/**
 * Tests for the C.2.5 incident logger — IO shape + summarizeIncidents
 * rate math. Mirrors the pattern in usage_log.test.ts.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  IncidentLogger,
  newIncidentId,
  summarizeIncidents,
  isNoOpRun,
  type IncidentEntry,
} from "../src/incident_log.js";

function fakeDeps() {
  const writes: Array<{ path: string; line: string }> = [];
  const warns: string[] = [];
  const files = new Map<string, string>();
  return {
    writes,
    warns,
    files,
    deps: {
      appendLine: (path: string, line: string) => {
        writes.push({ path, line });
        files.set(path, (files.get(path) ?? "") + line + "\n");
      },
      readAll: (path: string) => files.get(path) ?? "",
      exists: (path: string) => files.has(path),
      ensureDir: () => {},
      warn: (msg: string) => warns.push(msg),
    },
  };
}

function sampleEntry(over: Partial<IncidentEntry> = {}): IncidentEntry {
  return {
    incidentId: "premature_complete_1_1700000000",
    kind: "premature_complete",
    runId: "chat_1_1700000000",
    role: "manager",
    taskType: "chat",
    agentId: "manager",
    occurredAt: new Date(1_700_000_000_000).toISOString(),
    details: { unmatchedDispatchIds: ["dispatch_42_1700000000"], matchedClaim: "Готово:" },
    ...over,
  };
}

test("record appends one JSONL line", () => {
  const { writes, deps } = fakeDeps();
  const logger = new IncidentLogger("/tmp/incident.jsonl", deps);
  logger.record(sampleEntry());
  assert.equal(writes.length, 1);
  const parsed = JSON.parse(writes[0]!.line);
  assert.equal(parsed.kind, "premature_complete");
  assert.equal(parsed.runId, "chat_1_1700000000");
});

test("record swallows disk error via warn (does not throw)", () => {
  const { warns, deps } = fakeDeps();
  const explodingDeps = {
    ...deps,
    appendLine: () => {
      throw new Error("disk full");
    },
  };
  const logger = new IncidentLogger("/tmp/x.jsonl", explodingDeps);
  assert.doesNotThrow(() => logger.record(sampleEntry()));
  assert.equal(warns.length, 1);
  assert.match(warns[0]!, /append failed.*disk full/);
});

test("readAllEntries roundtrips multiple kinds", () => {
  const { deps } = fakeDeps();
  const logger = new IncidentLogger("/tmp/incident.jsonl", deps);
  logger.record(sampleEntry({ kind: "premature_complete", incidentId: "p1" }));
  logger.record(sampleEntry({ kind: "no_op_run", incidentId: "n1", runId: "dispatch_2_x", taskType: "dispatch", agentId: "character-artist#1", role: "character-artist" }));
  const all = logger.readAllEntries();
  assert.equal(all.length, 2);
  assert.equal(all[0]!.kind, "premature_complete");
  assert.equal(all[1]!.kind, "no_op_run");
});

test("readAllEntries skips corrupt lines but keeps valid ones", () => {
  const { warns, deps, files } = fakeDeps();
  files.set(
    "/tmp/incident.jsonl",
    JSON.stringify(sampleEntry()) + "\n" +
    "not-valid-json\n" +
    JSON.stringify({ kind: "premature_complete" /* missing other fields */ }) + "\n" +
    JSON.stringify(sampleEntry({ incidentId: "second" })) + "\n",
  );
  const logger = new IncidentLogger("/tmp/incident.jsonl", deps);
  const entries = logger.readAllEntries();
  assert.equal(entries.length, 2);
  assert.equal(entries[0]!.incidentId, "premature_complete_1_1700000000");
  assert.equal(entries[1]!.incidentId, "second");
  assert.equal(warns.length, 1);
  assert.match(warns[0]!, /skipped 2/);
});

test("newIncidentId is monotonic and tagged with kind", () => {
  const a = newIncidentId("premature_complete");
  const b = newIncidentId("no_op_run");
  assert.match(a, /^premature_complete_/);
  assert.match(b, /^no_op_run_/);
  assert.notEqual(a, b);
});

test("summarizeIncidents computes rates correctly", () => {
  const entries: IncidentEntry[] = [
    sampleEntry({ kind: "premature_complete", incidentId: "a" }),
    sampleEntry({ kind: "premature_complete", incidentId: "b" }),
    sampleEntry({ kind: "no_op_run", incidentId: "c" }),
  ];
  const r = summarizeIncidents(entries, 100);
  assert.equal(r.prematureCompleteCount, 2);
  assert.equal(r.noOpRunCount, 1);
  assert.equal(r.totalRuns, 100);
  assert.equal(r.prematureCompleteRate, 0.02);
  assert.equal(r.noOpRunRate, 0.01);
});

test("isNoOpRun: zero tool calls is a no-op", () => {
  assert.equal(isNoOpRun(0), true);
});

test("isNoOpRun: any positive tool count is not a no-op", () => {
  assert.equal(isNoOpRun(1), false);
  assert.equal(isNoOpRun(7), false);
  assert.equal(isNoOpRun(99), false);
});

test("summarizeIncidents handles zero divisor without NaN", () => {
  const r = summarizeIncidents([], 0);
  assert.equal(r.prematureCompleteRate, 0);
  assert.equal(r.noOpRunRate, 0);
  // The point of this test: no-data state must render cleanly in the UI,
  // not as "NaN%". Default to 0 is a deliberate choice over null/undef
  // because the daily-control surface needs a plottable number.
});
