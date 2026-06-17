/**
 * Restart-survival contract for the active project.
 *
 * `set_project` persists the new path into the server config file via
 * `updateConfigFile`; on boot `loadConfig` reads it back as the effective
 * `projectCwd`. These tests pin that round-trip — the regression they guard
 * against is a server restart silently resetting PROJECT_CWD to
 * `process.cwd()` while clients keep showing the previously selected project
 * (which made agents write into the wrong tree).
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { loadConfig, updateConfigFile } from "../src/config.js";

function withTmpConfig(fn: (configPath: string) => void): void {
  const dir = mkdtempSync(join(tmpdir(), "pixelcode-config-"));
  // Env overrides beat the file in loadConfig — neutralize an ambient
  // PROJECT_CWD so these tests assert the file round-trip, not the env.
  const savedEnvCwd = process.env.PROJECT_CWD;
  delete process.env.PROJECT_CWD;
  try {
    fn(join(dir, "config.json"));
  } finally {
    if (savedEnvCwd !== undefined) process.env.PROJECT_CWD = savedEnvCwd;
    rmSync(dir, { recursive: true, force: true });
  }
}

test("projectCwd persisted via updateConfigFile is restored by loadConfig", () => {
  withTmpConfig((configPath) => {
    // Simulate the set_project handler persisting a switch…
    updateConfigFile(configPath, { projectCwd: "/projects/worktree-a" });

    // …and a fresh server boot loading config from the same file.
    const reloaded = loadConfig({ configPath });
    assert.equal(reloaded.effective.projectCwd, "/projects/worktree-a");
    assert.equal(reloaded.fromFile.projectCwd, "/projects/worktree-a");
  });
});

test("a second switch overwrites the persisted projectCwd", () => {
  withTmpConfig((configPath) => {
    updateConfigFile(configPath, { projectCwd: "/projects/a" });
    updateConfigFile(configPath, { projectCwd: "/projects/b" });

    const reloaded = loadConfig({ configPath });
    assert.equal(reloaded.effective.projectCwd, "/projects/b");
  });
});

test("persisting projectCwd does not clobber other config keys", () => {
  withTmpConfig((configPath) => {
    updateConfigFile(configPath, { port: 9999 });
    updateConfigFile(configPath, { projectCwd: "/projects/a" });

    const reloaded = loadConfig({ configPath });
    assert.equal(reloaded.effective.port, 9999);
    assert.equal(reloaded.effective.projectCwd, "/projects/a");
  });
});

test("missing config file falls back to process.cwd() (boot default)", () => {
  withTmpConfig((configPath) => {
    const fresh = loadConfig({ configPath });
    assert.equal(fresh.effective.projectCwd, process.cwd());
  });
});
