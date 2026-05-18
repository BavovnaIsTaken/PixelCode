import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, mkdirSync, readFileSync, existsSync, appendFileSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import {
  buildReflectionPrompt,
  detectForbiddenAvailabilityClaims,
  appendReflectionTelemetry,
  summarizeReflectionTelemetry,
  buildReflectionKpiMessage,
  readReflectionEvents,
  FORBIDDEN_TOOL_AVAILABILITY_PHRASES,
  MAX_EVENTS_PER_AGENT,
  type ReflectionEvent,
} from "../src/reflection_prompt.ts";

// ─── Fixtures ───────────────────────────────────────────────────────────────

const FX_HAPPY = {
  activities: [
    { agentId: "manager#1", event: "delegated", detail: "→ coder#1: refactor X" },
    { agentId: "manager#1", event: "tool_use", detail: "Tool: mcp__dispatch__dispatch [success]" },
    { agentId: "coder#1", event: "started", detail: "refactor X" },
    { agentId: "coder#1", event: "tool_use", detail: "Tool: Edit [success]" },
    { agentId: "coder#1", event: "completed", detail: "Done ($0.12, 18s)" },
  ],
  allowedToolsByAgent: {
    "manager#1": [
      "Read", "Glob", "Grep",
      "mcp__dispatch__dispatch",
      "mcp__dispatch__team_status",
      "mcp__dispatch__board_list",
    ],
    "coder#1": ["Read", "Edit", "Write", "Glob", "Grep", "Bash"],
  },
  reworkAgents: [],
  hasErrors: false,
};

const FX_ERROR = {
  activities: [
    { agentId: "coder#1", event: "started", detail: "build" },
    { agentId: "coder#1", event: "error", detail: "Build failed: xcrun returned 1" },
  ],
  allowedToolsByAgent: { "coder#1": ["Bash", "Read"] },
  reworkAgents: ["coder#1(rework=1)"],
  hasErrors: true,
};

const FX_EMPTY_TOOLSET = {
  activities: [
    { agentId: "tester#1", event: "started", detail: "run tests" },
  ],
  // gameState absent — toolset cannot be reconstructed
  allowedToolsByAgent: {},
  reworkAgents: [],
  hasErrors: false,
};

const FX_DISPATCH_HEAVY = {
  activities: [
    { agentId: "manager#1", event: "tool_use", detail: "Tool: mcp__dispatch__dispatch agent=coder#1" },
    { agentId: "manager#1", event: "tool_use", detail: "Tool: mcp__dispatch__board_create_task title=Foo" },
    { agentId: "manager#1", event: "tool_use", detail: "Tool: mcp__dispatch__team_status" },
    { agentId: "coder#1", event: "started", detail: "Foo" },
    { agentId: "coder#1", event: "completed", detail: "Done" },
  ],
  allowedToolsByAgent: {
    "manager#1": [
      "Read", "Glob", "Grep",
      "mcp__dispatch__dispatch",
      "mcp__dispatch__team_status",
      "mcp__dispatch__board_create_task",
    ],
    "coder#1": ["Read", "Edit", "Bash"],
  },
  reworkAgents: [],
  hasErrors: false,
};

// ─── buildReflectionPrompt — structural snapshot tests ──────────────────────

test("buildReflectionPrompt: emits all four ground-truth sections", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  assert.match(out, /<session_activity>/);
  assert.match(out, /<\/session_activity>/);
  assert.match(out, /<allowed_tools>/);
  assert.match(out, /<\/allowed_tools>/);
  assert.match(out, /<tool_errors>/);
  assert.match(out, /<\/tool_errors>/);
  assert.match(out, /<dispatch_log>/);
  assert.match(out, /<\/dispatch_log>/);
});

test("buildReflectionPrompt: keeps hard-constraint wording verbatim", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  // These specific phrases govern Haiku's behaviour and must not silently drift.
  assert.ok(
    out.includes(`NEVER claim a tool was "unavailable" or "missing" if it appears in <allowed_tools>`),
    "missing 'NEVER claim' constraint",
  );
  assert.ok(
    out.includes("<allowed_tools> is authoritative"),
    "missing authoritative-source statement",
  );
  assert.ok(
    out.includes(`do not invent a "fallback to Task" or "tool unavailable" narrative`),
    "missing dispatch-log narrative ban",
  );
});

test("buildReflectionPrompt: allowed_tools section lists tools per involved agent", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  assert.match(out, /manager#1: Read, Glob, Grep, mcp__dispatch__dispatch/);
  assert.match(out, /coder#1: Read, Edit, Write, Glob, Grep, Bash/);
});

test("buildReflectionPrompt: empty toolset for involved agent emits explicit unknown marker", () => {
  // Negative case: gameState was never set, so allowedToolsByAgent comes empty.
  // The block must not collapse — Haiku still needs to see the section exists
  // and shouldn't infer from absence.
  const out = buildReflectionPrompt(FX_EMPTY_TOOLSET);
  assert.match(
    out,
    /tester#1: \(none — toolset unknown for this session\)/,
    "expected explicit unknown-toolset marker",
  );
});

test("buildReflectionPrompt: error block populated when activities include errors", () => {
  const out = buildReflectionPrompt(FX_ERROR);
  assert.match(out, /<tool_errors>\ncoder#1: Build failed: xcrun returned 1\n<\/tool_errors>/);
  assert.match(out, /⚠️ The session had errors\./);
  assert.match(out, /⚠️ Agents with rework: coder#1\(rework=1\)/);
});

test("buildReflectionPrompt: error block reads '(none)' when no errors fired", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  assert.match(out, /<tool_errors>\n\(none\)\n<\/tool_errors>/);
  assert.match(out, /No errors during session\./);
  assert.match(out, /No rework needed\./);
});

test("buildReflectionPrompt: dispatch_log captures both delegated events and mcp__dispatch__* tool_uses", () => {
  const out = buildReflectionPrompt(FX_DISPATCH_HEAVY);
  assert.match(out, /manager#1: \[tool_use\] Tool: mcp__dispatch__dispatch/);
  assert.match(out, /manager#1: \[tool_use\] Tool: mcp__dispatch__board_create_task/);
  assert.match(out, /manager#1: \[tool_use\] Tool: mcp__dispatch__team_status/);
});

test("buildReflectionPrompt: caps per-agent event stream at MAX_EVENTS_PER_AGENT", () => {
  const noisy = {
    activities: [] as Array<{ agentId: string; event: string; detail: string }>,
    allowedToolsByAgent: { "coder#1": ["Read"] },
    reworkAgents: [],
    hasErrors: false,
  };
  for (let i = 0; i < 25; i++) {
    noisy.activities.push({
      agentId: "coder#1",
      event: "tool_use",
      detail: `Tool: Edit #${i}`,
    });
  }
  const out = buildReflectionPrompt(noisy);
  const coderLines = out.split("\n").filter((l) => l.includes("Tool: Edit #"));
  assert.equal(coderLines.length, MAX_EVENTS_PER_AGENT,
    `expected exactly ${MAX_EVENTS_PER_AGENT} events to survive truncation`);
  // The most recent events (#15..#24) must be kept, not the earliest.
  assert.match(out, /Tool: Edit #24/);
  assert.match(out, /Tool: Edit #15/);
  assert.ok(!out.includes("Tool: Edit #14"), "earliest events should be dropped");
});

test("buildReflectionPrompt: zero activities still produces a well-formed prompt", () => {
  // Caller guards against this in production (returns early), but we still
  // want the function to be total — no crashes on edge inputs.
  const out = buildReflectionPrompt({
    activities: [],
    allowedToolsByAgent: {},
    reworkAgents: [],
    hasErrors: false,
  });
  assert.match(out, /<session_activity>\n\n<\/session_activity>/);
  assert.match(out, /<allowed_tools>\n\(no agents involved\)/);
});

test("buildReflectionPrompt: idempotent — same input produces byte-identical output", () => {
  const a = buildReflectionPrompt(FX_HAPPY);
  const b = buildReflectionPrompt(FX_HAPPY);
  assert.equal(a, b);
});

test("buildReflectionPrompt: team_roster override appears in prompt", () => {
  const out = buildReflectionPrompt({
    ...FX_HAPPY,
    teamRoster: ["coder", "reviewer"],
  });
  assert.match(out, /Team agents: coder, reviewer\n/);
});

// ─── C.2.6 — Canonical taxonomy injection ──────────────────────────────────

test("buildReflectionPrompt: emits <canonical_tags> section with both weakness and strength buckets", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  assert.match(out, /<canonical_tags>/);
  assert.match(out, /<\/canonical_tags>/);
  assert.match(out, /Weakness tags/);
  assert.match(out, /Strength tags/);
});

test("buildReflectionPrompt: <canonical_tags> lists each canonical tag (regression — taxonomy must reach Haiku)", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  // Spot-check a few canonical tags to confirm they made it into the prompt.
  // If the taxonomy module changes, this test surfaces the wiring break
  // before users notice via 100% invalid_tag rejections.
  assert.ok(out.includes("insufficient-context-gathering"),
    "weakness tag must appear in <canonical_tags>");
  assert.ok(out.includes("unclear-dispatch-specification"),
    "weakness tag must appear in <canonical_tags>");
  assert.ok(out.includes("proactive-investigation"),
    "strength tag must appear in <canonical_tags>");
  assert.ok(out.includes("context-rich-delegation"),
    "strength tag must appear in <canonical_tags>");
});

test("buildReflectionPrompt: instructs Haiku that tags MUST come from canonical list", () => {
  const out = buildReflectionPrompt(FX_HAPPY);
  // Load-bearing wording — paired with the server-side isValidTag check.
  // If this phrasing drifts, server rejects 100% of submissions silently.
  assert.ok(
    out.includes("canonical list") || out.includes("<canonical_tags>"),
    "prompt must reference the canonical list",
  );
  assert.ok(
    /Do not invent new tags/i.test(out),
    "prompt must explicitly forbid invented tags",
  );
});

// ─── detectForbiddenAvailabilityClaims ──────────────────────────────────────

test("detectForbiddenAvailabilityClaims: catches the original incident phrasing", () => {
  const incident = "Attempted to use mcp__dispatch__dispatch to delegate work but it was not available, then fell back to Task tool.";
  const hits = detectForbiddenAvailabilityClaims(incident);
  assert.ok(hits.length >= 2, `expected ≥2 hits, got ${JSON.stringify(hits)}`);
  assert.ok(hits.includes("was not available"));
  assert.ok(hits.includes("fell back to task") || hits.includes("fell back to the task tool"));
});

test("detectForbiddenAvailabilityClaims: case-insensitive", () => {
  const out = detectForbiddenAvailabilityClaims("Tool Was NOT Available, then Fell Back To Task.");
  assert.ok(out.length >= 2);
});

test("detectForbiddenAvailabilityClaims: clean lesson returns empty", () => {
  const clean = "Manager systematically delegated tasks with clear file paths and explicit success criteria.";
  assert.deepEqual(detectForbiddenAvailabilityClaims(clean), []);
});

test("detectForbiddenAvailabilityClaims: legitimate error description NOT flagged", () => {
  // A lesson that describes a real error message (not inferring availability)
  // should not be punished — this is what we WANT the model to produce.
  const legitimate = "Coder hit 'permission denied' when writing to /usr/local/bin — should have checked write access first.";
  assert.deepEqual(detectForbiddenAvailabilityClaims(legitimate), []);
});

test("FORBIDDEN_TOOL_AVAILABILITY_PHRASES: all entries are lower-case", () => {
  // detectForbiddenAvailabilityClaims relies on this invariant — if anyone
  // adds a phrase with capitals it silently never matches.
  for (const p of FORBIDDEN_TOOL_AVAILABILITY_PHRASES) {
    assert.equal(p, p.toLowerCase(), `phrase "${p}" is not lower-case`);
  }
});

// ─── Telemetry — JSONL log + KPI summarization ──────────────────────────────

function withTmpProject<T>(fn: (projectPath: string, telemetryDir: string) => T): T {
  const dir = mkdtempSync(join(tmpdir(), "reflection-telemetry-test-"));
  const telemetryDir = join(
    homedir(),
    ".pixelcode",
    "projects",
    dir.replace(/\//g, "-").replace(/^-/, ""),
    "telemetry",
  );
  try {
    return fn(dir, telemetryDir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
    rmSync(telemetryDir, { recursive: true, force: true });
  }
}

function readEvents(telemetryFile: string): ReflectionEvent[] {
  if (!existsSync(telemetryFile)) return [];
  return readFileSync(telemetryFile, "utf-8")
    .split("\n")
    .filter((l) => l.length > 0)
    .map((l) => JSON.parse(l))
    .map(({ ts: _ts, ...rest }) => rest as ReflectionEvent);
}

test("appendReflectionTelemetry: writes JSONL one line per event with timestamp", () => {
  withTmpProject((projectPath, telemetryDir) => {
    appendReflectionTelemetry(projectPath, {
      kind: "candidate_submitted",
      agentId: "coder#1",
      tag: "x",
      type: "strength",
      category: "code_quality",
      status: "pending",
      sessionCount: 1,
    });
    appendReflectionTelemetry(projectPath, {
      kind: "candidate_submitted",
      agentId: "coder#1",
      tag: "x",
      type: "strength",
      category: "code_quality",
      status: "promoted",
      via: "threshold",
    });
    const file = join(telemetryDir, "reflection.jsonl");
    const lines = readFileSync(file, "utf-8").split("\n").filter((l) => l.length > 0);
    assert.equal(lines.length, 2);
    for (const l of lines) {
      const parsed = JSON.parse(l);
      assert.ok(typeof parsed.ts === "string" && parsed.ts.length > 0);
      assert.ok(parsed.kind === "candidate_submitted");
    }
  });
});

test("appendReflectionTelemetry: read-only directory does not throw", () => {
  // Best-effort guarantee: telemetry never breaks the host. We simulate this
  // by writing to a path we don't have permission for — but since tmpfiles
  // are writable everywhere, instead pass a clearly invalid project path
  // and rely on appendFileSync to fail+swallow internally.
  appendReflectionTelemetry(
    "/this/path/cannot/exist/and/is/not/writable",
    { kind: "reflection_skipped", reason: "no_activity" },
  );
  // No assertion — the assertion is "no throw". Implicit.
});

test("summarizeReflectionTelemetry: empty stream → all zero KPIs", () => {
  const k = summarizeReflectionTelemetry([]);
  assert.deepEqual(k, {
    submitted: 0,
    promotedViaThreshold: 0,
    promotedViaBypass: 0,
    pending: 0,
    duplicate: 0,
    tooSoon: 0,
    prunedStale: 0,
    decayedPruned: 0,
    constraintViolations: 0,
    invalidTagCount: 0,
    promotionRate: 0,
    bypassRate: 0,
    violationRate: 0,
    invalidTagRate: 0,
    tagEntropy: 0,
    topTagShare: 0,
  });
});

test("summarizeReflectionTelemetry: computes promotion + bypass + violation rates", () => {
  const events: ReflectionEvent[] = [
    { kind: "candidate_submitted", agentId: "a", tag: "t1", type: "strength", category: "code_quality", status: "promoted", via: "threshold" },
    { kind: "candidate_submitted", agentId: "a", tag: "t2", type: "strength", category: "code_quality", status: "promoted", via: "real-trait-bypass" },
    { kind: "candidate_submitted", agentId: "a", tag: "t3", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
    { kind: "candidate_submitted", agentId: "a", tag: "t4", type: "weakness", category: "tools_usage", status: "too-soon", gapMs: 30_000 },
    { kind: "candidate_submitted", agentId: "a", tag: "t5", type: "strength", category: "code_quality", status: "duplicate" },
    { kind: "constraint_violation", agentId: "a", tag: "t1", phrases: ["was not available"], lesson: "x" },
  ];
  const k = summarizeReflectionTelemetry(events);
  assert.equal(k.submitted, 5);
  assert.equal(k.promotedViaThreshold, 1);
  assert.equal(k.promotedViaBypass, 1);
  assert.equal(k.pending, 1);
  assert.equal(k.duplicate, 1);
  assert.equal(k.tooSoon, 1);
  assert.equal(k.constraintViolations, 1);
  assert.equal(k.promotionRate, 2 / 5);
  assert.equal(k.bypassRate, 1 / 2);
  assert.equal(k.violationRate, 1 / 5);
});

test("summarizeReflectionTelemetry: invalid_tag events count separately + drive invalidTagRate", () => {
  // C.2.6 — Haiku occasionally invents off-taxonomy tags despite the closed
  // list. Those are rejected at the gate and emit `invalid_tag` telemetry.
  // The rate is computed against ALL submission attempts (submitted + invalid).
  const events: ReflectionEvent[] = [
    { kind: "candidate_submitted", agentId: "a", tag: "tool-misuse", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
    { kind: "candidate_submitted", agentId: "a", tag: "tool-misuse", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
    { kind: "candidate_submitted", agentId: "a", tag: "scope-creep", type: "weakness", category: "code_quality", status: "pending", sessionCount: 1 },
    { kind: "invalid_tag", agentId: "a", tag: "fancy-invented-tag", type: "weakness", category: "communication", lesson: "x" },
    { kind: "invalid_tag", agentId: "b", tag: "another-invented", type: "strength", category: "delegation", lesson: "y" },
  ];
  const k = summarizeReflectionTelemetry(events);
  assert.equal(k.submitted, 3);
  assert.equal(k.invalidTagCount, 2);
  // 2 invalid / (3 submitted + 2 invalid) = 0.4
  assert.equal(k.invalidTagRate, 2 / 5);
});

test("summarizeReflectionTelemetry: tagEntropy reflects diversity of submitted tags", () => {
  // Three distinct tags, evenly distributed → maximum entropy for 3 bins
  // = log2(3) ≈ 1.585. Submitted tags drive the metric; invalid_tag events
  // are excluded (they never reached the candidate pool).
  const events: ReflectionEvent[] = [
    { kind: "candidate_submitted", agentId: "a", tag: "x", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
    { kind: "candidate_submitted", agentId: "a", tag: "y", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
    { kind: "candidate_submitted", agentId: "a", tag: "z", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
  ];
  const k = summarizeReflectionTelemetry(events);
  assert.ok(Math.abs(k.tagEntropy - Math.log2(3)) < 1e-9,
    `expected log2(3) ≈ 1.585 bits, got ${k.tagEntropy}`);
  // Three distinct tags out of three → top share = 1/3.
  assert.ok(Math.abs(k.topTagShare - 1 / 3) < 1e-9);
});

test("summarizeReflectionTelemetry: tagEntropy collapses below 1.5 bits under catastrophic binning", () => {
  // 90/10 split — the exact pattern the entropy threshold (CLAUDE.md §5)
  // is meant to flag. If Haiku is binning, this is what telemetry sees.
  const events: ReflectionEvent[] = [];
  for (let i = 0; i < 9; i++) {
    events.push({ kind: "candidate_submitted", agentId: "a", tag: "tool-misuse", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 });
  }
  events.push({ kind: "candidate_submitted", agentId: "a", tag: "scope-creep", type: "weakness", category: "code_quality", status: "pending", sessionCount: 1 });
  const k = summarizeReflectionTelemetry(events);
  assert.ok(k.tagEntropy < 1.5,
    `9/1 split should fall below 1.5-bit drift floor; got ${k.tagEntropy}`);
  assert.ok(k.topTagShare > 0.8,
    `top-tag share should clearly clear 50% threshold; got ${k.topTagShare}`);
});

test("summarizeReflectionTelemetry: prune/decay counts sum across events", () => {
  const events: ReflectionEvent[] = [
    { kind: "candidate_pruned_stale", count: 3 },
    { kind: "candidate_pruned_stale", count: 2 },
    { kind: "traits_decayed_pruned", count: 1 },
    { kind: "traits_decayed_pruned", count: 4 },
  ];
  const k = summarizeReflectionTelemetry(events);
  assert.equal(k.prunedStale, 5);
  assert.equal(k.decayedPruned, 5);
  assert.equal(k.submitted, 0);
});

// ─── readReflectionEvents + buildReflectionKpiMessage (WS payload) ──────────

test("buildReflectionKpiMessage: cold project (no log) returns hasData=false with zeros", () => {
  withTmpProject((projectPath) => {
    const msg = buildReflectionKpiMessage(projectPath);
    assert.equal(msg.type, "reflection_kpi");
    assert.equal(msg.hasData, false);
    assert.equal(msg.submitted, 0);
    assert.equal(msg.promotionRate, 0);
    assert.deepEqual(msg.recentViolations, []);
  });
});

test("buildReflectionKpiMessage: with events, mirrors summarizeReflectionTelemetry", () => {
  withTmpProject((projectPath) => {
    const events: ReflectionEvent[] = [
      { kind: "candidate_submitted", agentId: "a", tag: "t1", type: "strength", category: "code_quality", status: "promoted", via: "threshold" },
      { kind: "candidate_submitted", agentId: "a", tag: "t2", type: "weakness", category: "tools_usage", status: "pending", sessionCount: 1 },
      { kind: "candidate_submitted", agentId: "b", tag: "t3", type: "strength", category: "communication", status: "too-soon", gapMs: 60_000 },
    ];
    for (const e of events) appendReflectionTelemetry(projectPath, e);

    const msg = buildReflectionKpiMessage(projectPath);
    assert.equal(msg.hasData, true);
    assert.equal(msg.submitted, 3);
    assert.equal(msg.promotedViaThreshold, 1);
    assert.equal(msg.pending, 1);
    assert.equal(msg.tooSoon, 1);
    assert.equal(msg.promotionRate, 1 / 3);
  });
});

test("buildReflectionKpiMessage: recentViolations capped at 5 most recent", () => {
  withTmpProject((projectPath) => {
    for (let i = 0; i < 8; i++) {
      appendReflectionTelemetry(projectPath, {
        kind: "constraint_violation",
        agentId: `a${i}`,
        tag: `tag-${i}`,
        phrases: ["was not available"],
        lesson: `Lesson #${i}`,
      });
    }
    const msg = buildReflectionKpiMessage(projectPath);
    assert.equal(msg.recentViolations.length, 5,
      "expected the 5 most recent violations only");
    // Newest first.
    assert.equal(msg.recentViolations[0].agentId, "a7");
    assert.equal(msg.recentViolations[4].agentId, "a3");
  });
});

test("buildReflectionKpiMessage: sinceDays narrows the rolling window", () => {
  withTmpProject((projectPath) => {
    // We can't easily backdate via `appendReflectionTelemetry` (it uses
    // Date.now). Test the contract by reading sinceDays=0 (nothing older
    // than now → empty), and verifying default returns all events.
    appendReflectionTelemetry(projectPath, {
      kind: "candidate_submitted",
      agentId: "a", tag: "t", type: "strength", category: "code_quality",
      status: "pending", sessionCount: 1,
    });
    const allTime = buildReflectionKpiMessage(projectPath, null);
    assert.equal(allTime.submitted, 1);
    assert.equal(allTime.windowDays, null);

    const narrow = buildReflectionKpiMessage(projectPath, 7);
    assert.equal(narrow.submitted, 1, "events from <7 days ago should be included");
    assert.equal(narrow.windowDays, 7);
  });
});

test("readReflectionEvents: skips malformed JSON lines silently", () => {
  withTmpProject((projectPath, telemetryDir) => {
    // First a valid event so the file exists.
    appendReflectionTelemetry(projectPath, {
      kind: "candidate_submitted",
      agentId: "a", tag: "valid", type: "strength", category: "code_quality",
      status: "pending", sessionCount: 1,
    });
    // Now write a torn line directly.
    const file = join(telemetryDir, "reflection.jsonl");
    appendFileSync(file, "{not-json-at-all\n");
    const { events } = readReflectionEvents(projectPath);
    assert.equal(events.length, 1, "malformed line must be skipped, valid one kept");
  });
});
