import { test } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  parseAgentsList,
  parseExistingSkins,
  validateSkinPalette,
  insertSkinDeclaration,
  buildSkinDeclaration,
  skinIdToVarName,
  type CharacterSkin,
  type SkinPalette,
} from "../src/lib/skin_io.js";

const TINY_FIXTURE = `import 'package:flutter/material.dart';

import '../../models/resource_pack.dart';

const _agents = [
  'tech-lead',
  'manager',
  'coder',
];

Map<String, SkinPalette> _buildPalettes(List<SkinPalette> list) {
  return {};
}

// ─── 1. Default ─────────────────────────────────────────────────────────────

final skinDefault = CharacterSkin(
  id: 'default',
  name: 'Стандарт',
  nameEn: 'Default',
  palettes: _buildPalettes(const [
    // tech-lead
    SkinPalette(
      hair: Color(0xFF1A1A2E), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF00C0D1),
      clothes: Color(0xFF00949F), pants: Color(0xFF2C3E50),
      boots: Color(0xFF1A1A1A),
    ),
    // manager
    SkinPalette(
      hair: Color(0xFF8B4513), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFF59E0B),
      clothes: Color(0xFFD97706), pants: Color(0xFF44403C),
      boots: Color(0xFF292524),
    ),
    // coder
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

CharacterSkin characterSkinById(String id) =>
    allCharacterSkins.firstWhere((s) => s.id == id);
`;

function makeFixtureFile(): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), "pixelcode-skin-io-"));
  const file = join(dir, "character_skins.dart");
  writeFileSync(file, TINY_FIXTURE, "utf8");
  return { dir, file };
}

test("parseAgentsList extracts all agent ids in declaration order", () => {
  const agents = parseAgentsList(TINY_FIXTURE);
  assert.deepEqual(agents, ["tech-lead", "manager", "coder"]);
});

test("parseExistingSkins reads id, name, nameEn, palettes correctly", () => {
  const skins = parseExistingSkins(TINY_FIXTURE, ["tech-lead", "manager", "coder"]);
  assert.equal(skins.length, 1);
  assert.equal(skins[0].id, "default");
  assert.equal(skins[0].name, "Стандарт");
  assert.equal(skins[0].nameEn, "Default");
  assert.equal(skins[0].palettes["tech-lead"].hair, "#1A1A2E");
  assert.equal(skins[0].palettes["manager"].clothes, "#D97706");
  assert.equal(skins[0].palettes["coder"].boots, "#0F172A");
});

test("validateSkinPalette accepts valid palette and rejects bad hex", () => {
  const valid = {
    hair: "#aaaaaa",
    skin: "#BBBBBB",
    skinLight: "#cccccc",
    eye: "#DDDDDD",
    clothes: "#EEEEEE",
    pants: "#FFFFFF",
    boots: "#000000",
  };
  const v = validateSkinPalette(valid, "manager");
  assert.equal(v.hair, "#AAAAAA");
  assert.equal(v.boots, "#000000");

  assert.throws(() => validateSkinPalette({ ...valid, hair: "#FFF" }, "manager"), /hair/);
  assert.throws(() => validateSkinPalette({ ...valid, eye: "not-a-hex" }, "manager"), /eye/);
});

test("skinIdToVarName converts snake_case to skinPascalCase", () => {
  assert.equal(skinIdToVarName("default"), "skinDefault");
  assert.equal(skinIdToVarName("demon_slayer"), "skinDemonSlayer");
  assert.equal(skinIdToVarName("retro_2"), "skinRetro2");
  assert.throws(() => skinIdToVarName("Demon"), /Invalid skin id/);
  assert.throws(() => skinIdToVarName("demon-slayer"), /Invalid skin id/);
});

test("buildSkinDeclaration produces parseable Dart for a 3-agent skin", () => {
  const skin: CharacterSkin = {
    id: "neon",
    name: "Неон",
    nameEn: "Neon",
    palettes: {
      "tech-lead": fakePalette(0x10, 0x20, 0x30),
      manager: fakePalette(0x40, 0x50, 0x60),
      coder: fakePalette(0x70, 0x80, 0x90),
    },
  };
  const dart = buildSkinDeclaration("skinNeon", skin, ["tech-lead", "manager", "coder"]);
  assert.match(dart, /final skinNeon = CharacterSkin\(/);
  assert.match(dart, /id: 'neon'/);
  assert.match(dart, /name: 'Неон'/);
  assert.match(dart, /nameEn: 'Neon'/);
  assert.match(dart, /\/\/ tech-lead/);
  assert.match(dart, /\/\/ manager/);
  assert.match(dart, /\/\/ coder/);
  assert.match(dart, /Color\(0xFF102030\)/);
});

test("insertSkinDeclaration adds new skin and registers in list", () => {
  const { dir, file } = makeFixtureFile();
  try {
    const skin: CharacterSkin = {
      id: "neon",
      name: "Неон",
      nameEn: "Neon",
      palettes: {
        "tech-lead": fakePalette(0x10, 0x20, 0x30),
        manager: fakePalette(0x40, 0x50, 0x60),
        coder: fakePalette(0x70, 0x80, 0x90),
      },
    };
    const result = insertSkinDeclaration(file, skin);
    assert.equal(result.status, "added");
    assert.equal(result.registeredInList, true);

    const after = readFileSync(file, "utf8");
    assert.match(after, /final skinNeon = CharacterSkin\(/);
    assert.match(after, /skinDefault,\n {2}skinNeon,\n\];/);

    const skins = parseExistingSkins(after, ["tech-lead", "manager", "coder"]);
    assert.equal(skins.length, 2);
    assert.equal(skins[1].id, "neon");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("insertSkinDeclaration is idempotent for identical content", () => {
  const { dir, file } = makeFixtureFile();
  try {
    const skin: CharacterSkin = {
      id: "neon",
      name: "Неон",
      nameEn: "Neon",
      palettes: {
        "tech-lead": fakePalette(0x10, 0x20, 0x30),
        manager: fakePalette(0x40, 0x50, 0x60),
        coder: fakePalette(0x70, 0x80, 0x90),
      },
    };
    insertSkinDeclaration(file, skin);
    const r2 = insertSkinDeclaration(file, skin);
    assert.equal(r2.status, "noop_identical");

    const skins = parseExistingSkins(readFileSync(file, "utf8"), [
      "tech-lead",
      "manager",
      "coder",
    ]);
    assert.equal(skins.length, 2, "second insert must NOT duplicate");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("insertSkinDeclaration rejects id collision with different content", () => {
  const { dir, file } = makeFixtureFile();
  try {
    const skinA: CharacterSkin = {
      id: "neon",
      name: "Неон",
      nameEn: "Neon",
      palettes: {
        "tech-lead": fakePalette(0x10, 0x20, 0x30),
        manager: fakePalette(0x40, 0x50, 0x60),
        coder: fakePalette(0x70, 0x80, 0x90),
      },
    };
    const skinB: CharacterSkin = {
      ...skinA,
      palettes: {
        ...skinA.palettes,
        "tech-lead": fakePalette(0xff, 0xff, 0xff),
      },
    };
    insertSkinDeclaration(file, skinA);
    assert.throws(() => insertSkinDeclaration(file, skinB), /already exists with different/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("insertSkinDeclaration rejects palette set with missing agent", () => {
  const { dir, file } = makeFixtureFile();
  try {
    const skin: CharacterSkin = {
      id: "incomplete",
      name: "Неповний",
      nameEn: "Incomplete",
      palettes: {
        "tech-lead": fakePalette(0x10, 0x20, 0x30),
        manager: fakePalette(0x40, 0x50, 0x60),
      },
    };
    assert.throws(() => insertSkinDeclaration(file, skin), /coder/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

function fakePalette(r: number, g: number, b: number): SkinPalette {
  const hex = `#${r.toString(16).padStart(2, "0").toUpperCase()}${g.toString(16).padStart(2, "0").toUpperCase()}${b.toString(16).padStart(2, "0").toUpperCase()}`;
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
