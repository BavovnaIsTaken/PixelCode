import { test } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdtempSync, rmSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { runAddCharacterSkin } from "../src/tools/add_skin.js";
import type { SkinPalette } from "../src/lib/skin_io.js";

const FIXTURE_DART = `import 'package:flutter/material.dart';

const _agents = [
  'tech-lead',
  'manager',
  'coder',
];

Map<String, SkinPalette> _buildPalettes(List<SkinPalette> list) { return {}; }

// ─── 1. Default ─────────────────────────────────────────────────────────────

final skinDefault = CharacterSkin(
  id: 'default',
  name: 'Стандарт',
  nameEn: 'Default',
  palettes: _buildPalettes(const [
    SkinPalette(
      hair: Color(0xFF1A1A2E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00C0D1),
      clothes: Color(0xFF00949F), pants: Color(0xFF2C3E50),
      boots: Color(0xFF1A1A1A),
    ),
    SkinPalette(
      hair: Color(0xFF8B4513), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFF59E0B),
      clothes: Color(0xFFD97706), pants: Color(0xFF44403C),
      boots: Color(0xFF292524),
    ),
    SkinPalette(
      hair: Color(0xFF2D1B69), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF10B981),
      clothes: Color(0xFF059669), pants: Color(0xFF1E293B),
      boots: Color(0xFF0F172A),
    ),
  ]),
);

// ─── All skins ──────────────────────────────────────────────────────────────

final allCharacterSkins = <CharacterSkin>[
  skinDefault,
];
`;

function makeFixtureProject(): { dir: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "pixelcode-add-skin-"));
  const skinDir = join(dir, "lib", "widgets", "canvas");
  mkdirSync(skinDir, { recursive: true });
  writeFileSync(join(skinDir, "character_skins.dart"), FIXTURE_DART, "utf8");
  return { dir, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

const NEW_PALETTES: Record<string, SkinPalette> = {
  "tech-lead": fp("#332244"),
  manager: fp("#665544"),
  coder: fp("#445566"),
};

function fp(hex: string): SkinPalette {
  return {
    hair: hex,
    skin: hex,
    skinLight: hex,
    eye: hex,
    clothes: hex,
    pants: hex,
    boots: hex,
  };
}

test("add_skin: happy path inserts and registers", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const result = runAddCharacterSkin(
      {
        skin_id: "neon",
        name_uk: "Неон",
        name_en: "Neon",
        palettes: NEW_PALETTES,
      },
      dir,
    );
    assert.equal(result.status, "added");
    assert.equal(result.skin_id, "neon");
    assert.equal(result.variable_name, "skinNeon");
    assert.equal(result.agents_count, 3);
    assert.equal(result.registered_in_list, true);

    const after = readFileSync(
      join(dir, "lib", "widgets", "canvas", "character_skins.dart"),
      "utf8",
    );
    assert.match(after, /final skinNeon = CharacterSkin\(/);
    assert.match(after, /skinDefault,\n {2}skinNeon,\n\];/);
  } finally {
    cleanup();
  }
});

test("add_skin: idempotent on identical re-insert", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const args = {
      skin_id: "neon",
      name_uk: "Неон",
      name_en: "Neon",
      palettes: NEW_PALETTES,
    };
    runAddCharacterSkin(args, dir);
    const r2 = runAddCharacterSkin(args, dir);
    assert.equal(r2.status, "noop_identical");

    const after = readFileSync(
      join(dir, "lib", "widgets", "canvas", "character_skins.dart"),
      "utf8",
    );
    const matches = after.match(/final skinNeon = CharacterSkin/g) ?? [];
    assert.equal(matches.length, 1, "must not duplicate declaration");
  } finally {
    cleanup();
  }
});

test("add_skin: missing agent palette is rejected with names", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const partial = { ...NEW_PALETTES };
    delete (partial as Record<string, SkinPalette>).coder;
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "broken",
            name_uk: "Поламаний",
            name_en: "Broken",
            palettes: partial,
          },
          dir,
        ),
      /coder/,
    );
  } finally {
    cleanup();
  }
});

test("add_skin: extra unknown agent is rejected", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const extended = { ...NEW_PALETTES, "unknown-agent": fp("#abcdef") };
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "extra",
            name_uk: "Зайвий",
            name_en: "Extra",
            palettes: extended,
          },
          dir,
        ),
      /unknown agents/,
    );
  } finally {
    cleanup();
  }
});

test("add_skin: invalid hex rejected with field name", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const broken: Record<string, SkinPalette> = {
      ...NEW_PALETTES,
      coder: { ...NEW_PALETTES.coder, eye: "rgb(1,2,3)" },
    };
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "bad_hex",
            name_uk: "Помилка",
            name_en: "BadHex",
            palettes: broken,
          },
          dir,
        ),
      /eye/,
    );
  } finally {
    cleanup();
  }
});

test("add_skin: invalid skin_id rejected", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "Bad-Id",
            name_uk: "Поганий",
            name_en: "BadId",
            palettes: NEW_PALETTES,
          },
          dir,
        ),
      /Invalid skin id/,
    );
  } finally {
    cleanup();
  }
});

test("add_skin: id collision with different content errors", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    runAddCharacterSkin(
      {
        skin_id: "neon",
        name_uk: "Неон",
        name_en: "Neon",
        palettes: NEW_PALETTES,
      },
      dir,
    );
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "neon",
            name_uk: "Інший",
            name_en: "Different",
            palettes: NEW_PALETTES,
          },
          dir,
        ),
      /already exists with different/,
    );
  } finally {
    cleanup();
  }
});

test("add_skin: missing project file errors clearly", () => {
  const dir = mkdtempSync(join(tmpdir(), "pixelcode-empty-"));
  try {
    assert.throws(
      () =>
        runAddCharacterSkin(
          {
            skin_id: "neon",
            name_uk: "Неон",
            name_en: "Neon",
            palettes: NEW_PALETTES,
          },
          dir,
        ),
      /not found/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
