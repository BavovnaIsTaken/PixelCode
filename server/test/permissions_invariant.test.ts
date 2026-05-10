/**
 * Permissions invariant — pin "PixelCode runtime never surfaces permission
 * prompts" as a hard project rule.
 *
 * Every `permissionMode:` literal under `server/src/` MUST resolve to
 * `"bypassPermissions"`. Other modes (`"acceptEdits"`, `"plan"`, `"default"`)
 * break the runtime contract documented in:
 *   - CLAUDE.md → Working Agreement #4
 *   - docs/STRATEGY.md → "Permissions runtime: bypass-by-default"
 *
 * If you intentionally need a non-bypass mode, add the file path to
 * `WHITELIST` below with a one-line justification — and update the docs.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const SERVER_SRC = fileURLToPath(new URL("../src", import.meta.url));

const WHITELIST: ReadonlyArray<{ file: string; mode: string; reason: string }> = [
  // Empty by default. Add entries only with explicit STRATEGY.md amendment.
];

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const s = statSync(full);
    if (s.isDirectory()) {
      walk(full, out);
    } else if (full.endsWith(".ts")) {
      out.push(full);
    }
  }
  return out;
}

const PERMISSION_MODE_RE = /permissionMode\s*:\s*"([^"]+)"/g;

test("every permissionMode in server/src is bypassPermissions", () => {
  const files = walk(SERVER_SRC);
  const violations: string[] = [];

  for (const file of files) {
    const src = readFileSync(file, "utf8");
    PERMISSION_MODE_RE.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = PERMISSION_MODE_RE.exec(src)) !== null) {
      const mode = match[1];
      if (mode === "bypassPermissions") continue;

      const rel = relative(SERVER_SRC, file);
      const allowed = WHITELIST.some(
        (w) => w.file === rel && w.mode === mode,
      );
      if (allowed) continue;

      const lineNo = src.slice(0, match.index).split("\n").length;
      violations.push(`${rel}:${lineNo} → permissionMode: "${mode}"`);
    }
  }

  assert.deepEqual(
    violations,
    [],
    `Non-bypass permissionMode found. PixelCode runtime must never surface ` +
      `permission prompts (see CLAUDE.md WA #4). Either change the mode to ` +
      `"bypassPermissions" or add the file to WHITELIST with justification.\n\n` +
      violations.map((v) => "  - " + v).join("\n"),
  );
});

test("WHITELIST stays empty unless STRATEGY.md is amended", () => {
  assert.equal(
    WHITELIST.length,
    0,
    "Non-empty WHITELIST detected. The bypass invariant is project-wide; " +
      "any exception must be reflected in docs/STRATEGY.md and CLAUDE.md " +
      "before this whitelist grows.",
  );
});
