import { test } from "node:test";
import assert from "node:assert/strict";

import { runPreviewSkinPalette } from "../src/tools/preview_palette.js";
import type { SkinPalette } from "../src/lib/skin_io.js";

const HIGH_CONTRAST: SkinPalette = {
  hair: "#FFFFFF",
  skin: "#F0D0BC",
  skinLight: "#FFE4D0",
  eye: "#FF8800",
  clothes: "#FFFF00",
  pants: "#FFFFFF",
  boots: "#FFFFFF",
};

const LOW_CONTRAST: SkinPalette = {
  hair: "#0E1418",
  skin: "#101A1E",
  skinLight: "#101A1E",
  eye: "#0E1418",
  clothes: "#101A1E",
  pants: "#0E1418",
  boots: "#101A1E",
};

test("preview accepts single palette+class_id", () => {
  const result = runPreviewSkinPalette({ palette: HIGH_CONTRAST, class_id: "tester" });
  assert.equal(result.summary.total_palettes, 1);
  assert.equal(result.reports[0].class_id, "tester");
  assert.equal(result.reports[0].floor_contrast.length, 5, "5 office tiers");
});

test("preview flags unreadable palette across all tiers", () => {
  const result = runPreviewSkinPalette({ palette: LOW_CONTRAST, class_id: "ghost" });
  assert.equal(result.summary.unreadable_count, 1);
  for (const fc of result.reports[0].floor_contrast) {
    assert.equal(fc.verdict, "unreadable", `tier ${fc.tier} should be unreadable`);
  }
});

test("preview marks high-contrast palette as readable on all tiers", () => {
  const result = runPreviewSkinPalette({ palette: HIGH_CONTRAST, class_id: "tester" });
  assert.equal(result.summary.unreadable_count, 0);
  for (const fc of result.reports[0].floor_contrast) {
    assert.equal(fc.verdict, "readable", `tier ${fc.tier} should be readable`);
  }
});

test("preview accepts palettes map", () => {
  const result = runPreviewSkinPalette({
    palettes: {
      a: HIGH_CONTRAST,
      b: LOW_CONTRAST,
    },
  });
  assert.equal(result.summary.total_palettes, 2);
  assert.equal(result.summary.unreadable_count, 1);
});

test("preview rejects both single + map together", () => {
  assert.throws(
    () =>
      runPreviewSkinPalette({
        palette: HIGH_CONTRAST,
        class_id: "tester",
        palettes: { a: HIGH_CONTRAST },
      }),
    /not both/,
  );
});

test("preview rejects missing input entirely", () => {
  assert.throws(() => runPreviewSkinPalette({}), /Pass `palette`/);
});

test("preview rejects bad hex with descriptive error", () => {
  const broken = { ...HIGH_CONTRAST, hair: "not-a-hex" };
  assert.throws(() => runPreviewSkinPalette({ palette: broken, class_id: "tester" }), /hair/);
});

test("preview hex_codes are uppercased (normalized)", () => {
  const lower: SkinPalette = {
    hair: "#aabbcc",
    skin: "#ffffff",
    skinLight: "#ffffff",
    eye: "#ff8800",
    clothes: "#ffff00",
    pants: "#ffffff",
    boots: "#ffffff",
  };
  const result = runPreviewSkinPalette({ palette: lower, class_id: "tester" });
  assert.equal(result.reports[0].hex_codes.hair, "#AABBCC");
});
