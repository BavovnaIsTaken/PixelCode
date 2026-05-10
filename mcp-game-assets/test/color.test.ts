import { test } from "node:test";
import assert from "node:assert/strict";

import {
  isValidHex,
  parseHex,
  normalizeHex,
  rgbDistance,
  hexDistance,
  contrastRatio,
  contrastVerdict,
  relativeLuminance,
} from "../src/lib/color.js";

test("isValidHex accepts uppercase, lowercase, and rejects bad input", () => {
  assert.equal(isValidHex("#FFFFFF"), true);
  assert.equal(isValidHex("#ffffff"), true);
  assert.equal(isValidHex("#1A2B3C"), true);
  assert.equal(isValidHex("FFFFFF"), false);
  assert.equal(isValidHex("#FFF"), false);
  assert.equal(isValidHex("#GGGGGG"), false);
  assert.equal(isValidHex(""), false);
});

test("parseHex extracts RGB channels correctly", () => {
  assert.deepEqual(parseHex("#000000"), { r: 0, g: 0, b: 0 });
  assert.deepEqual(parseHex("#FFFFFF"), { r: 255, g: 255, b: 255 });
  assert.deepEqual(parseHex("#FF0000"), { r: 255, g: 0, b: 0 });
  assert.deepEqual(parseHex("#1A2B3C"), { r: 0x1a, g: 0x2b, b: 0x3c });
});

test("parseHex throws on bad input", () => {
  assert.throws(() => parseHex("FFFFFF"), /Invalid hex/);
  assert.throws(() => parseHex("#FFF"), /Invalid hex/);
});

test("normalizeHex uppercases lowercase input", () => {
  assert.equal(normalizeHex("#abcdef"), "#ABCDEF");
  assert.equal(normalizeHex("#ABCDEF"), "#ABCDEF");
});

test("rgbDistance is zero for identical colors and symmetric", () => {
  const a = { r: 100, g: 50, b: 200 };
  const b = { r: 100, g: 50, b: 200 };
  assert.equal(rgbDistance(a, b), 0);

  const c = { r: 0, g: 0, b: 0 };
  const d = { r: 255, g: 255, b: 255 };
  assert.ok(Math.abs(rgbDistance(c, d) - rgbDistance(d, c)) < 1e-9);
});

test("rgbDistance reaches expected max for black ↔ white", () => {
  const black = { r: 0, g: 0, b: 0 };
  const white = { r: 255, g: 255, b: 255 };
  const dist = rgbDistance(black, white);
  assert.ok(dist > 441 && dist < 442, `expected ~441.67, got ${dist}`);
});

test("hexDistance composes parseHex + rgbDistance", () => {
  assert.equal(hexDistance("#000000", "#000000"), 0);
  assert.ok(hexDistance("#000000", "#FFFFFF") > 441);
});

test("relativeLuminance: black ≈ 0, white = 1", () => {
  assert.ok(relativeLuminance({ r: 0, g: 0, b: 0 }) < 1e-9);
  assert.equal(relativeLuminance({ r: 255, g: 255, b: 255 }), 1);
});

test("contrastRatio: black/white = 21, identical = 1", () => {
  const black = { r: 0, g: 0, b: 0 };
  const white = { r: 255, g: 255, b: 255 };
  assert.equal(contrastRatio(black, white), 21);
  assert.equal(contrastRatio(white, white), 1);
  assert.equal(contrastRatio(black, white), contrastRatio(white, black));
});

test("contrastVerdict thresholds", () => {
  assert.equal(contrastVerdict(2.5), "unreadable");
  assert.equal(contrastVerdict(3.0), "borderline");
  assert.equal(contrastVerdict(4.4), "borderline");
  assert.equal(contrastVerdict(4.5), "readable");
  assert.equal(contrastVerdict(21), "readable");
});
