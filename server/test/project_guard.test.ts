import { test } from "node:test";
import assert from "node:assert/strict";
import { checkProjectPath, normalizeProjectPath } from "../src/project_guard.js";

// ─── normalizeProjectPath ───────────────────────────────────────────────────

test("normalizeProjectPath strips a trailing separator", () => {
  assert.equal(normalizeProjectPath("/projects/demo/"), "/projects/demo");
});

test("normalizeProjectPath keeps a bare path unchanged", () => {
  assert.equal(normalizeProjectPath("/projects/demo"), "/projects/demo");
});

test("normalizeProjectPath collapses redundant segments", () => {
  assert.equal(normalizeProjectPath("/projects/./demo/../demo"), "/projects/demo");
});

test("normalizeProjectPath leaves the filesystem root intact", () => {
  assert.equal(normalizeProjectPath("/"), "/");
});

// ─── checkProjectPath — pass cases ──────────────────────────────────────────

test("undefined requested path passes (legacy clients)", () => {
  assert.equal(checkProjectPath(undefined, "/projects/demo"), null);
});

test("empty requested path passes (defensive)", () => {
  assert.equal(checkProjectPath("", "/projects/demo"), null);
});

test("exact match passes", () => {
  assert.equal(checkProjectPath("/projects/demo", "/projects/demo"), null);
});

test("trailing-slash variant of the same project passes", () => {
  assert.equal(checkProjectPath("/projects/demo/", "/projects/demo"), null);
  assert.equal(checkProjectPath("/projects/demo", "/projects/demo/"), null);
});

test("dot-segment variant of the same project passes", () => {
  assert.equal(
    checkProjectPath("/projects/x/../demo", "/projects/demo"),
    null,
  );
});

// ─── checkProjectPath — mismatch cases ──────────────────────────────────────

test("different project is rejected with normalized pair", () => {
  const result = checkProjectPath(
    "/Users/dev/Projects/worktree-a/",
    "/Users/dev/GitHub/PixelCode",
  );
  assert.deepEqual(result, {
    requested: "/Users/dev/Projects/worktree-a",
    active: "/Users/dev/GitHub/PixelCode",
  });
});

test("subdirectory of the active project is still a mismatch", () => {
  // A worktree under the repo is a different tree — must not pass.
  const result = checkProjectPath(
    "/projects/demo/worktrees/feature",
    "/projects/demo",
  );
  assert.ok(result);
  assert.equal(result.requested, "/projects/demo/worktrees/feature");
});

test("parent directory of the active project is a mismatch", () => {
  assert.ok(checkProjectPath("/projects", "/projects/demo"));
});
