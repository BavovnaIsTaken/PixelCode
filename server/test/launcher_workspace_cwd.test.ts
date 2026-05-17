/**
 * Regression net for the spawned-server cwd contract.
 *
 * The launcher pins the spawned child's cwd, which becomes:
 *   * the server's `process.cwd()`
 *   * the default `projectCwd` of the loaded config
 *   * the agents' working directory
 *   * the key segment in `~/.claude/projects/<cwd>/chat_history.json`
 *
 * A prior fix (commit 0f8bff4) pinned cwd to `dirname(dirname(serverEntry))`
 * = `<workspace>/server` to avoid ENOENT on `process.cwd()` when the
 * launcher's own cwd had been wiped. That landed correctly but silently
 * rerouted chat-history persistence to a sibling project key
 * (`…-PixelCode-server`) and pointed agents at the `server/` subtree
 * instead of the workspace — surfacing as "messages disappear after a
 * server restart" on 2026-05-16. This test pins the workspace-root
 * contract so the fix doesn't get reverted into the previous bug.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { workspaceRootFromServerEntry } from "../src/launcher.js";

test("workspaceRootFromServerEntry returns the workspace, not server/", () => {
  const entry = "/Users/dev/Projects/KMP/PixelCode/server/src/server.ts";
  assert.equal(
    workspaceRootFromServerEntry(entry),
    "/Users/dev/Projects/KMP/PixelCode",
  );
});

test("workspaceRootFromServerEntry handles trailing slashes-free paths", () => {
  const entry = "/tmp/x/server/src/server.ts";
  assert.equal(workspaceRootFromServerEntry(entry), "/tmp/x");
});

test("workspaceRootFromServerEntry — regression: never returns server/", () => {
  // Before the fix this function (inlined as `dirname(dirname(entry))`)
  // returned the `server/` directory. Pin that path is rejected.
  const entry = "/w/server/src/server.ts";
  const result = workspaceRootFromServerEntry(entry);
  assert.notEqual(
    result,
    "/w/server",
    "cwd must be workspace root, not the server subdirectory",
  );
  assert.equal(result, "/w");
});
