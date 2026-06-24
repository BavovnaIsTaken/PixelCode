/**
 * Traits are ACCOUNT-scoped, not project-scoped — the team carries its learned
 * lessons across every project. trait_memory resolves storage via the home
 * directory, so we redirect $HOME to a temp dir for the duration (mirroring the
 * env-override pattern in project_persistence.test.ts) and assert the on-disk
 * location + that the store key is the account id alone.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, existsSync, rmSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join } from "node:path";
import { loadTraits, recordLesson } from "../src/trait_memory.ts";

function withTmpHome(fn: (base: string) => void): void {
  const base = mkdtempSync(join(tmpdir(), "pixelcode-trait-scope-"));
  const savedHome = process.env.HOME;
  const savedUserProfile = process.env.USERPROFILE;
  process.env.HOME = base;
  process.env.USERPROFILE = base;
  try {
    // Guard: the override must actually redirect homedir(), or the test would
    // silently write into the real ~/.pixelcode.
    assert.equal(homedir(), base, "HOME override did not take effect");
    fn(base);
  } finally {
    if (savedHome === undefined) delete process.env.HOME; else process.env.HOME = savedHome;
    if (savedUserProfile === undefined) delete process.env.USERPROFILE; else process.env.USERPROFILE = savedUserProfile;
    rmSync(base, { recursive: true, force: true });
  }
}

test("a recorded lesson is stored under accounts/{id}, never under projects/", () => {
  withTmpHome((base) => {
    const store = { version: 1, agents: {} };
    recordLesson("local", store, {
      agentId: "coder#1",
      type: "weakness",
      category: "testing",
      tag: "skips-tests",
      lesson: "Tends to skip writing tests.",
      source: "hook",
    });

    assert.ok(
      existsSync(join(base, ".pixelcode", "accounts", "local", "traits.json")),
      "traits must live under the account dir",
    );
    assert.ok(
      !existsSync(join(base, ".pixelcode", "projects")),
      "nothing should be written under the legacy projects/ tree",
    );
  });
});

test("loadTraits round-trips by account id (independent of any project)", () => {
  withTmpHome((base) => {
    const store = { version: 1, agents: {} };
    recordLesson("local", store, {
      agentId: "coder#1",
      type: "strength",
      category: "architecture",
      tag: "clean-layers",
      lesson: "Designs clean layered architecture.",
      source: "hook",
    });

    // Same account id → the lesson is there, no matter which project the team
    // is currently pointed at (project is no longer an input to trait storage).
    const reloaded = loadTraits("local");
    assert.equal(reloaded.agents["coder#1"]?.length, 1);
    assert.equal(reloaded.agents["coder#1"][0].tag, "clean-layers");
  });
});

test("a different account id is an isolated store", () => {
  withTmpHome((base) => {
    const store = { version: 1, agents: {} };
    recordLesson("local", store, {
      agentId: "coder#1",
      type: "weakness",
      category: "testing",
      tag: "skips-tests",
      lesson: "Skips tests.",
      source: "hook",
    });

    // Another account never sees the local account's lessons.
    const other = loadTraits("scratch-account");
    assert.deepEqual(other.agents, {});
  });
});
