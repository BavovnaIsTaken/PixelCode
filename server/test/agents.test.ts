import { test } from "node:test";
import assert from "node:assert/strict";
import { skillsToModel, capabilityProfileForRole } from "../src/agents.ts";

// Skill indices: 0=speed, 1=precision, 2=creativity, 3=insight, 4=reliability

test("skillsToModel — starter agent (all ~2) → haiku", () => {
  const skills = { "0": 3, "1": 3, "2": 2, "3": 3, "4": 2 };
  // capability = 0.4*3 + 0.3*3 + 0.2*2 + 0.1*2 = 1.2 + 0.9 + 0.4 + 0.2 = 2.7
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — mid-Lv reviewer (capability 7.3, just under 8) → haiku", () => {
  // Precision 10, Insight 8, Reliability 5, Creativity 1
  const skills = { "0": 1, "1": 10, "2": 1, "3": 8, "4": 5 };
  // capability = 0.4*8 + 0.3*10 + 0.2*5 + 0.1*1 = 7.3 → still haiku (threshold 8)
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — upgraded mid-tier agent → sonnet", () => {
  // capability = 0.4*14 + 0.3*10 + 0.2*8 + 0.1*4 = 5.6 + 3.0 + 1.6 + 0.4 = 10.6
  const skills = { "0": 4, "1": 10, "2": 4, "3": 14, "4": 8 };
  assert.equal(skillsToModel(skills), "sonnet");
});

test("skillsToModel — elite agent (insight-max) → opus", () => {
  // capability = 0.4*20 + 0.3*15 + 0.2*15 + 0.1*10 = 8 + 4.5 + 3 + 1 = 16.5
  const skills = { "0": 5, "1": 15, "2": 10, "3": 20, "4": 15 };
  assert.equal(skillsToModel(skills), "opus");
});

test("skillsToModel — speed is ignored for capability", () => {
  // Very high Speed, mediocre everything else → should still be haiku.
  const skills = { "0": 50, "1": 3, "2": 3, "3": 3, "4": 3 };
  // capability = 0.4*3 + 0.3*3 + 0.2*3 + 0.1*3 = 3.0
  assert.equal(skillsToModel(skills), "haiku");
});

test("skillsToModel — empty skills → haiku", () => {
  assert.equal(skillsToModel({}), "haiku");
});

// ─── Role-aware capability profiles ──────────────────────────────────────

test("capabilityProfileForRole — analytical roles use default profile", () => {
  assert.equal(capabilityProfileForRole("coder"), "default");
  assert.equal(capabilityProfileForRole("reviewer"), "default");
  assert.equal(capabilityProfileForRole("tech-lead"), "default");
  assert.equal(capabilityProfileForRole("security"), "default");
  assert.equal(capabilityProfileForRole("llm-specialist"), "default");
  assert.equal(capabilityProfileForRole(undefined), "default");
});

test("capabilityProfileForRole — creative roles use creative profile", () => {
  assert.equal(capabilityProfileForRole("ui-ux-designer"), "creative");
  assert.equal(capabilityProfileForRole("game-designer"), "creative");
});

test("skillsToModel — designer Lv1 starter (creative profile) → haiku", () => {
  // Соня roster spec: speed=3, prec=2, crt=7, ins=2, rel=4
  // creative cap = 0.25*2 + 0.2*2 + 0.2*4 + 0.35*7 = 0.5 + 0.4 + 0.8 + 2.45 = 4.15
  const skills = { "0": 3, "1": 2, "2": 7, "3": 2, "4": 4 };
  assert.equal(skillsToModel(skills, "ui-ux-designer"), "haiku");
});

test("skillsToModel — same designer with default profile would be haiku-locked even with mid upgrades", () => {
  // crt=12, prc=8, ins=8, rel=8 — strong creative-bias build
  const skills = { "0": 3, "1": 8, "2": 12, "3": 8, "4": 8 };
  // default cap = 0.4*8 + 0.3*8 + 0.2*8 + 0.1*12 = 3.2 + 2.4 + 1.6 + 1.2 = 8.4 → barely sonnet
  assert.equal(skillsToModel(skills), "sonnet");
  // creative cap = 0.25*8 + 0.2*8 + 0.2*8 + 0.35*12 = 2 + 1.6 + 1.6 + 4.2 = 9.4 → sonnet
  assert.equal(skillsToModel(skills, "ui-ux-designer"), "sonnet");
});

test("skillsToModel — designer endgame maxed-creative → opus", () => {
  // Lv10 maxed creative-bias: crt=20, ins=18, prc=18, rel=20
  const skills = { "0": 5, "1": 18, "2": 20, "3": 18, "4": 20 };
  // creative cap = 0.25*18 + 0.2*18 + 0.2*20 + 0.35*20 = 4.5 + 3.6 + 4 + 7 = 19.1
  assert.equal(skillsToModel(skills, "ui-ux-designer"), "opus");
});

test("skillsToModel — game-designer also uses creative profile", () => {
  // Same starter as Соня — confirm game-designer maps to creative
  const skills = { "0": 3, "1": 2, "2": 14, "3": 6, "4": 4 };
  // creative cap = 0.25*6 + 0.2*2 + 0.2*4 + 0.35*14 = 1.5 + 0.4 + 0.8 + 4.9 = 7.6 → still haiku
  // default  cap = 0.4*6 + 0.3*2 + 0.2*4 + 0.1*14 = 2.4 + 0.6 + 0.8 + 1.4 = 5.2 → haiku
  // both haiku at this point but creative gets there faster on next upgrade
  assert.equal(skillsToModel(skills, "game-designer"), "haiku");
});
