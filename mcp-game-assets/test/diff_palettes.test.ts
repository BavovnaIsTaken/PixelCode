import { test } from "node:test";
import assert from "node:assert/strict";
import { writeFileSync, mkdtempSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { runDiffAgainstExistingPalettes } from "../src/tools/diff_palettes.js";
import type { SkinPalette } from "../src/lib/skin_io.js";

const FIXTURE = `import 'package:flutter/material.dart';

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

// ─── 2. Casual ──────────────────────────────────────────────────────────────

final skinCasual = CharacterSkin(
  id: 'casual',
  name: 'Кежуал',
  nameEn: 'Casual',
  palettes: _buildPalettes(const [
    SkinPalette(
      hair: Color(0xFF884444), skin: Color(0xFFE8B89D),
      skinLight: Color(0xFFF5CDB8), eye: Color(0xFF44AA88),
      clothes: Color(0xFF668866), pants: Color(0xFF334455),
      boots: Color(0xFF222222),
    ),
    SkinPalette(
      hair: Color(0xFF994433), skin: Color(0xFFD4A574),
      skinLight: Color(0xFFE8C49A), eye: Color(0xFFAA8844),
      clothes: Color(0xFFAA6633), pants: Color(0xFF665544),
      boots: Color(0xFF332211),
    ),
    SkinPalette(
      hair: Color(0xFF553388), skin: Color(0xFFC68642),
      skinLight: Color(0xFFD4956B), eye: Color(0xFF44CC99),
      clothes: Color(0xFF338855), pants: Color(0xFF334466),
      boots: Color(0xFF112233),
    ),
  ]),
);

// ─── All skins ──────────────────────────────────────────────────────────────

final allCharacterSkins = <CharacterSkin>[
  skinDefault,
  skinCasual,
];
`;

function makeFixtureProject(): { dir: string; cleanup: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "pixelcode-diff-"));
  const skinDir = join(dir, "lib", "widgets", "canvas");
  mkdirSync(skinDir, { recursive: true });
  writeFileSync(join(skinDir, "character_skins.dart"), FIXTURE, "utf8");
  return {
    dir,
    cleanup: () => rmSync(dir, { recursive: true, force: true }),
  };
}

const NEAR_DEFAULT_TECH_LEAD: SkinPalette = {
  hair: "#1A1A2E",
  skin: "#E8B89D",
  skinLight: "#F5CDB8",
  eye: "#00C0D1",
  clothes: "#00949F",
  pants: "#2C3E50",
  boots: "#1A1A1B",
};

const FAR_FROM_ALL: SkinPalette = {
  hair: "#FF00FF",
  skin: "#00FF00",
  skinLight: "#00FFFF",
  eye: "#FFFFFF",
  clothes: "#FF8800",
  pants: "#880088",
  boots: "#444444",
};

test("diff: near-clone of existing tech-lead default palette flagged is_clone", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const result = runDiffAgainstExistingPalettes(
      { palette: NEAR_DEFAULT_TECH_LEAD, class_id: "tech-lead" },
      dir,
    );
    assert.equal(result.is_clone, true);
    assert.equal(result.closest_skin_id, "default");
    assert.ok(
      result.matches[0].total_distance < 5,
      `expected near-zero distance, got ${result.matches[0].total_distance}`,
    );
  } finally {
    cleanup();
  }
});

test("diff: distinct palette has is_clone=false", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const result = runDiffAgainstExistingPalettes(
      { palette: FAR_FROM_ALL, class_id: "tech-lead" },
      dir,
    );
    assert.equal(result.is_clone, false);
    assert.ok(result.matches[0].total_distance > 80);
  } finally {
    cleanup();
  }
});

test("diff: top_k controls match count", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const r1 = runDiffAgainstExistingPalettes(
      { palette: FAR_FROM_ALL, class_id: "tech-lead", top_k: 1 },
      dir,
    );
    assert.equal(r1.matches.length, 1);

    const r2 = runDiffAgainstExistingPalettes(
      { palette: FAR_FROM_ALL, class_id: "tech-lead", top_k: 2 },
      dir,
    );
    assert.equal(r2.matches.length, 2);
  } finally {
    cleanup();
  }
});

test("diff: matches are sorted by total_distance ascending", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const result = runDiffAgainstExistingPalettes(
      { palette: FAR_FROM_ALL, class_id: "tech-lead", top_k: 5 },
      dir,
    );
    for (let i = 1; i < result.matches.length; i++) {
      assert.ok(
        result.matches[i].total_distance >= result.matches[i - 1].total_distance,
        "matches must be sorted ascending by total_distance",
      );
    }
  } finally {
    cleanup();
  }
});

test("diff: clone_threshold override changes the verdict", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const r1 = runDiffAgainstExistingPalettes(
      { palette: FAR_FROM_ALL, class_id: "tech-lead", clone_threshold: 10000 },
      dir,
    );
    assert.equal(r1.is_clone, true, "with huge threshold everything is a clone");

    const r2 = runDiffAgainstExistingPalettes(
      { palette: NEAR_DEFAULT_TECH_LEAD, class_id: "tech-lead", clone_threshold: 0.001 },
      dir,
    );
    assert.equal(r2.is_clone, false, "with near-zero threshold, only exact match clones");
  } finally {
    cleanup();
  }
});

test("diff: rejects unknown class_id", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    assert.throws(
      () =>
        runDiffAgainstExistingPalettes(
          { palette: FAR_FROM_ALL, class_id: "no-such-class" },
          dir,
        ),
      /Unknown class_id/,
    );
  } finally {
    cleanup();
  }
});

test("diff: rejects bad hex in proposed palette", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    assert.throws(
      () =>
        runDiffAgainstExistingPalettes(
          {
            palette: { ...FAR_FROM_ALL, eye: "not-hex" },
            class_id: "tech-lead",
          },
          dir,
        ),
      /eye/,
    );
  } finally {
    cleanup();
  }
});

test("diff: per_slot_distance is reported per slot key", () => {
  const { dir, cleanup } = makeFixtureProject();
  try {
    const result = runDiffAgainstExistingPalettes(
      { palette: NEAR_DEFAULT_TECH_LEAD, class_id: "tech-lead" },
      dir,
    );
    const closest = result.matches[0];
    for (const key of ["hair", "skin", "skinLight", "eye", "clothes", "pants", "boots"]) {
      assert.ok(
        Object.hasOwn(closest.per_slot_distance, key),
        `per_slot_distance missing key "${key}"`,
      );
    }
  } finally {
    cleanup();
  }
});
