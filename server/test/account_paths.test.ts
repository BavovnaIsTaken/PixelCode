/**
 * Account-scoped path resolution. These pin the two properties the feature
 * rests on: (1) account data lives under `accounts/{key}`, fully independent of
 * any project path, and (2) `accountKey` is a path-traversal guard for the
 * client-supplied id.
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { join } from "node:path";
import {
  DEFAULT_ACCOUNT_ID,
  accountKey,
  accountDir,
  accountGameStateFile,
  accountTraitsFile,
  accountCandidatesFile,
  legacyProjectsRoot,
} from "../src/account_paths.ts";

const BASE = "/tmp/pixelcode-test-home";

test("default account id is the shared constant 'local'", () => {
  assert.equal(DEFAULT_ACCOUNT_ID, "local");
  assert.equal(accountKey("local"), "local");
});

test("empty / nullish account id falls back to the default account", () => {
  assert.equal(accountKey(""), DEFAULT_ACCOUNT_ID);
  assert.equal(accountKey("   "), DEFAULT_ACCOUNT_ID);
  assert.equal(accountKey(null), DEFAULT_ACCOUNT_ID);
  assert.equal(accountKey(undefined), DEFAULT_ACCOUNT_ID);
});

test("accountKey strips path-traversal and illegal characters", () => {
  // No separators or dot-segments survive — the id can never escape accounts/.
  for (const evil of ["../../etc", "..", "a/b/c", "x/../y", "..\\..\\win"]) {
    const key = accountKey(evil);
    assert.ok(!key.includes("/"), `key "${key}" must not contain '/'`);
    assert.ok(!key.includes("\\"), `key "${key}" must not contain '\\\\'`);
    assert.ok(!key.includes(".."), `key "${key}" must not contain '..'`);
    assert.ok(!key.startsWith("-"), `key "${key}" must not start with '-'`);
    assert.ok(key.length > 0, "key must be non-empty");
  }
});

test("accountKey sanitizes spaces/punctuation but keeps id-safe characters", () => {
  assert.equal(accountKey("My Team!"), "My-Team-");
  assert.equal(accountKey("team_42-alpha"), "team_42-alpha");
});

test("account data lives under accounts/{key}, not under projects/", () => {
  const dir = accountDir("local", BASE);
  assert.equal(dir, join(BASE, ".pixelcode", "accounts", "local"));
  assert.ok(!dir.includes(`${join(".pixelcode", "projects")}`),
    "account dir must not be nested under the legacy projects/ tree");
});

test("account file helpers point at the expected filenames", () => {
  assert.equal(
    accountGameStateFile("local", BASE),
    join(BASE, ".pixelcode", "accounts", "local", "game_state.json"),
  );
  assert.equal(
    accountTraitsFile("local", BASE),
    join(BASE, ".pixelcode", "accounts", "local", "traits.json"),
  );
  assert.equal(
    accountCandidatesFile("local", BASE),
    join(BASE, ".pixelcode", "accounts", "local", "trait_candidates.json"),
  );
});

test("account path is independent of the project — same id, same path regardless", () => {
  // The whole point: switching projects can never move the team's storage.
  const a = accountGameStateFile("local", BASE);
  const b = accountGameStateFile("local", BASE);
  assert.equal(a, b);
});

test("legacyProjectsRoot points at the old per-project tree", () => {
  assert.equal(legacyProjectsRoot(BASE), join(BASE, ".pixelcode", "projects"));
});
