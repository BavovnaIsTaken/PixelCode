/**
 * One-time migration of a legacy per-project team into the account.
 *
 * All IO is rooted at a temp baseDir, so these never touch real user data.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { migrateLegacyAccountData } from "../src/account_migration.ts";
import {
  accountGameStateFile,
  accountTraitsFile,
  accountCandidatesFile,
} from "../src/account_paths.ts";

function withTmpHome<T>(fn: (base: string) => T): T {
  const base = mkdtempSync(join(tmpdir(), "pixelcode-acct-mig-"));
  try {
    return fn(base);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
}

/** Write a legacy `projects/{key}/game_state.json` envelope. */
function writeLegacyGameState(base: string, key: string, updatedAt: number, instances: Record<string, unknown> = {}): void {
  const dir = join(base, ".pixelcode", "projects", key);
  mkdirSync(dir, { recursive: true });
  const fullState = JSON.stringify({ schemaVersion: 1, instances, grymni: 500 });
  writeFileSync(join(dir, "game_state.json"), JSON.stringify({ fullState, updatedAt }));
}

function writeLegacyFile(base: string, key: string, name: string, content: string): void {
  const dir = join(base, ".pixelcode", "projects", key);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, name), content);
}

test("migrates the most-recently-updated project's game_state into the account", () => {
  withTmpHome((base) => {
    writeLegacyGameState(base, "projA", 100, { "manager#1": { roleType: "manager" } });
    writeLegacyGameState(base, "projB", 200, { "coder#1": { roleType: "coder" } });

    const report = migrateLegacyAccountData("local", base);

    assert.equal(report.migrated, true);
    assert.equal(report.reason, "migrated");
    assert.equal(report.fromProjectKey, "projB"); // newest updatedAt wins
    assert.equal(report.updatedAt, 200);

    const target = accountGameStateFile("local", base);
    assert.ok(existsSync(target), "account game_state.json must exist after migration");
    const envelope = JSON.parse(readFileSync(target, "utf-8"));
    assert.equal(envelope.updatedAt, 200);
    assert.ok((envelope.fullState as string).includes("coder#1"), "must adopt projB's roster");
  });
});

test("migration also adopts traits + candidates from the chosen project", () => {
  withTmpHome((base) => {
    writeLegacyGameState(base, "projB", 200);
    writeLegacyFile(base, "projB", "traits.json", JSON.stringify({ version: 1, agents: { "coder#1": [] } }));
    writeLegacyFile(base, "projB", "trait_candidates.json", JSON.stringify({ version: 1, candidates: {} }));

    const report = migrateLegacyAccountData("local", base);

    assert.equal(report.traits.migrated, true);
    assert.equal(report.candidates.migrated, true);
    assert.ok(existsSync(accountTraitsFile("local", base)));
    assert.ok(existsSync(accountCandidatesFile("local", base)));
    const traits = JSON.parse(readFileSync(accountTraitsFile("local", base), "utf-8"));
    assert.deepEqual(Object.keys(traits.agents), ["coder#1"]);
  });
});

test("traits absent in the source project → game_state still migrates, traits reported no_source", () => {
  withTmpHome((base) => {
    writeLegacyGameState(base, "projB", 200);
    const report = migrateLegacyAccountData("local", base);
    assert.equal(report.migrated, true);
    assert.equal(report.traits.migrated, false);
    assert.equal(report.traits.reason, "no_source");
    assert.ok(!existsSync(accountTraitsFile("local", base)));
  });
});

test("idempotent: a second run does not clobber an initialized account", () => {
  withTmpHome((base) => {
    writeLegacyGameState(base, "projB", 200, { "coder#1": {} });
    migrateLegacyAccountData("local", base);

    // The account file now exists. Simulate divergence (e.g. the user kept
    // playing) and confirm a re-run leaves it untouched.
    const target = accountGameStateFile("local", base);
    writeFileSync(target, JSON.stringify({ fullState: "{\"diverged\":true}", updatedAt: 999 }));

    const second = migrateLegacyAccountData("local", base);
    assert.equal(second.migrated, false);
    assert.equal(second.reason, "account_exists");
    const after = JSON.parse(readFileSync(target, "utf-8"));
    assert.equal(after.updatedAt, 999, "must not overwrite a live account");
  });
});

test("no legacy data → no-op", () => {
  withTmpHome((base) => {
    const report = migrateLegacyAccountData("local", base);
    assert.equal(report.migrated, false);
    assert.equal(report.reason, "no_legacy");
    assert.ok(!existsSync(accountGameStateFile("local", base)));
  });
});

test("projects dir with only malformed game_state → no-op (corrupt files skipped)", () => {
  withTmpHome((base) => {
    writeLegacyFile(base, "broken", "game_state.json", "{ not valid json");
    const report = migrateLegacyAccountData("local", base);
    assert.equal(report.migrated, false);
    assert.equal(report.reason, "no_legacy");
  });
});

test("a corrupt project is skipped but a valid sibling still migrates", () => {
  withTmpHome((base) => {
    writeLegacyFile(base, "broken", "game_state.json", "{ not valid json");
    writeLegacyGameState(base, "good", 150, { "manager#1": {} });
    const report = migrateLegacyAccountData("local", base);
    assert.equal(report.migrated, true);
    assert.equal(report.fromProjectKey, "good");
  });
});
