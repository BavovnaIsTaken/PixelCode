/**
 * Smoke test: parse the real lib/widgets/canvas/character_skins.dart from the
 * checked-in PixelCode project. Catches drift between this MCP server's
 * regex-based parser and the actual Dart formatting in the repo.
 *
 * Skipped automatically if the file isn't where we expect (so the test suite
 * doesn't fail when this package is consumed elsewhere).
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { parseAgentsList, parseExistingSkins, SKIN_KEYS } from "../src/lib/skin_io.js";

const PROJECT_ROOT = resolve(fileURLToPath(new URL("../..", import.meta.url)));
const SKINS_FILE = join(PROJECT_ROOT, "lib", "widgets", "canvas", "character_skins.dart");

test("real character_skins.dart parses cleanly", { skip: !existsSync(SKINS_FILE) }, () => {
  const src = readFileSync(SKINS_FILE, "utf8");
  const agents = parseAgentsList(src);
  assert.ok(agents.length >= 7, `expected at least 7 agents, got ${agents.length}`);

  const skins = parseExistingSkins(src, agents);
  assert.ok(skins.length >= 1, "expected at least one skin definition");

  for (const skin of skins) {
    assert.ok(skin.id, `skin missing id: ${JSON.stringify(skin)}`);
    assert.ok(skin.name, `skin "${skin.id}" missing name`);
    assert.ok(skin.nameEn, `skin "${skin.id}" missing nameEn`);

    for (const a of agents) {
      const palette = skin.palettes[a];
      assert.ok(palette, `skin "${skin.id}" missing palette for agent "${a}"`);
      for (const k of SKIN_KEYS) {
        assert.match(palette[k], /^#[0-9A-F]{6}$/, `skin "${skin.id}" / "${a}" / ${k}: bad hex`);
      }
    }
  }
});
