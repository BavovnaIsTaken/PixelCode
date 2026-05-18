/**
 * Type-level pin between `analyze`'s return type (`BaselineReport`) and the
 * over-the-wire `usage_baselines` ServerMessage shape declared in
 * `protocol.ts`. If anyone tweaks one without the other, this test fails
 * at compile-time before any client code starts disagreeing about JSON shape.
 *
 * No runtime assertions — the assignment compiles iff the shapes line up.
 */

import { test } from "node:test";

import { analyze } from "../src/usage_baseline.js";
import type { ServerMessage } from "../src/protocol.js";

type UsageBaselinesMessage = Extract<ServerMessage, { type: "usage_baselines" }>;

test("usage_baselines payload matches analyzer BaselineReport shape", () => {
  // Compile-only — generate a structurally-typed value from the analyzer and
  // assert it fits the protocol message (minus the discriminator key).
  const report = analyze([], new Date("2026-05-18T00:00:00.000Z"));
  const wire: Omit<UsageBaselinesMessage, "type"> = {
    generatedAt: report.generatedAt,
    totalEntries: report.totalEntries,
    buckets: report.buckets,
    health: report.health,
  };
  // Touch `wire` so TS does not erase the assignment under aggressive DCE.
  if (!wire.generatedAt) {
    throw new Error("generatedAt should be set");
  }
});
